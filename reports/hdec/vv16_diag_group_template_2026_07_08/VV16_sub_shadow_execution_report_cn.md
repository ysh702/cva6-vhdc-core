# VV16 sub-shadow diagonal folding execution report

## 当前结论

VV16 当前保留的版本不是 scalar leading-zero skip，也不是 K=0/bit=0 跳过版本。它仍然执行固定 233-bit scalar schedule，保持点乘控制流不依赖 scalar 稀疏性。

当前保留版本是：

```text
diagonal group capture
-> sub 完成时生成固定 sub32 leaf-delta token
-> 在下一段 diagonal capture / leaf-fold 空档用已有 leaf reducer 折叠
-> 通过既有 XOR0 accumulator 累加 reduced packet
```

它比 VV15/VV16 初始版本更接近主线，因为 modular folding 已经从 leaf 结束后的独立 drain，推进到 sub 完成边界，并且与下一段 diagonal capture 发生重叠。但它仍然不是最终的 group-pair/diagonal-pair 并行结构；真正占周期主体的 diagonal capture 还没有被压缩。

## 保留版本指标

基线参照：

```text
VV15 fulltext-plan baseline: PMUL 339100, Logic LUT 4655, FF 1422, Fmax 207.297 MHz
VV16 pushed checkpoint 6b6f548b: PMUL 315340, Logic LUT 4678, FF 1426, Fmax 207.297 MHz
```

当前保留版本：

```text
PMUL wall cycles : 305836
Logic LUT        : 4718
FF               : 1426
BRAM             : 4
DSP              : 0
Fmax estimate    : 207.297 MHz
WNS              : 0.176 ns
```

相对 VV15：

```text
cycles: -33264
Logic LUT: +63
FF: +4
Fmax: unchanged
```

相对 VV16 pushed checkpoint：

```text
cycles: -9504
Logic LUT: +40
FF: unchanged
Fmax: unchanged
```

这版略高于 4700 Logic LUT 的旧硬门槛，但仍在“小于 100 LUT 换真实 diagonal/sub-level overlap”的用户容忍范围内。它比直接 group-level folding 的面积小很多，也没有牺牲 Fmax。

## 周期占比

修正 `tb_hdec_ecc_pmul_profile_v27` 的状态枚举后，当前版本的真实 PMUL breakdown 是：

```text
PMUL_PROFILE_WALL_CYCLES          = 305836
PMUL_PROFILE_GF_MUL_STARTS        = 1188
PMUL_PROFILE_ST_ECC_LOAD_CYCLES   = 4752
PMUL_PROFILE_ST_ECC_DIAG_CYCLES   = 267300
PMUL_PROFILE_ST_ECC_LEAF_FOLD_CYCLES = 10692
PMUL_PROFILE_ST_ECC_WRITE_PAIR_CYCLES = 1188
PMUL_PROFILE_ST_ECC_WRITE_DRAIN_CYCLES = 1633
PMUL_PROFILE_ST_ECC_REDUCE_CYCLES = 0
PMUL_PROFILE_SUB_ZERO_CYCLES      = 0
```

这说明当前最值得继续优化的不是 leaf-fold drain，而是 diagonal capture 主体。leaf-fold 已经被压到约 1.07 万周期；diagonal capture 仍然约 26.73 万周期，约占总 PMUL 的 87%。所以进入 10W-20W 周期区间，必须减少 capture 次数、减少 issue/capture 泡泡，或让一次 capture 产生更多有效 modular contribution。

## RTL 方法

当前版本在 `core/hdec/rtl/hdec_top.sv` 中做了三件事。

第一，加入固定 sub32 delta template：

```text
sub0: {0, hi, hi ^ lo, lo}
sub1: {hi, hi ^ lo, lo, 0}
sub2: {0, hi, lo, 0}
```

这避免了 VV14-1 那类 `path/sub/group/parity_row` 全动态 group packet 在主综合路径里展开。综合路径只保留小模板和既有 leaf reducer。

第二，使用 sub-shadow schedule：

```text
group7/sub0: capture sub0 delta
group7/sub1: XOR0 folds previous sub0 delta while capture sub1 delta
group7/sub2: XOR0 folds previous sub1 delta while capture sub2 delta and prefetch next leaf A
S_ECC_LEAF_FOLD: XOR0 folds sub2 delta and captures next leaf B
```

这样将 sub folding 与 diagonal capture 边界重叠，但不新增第二套 reducer 或 accumulator。

第三，保留 group-level direct reduce helper 作为验证专用函数：

```text
ecc_kpd64_diag_group_leaf_delta
ecc_kpd64_diag_reduce_packet
ecc_kpd64_diag_group_reduce_packet
```

它们被 `synthesis translate_off/on` 包住，仍可被 `diag_reduce_map` 验证使用，但不会进入主综合面积。

## 为什么面积能控制住

保留版本没有采用“每个 group 直接生成完整 reduced packet”的大动态组合逻辑。它只新增：

```text
sub32_delta fixed template
少量 shadow-control 条件
下一 leaf A/B 的有限提前读调度
```

