# HDEC ECC KPD32 V6 PPA 优化报告

日期：2026-06-09

## 范围

分支：

- `hdec-ecc-kpd32-v6-ppa`

基线：

- `origin/hdec-ecc-kpd32-v5 / 62b7cb12`

目标：

- 200 MHz OOC 是硬底线。
- 在保住 200 MHz 的前提下，优先减少 LUT 和 FF。
- 继续规范 KPD32 的控制和数据结构，避免后续加入 ECC 标量点乘、模约简、ITA 等控制后重新形成宽控制关键路径。
- 保留 V5 的核心算法：Karatsuba + packed diagonal popcount。

综合环境：

| 项目 | 值 |
|---|---|
| Vivado | 2024.2 |
| FPGA part | `xc7z020clg400-2` |
| Top | `hdec_top` |
| OOC clock | 5.000 ns / 200 MHz |

## V3 和 V5 算法差异

V3 是“一次算一条 256-bit 大斜线”：

```text
for k = 0..510:
  构造 product[k] 对应的 256-bit 斜线部分积
  喂给 4 个 64-bit lane 的 popcount
  取 popcount 奇偶性
  得到 1 个 product bit
```

这个方法最直观，也最接近最初的斜线加法想法，但吞吐低：一次 popcount issue 只能得到 1 个 product bit。

V5 改成 KPD32：

```text
256-bit 乘法
  -> 3 层 Karatsuba：256 -> 128 -> 64 -> 32
  -> 27 个 32x32 GF(2) leaf multiply
```

每个 32x32 leaf 仍然用斜线奇偶性计算。关键是粒度刚好匹配 HDEC：

```text
4 lanes * 每 lane 2 个 32-bit half-popcount
= 一拍 8 个 32-bit parity reducer
```

所以 V5 一拍可以打包计算 8 条 32-bit 小斜线。这就是它比 V3 快很多，同时又保留 HDC popcount 复用故事的核心原因。

## 单次乘法周期

新增 cycle-count testbench：

- `verif/hdec/tb_hdec_ecc_mul_cycle_count.sv`
- `scripts/hdec/xsim_hdec_ecc_mul_cycle_count.tcl`

计数范围：一条 `HDEC_ECC_MUL` 从命令被接受到 `valid_o` 返回。三个版本都通过同一个 256-bit x 256-bit raw polynomial product 校验。

| 版本 | 算法 | ECC_MUL cycles | 相对 V3 加速 |
|---|---|---:|---:|
| ECC V3 | 一次一条 256-bit 大斜线 | 1549 | 1.00x |
| ECC KPD32 V5 | Karatsuba + 每拍 8 条 32-bit 小斜线 | 340 | 4.56x |
| ECC KPD32 V6 | V5 算法，但 leaf fold 改成 64-bit word 串行 | 529 | 2.93x |

解释：

- V5 是吞吐优先点。
- V6 为了减少面积，把每个 leaf 的 512-bit 一拍折叠改成 8 个 64-bit word 串行折叠。
- V6 比 V5 慢 189 cycles，但仍然比 V3 快约 2.93 倍。

归档日志：

- `xsim/cycle_count_v3.log`
- `xsim/cycle_count_v5.log`
- `xsim/cycle_count_v6.log`

## V6 保留的 RTL 修改

### 1. pop slice 只寄存 Boolean 结果

V5 在每个 `hdec_p2_pop_slice` 里同时寄存：

```text
src_a_q
src_b_q
```

然后再做 XOR + popcount。

V6 改成只寄存：

```text
bool_result_q = src_a_i ^ src_b_i
```

语义不变，但每个 lane 少一份 64-bit operand 寄存器。

理论节省：

```text
4 lanes * 64 FF = 256 FF
```

OOC 结果基本吻合这个预期。

### 2. KPD32 leaf fold 改成 64-bit word 串行

V5 的 leaf fold 是一拍把一个 64-bit leaf product 通过大 512-bit shift/XOR mask 折叠进 `ecc_product_q`。

V6 改成：

```text
leaf_id -> 15-bit offset mask
fold_word_idx = 0..7
每拍只更新一个 64-bit product word
```

这是明确的面积优先取舍：

- 减少 512-bit 宽组合折叠逻辑；
- ECC 乘法周期增加；
- HDC 主路径不变；
- BRAM/DSP 仍然为 0。

## 回退的 trial

我还试了一个 parity-sideband 版本：让 ECC 在 pop slice 内部直接取 32-bit parity sideband，而不是使用 full popcount 结果的 bit0。

结果如下：

