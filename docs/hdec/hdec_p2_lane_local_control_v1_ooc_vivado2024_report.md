# HDEC P2 Lane-local Control v1 Vivado 2024.2 OOC Synthesis Report

## 1. 分支与版本

- Branch: hdec-p2-lane-local-control-v1
- Commit: a010fdf9
- Base branch: hdec-p2p3-split-result-payload-v1
- Previous OOC baseline: ec561b73
- Vivado version: 2024.2
- Part: xc7z020clg400-2
- Top: hdec_top
- 本地报告目录: reports/vivado/ooc_hdc_hdcu_p2_lane_local_control_v1

## 2. 阶段一 RTL 变化摘要

本次只运行 Vivado OOC 综合和报告分析，没有修改 RTL，也没有修改测试。

- `hdec_uop_t` 中已经没有旧的 `use_xor` / `use_popcount` / `use_counter` / `use_clip` / `use_shift` 控制位。
- `hdec_top` 不再直接生成 lane 的 `bool` / `cnt` / `shift` / `clip` valid 信号。
- 新增的 `hdec_lane_p2_local.sv` 已存在，并由 `hdec_top` 按 lane 实例化。
- lane-local decode 在靠近 `hdec_lane_4x64` 的位置生成本地 lane valid。
- P2 payload capture 使用 `lane_ctrl.capture_kind` 区分 `vec64` / `pop7` / `clip16` 载荷。
- Verilator 20/20 regression 已在此前 Linux/VMware 环境报告为 PASS；本次 Win11 任务没有重新运行 Verilator、Spike、GCC 或其他仿真工具链。

## 3. OOC 方法

- 工具: Vivado 2024.2 on Win11。
- 脚本: `scripts/vivado/ooc_hdec_p2_lane_local_control_v1.tcl`。
- 模式: `synth_design -top hdec_top -part xc7z020clg400-2 -mode out_of_context`。
- Clock sweep: 100 / 125 / 150 / 175 / 200 MHz。
- 每个频率输出:
  - `timing_summary.rpt`
  - `critical_paths.rpt`
  - `utilization.rpt`
  - `power.rpt`
  - `high_fanout_nets.rpt`
  - `control_sets.rpt`

Vivado 报告了 OOC 模式常见警告: `clk_i` 没有设置 `HD.CLK_SRC`，因此 clock delay/skew 属于 OOC 估算。

## 4. Timing Summary

| Target Frequency | Period | WNS | TNS | Failing Endpoints | Result |
|---|---:|---:|---:|---:|---|
| 100 MHz | 10.000 ns | +2.968 ns | 0.000 ns | 0 | PASS |
| 125 MHz | 8.000 ns | +0.968 ns | 0.000 ns | 0 | PASS |
| 150 MHz | 6.667 ns | -0.365 ns | -1.748 ns | 8 | FAIL |
| 175 MHz | 5.714 ns | -1.318 ns | -32.324 ns | 39 | FAIL |
| 200 MHz | 5.000 ns | -2.032 ns | -202.679 ns | 905 | FAIL |

Estimated Fmax 约为 142.2 MHz。计算方式采用重复出现的最差路径零 slack 周期:

`6.667 ns - (-0.365 ns) = 7.032 ns`，因此 `1000 / 7.032 = 142.2 MHz`。

## 5. Utilization

下面使用 150 MHz 综合结果作为与 baseline 对比的资源数据。

| Resource | Usage |
|---|---:|
| LUT | 5038 |
| Logic LUT | 4350 |
| LUTRAM | 688 |
| FF | 2203 |
| BRAM | 0 |
| DSP | 0 |
| CARRY4 | 11 |
| CARRY8 | 0 |

100 / 125 / 150 MHz 的资源基本一致。175 / 200 MHz 下 Vivado 为更紧时序目标使用了略多 LUT，但 FF、LUTRAM、BRAM、DSP 和 CARRY4 保持不变。

## 6. Power

Power 为综合后 vector-less 估算，Vivado confidence level 为 Medium。

| Target Frequency | Total Power | Dynamic Power |
|---|---:|---:|
| 100 MHz | 0.123 W | 0.020 W |
| 125 MHz | 0.128 W | 0.026 W |
| 150 MHz | 0.134 W | 0.031 W |
| 175 MHz | 0.139 W | 0.036 W |
| 200 MHz | 0.144 W | 0.041 W |

## 7. Critical Path Analysis

150 MHz 下的最差路径:

- Startpoint: `uop_p2_q_reg[lane_ctrl][op][1]/C`
- Endpoint: `lane_popcnt_q_reg[1][4]/D`
- Data path delay: 7.029 ns
- Logic delay: 1.440 ns
- Route delay: 5.589 ns
- Route ratio: 79.5%
- Logic levels: 8 (`LUT2=1`, `LUT3=1`, `LUT4=1`, `LUT5=2`, `LUT6=3`)
- 150 MHz slack: -0.365 ns