实际 reduced packet 仍由原来的 `ecc_kpd64_leaf_reduce_packet` 产生，GF(2) 累加仍走 `XOR0`。这保持了 HDC/ECC 共享 bit-matrix 与 XOR0 的故事，而不是在 ECC 旁边新增一块独立折叠单元。

## 被拒绝的试验

| 试验 | PMUL | Logic LUT | Fmax MHz | 结论 |
|---|---:|---:|---:|---|
| full group-level dynamic reduce | 304648 | 6069 | 188.822 | 面积和时序都不可接受，证明通用动态 group packet 不是低面积路线 |
| sub-completion direct combinational reduce | 304648 | 5559 | 211.909 | 功能正确但面积过大，仍是“大 reducer” |
| sub-shadow group0 consumption | 305836 | 4856 -> 4781 | 207.297 | 思路正确但 group0 条件和 token 选择偏贵 |
| sub-shadow group7 consumption | 305836 | 4718 | 207.297 | 当前保留版本 |
| condition slim | 305836 | 4765 | 207.297 | 看似简化，综合结果变差，回退 |
| row-wise sub32_delta template | 305836 | 4720 | 207.297 | 比当前多 2 LUT，回退 |
| sub32_delta default `'x` | 305836 | 4783 | 207.297 | 不利于综合，回退 |
| leaf-fold next group0 issue | 296332 | 4677 | 175.562 | 周期和面积很好，但 VRF -> payload 时序失败，不能保留 |
| registered A/B next issue | 296332 | 4938 | 207.297 | 修复时序但面积超标，不能保留 |
| staged A/B next issue | 296332 | 5009 | 214.041 | 时序更好但面积和 FF 代价过高，不能保留 |

`leaf-fold next group0 issue` 是值得后续继续研究的方向，因为它能再省 9504 cycles；但当前低面积版本时序失败，时序安全版本又明显涨面积，所以不能作为 VV16 checkpoint。

## 功能与 OOC 验证

最终保留版本通过以下回归：

```text
xsim_hdec_ecc_pmul_profile_v27 : PASS, PMUL 305836
xsim_hdec_ecc_diag_reduce_map_v1 : PASS
xsim_hdec_ecc_reduce_v1 : PASS
xsim_hdec_ecc_add_v1 : PASS
xsim_hdec_hdc_full_flow_v20 : PASS
OOC hdec_top @ 5 ns : PASS, Logic LUT 4718, Fmax 207.297 MHz
```

关键证据路径：

```text
reports/hdec/vv16_diag_group_template_2026_07_08/xsim_pmul_final_recheck_v1/xsim_ecc_pmul_profile_v27/xsim.log
reports/hdec/vv16_diag_group_template_2026_07_08/ooc_final_recheck_v1/reports/utilization.rpt
reports/hdec/vv16_diag_group_template_2026_07_08/ooc_final_recheck_v1/reports/run_summary.txt
reports/hdec/vv16_diag_group_template_2026_07_08/xsim_diag_reduce_map_final_v1/xsim_ecc_diag_reduce_map_v1/xsim.log
reports/hdec/vv16_diag_group_template_2026_07_08/xsim_reduce_final_v1/xsim_ecc_reduce_v1/xsim.log
reports/hdec/vv16_diag_group_template_2026_07_08/xsim_add_final_v1/xsim_ecc_add_v1/xsim.log
reports/hdec/vv16_diag_group_template_2026_07_08/xsim_hdc_full_final_v1/xsim_hdc_full_flow_v20/xsim.log
```

## 下一步判断

用户提出的判断是正确的：主线应该继续是斜线级/diagonal-group 级边算边模，而不是绕到 scalar skip 或单纯加倍硬件。

当前数据说明：

```text
leaf-fold drain 已经不再是最大头
diagonal capture 仍然是最大头
直接动态 group folding 面积不可接受
单纯提前 issue 下一 group 有真实周期收益，但低面积版本时序失败
```

因此 VV17/VV16 后续最值得推进的方向应该是：

1. 做真正 finite-template group-pair，而不是通用 group reducer。
2. 只允许固定 path/sub/group 小模板，不允许 `path/sub/group/parity_row` 全动态 packet 进入主综合路径。
3. 优先尝试让一次 bit-matrix capture 产生两个相邻 group 的可折叠 token，但共享同一套 row/parity/XOR0，不复制完整 bit-matrix。
4. 重新研究 `leaf-fold next group0 issue` 的低面积 retime：它的周期收益明确，但必须避免 VRF -> bitrev/lowxor -> bitband -> payload 的长路径。
5. 保持固定 233-bit scalar schedule，不做 K=0 或 scalar leading-zero skip。

下一轮的接受标准应是：

```text
功能回归全部 PASS
PMUL cycles 明确下降
Logic LUT 不超过当前 4718，或小幅超过但换来 10k+ 真实周期下降
Fmax >= 200 MHz
不新增独立 ECC reducer/accumulator
不破坏 HDC/ECC 共享 bit-matrix 与 XOR0 复用故事
```
