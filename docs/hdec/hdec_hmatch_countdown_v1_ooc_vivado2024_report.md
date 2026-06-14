# HDEC HMATCH countdown V1 Vivado 2024.2 OOC 综合报告

## 1. 结论摘要

本次对 `ff838841` 完成了 100/125/150/175/200 MHz 五档 OOC 综合，并与
`e0925738` baseline 对比。综合条件保持一致：

- Vivado 2024.2
- FPGA part: `xc7z020clg400-2`
- Top: `hdec_top`
- `synth_design -mode out_of_context`
- 相同 source list、clock constraint 和 synthesis flow

V1 达成了最直接的结构目标：baseline 的
`hsim_total_q -> hmatch_best_dist_q/CE` 6.330 ns 路径在新 netlist 中已经不存在，
`hmatch_budget_q -> HMATCH CE` 仅为 4.110 ns，没有成为新瓶颈。

但整体 PPA 改善很小。150 MHz WNS 仅从 `+0.126 ns` 改善到 `+0.156 ns`，
保守 Fmax 从 152.88 MHz 提升到 153.59 MHz，约 `+0.71 MHz / +0.46%`。
新的 top1 仍属于 HMATCH 更新锥：
`lane_popcnt_q -> hmatch_best_idx_q/CE`，延迟 6.300 ns。P2 capture 紧随其后，
最差延迟 6.432 ns。

资源方面，FF 净增 10，接近预期的 12-bit countdown 代价；但 150 MHz 的
Slice LUT 增加 137（+2.74%），明显高于“几乎不增加 LUT”的预期。综合层级显示
其中约 +48 LUT 位于 `hdec_top` 自身，约 +91 LUT 来自 `i_vrf` 的映射变化，
lane 合计少 2 LUT。该结果在 100/125/150 MHz 重复一致，不宜视为单次随机误差。

**建议：保留该分支作为结构实验和后续优化基础，但暂不替换 `e0925738` 作为
PPA baseline。** 下一版应优先缩短 `lane_popcnt -> update_best -> best_idx/best_dist`
组合锥，并查明 countdown 改写为何扰动 VRF LUT 映射。

## 2. 版本与修改范围

| 项目 | Baseline | Countdown V1 |
|---|---|---|
| Branch | `origin/hdec-p2p3-split-result-payload-v1` | `origin/hdec-hmatch-countdown-v1` |
| Commit | `e09257383f32367a22a4e553237084f827c2b489` | `ff83884189e045e3ab0d45f138479cd6643d62d9` |
| RTL 变化 | - | 仅 `core/hdec/rtl/hdec_top.sv` |
| 功能 | distance accumulator 直接参与 best compare | 新增 12-bit countdown；无 early skip |

综合期间未修改 RTL。分析脚本和所有输出均位于 `E:\HDEC`。

## 3. 资源对比

150 MHz 代表性 netlist：

| Resource | Baseline | Countdown V1 | Delta |
|---|---:|---:|---:|
| Slice LUT | 5004 | 5141 | +137 (+2.74%) |
| Logic LUT | 4316 | 4453 | +137 (+3.17%) |
| LUTRAM | 688 | 688 | 0 |
| FF | 2188 | 2198 | +10 |
| BRAM | 0 | 0 | 0 |
| DSP | 0 | 0 | 0 |
| CARRY4 | 11 | 12 | +1 |
| Control sets | 31 | 33 | +2 |
| Estimated power | 0.131 W | 0.130 W | -0.001 W |

功耗为 synthesis 后 vectorless estimate，`1 mW` 差异低于应当据此做架构判断的精度。

Countdown V1 各频点资源：

| Frequency | Slice LUT | Logic LUT | LUTRAM | FF | CARRY4 |
|---:|---:|---:|---:|---:|---:|
| 100 MHz | 5141 | 4453 | 688 | 2198 | 12 |
| 125 MHz | 5141 | 4453 | 688 | 2198 | 12 |
| 150 MHz | 5141 | 4453 | 688 | 2198 | 12 |
| 175 MHz | 5146 | 4458 | 688 | 2198 | 12 |
| 200 MHz | 5152 | 4464 | 688 | 2198 | 12 |

