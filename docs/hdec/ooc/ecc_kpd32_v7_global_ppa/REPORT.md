# HDEC ECC KPD32 V7 全局 PPA 优化报告

日期：2026-06-09

## 范围

分支：
- `hdec-ecc-kpd32-v7-global-ppa`

基线：
- `hdec-ecc-kpd32-v6-ppa`

综合环境：

| 项目 | 值 |
|---|---|
| Vivado | 2024.2 |
| FPGA part | `xc7z020clg400-2` |
| Top | `hdec_top` |
| OOC clock | 5.000 ns / 200 MHz |

## V7 保留的改动

1. KPD32 leaf fold 从每拍折叠 1 个 64-bit word，改成每拍折叠 2 个相邻 64-bit word。
   - ECC_MUL 周期从 529 降到 421。
   - 仍然不增加 leaf 并行硬件，只是把原来过慢的串行 fold 做得更紧凑。

2. KPD32 leaf decode 做成共享线网。
   - `leaf_path` 和 `leaf_offset_mask` 不在多个函数调用处重复展开。
   - OOC PPA 与 round01 相同，但语义更规整，便于后续继续改。

3. `hdec_lane_4x64` 去掉已经不用的 legacy shell FSM/寄存器。
   - lane shell 现在只保留实际仍在使用的 Boolean、counter、shift、clip 组合计算。
   - 不再保留无效的 passthrough 状态和结果寄存器。

## OOC 结果

| 版本 / 轮次 | WNS @200MHz | Worst delay | 估算 Fmax | Slice LUT | Logic LUT | LUTRAM | FF | BRAM | DSP | CARRY4 | ECC_MUL cycles | 结论 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| V6 repro | +0.322 ns | 4.704 ns | 213.767 MHz | 6709 | 6021 | 688 | 3878 | 0 | 0 | 16 | 529 | 基线 |
| round01 pair fold | +0.326 ns | 4.700 ns | 213.950 MHz | 6510 | 5822 | 688 | 3872 | 0 | 0 | 16 | 421 | 保留 |
| round02 shared decode | +0.326 ns | 4.700 ns | 213.950 MHz | 6510 | 5822 | 688 | 3872 | 0 | 0 | 16 | 421 | 保留 |
| round04 lane shell tieoff | +0.254 ns | 4.743 ns | 210.704 MHz | 6458 | 5770 | 688 | 3864 | 0 | 0 | 16 | 421 | V7 最终保留 |

V7 最终相对 V6：

| 指标 | 变化 |
|---|---:|
| WNS | -0.068 ns |
| 估算 Fmax | -3.063 MHz |
| Slice LUT | -251 |
| Logic LUT | -251 |
| LUTRAM | 0 |
| FF | -14 |
| ECC_MUL cycles | -108 |

结论：V7 牺牲了约 3 MHz 余量，但仍超过 200 MHz；同时 LUT 明确下降，ECC 多项式乘法周期也下降。这个版本值得作为 V8 的干净起点。

## 回退的试验

| 轮次 | 结果 | 回退原因 |
|---|---|---|
| round03 lane result/clip CE split | LUT 6512, FF 3872, Fmax 213.402 MHz | Fmax 略低于 round01/02，且关键路径转向 `lane_result_q`，收益不够稳定 |
| round05 VRF init one-bit FSM | LUT 6726, FF 3883, Fmax 205.592 MHz | 面积和时序都明显变差 |

## 功能验证

Vivado xsim 结果：

| 测试 | 结果 |
|---|---|
| `xsim_ecc_diag_mul_v1` | PASS |
| `xsim_ecc_mul_cycle_count_v7_final` | PASS, `ECC_MUL_CYCLES=421` |

## 当前关键路径

V7 最终最差路径：

```text
FSM_onehot_st_q_reg[19] -> lane_result_q_reg[0][55]/D
```

这条路不是 ECC 多项式乘法本体，而是 HDC/P3 控制到 lane result capture 的控制/布线路径。它已经满足 200 MHz，但说明后续 V8 如果继续大幅减少面积，需要特别小心控制信号和 VRF/lane 写回选择逻辑，不能让宽控制重新扩散。

## 下一步 V8 方向

优先尝试：

1. ECC operand streaming：去掉 `ecc_a_q/ecc_b_q` 两个 256-bit 影子寄存器，用 fold 空拍预取下一组 leaf 输入，目标减少约 512 FF，周期不增加，最好还能减少。
2. HDC/uop 控制压缩：减少全宽 uop 在多级流水里的重复保存，改成 stage-local 小标签，目标减少控制 FF 和 mux LUT。
3. ECC product 存储重构：如果前两项后仍有明显 FF 压力，再评估是否把 512-bit product accumulator 拆成更局部的 word-bank 结构。