| Trial | WNS | Fmax | LUT | FF | ECC_MUL cycles | 结论 |
|---|---:|---:|---:|---:|---:|---|
| trial01：bool-result + 64-bit fold word | +0.322 ns | 213.767 MHz | 6709 | 3878 | 529 | 保留 |
| trial02：parity sideband | +0.328 ns | 214.041 MHz | 6817 | 3881 | 529 | 回退 |

原因：

- trial02 只多一点点时序余量；
- 但比 trial01 多 108 LUT、3 FF；
- 当前目标是 200 MHz 保底下尽量降面积，所以不保留。

## OOC PPA 对比

| 版本 | WNS @200MHz | Worst delay | 估算 Fmax | Slice LUT | Logic LUT | LUTRAM | FF | BRAM | DSP | CARRY4 | ECC_MUL cycles |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| ECC V3 | +0.069 ns | 4.960 ns | 202.799 MHz | 5476 | 4788 | 688 | 3275 | 0 | 0 | 16 | 1549 |
| ECC KPD32 V5 | +0.232 ns | 4.765 ns | 209.732 MHz | 6946 | 6258 | 688 | 4125 | 0 | 0 | 16 | 340 |
| ECC KPD32 V6 | +0.322 ns | 4.704 ns | 213.767 MHz | 6709 | 6021 | 688 | 3878 | 0 | 0 | 16 | 529 |

V6 相对 V5：

| 项目 | 变化 |
|---|---:|
| WNS | +0.090 ns |
| 估算 Fmax | +4.035 MHz |
| Slice LUT | -237 |
| Logic LUT | -237 |
| LUTRAM | 0 |
| FF | -247 |
| BRAM/DSP | 0 |
| CARRY4 | 0 |
| ECC_MUL cycles | +189 |

## 层次资源变化

| 版本 | top-local LUT | pop slice LUT 合计 | VRF total LUT | top-local FF | pop slice FF 合计 | VRF FF |
|---|---:|---:|---:|---:|---:|---:|
| ECC KPD32 V5 | 1772 | 1493 | 3681 | 3288 | 568 | 269 |
| ECC KPD32 V6 | 1619 | 1721 | 3369 | 3297 | 312 | 269 |
| 变化 | -153 | +228 | -312 | +9 | -256 | 0 |

注意：

- FF 的下降正好发生在 pop slice：568 -> 312，减少 256 FF。
- top-local LUT 降低，说明 512-bit fold 拆成 64-bit word 后，大折叠逻辑确实变轻。
- pop slice 层次下 LUT 反而上升，这是 Vivado 跨层级吸收逻辑后的归因结果；看总量才是准的，总 LUT 下降 237。
- VRF total LUT 也下降 312，说明输入/折叠结构变化对 VRF 周边 mux 有正面影响。

## 时序结果

V6 200 MHz OOC：

| 指标 | 值 |
|---|---:|
| WNS | +0.322 ns |
| Worst data delay | 4.704 ns |
| 估算 Fmax | 213.767 MHz |
| Worst endpoint | `group_dist_q_reg[8]/D` |

当前最差路径：

```text
gen_lane[1].i_p2_pop_slice/popcount_part_q_o_reg[1][0]/C
  -> group_dist_q_reg[8]/D
```

也就是说，V6 没有把 ECC fold 或 512-bit product accumulator 变成关键路径。最差路径仍是正常 HDC popcount 聚合路径，这是可以接受的。

## 验证

Vivado xsim：

| 测试 | 结果 |
|---|---|
| `tb_hdec_ecc_diag_mul_v1` | PASS |
| `tb_hdec_ecc_mul_cycle_count` on V3 | PASS |
| `tb_hdec_ecc_mul_cycle_count` on V5 | PASS |
| `tb_hdec_ecc_mul_cycle_count` on V6 | PASS |

归档日志：

- `xsim/xsim_ecc_diag_mul_v1_v6.log`
- `xsim/cycle_count_v3.log`
- `xsim/cycle_count_v5.log`
- `xsim/cycle_count_v6.log`

## 结论

V6 是比 V5 更适合作为“面积优先后续 ECC 完整实现基线”的版本：

- 保住 200 MHz，并且 Fmax 估算提高到 213.767 MHz；
- 相比 V5 减少 237 LUT、247 FF；
- LUTRAM 不变，BRAM/DSP 仍为 0；
- 保留 KPD32 Karatsuba + diagonal popcount 的核心算法；
- 没有把 ECC fold 推成关键路径；
- ECC 单次 raw 256-bit polynomial multiply 虽然比 V5 慢，但仍比 V3 快约 2.93 倍。

建议：

- 保留 V6 作为面积优先 KPD32 基线。
- 保留 V5 作为吞吐优先参考点。
- 后续加模约简和标量点乘时，优先沿用 V6 这种 word-local / serialized fold 控制风格，不要重新引入一拍 512-bit 大折叠组合锥。
