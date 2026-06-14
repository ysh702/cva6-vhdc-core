# HDEC e0925738 Vivado 2024.2 OOC timing profile / path atlas

## 中文结论摘要

本次在 `e0925738` 上完成了 150/175/200 MHz 三档 OOC 综合。每档均包含
200 个唯一 endpoint 的 setup path、19 组 stage path、10 组固定 from-to
path、top-50 high-fanout、control sets 和二级 hierarchical utilization。

1. 当前真正 top1 是
   `hsim_total_q_reg[0]/C -> hmatch_best_dist_q_reg[0]/CE`。150 MHz 下
   WNS 为 +0.126 ns，data delay 6.330 ns，其中 logic 3.206 ns、route
   3.124 ns，包含 5 级 CARRY4。
2. Top10 全部属于 HSIM/HMATCH global compare/update cone。Rank 1-19
   均为 `hmatch_best_dist_q/CE` 或 `hmatch_best_idx_q/CE`。Top50 则包含
   19 条 HMATCH、24 条 P2 popcount capture 和 7 条 VRF read/capture。
3. P2 lane capture 最长为 6.455 ns。固定
   `uop_p2_q/use_popcount -> lane_popcnt_q` 路径为 6.439 ns，route ratio
   为 79.58%，仍然是 6.x ns 路径。
4. 只优化 P2 control 对当前 Fmax 的直接提升为 0，因为 HMATCH CE
   仍会把 Fmax 限制在约 152.88 MHz。HMATCH 修好后，现有 P2 路径会在
   约 155 MHz 立即成为新上限。
5. 当前最值得优化的三类路径依次是：HMATCH best-update CE、P2
   popcount capture、VRF registered read/forwarding。
6. 最严重的 control CE 问题是 11 个 `hmatch_best_dist_q/CE` 和 8 个
   `hmatch_best_idx_q/CE`。`res_q/CE` 最差为 4.806 ns，属于次要问题。
7. arithmetic/carry 问题集中在 HSIM/HMATCH：HMATCH CE 使用 5 级
   CARRY4，HSIM accumulate 和 HMATCH D 路径使用 3 级 CARRY4。
8. route/fanout 问题集中在 P2 popcount capture、VRF read/forward、
   VRF RAM write，以及 `lane_shift_valid`、`uop_p2.use_xor`、`uop_p3_n`
   等高扇出控制。
9. 后续必须固定追踪 P2-to-lane、lane-popcount-to-HSIM、
   HSIM-to-HMATCH D/CE、lane-popcount-to-HMATCH、HMATCH-to-response、
   VRF read-forward 和 VRF RAM write，不能只看新的 top1。
10. 建议先简化 HMATCH CE 生成，因为 HMATCH D 只有 4.797 ns，而 CE
    达到 6.330 ns。若目标是 175 MHz 以上且允许增加一个周期，再考虑
    在 HSIM accumulate 与 HMATCH compare 之间加入 global-finish
    register；但该流水级必须与 P2 popcount route 优化配套，否则 Fmax
    仍会停在约 155 MHz。

完整 top-200 分类表位于
`reports/vivado/ooc_hdec_timing_atlas_e0925738/150mhz/top200_paths.csv`。

## 1. Run configuration

- Date: 2026-06-06
- Branch: `hdec-p2p3-split-result-payload-v1`
- Commit: `e09257383f32367a22a4e553237084f827c2b489`
- Vivado: 2024.2, build 5239630
- Part: `xc7z020clg400-2`
- Top: `hdec_top`
- Mode: `synth_design -mode out_of_context`
- Clock runs: 150, 175, and 200 MHz
- RTL changes: none

The source list, FPGA part, OOC mode, and clock constraint are the same as the
previous baseline runs.

The timing-atlas Tcl is:

`scripts/vivado/ooc_hdec_timing_atlas.tcl`

Raw reports are under:

`reports/vivado/ooc_hdec_timing_atlas_e0925738`

The route delays in this report are Vivado synthesized-netlist estimates. They
are useful for relative profiling, but they are not post-placement/post-route
measurements.

## 2. Global timing summary

