# V37 Vivado 2024.2 三种 V36 优化方向复测

日期：2026-06-15

分支：`hdec-ecc-pointmul-v37`

基线：`4193f204 hdec: select V35 5M point-add optimization`

工具：

- 仿真：`scripts/hdec/xsim_hdec_ecc_pmul_profile_v27.tcl`
- OOC：`scripts/hdec/run_ooc_200.ps1`
- Vivado：2024.2
- 器件：`xc7z020clg400-2`
- 约束：5.000 ns

流程说明：

每个 plan 都从 V35 RTL 基线开始：

1. 回退 `core/hdec/rtl/hdec_top.sv` 到 V35。
2. 临时应用远程 V36 中对应 plan 的 RTL diff。
3. 跑 PMUL profile 仿真，记录完整标量点乘周期和内部计数。
4. 跑 Vivado 2024.2 OOC，记录面积和时序。
5. 回退到 V35 RTL，再进入下一个 plan。

本报告记录结果；当前工作区 RTL 已回到 V35 基线。

## V35 / V36 参考基线

| 项目 | Vivado | 周期 | Logic LUT | Slice LUT | LUTRAM | FF | WNS(ns) | Fmax(MHz) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| V35 基线 | 2024.2 | 341624 | 5921 | 6393 | 472 | 1802 | 0.243 | 210.217 |
| V36 文档基线 | 2022.2 | 341624 | 6035 | 6507 | 472 | 1807 | -0.059 | 197.668 |

## 三个 plan 的 2024.2 实测

| 方案 | 仿真 | 周期 | 比 V35 少 | Logic LUT | 比 V35 多 | Slice LUT | FF | WNS(ns) | Fmax(MHz) | 判断 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Plan1 leaf compute/fold overlap | PASS | 310346 | 31278 | 6134 | 213 | 6606 | 1865 | -1.297 | 158.806 | reject |
| Plan2 tail bypass | PASS | 309143 | 32481 | 6051 | 130 | 6523 | 1806 | 0.247 | 210.393 | accept candidate |
| Plan3 KPD64 64-bit leaf | PASS | 190046 | 151578 | 6677 | 756 | 7149 | 1951 | -0.063 | 197.511 | fast but timing-open |

内部周期拆分：

| 方案 | SUB_ADD | ST_ECC_DIAG | ST_ECC_LEAF_FOLD |
|---|---:|---:|---:|
| V35 基线 | 309657 | 162405 | 129924 |
| Plan1 | 279367 | 131127 | 129924 |
| Plan2 | 278202 | 162405 | 97443 |
| Plan3 | 162867 | 97443 | 43308 |

## 与 V36 2022.2 结果对比

| 方案 | Vivado | 周期 | Logic LUT | 相对各自基线 | FF | WNS(ns) | 备注 |
|---|---:|---:|---:|---:|---:|---:|---|
| Plan1 | 2022.2 | 310346 | 6221 | +186 | 1871 | -1.318 | V36 文档 |
| Plan1 | 2024.2 | 310346 | 6134 | +213 | 1865 | -1.297 | 时序仍严重失败 |
| Plan2 | 2022.2 | 309143 | 6892 | +857 | 1808 | -0.061 | V36 文档 |
| Plan2 | 2024.2 | 309143 | 6051 | +130 | 1806 | 0.247 | 2024.2 下明显变好 |
| Plan3 | 2022.2 | 190046 | 6612 | +577 | 1953 | -0.054 | V36 文档 |
| Plan3 | 2024.2 | 190046 | 6677 | +756 | 1951 | -0.063 | 周期不变，时序仍差一点 |

说明：

- 周期是 RTL 行为决定的，所以 V36 2022.2 和 V37 2024.2 的三个 plan 周期一致。
- 面积 delta 用各自工具版本下的基线计算。2024.2 的 V35 基线 Logic LUT 更低，所以 Plan3 的相对增量显得更大。
- Plan2 是这轮最重要的发现：同样 RTL 在 2022.2 下看起来是大面积方案，在 2024.2 下变成只多 130 个 Logic LUT、并且 OOC 过 5ns。

## 额外 2024.2 优化尝试

针对 Plan3 的 -0.063 ns 小负时序，尝试过 leaf operand fanout 约束：

| 尝试 | 周期 | Logic LUT | 比 V35 多 | FF | WNS(ns) | 结果 |
|---|---:|---:|---:|---:|---:|---|
| Plan3 原版 | 190046 | 6677 | 756 | 1951 | -0.063 | 保留为原始实测 |
| Plan3 `ecc_leaf_a_q/ecc_leaf_b_q max_fanout=16` | 190046 | 7055 | 1134 | 2014 | 0.026 | reject，面积过高 |
| Plan3 only `ecc_leaf_b_q max_fanout=32` | 190046 | 6716 | 795 | 1949 | -0.430 | reject，时序更差 |

这个方向说明：Plan3 的 2024.2 时序可以靠寄存器复制硬推过，但代价会明显放大，不符合“小面积大收益”的目标。原版 Plan3 只差 0.063 ns，后续更适合从 diagonal parity 结构或调度边界下手，而不是靠粗暴 fanout 约束。

## 结论

1. 当前最值得保留为 V37 候选 RTL 的是 Plan2 tail bypass。
   它在 2024.2 下只增加 130 个 Logic LUT，却减少 32481 个 PMUL 周期，且 WNS 从 V35 的 0.243 ns 变为 0.247 ns，没有时序惩罚。

2. Plan3 KPD64 是最快方案。
   它把 PMUL 周期从 341624 降到 190046，减少 151578 周期。但 2024.2 OOC 下 Logic LUT 增加 756，WNS 为 -0.063 ns，暂时不能作为干净收敛版本。

3. Plan1 不建议继续作为独立方向。
   它减少 31278 周期，但增加 213 个 Logic LUT，并且 WNS 为 -1.297 ns。Plan2 周期更好、面积更小、时序还通过，所以 Plan1 在这轮比较中被 Plan2 全面压过。

4. 针对“低面积大周期收益”的目标，2024.2 下的新优先级建议是：
   `Plan2 tail bypass` 先进入候选；`Plan3 KPD64` 继续做时序/面积局部优化；`Plan1 overlap` 暂停。

原始报告路径：

- V35 基线：`reports/hdec/v35_selected_5m_final_2026_06_15`
- Plan1：`reports/hdec/v37_plan1_fold_overlap_2026_06_15`
- Plan2：`reports/hdec/v37_plan2_tail_bypass_2026_06_15`
- Plan3：`reports/hdec/v37_plan3_kpd64_leaf_2026_06_15`