150 MHz 层级 LUT 变化：

| Hierarchy | Baseline | Countdown V1 | Delta |
|---|---:|---:|---:|
| `hdec_top` own logic | 559 | 607 | +48 |
| Four lane modules | 258 | 256 | -2 |
| `i_vrf` | 4187 | 4278 | +91 |

因此 LUT 增量不只是 12-bit decrementer 本身，还包含较大的 VRF 周边逻辑重映射。

## 4. 频率扫描

| Freq | Baseline WNS | New WNS | Baseline TNS / fail | New TNS / fail | Baseline top1 delay | New top1 delay | Est. Fmax baseline/new |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 100 MHz | +3.359 | +3.489 | 0 / 0 | 0 / 0 | 6.430 | 6.300 | 150.58 / 153.59 MHz |
| 125 MHz | +1.359 | +1.489 | 0 / 0 | 0 / 0 | 6.430 | 6.300 | 150.58 / 153.59 MHz |
| 150 MHz | +0.126 | +0.156 | 0 / 0 | 0 / 0 | 6.330 | 6.300 | 152.88 / 153.59 MHz |
| 175 MHz | -0.827 | -0.783 | -25.291 / 35 | -30.090 / 46 | 6.330 | 6.286 | 152.88 / 153.92 MHz |
| 200 MHz | -1.541 | -1.497 | -121.613 / 758 | -83.902 / 566 | 6.330 | 6.286 | 152.88 / 153.92 MHz |

新版本 top1：

- 100/125/150 MHz: `lane_popcnt_q_reg[3][4]/C -> hmatch_best_idx_q_reg[0]/CE`
- 175/200 MHz: `lane_popcnt_q_reg[3][2]/C -> hmatch_best_idx_q_reg[0]/CE`
- 150 MHz: logic 2.541 ns，route 3.759 ns，route ratio 59.67%，9 levels，3 个 CARRY4
- 175/200 MHz: logic 2.698 ns，route 3.588 ns，11 levels，4 个 CARRY4

200 MHz 的 failing endpoints 明显减少，但 175 MHz 的 TNS 和 failing endpoints
略差；这说明改善主要集中在最差尾部，不是整个负 slack 分布一致改善。

## 5. 固定路径对比

以下均为 150 MHz synthesis netlist：

| 固定路径 | Baseline delay | Countdown V1 delay | 结论 |
|---|---:|---:|---|
| `hsim_total_q -> hmatch_best_dist_q/CE` | 6.330 ns | No path | 原始核心 CE 路径已消除 |
| `hmatch_budget_q -> HMATCH best CE` | N/A | 4.110 ns | 新 budget 控制不是瓶颈 |
| `hsim_total_q -> hmatch_best_dist_q/D` | 4.797 ns | 2.657 ns | 明显缩短 2.140 ns |
| `lane_popcnt_q -> HMATCH best update` | 6.087 ns | 6.300 ns | 变成新 top1，反而增加 0.213 ns |
| Broad P2 control -> `lane_popcnt_q` | 6.439 ns | 6.432 ns | 基本不变；实际最差起点为 `use_xor` |
| Exact `use_popcount -> lane_popcnt_q` | 5.264 ns | 5.829 ns | 增加 0.565 ns，但仍非 top1 |
| VRF registered read/forward | 5.143 ns | 未进入 top200 | 新 top200 截止为 4.698 ns，故该类路径不高于 4.698 ns |
| VRF write mux/control -> RAM write | - | 4.698 ns | 新 top200 中占 146 条 |
| `hmatch_budget_q -> hmatch_budget_q` | N/A | 4.208 ns | countdown feedback 有充足余量 |

注意：用户给出的约 6.439 ns “P2 popcount capture”对应 broad `use_*` 查询；
netlist 中其最差起点实际是 `uop_p2_q/use_xor`。严格限定 `use_popcount` 时，
baseline/new 分别为 5.264/5.829 ns。

## 6. Top20 / Top200 path atlas

150 MHz 分类统计：

