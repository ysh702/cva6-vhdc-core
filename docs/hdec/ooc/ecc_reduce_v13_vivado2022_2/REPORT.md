# HDEC ECC REDUCE V13 Vivado 2022.2 Report

## 1. 结论

本轮把 ECC 底层有限域运算推进到 `GF(2^233)`：

- 选择曲线族：优先面向 `sect233k1 / K-233`，保留切换到 `sect233r1 / B-233` 的可能。
- 选择不可约多项式：`f(x) = x^233 + x^74 + 1`。
- 新增底层指令：`HDEC_ECC_REDUCE`，把 512-bit 原始多项式乘积约减成 233-bit 域元素。
- 修正 `HSPREAD` 语义：现在它输出标准 512-bit 平方展开，低 256-bit 和高 256-bit 连续放在相邻 VRF 行里，可以直接接 `HDEC_ECC_REDUCE`。
- 功能验证：`ECC_MUL raw -> REDUCE` 和 `HSPREAD square -> REDUCE` 均已通过 xsim。
- Vivado 2022.2 OOC：5.000 ns 约束通过，估算 Fmax `205.804 MHz`。

这版还不是完整点乘控制器，但底层已经形成：

```text
ECC_ADD    : 复用 XOR lane，完成 GF(2) 加法
ECC_ALIGN  : 复用 HPERM/shift-align，完成域元素对齐
ECC_MUL    : 复用 popcount-assisted KPD32 diagonal parity，输出 512-bit raw product
HSPREAD    : 复用 HPERM 扩展，输出 512-bit raw square
ECC_REDUCE : 用稀疏三项式固定 XOR fold，输出 GF(2^233) 元素
```

## 2. 曲线和多项式选择

当前硬件最适合 `GF(2^233)`，原因不是单纯“标准里有”，而是它和 HDEC 的数据宽度、已有算子、约减成本非常贴：

1. 一个域元素放进一个 256-bit VRF row，只浪费高 23 bit。
2. 原始乘法和平方都天然产生 512-bit 中间结果，正好用两个相邻 VRF row 存放。
3. `x^233 + x^74 + 1` 是三项式，约减时每个高位只需要折回到两个低位位置，硬件就是固定连线和异或。
4. `K-233` 是 Koblitz 曲线，后续如果做 Frobenius / ITA / 标量点乘调度，平方和线性变换的叙事更顺。
5. `B-233` 和 `K-233` 使用同一个底层域和同一个约减多项式，所以本轮 REDUCE 硬件不锁死曲线类型。

严格 128-bit 安全强度时，标准二元域会更自然地选 `K-283/B-283`。但 283 位会超过当前 256-bit VRF row，域元素至少要跨两行，HPERM 平方展开和 REDUCE 都会变成跨行调度，面积、控制和论文里的复用故事都会变重。所以这版选择 233 位作为 HDEC-friendly 的标准二元域原型；如果后续目标变成产品级 128-bit security，再单独开 283 位路线。

参考标准：

- NIST SP 800-186 把 K-233/B-233、K-283/B-283 等列为二元域曲线族，并说明 K-233/B-233 是 `m=233` 的二元域曲线。
- SEC 2 v2.0 明确给出 `sect233k1` 和 `sect233r1`，二者的域表示都是 `f(x)=x^233+x^74+1`。

## 3. 模约减设计

对 `f(x)=x^233+x^74+1`，在这个域里有一个很关键的等价关系：

```text
x^233 = x^74 + 1
```

所以任何超过 232 次的高位项，都可以折回低位。比如某个中间结果里有 `x^(233+j)`，它就等价于同时翻转 `x^j` 和 `x^(74+j)`。因为二元域加法就是异或，翻转两次会自动抵消。

硬件上没有做循环移位累加，而是做固定两级 XOR fold：

1. 第一级把 raw product 的 233..511 位整体折回到低位窗口和偏移 74 的窗口。
2. 第一级折回后，可能还有 233..352 的残余高位。
3. 第二级再把这 120 个残余高位折回一次。
4. 输出只保留 0..232 位，高 23 位清零，保持一个 256-bit row 的统一存储格式。

这个 REDUCE 不是复用 popcount，因为模约减本质是线性异或，强行经过 popcount 会浪费计数高位和时序余量。它复用的是 HDEC 已经建立好的 VRF row、写回通路、ECC raw product 存储方式，以及 HPERM 产生的 512-bit square 布局。也就是说，ECC 最重的非线性乘法继续复用 popcount；线性的模约减用最小 XOR fold 补齐有限域闭包。

## 4. RTL 变化

主要修改：

- `core/hdec/rtl/hdec_pkg.sv`
  - 新增 `HDEC_ECC_REDUCE = 4'd15`。
  - 新增 `F3_ECC_REDUCE = 3'b111`。
  - 指令表从 15 条扩展到 16 条。
- `core/hdec/rtl/hdec_cvxif_wrapper.sv`
  - 补齐 `ECC_ADD / ECC_ALIGN / ECC_REDUCE` decode。
  - 补齐 perf op name。