| Frequency | WNS | TNS | Failing endpoints | Worst startpoint | Worst endpoint | Data delay |
|---:|---:|---:|---:|---|---|---:|
| 150 MHz | +0.126 ns | 0.000 ns | 0 | `hsim_total_q_reg[0]/C` | `hmatch_best_dist_q_reg[0]/CE` | 6.330 ns |
| 175 MHz | -0.827 ns | -25.291 ns | 35 | `hsim_total_q_reg[0]/C` | `hmatch_best_dist_q_reg[0]/CE` | 6.330 ns |
| 200 MHz | -1.541 ns | -121.613 ns | 758 | `hsim_total_q_reg[0]/C` | `hmatch_best_dist_q_reg[0]/CE` | 6.330 ns |

The path ordering and data delays are stable across all three constraints.
The WNS-derived conservative Fmax is approximately:

`1000 / (6.667 - 0.126) = 152.88 MHz`

## 3. True top path

The current top1 path is:

`hsim_total_q -> current-cycle accumulate/compare -> hmatch_best_dist_q/CE`

At 150 MHz:

| Metric | Value |
|---|---:|
| WNS | +0.126 ns |
| Data delay | 6.330 ns |
| Logic delay | 3.206 ns |
| Route delay | 3.124 ns |
| Route ratio | 49.35% |
| Logic levels | 9 |
| Main cells | `CARRY4=5, LUT3=2, LUT4=1, LUT6=1` |

The same compare result also drives all eight `hmatch_best_idx_q/CE` pins.
Ranks 1 through 19 are therefore the same global HMATCH compare/update cone:

- 11 `hmatch_best_dist_q/CE` endpoints
- 8 `hmatch_best_idx_q/CE` endpoints

The `/D` path to `hmatch_best_dist_q` is shorter at 4.797 ns. The critical
problem is specifically the update decision feeding `/CE`, not the payload D
input.

## 4. Top-200 classification

The complete requested 200-row table is:

`150mhz/top200_paths.csv`

It contains:

| Rank | Path class | Startpoint | Endpoint | Slack | Delay | Logic | Route | Route ratio | Levels | Main cells | Notes |
|---|---|---|---|---:|---:|---:|---:|---:|---:|---|---|

Every row represents a unique endpoint (`-nworst 1`), which avoids filling the
atlas with multiple alternatives for one endpoint.

### 4.1 Class summary

| Path class | Count in top 200 | Maximum delay | Worst endpoint | Contains CARRY4 | Route-dominated |
|---|---:|---:|---|---:|---:|
| P3 HMATCH best compare/update | 19 | 6.330 ns | `hmatch_best_*_q/CE` | 19 | 0 |
| P2 lane capture | 24 | 6.455 ns | `lane_popcnt_q_reg[2][6]/D` | 0 | 24 |
| P1 VRF read/capture | 157 | 5.143 ns | `i_vrf/bank_ra_data_o_reg[*]/D` | 0 | 157 |

Route-dominated means route delay is greater than 50% of data-path delay.

### 4.2 Rank distribution

- Top 10: 10/10 HMATCH compare/update CE paths.
- Ranks 1-19: all HMATCH compare/update CE paths.
- Ranks 20-43: all P2 popcount capture paths.
- Ranks 44-200: registered VRF read/forwarding paths.
- Top 50: 19 HMATCH, 24 P2 capture, and 7 VRF read/capture paths.

Therefore the top10 is completely concentrated in the HSIM/HMATCH global
cone. The top50 is not exclusively global: after the first 19 endpoints, P2
popcount capture immediately becomes the second timing wall.

### 4.3 Representative ranked paths