上一版显式最差路径 `FSM_onehot_st_q_reg[6] / S_UOP_P2_LANE -> lane_popcnt_q_reg[0][4]` 不再是 Vivado 2024.2 报告的最差路径。当前 endpoint 仍然是 `lane_popcnt_q` capture register，但 startpoint 已经从 TOP FSM one-hot state bit 变为 `uop_p2_q_reg[lane_ctrl][op][1]`。

这说明阶段一 lane-local control 的改动确实把直接的 FSM state -> lane_popcnt 最差路径移走了，方向与设计目标一致。不过，新的瓶颈仍然落在 P2 lane control 到 popcount capture 的组合锥上。route delay 占比约 79.5%，路径仍然明显受布线估算主导。

## 8. High Fanout Analysis

150 MHz 下 fanout 大于 50 的高扇出信号:

| Net | Fanout | Driver Type |
|---|---:|---|
| `i_vrf/rst_ni_0` | 2203 | LUT1 |
| `i_vrf/lane_result_q[3][63]_i_14_n_0` | 328 | LUT2 |
| `i_vrf/p_0_in__0[0]` | 287 | FDCE |
| `i_vrf/init_state_q[0]` | 282 | FDCE |
| `uop_p3_q_reg[subgroup_idx_n_0_][0]` | 277 | FDCE |
| `i_vrf/lane_result_q[3][63]_i_7_n_0` | 272 | LUT2 |
| `i_vrf/uop_p1_q_reg[op_type][1]` | 262 | LUT4 |
| `lane_result_n` | 256 | LUT4 |
| `hcntadd_hv_n` | 256 | LUT4 |
| `src0_n` | 256 | LUT4 |

reset 仍然是最大扇出信号。高扇出列表中没有 TOP FSM state 成为主导项；但 150 MHz 关键路径显示 `uop_p2_q_reg[lane_ctrl][op][1]` 先驱动 fanout 161 的网络再进入 popcount cone，因此 lane control fanout 仍然值得关注，即使它没有进入 `report_high_fanout_nets` 的 top-10 列表。

`report_control_sets` 显示 total control sets 为 31。

## 9. Comparison with ec561b73

旧 baseline 使用 Vivado 2022.2，本次使用 Vivado 2024.2。下面对比主要用于观察趋势，不能把全部变化绝对归因于 RTL。

| Metric | ec561b73 split-path baseline | a010fdf9 p2-lane-local | Change |
|---|---:|---:|---:|
| Fmax | ~143.3 MHz | ~142.2 MHz | -1.1 MHz |
| WNS @150MHz | -0.312 ns | -0.365 ns | -0.053 ns |
| WNS @200MHz | -1.979 ns | -2.032 ns | -0.053 ns |
| LUT | 4709 | 5038 | +329 |
| Logic LUT | 4021 | 4350 | +329 |
| LUTRAM | 688 | 688 | 0 |
| FF | 2177 | 2203 | +26 |
| CARRY4 | 13 | 11 | -2 |
| Critical path | `FSM_onehot_st_q_reg[6] -> lane_popcnt_q_reg[0][4]` | `uop_p2_q_reg[lane_ctrl][op][1] -> lane_popcnt_q_reg[1][4]` | FSM state source 被移除，但 popcount capture 仍关键 |

相对 2022.2 baseline，本次 2024.2 OOC timing 基本持平但略差。lane-local decode 让最差路径 startpoint 离开 FSM one-hot state bit，但没有改善 150 MHz WNS。资源增长幅度中等: LUT +329，FF +26，LUTRAM 不变，没有引入 BRAM/DSP，CARRY4 减少 2 个。

## 10. Conclusion

1. 阶段一在本次 Vivado 2024.2 OOC 结果中没有改善总体 timing；150 MHz WNS 为 -0.365 ns，旧 baseline 为 -0.312 ns。
2. 当前综合 OOC 结果没有达到 150 MHz；100 MHz 和 125 MHz PASS。
3. 175 MHz / 200 MHz 尚未接近收敛，WNS 分别为 -1.318 ns / -2.032 ns。
4. `FSM_onehot_st_q_reg[6] -> lane_popcnt_q` 这条显式关键路径不再存在于最差路径报告中；新的最差路径是 `uop_p2_q_reg[lane_ctrl][op][1] -> lane_popcnt_q_reg[*]`。
5. 下一阶段仍建议继续瘦身 P3/global control 和 lane-control fanout；但当前最直接的证据表明剩余瓶颈在 P2 lane control 驱动的 lane popcount capture cone，且 route delay 仍占约 80%。

本次没有修改 RTL 或测试文件。