- `core/hdec/rtl/hdec_top.sv`
  - 新增 `ecc_reduce233()` 固定约减函数。
  - 新增 `S_ECC_REDUCE_LOAD_LO_WAIT / LOAD_LO / LOAD_HI_WAIT / WRITE` 状态。
  - REDUCE 操作数编码：`dst = rs1[17:12]`，raw product 源基地址 `src = rs1[5:0]`，读取 `src` 和 `src+1` 两个 row。
  - `src=63` 被拒绝，避免读取 `src+1` 溢出。
  - `HSPREAD` 输出改为标准 512-bit square layout，并缓存源 row，修正非 0 源行时第二拍可能读错的问题。
- `verif/hdec/tb_hdec_hperm_bit_align.sv`
  - 更新 `HSPREAD` 期望布局。
- `verif/hdec/tb_hdec_ecc_reduce_v1.sv`
  - 新增 REDUCE 功能测试。
- `scripts/hdec/xsim_hdec_ecc_reduce_v1.tcl`
  - 新增 REDUCE xsim 脚本。

## 5. 验证

Vivado 2022.2 xsim 回归：

| Test | Result |
|---|---:|
| `tb_hdec_ecc_add_v1` | PASS |
| `tb_hdec_ecc_align_v1` | PASS |
| `tb_hdec_ecc_diag_mul_v1` | PASS |
| `tb_hdec_ecc_reduce_v1` | PASS |
| `tb_hdec_hperm_bit_align` | PASS |
| `tb_hdec_hmatch_compare_split` | PASS |

`tb_hdec_ecc_reduce_v1` 覆盖：

- 直接 512-bit product REDUCE。
- `ECC_MUL raw -> ECC_REDUCE`，结果对比慢速 GF(2^233) golden model。
- `HSPREAD square -> ECC_REDUCE`，结果对比慢速平方加约减 golden model。
- `src=63` 非法源基地址检查。

归档日志：

- `xsim_ecc_reduce_v1.log`
- `xsim_hperm_bit_align.log`
- `xsim_ecc_diag_mul_v1.log`
- `xsim_ecc_add_v1.log`
- `xsim_ecc_align_v1.log`
- `xsim_hmatch_compare_split.log`

## 6. OOC PPA

工具和约束：

- Vivado 2022.2
- Part: `xc7z020clg400-2`
- Top: `hdec_top`
- OOC clock: `5.000 ns`

| Version | Main change | WNS ns | Fmax est MHz | Slice LUT | Logic LUT | LUTRAM | FF | Worst path |
|---|---|---:|---:|---:|---:|---:|---:|---|
| V12 baseline | shared ops before REDUCE | 0.200 | 208.333 | 5581 | 5109 | 472 | 2030 | HDC lane result capture |
| V13 round01 | add REDUCE, old HSPREAD layout | 0.193 | 208.030 | 5772 | 5300 | 472 | 2021 | HDC lane result capture |
| V13 round03 | canonical HSPREAD + source cache | 0.141 | 205.804 | 5790 | 5318 | 472 | 2035 | HDC lane result capture |

增量：

| Compare | LUT delta | Logic LUT delta | LUTRAM delta | FF delta | Fmax delta |
|---|---:|---:|---:|---:|---:|
| V13 round03 - V12 | +209 | +209 | 0 | +5 | -2.529 MHz |
| V13 round03 - V13 round01 | +18 | +18 | 0 | +14 | -2.226 MHz |

观察：

- REDUCE 和 HSPREAD 修正没有增加 LUTRAM、BRAM、DSP。
- FF 几乎不变，因为 REDUCE 复用了已有 `hdc_src0_q` 暂存，没新增 512-bit shadow register。
- 前 200 条 worst timing paths 全部是 `P2 lane result capture`，不是 ECC fold，也不是 REDUCE。
- 当前 200 MHz 余量仍有 `0.141 ns`，满足本轮底线。

归档 OOC 文件：

- `v12_baseline_run_summary.txt`
- `v12_baseline_utilization.rpt`
- `v13_reduce_round01_run_summary.txt`
- `v13_reduce_round01_utilization.rpt`
- `v13_reduce_round03_run_summary.txt`
- `v13_reduce_round03_utilization.rpt`
- `v13_reduce_round03_timing_top200.csv`

## 7. 当前边界和下一步

已经完成的底层闭包：

- GF add: `ECC_ADD`
- raw GF multiply: `ECC_MUL`
- raw square: `HSPREAD`
- modular reduction: `ECC_REDUCE`
- GF multiply composition: `ECC_MUL -> ECC_REDUCE`
- GF square composition: `HSPREAD -> ECC_REDUCE`

还没完成：

- 一个单指令 `GF_MUL` wrapper，把 raw multiply 和 reduce 自动串起来。
- 一个单指令 `GF_SQR` wrapper，把 HSPREAD 和 reduce 自动串起来。
- ITA inversion / point add / point double / scalar point multiplication 控制。
- 常数时间调度策略和 HDC/ECC 并发仲裁。

建议下一步不要急着做完整点乘，而是先加两个薄 wrapper：

1. `HDEC_ECC_GFMUL`: 内部执行 `ECC_MUL raw -> ECC_REDUCE`。
2. `HDEC_ECC_GFSQR`: 内部执行 `HSPREAD -> ECC_REDUCE`。

这样上层 ITA 和点运算可以只面对闭合的 `GF(2^233)` 运算，底层仍然保留“乘法复用 popcount、平方复用 HPERM、约减用最小 XOR fold”的清楚故事。