| Rank range | Class | Startpoint | Endpoint | Delay | Logic | Route | Route ratio | Levels |
|---|---|---|---|---:|---:|---:|---:|---:|
| 1-19 | HMATCH CE | `hsim_total_q_reg[0]/C` | `hmatch_best_dist_q/CE`, `hmatch_best_idx_q/CE` | 6.330 | 3.206 | 3.124 | 49.35% | 9 |
| 20-31 | P2 popcount capture | `FSM_onehot_st_q_reg[6]/C` | `lane_popcnt_q[*][4:6]/D` | 6.455 | 1.295 | 5.160 | 79.94% | 7 |
| 32-35 | P2 popcount capture | `FSM_onehot_st_q_reg[6]/C` | `lane_popcnt_q[*][3]/D` | 5.876 | 1.308 | 4.568 | 77.74% | 7 |
| 36-39 | P2 popcount capture | `FSM_onehot_st_q_reg[6]/C` | `lane_popcnt_q[*][2]/D` | 5.601 | 1.190 | 4.411 | 78.75% | 6 |
| 40-43 | P2 popcount capture | `uop_p2_q_reg[use_popcount]_rep/C` | `lane_popcnt_q[*][1]/D` | 5.264 | 1.105 | 4.159 | 79.01% | 5 |
| 44-200 | VRF read/capture | `FSM_onehot_st_q_reg[7]_rep__4/C` | `i_vrf/bank_ra_data_o_reg[*]/D` | 5.143 | 1.085 | 4.058 | 78.90% | 5 |

## 5. Stage-group path atlas

These are the worst paths from each requested stage group at 150 MHz.

| Group | Startpoint | Endpoint | Delay | Logic | Route | Route ratio | Levels | Main cells |
|---|---|---|---:|---:|---:|---:|---:|---|
| FSM/decode -> P1 | `FSM_onehot_st_q_reg[7]_rep__4/C` | `uop_p1_q_reg[valid]/D` | 1.901 | 0.770 | 1.131 | 59.50% | 2 | `LUT5=2` |
| P1/VRF capture -> P2 | `uop_p1_q_reg[valid]/C` | `uop_p2_q_reg[valid]/D` | 1.455 | 0.665 | 0.790 | 54.30% | 1 | `LUT6=1` |
| P2 -> lane result | `i_vrf/bank_ra_data_o_reg[1][35]/C` | `lane_result_q_reg[2][55]/D` | 3.999 | 1.105 | 2.894 | 72.37% | 5 | `LUT4=1, LUT6=4` |
| P2 -> lane popcount | `uop_p2_q_reg[use_popcount]_rep/C` | `lane_popcnt_q_reg[0][4]/D` | 6.439 | 1.315 | 5.124 | 79.58% | 7 | `LUT4=1, LUT5=2, LUT6=4` |
| P2 -> lane clip | `uop_p2_q_reg[use_shift]/C` | `lane_clip_q_reg[0][0]/CE` | 2.097 | 0.770 | 1.327 | 63.28% | 2 | `LUT2=1, LUT6=1` |
| lane popcount -> HSIM | `lane_popcnt_q_reg[0][0]/C` | `hsim_total_q_reg[7]/D` | 4.554 | 2.291 | 2.263 | 49.69% | 6 | `CARRY4=3, LUT3=3` |
| HSIM -> HSIM | `hsim_total_q_reg[0]/C` | `hsim_total_q_reg[7]/D` | 4.797 | 2.291 | 2.506 | 52.24% | 6 | `CARRY4=3, LUT3=3` |
| HSIM -> HMATCH CE | `hsim_total_q_reg[0]/C` | `hmatch_best_dist_q_reg[0]/CE` | 6.330 | 3.206 | 3.124 | 49.35% | 9 | `CARRY4=5, LUT3=2, LUT4=1, LUT6=1` |
| lane popcount -> HMATCH CE | `lane_popcnt_q_reg[0][0]/C` | `hmatch_best_dist_q_reg[0]/CE` | 6.087 | 3.206 | 2.881 | 47.33% | 9 | `CARRY4=5, LUT3=2, LUT4=1, LUT6=1` |
| HMATCH distance D | `hsim_total_q_reg[0]/C` | `hmatch_best_dist_q_reg[7]/D` | 4.797 | 2.291 | 2.506 | 52.24% | 6 | `CARRY4=3, LUT2=1, LUT3=2` |
| HMATCH distance CE | `hsim_total_q_reg[0]/C` | `hmatch_best_dist_q_reg[0]/CE` | 6.330 | 3.206 | 3.124 | 49.35% | 9 | five CARRY4 stages |
| HMATCH index D | `FSM_onehot_st_q_reg[7]_rep__4/C` | `hmatch_best_idx_q_reg[3]/D` | 1.136 | 0.685 | 0.451 | 39.70% | 1 | `LUT2=1` |
| HMATCH index CE | `hsim_total_q_reg[0]/C` | `hmatch_best_idx_q_reg[0]/CE` | 6.330 | 3.206 | 3.124 | 49.35% | 9 | five CARRY4 stages |
| VRF registered read/forward | `uop_p3_q_reg[op_type][2]/C` | `i_vrf/bank_ra_data_o_reg[0][0]/D` | 5.083 | 1.085 | 3.998 | 78.65% | 5 | `LUT5=3, LUT6=1, RAMD64E=1` |
| VRF RAM write | `uop_p3_q_reg[chunk_idx][1]/C` | `i_vrf/vrf_b1.../DP/I` | 4.625 | 1.085 | 3.540 | 76.54% | 5 | `LUT5=2, LUT6=2, RAMD64E=1` |
| scalar/VRD response | `i_vrf/bank_ra_data_o_reg[2][10]/C` | `res_q_reg[10]/D` | 1.944 | 0.770 | 1.174 | 60.39% | 2 | `LUT2=1, LUT6=1` |
| fast op -> VRF | `op_q_reg[1]/C` | VRF RAM write input | 4.742 | 1.085 | 3.657 | 77.12% | 5 | LUT/RAMD path |
| reset/enable-heavy | `op_q_reg[3]/C` | `FSM_onehot_st_q_reg[0]/CE` | 2.879 | 0.980 | 1.899 | 65.96% | 4 | `LUT2=2, LUT6=2` |