| Scope | Baseline | Countdown V1 |
|---|---|---|
| Top10 | 10 HMATCH | 8 HMATCH + 2 P2 |
| Top20 | 19 HMATCH + 1 P2 | 8 HMATCH + 12 P2 |
| Top50 | 19 HMATCH + 24 P2 + 7 VRF read | 19 HMATCH + 20 P2 + 11 budget feedback |
| Top200 | 19 HMATCH + 24 P2 + 157 VRF read | 19 HMATCH + 24 P2 + 11 budget feedback + 146 VRF write |

Countdown V1 各类最差路径：

| Path class | Count | Max delay | Worst endpoint | Carry | Route dominated |
|---|---:|---:|---|---|---|
| HMATCH best compare/update | 19 | 6.398 ns | `hmatch_best_idx_q/CE` / `hmatch_best_dist_q/D` | Yes | No |
| P2 lane capture | 24 | 6.432 ns | `lane_popcnt_q/D` | No | Yes, all 24 |
| Budget feedback | 11 | 6.398 ns | `hmatch_budget_q/D` | Yes | No |
| VRF writeback | 146 | 4.698 ns | VRF distributed RAM write input | No | Yes, all 146 |

名次变化说明 HMATCH CE 的集中程度下降：Top10 从 10 条降至 8 条，P2 已进入
Top10；但 Top50/Top200 中 HMATCH update 仍有 19 条，数量没有减少。新增的
11 条 budget feedback 又占据 rank 32-42，延迟 6.389-6.398 ns。

## 7. HMATCH countdown 是否达到目标

逐项判断：

1. **原始 HMATCH CE 是否明显缩短：是。** 6.330 ns 路径被彻底移除。
2. **Budget 是否成为新 CE 瓶颈：否。** Budget-to-CE 只有 4.110 ns。
3. **大比较器是否被削弱：是。** Top1 CARRY4 从 5 个降到 3 个，logic delay
   从 3.206 ns 降到 2.541 ns。
4. **全局 WNS/Fmax 是否明显改善：否。** 150 MHz 仅改善 0.030 ns。
5. **P2 是否成为唯一新 timing wall：尚未。** P2 已进入 Top10，最差 data delay
   甚至为 6.432 ns，但由于 endpoint/setup 差异，其 slack 仍略好于 HMATCH CE。
6. **是否引入更差的新路径：没有超过 baseline top1，但引入了 6.398 ns 的
   budget feedback，并使 lane-popcount-to-update 成为 top1。**
7. **FF 是否符合预期：基本符合。** 净增 10，接近 RTL 12-bit budget 的预期。
8. **LUT 是否符合预期：不符合。** +137 LUT 不能视为“几乎不增加”。

## 8. 建议

1. 暂不把 `ff838841` 提升为新的 PPA baseline；保留分支用于继续迭代。
2. 下一版优先拆解或寄存 `lane_popcnt -> budget_next/update_best -> best_*`，
   而不是继续优化已经只有 4.110 ns 的 budget-to-CE 局部路径。
3. 单独研究 HMATCH best index/dist 的 CE 生成，考虑将 compare result 预注册，
   或把 CE 转成更简单的数据选择，避免同一 carry/compare 锥同时驱动
   `best_idx`、`best_dist` 和 `budget`。
4. 对比综合后的 VRF 逻辑方程，确认 +91 LUT 是跨层级优化重映射还是由新的全局
   控制可达性触发；若不能消除，该面积代价足以抵消当前 0.46% Fmax 收益。
5. 后续固定追踪：
   `lane_popcnt -> best_idx/CE`、`lane_popcnt -> best_dist/D`、
   `lane_popcnt -> budget/D`、`budget -> best/CE`、
   broad P2 control -> `lane_popcnt/D`、exact `use_popcount -> lane_popcnt/D`。

## 9. 原始报告位置

- Countdown V1: `reports/vivado/ooc_hdec_hmatch_countdown_v1_ff838841`
- Baseline atlas: `reports/vivado/ooc_hdec_timing_atlas_e0925738`
- Baseline five-frequency scan:
  `reports/vivado/ooc_hdec_p2_onehot_compare/baseline_e0925738`
- 150 MHz top200 CSV:
  `reports/vivado/ooc_hdec_hmatch_countdown_v1_ff838841/150mhz/top200_paths.csv`