The synthesized netlist does not preserve separate operation-name hierarchy
for VWR64, VRD64, HCLR, and HCNTCLR. The fast-path reports therefore use their
shared architectural registers and VRF/result endpoints:

- VWR64/HCLR/HCNTCLR proxy: `op_q`, `a_q`, `clr_*`, FSM -> VRF RAM write
- VRD64 proxy: VRF registered read -> `res_q`

## 6. Fixed path tracking

The fixed reports ensure that these paths remain visible even after another
path becomes top1.

| Fixed path | 150 MHz slack | 175 MHz slack | 200 MHz slack | Delay | Main diagnosis |
|---|---:|---:|---:|---:|---|
| P2 control -> lane popcount | +0.225 | -0.728 | -1.442 | 6.439 | 79.58% route |
| P2 control -> lane result | +2.741 | +1.788 | +1.074 | 3.923 | 72.34% route |
| P2 control -> lane clip | +4.359 | +3.406 | +2.692 | 2.097 | not limiting |
| HSIM -> HMATCH CE | +0.126 | -0.827 | -1.541 | 6.330 | five CARRY4 stages, current top1 |
| HSIM -> HMATCH D | +1.867 | +0.914 | +0.200 | 4.797 | three CARRY4 stages |
| lane popcount -> HSIM | +2.110 | +1.157 | +0.443 | 4.554 | three CARRY4 stages |
| lane popcount -> HMATCH | +0.369 | -0.584 | -1.298 | 6.087 | five CARRY4 stages |
| HMATCH -> scalar response | +5.202 | +4.249 | +3.535 | 1.462 | not limiting |
| VRF read/forward control | +1.521 | +0.568 | -0.146 | 5.143 | 78.90% route |
| VRF RAM write | +1.692 | +0.739 | +0.025 | 4.625 | 76.54% route |

The P2 control-to-popcount path has not fallen into the 5 ns range. Its worst
fixed path is still 6.439 ns. P2 result and clip capture are already well below
that level.

## 7. Control-enable paths

The top-50 `/CE` report contains:

| Endpoint family | Count |
|---|---:|
| `hmatch_best_dist_q/CE` | 11 |
| `hmatch_best_idx_q/CE` | 8 |
| `res_q/CE` | 31 |

The first 19 CE endpoints are the 6.330 ns HMATCH comparison. The worst
`res_q/CE` path is 4.806 ns with:

- two CARRY4 stages
- seven logic levels
- 59.4% route delay

Other CE paths are not current limiters:

- lane clip CE: 2.097 ns
- FSM/reset/clear-heavy CE: 2.879 ns

The HMATCH best registers have short D paths but long CE paths. This is strong
evidence that update-enable generation should be examined before widening or
duplicating the payload datapath.

## 8. Arithmetic versus route problems

### Arithmetic/carry dominated

| Path | Delay | Carry structure | Assessment |
|---|---:|---|---|
| HSIM -> HMATCH CE | 6.330 | `CARRY4=5` | current WNS limiter |
| lane popcount -> HMATCH CE | 6.087 | `CARRY4=5` | same global finish/compare cone |
| HSIM -> HMATCH D | 4.797 | `CARRY4=3` | accumulation payload path |
| lane popcount -> HSIM D | 4.554 | `CARRY4=3` | global reduction path |

### Route/fanout dominated

| Path | Delay | Route ratio | Assessment |
|---|---:|---:|---|
| P2 popcount capture | 6.455 top200 / 6.439 fixed control path | 79.6-79.9% | second timing wall |
| VRF registered read/forward | 5.143 | 78.90% | third timing wall |
| VRF RAM write | 4.625 | 76.54% | secondary |
| P2 lane result capture | 3.999 | 72.37% | currently safe |

The P2 popcount problem is not primarily arithmetic depth. It has only about
1.3 ns logic delay and more than 5.1 ns estimated route delay.

## 9. High-fanout atlas

The complete top-50 tables are:

- `150mhz/high_fanout_top50.rpt`
- `150mhz/high_fanout_top50.csv`

The CSV includes source pin/type and load categories.

| Rank | Net | Fanout | Source | Principal loads |
|---:|---|---:|---|---|
| 1 | `clk_i` | 2876 | clock input | 2188 FF + 688 RAM clocks |
| 2 | synthesized reset net `i_vrf_n_934` | 2188 | LUT1 | 2188 reset pins |
| 3 | `i_vrf/<const1>` | 945 | VCC | 688 RAM data/control + 257 CE |
| 4 | `i_vrf/lane_shift_valid[0]` | 509 | LUT2 | 509 LUT inputs |
| 5 | `uop_p3_n` | 454 | FDCE | 74 CE + 380 LUT inputs |
| 6 | `uop_p2_q_reg[use_xor]__0` | 290 | FDCE | 289 LUT inputs |
| 7 | `FSM_onehot_st_q_reg_n_0_[8]` | 288 | FDCE | 288 LUT inputs |
| 8 | `i_vrf/p_0_in[0]` | 287 | FDCE | 287 LUT inputs |
| 9 | `i_vrf/init_state_q[0]` | 282 | FDCE | 282 LUT inputs |
| 10 | `i_vrf/lane_result_q...` | 262 | LUT6 | 262 LUT inputs |
| 11 | `hperm_a_n` | 262 | LUT4 | 256 CE + 6 LUT inputs |
| 12 | synthesized `src0_q` enable net | 261 | LUT4 | 256 CE + 5 LUT inputs |
| 16 | `lane_result_n` | 256 | LUT6 | 256 CE |
| 17 | `hcntadd_hv_n` | 256 | LUT4 | 256 CE |

The high-fanout list confirms three distinct pressures:

1. global reset/clock fanout, expected in OOC synthesis;
2. shared P2 control and lane-shift control fanout;
3. wide payload-register CE generation (`hperm_a_n`, `src0_q`, lane result).

## 10. Control sets and resource hierarchy

Total control sets: 31.

| Hierarchy | Total LUT | Logic LUT | LUTRAM | FF | Share of total LUT |
|---|---:|---:|---:|---:|---:|
| `hdec_top` total | 5004 | 4316 | 688 | 2188 | 100% |
| `i_vrf` | 4187 | 3499 | 688 | 268 | 83.7% |
| four `hdec_lane_4x64` instances | 258 | 258 | 0 | 0 | 5.2% |
| top-owned global/control/response | 559 | 559 | 0 | 1920 | 11.2% |

The synthesized hierarchy gives a reliable split for VRF and lane modules.
P3 global reduction, response, and control/FSM are flattened into the
top-owned 559 LUTs, so they cannot be separated further by
`report_utilization -hierarchical` without changing hierarchy preservation.

The large VRF logic-LUT count includes distributed-RAM addressing, registered
read/forwarding, initialization, and logic reconstructed under the VRF
hierarchy. It should not be interpreted as 3499 LUTs of memory bits alone.

## 11. Optimization conclusions

### 11.1 What is the true top1?

`hsim_total_q -> hmatch_best_dist_q/CE`, 6.330 ns, five CARRY4 stages, WNS
+0.126 ns at 150 MHz.

### 11.2 Are top10/top50 concentrated in the global cone?

- Top10: yes, 100% HSIM/HMATCH.
- Ranks 1-19: yes, all HMATCH CE endpoints.
- Top50: partly. It contains 19 HMATCH paths, 24 P2 popcount-capture paths,
  and 7 VRF-read paths.

### 11.3 Longest P2 lane control/capture path

- Full P2 capture class: 6.455 ns.
- Fixed `uop_p2_q/use_popcount -> lane_popcnt_q`: 6.439 ns.
- Approximately 80% of both paths is route delay.

### 11.4 Maximum Fmax gain from optimizing only P2 control

Zero immediate gain. The 6.330 ns HMATCH CE path remains the WNS limiter.

If the HMATCH path were removed first, the current P2 path would become a
ceiling around 154.9-155.2 MHz. Thus optimizing only P2 cannot move the design
past the present 152.9 MHz ceiling, and optimizing only HMATCH would expose
P2 almost immediately.

### 11.5 Three highest-value path classes

1. HMATCH best-update CE generation: current WNS limiter.
2. P2 popcount capture: next limiter, strongly route/fanout dominated.
3. VRF registered read/forwarding: 5.143 ns and already slightly failing at
   the 200 MHz constraint.

### 11.6 CE problems

- HMATCH distance/index CE: critical, 6.330 ns.
- `res_q/CE`: secondary, 4.806 ns.
- wide payload capture enables: high fanout but currently adequate slack.

### 11.7 Arithmetic/carry problems

- five-stage carry compare/update in HMATCH;
- three-stage HSIM accumulation;
- lane-popcount-to-HMATCH combines reduction and compare in one global cone.

### 11.8 Route/fanout problems

- P2 popcount capture;
- VRF registered read/forwarding and RAM write;
- shared `lane_shift_valid`, `uop_p2.use_xor`, `uop_p3_n`, and 256-bit CE
  controls.

### 11.9 Paths that must remain fixed in future comparisons

Always retain these from-to reports:

1. `uop_p2_q/use_popcount -> lane_popcnt_q/D`
2. `uop_p2_q/use_shift/use_counter/use_xor -> lane_result_q/D`
3. `uop_p2_q/use_clip -> lane_clip_q/D|CE`
4. `lane_popcnt_q -> hsim_total_q/D`
5. `hsim_total_q -> hsim_total_q/D`
6. `hsim_total_q -> hmatch_best_dist_q/D`
7. `hsim_total_q -> hmatch_best_dist_q/CE`
8. `lane_popcnt_q -> hmatch_best_dist_q/CE`
9. `hsim_total_q -> hmatch_best_idx_q/CE`
10. `hmatch_best_dist_q/hmatch_best_idx_q -> scalar_response_q/D`
11. FSM/uop/writeback control -> `bank_ra_data_o/D`
12. lane payload/uop/FSM -> VRF RAM write pins

### 11.10 Pipeline stage or CE simplification?

Recommendation: simplify the HMATCH CE decision first.

The evidence is unusually direct:

- HMATCH D is 4.797 ns;
- HMATCH CE is 6.330 ns;
- all top 19 paths end at HMATCH CE;
- the CE cone contains the five-stage carry comparison.

A separate global-finish register between HSIM accumulation and HMATCH compare
would break this path decisively, but it changes latency/FSM behavior. It is
appropriate if the target is 175 MHz or higher and one extra cycle is
acceptable.

However, that register alone will expose the 6.44-6.46 ns P2 popcount-capture
path. The preferred sequence is:

1. simplify or precompute the HMATCH CE condition without changing latency;
2. reduce P2 popcount control/data routing and fanout;
3. re-run this fixed path atlas;
4. add a global-finish pipeline stage only if the remaining target still
   requires it.

For a firm 175/200 MHz target, both the HMATCH global finish cone and P2
popcount capture must be addressed. Optimizing only one will not be enough.
