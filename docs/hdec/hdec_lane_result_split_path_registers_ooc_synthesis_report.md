# HDEC Lane Result Split-Path Registers OOC Synthesis Report

## 1. Branch and Commit

| Item | Value |
|---|---|
| Branch | `hdec-p2p3-split-result-payload-v1` |
| Commit | `ec561b73` |
| Commit message | `hdec: split narrow P2 payload registers` |
| Base branch | `hdec-seven-souls-vmware-regression-v1` |
| Base commit | `8f8774e9` |
| RTL scope | `core/hdec/rtl/hdec_top.sv` only |

This report summarizes the Vivado out-of-context synthesis result for the HDEC lane result split-path register optimization. The RTL functional logic, ISA encoding, VRF structure, CV-X-IF wrapper, and pipeline stage count are unchanged by this report.

## 2. RTL Change Summary

The split-path register version modifies only:

```text
core/hdec/rtl/hdec_top.sv
```

The core RTL changes are:

| Area | Summary |
|---|---|
| Vector payload | Keeps `lane_result_q/n` as the 4 x 64-bit wide payload register. |
| Popcount payload | Adds `lane_popcnt_q/n` as a 4 x 7-bit narrow popcount payload register. |
| Clip payload | Adds `lane_clip_q/n` as a 4 x 16-bit narrow clip payload register. |
| P2 popcount capture | `use_popcount` writes `lane_popcnt_q`; it no longer zero-extends into `lane_result_q`. |
| P2 clip capture | `use_clip` writes `lane_clip_q`; it no longer zero-extends into `lane_result_q`. |
| P3 HSIM/HMATCH | HSIM and HMATCH read `lane_popcnt_q` for the 4-lane distance sum. |
| P3 HCNTCLIP | HCNTCLIP reads `lane_clip_q` for subgroup packing. |
| Vector operations | HBIND, HPERM, and HCNTADD continue to read `lane_result_q`. |
| Pipeline latency | No pipeline stage is added. |
| Instruction cycles | No cycles are added. |
| Functional regression | Verilator 20/20 regression PASS. |

The intent is to remove narrow popcount and clip payloads from the 64-bit mixed `lane_result_q` payload path, reducing unnecessary muxing and control fanout around the P2-to-P3 boundary.

## 3. OOC Synthesis Environment

| Item | Value |
|---|---|
| Vivado version | 2022.2 |
| Top module | `hdec_top` |
| FPGA part | `xc7z020clg400-2` |
| Mode | `synth_design -mode out_of_context` |
| Clock sweep | 100 / 125 / 150 / 175 / 200 MHz |
| Report directory | `reports/vivado/ooc_hdc_hdcu_ec561b73` |

## 4. Timing Results

| Target Frequency | Period | WNS | TNS | Failing Endpoints | Result |
|---|---:|---:|---:|---:|---|
| 100 MHz | 10.000 ns | +3.359 ns | 0.000 ns | 0 | PASS |
| 125 MHz | 8.000 ns | +1.021 ns | 0.000 ns | 0 | PASS |
| 150 MHz | 6.667 ns | -0.312 ns | -3.740 ns | 12 | FAIL |
| 175 MHz | 5.714 ns | -1.265 ns | -108.319 ns | 563 | FAIL |
| 200 MHz | 5.000 ns | -1.979 ns | -559.456 ns | 833 | FAIL |

Key timing summary:

| Metric | Value |
|---|---:|
| Worst data path delay | 6.976 ns |
| Estimated Fmax | Approximately 143.3 MHz |

The design passes 100 MHz and 125 MHz OOC synthesis timing. It does not close timing at 150 MHz. The conservative estimated Fmax is approximately 143.3 MHz, based on the 6.976 ns worst data path delay.

## 5. Utilization Results

The following table uses the 150 MHz OOC synthesis result.

| Resource | Usage |
|---|---:|
| LUT | 4709 |
| Logic LUT | 4021 |
| LUTRAM | 688 |
| FF | 2177 |
| BRAM | 0 |
| DSP | 0 |
| CARRY4 | 13 |
| CARRY8 | 0 |

Additional utilization note:

| Frequency range | LUT observation |
|---|---|
| 100 MHz | 5025 LUT |
| 125-200 MHz | Approximately 4709 LUT |

The 125-200 MHz sweep points are stable around 4709 LUT. The 100 MHz run uses 5025 LUT, which is likely due to different synthesis choices under the relaxed timing target.

## 6. Power Results

| Target Frequency | Total Power | Dynamic Power |
|---|---:|---:|
| 100 MHz | 0.124 W | 0.021 W |
| 125 MHz | 0.129 W | 0.026 W |
| 150 MHz | 0.134 W | 0.031 W |
| 175 MHz | 0.139 W | 0.036 W |
| 200 MHz | 0.145 W | 0.042 W |

Power scales as expected with the clock target. The total on-chip power remains low in this HDEC-only OOC synthesis context.

## 7. Baseline Comparison

Baseline:

```text
hdec-seven-souls-vmware-regression-v1 / 8f8774e9
```

Optimized split-path version:

```text
hdec-p2p3-split-result-payload-v1 / ec561b73
```

| Metric | Baseline 8f8774e9 | Split-path ec561b73 | Change |
|---|---:|---:|---:|
| Estimated Fmax | ~134.2 MHz | ~143.3 MHz | +9.1 MHz |
| WNS @150MHz | -0.788 ns | -0.312 ns | +0.476 ns |
| WNS @200MHz | -2.455 ns | -1.979 ns | +0.476 ns |
| LUT @150MHz | 4913 | 4709 | -204 |
| Logic LUT @150MHz | 4225 | 4021 | -204 |
| LUTRAM | 688 | 688 | 0 |
| FF | 2086 | 2177 | +91 |
| CARRY4 | 13 | 13 | 0 |

The split-path version improves timing and reduces LUT usage at the cost of a small and expected FF increase. The +91 FF increase matches the introduction of narrow payload registers for popcount and clip results.

## 8. Critical Path Analysis

Current 150 MHz worst path:

```text
FSM_onehot_st_q_reg[6] / S_UOP_P2_LANE
  -> lane_popcnt_q_reg[0][4]
```

Path characteristics:

| Metric | Value |
|---|---:|
| Data path delay | 6.976 ns |
| Logic delay | 1.400 ns |
| Route delay | 5.576 ns |
| Logic levels | 8 |
| Route delay ratio | Approximately 79.9% |

Interpretation:

The split-path register optimization removes the previous issue where popcount and clip narrow results were zero-extended into the shared 64-bit `lane_result_q` payload path. This reduces unnecessary mixed-payload muxing and lowers control fanout around the P2/P3 boundary.

The `uop_p3_n` fanout is reduced from approximately 354 to approximately 165. This is a meaningful structural improvement.

However, the new worst path still starts from the TOP FSM state bit for `S_UOP_P2_LANE` and ends at the popcount payload register `lane_popcnt_q`. This means the current timing bottleneck has moved from the mixed 64-bit payload mux toward TOP-level P2 control fanout and payload capture control.

In practical terms, the data payload split worked, but the P2 capture decision is still controlled directly by TOP FSM state and `use_*` control signals. The path is route-dominated, not deep arithmetic dominated. The next optimization should therefore reduce TOP control fanout and move P2 lane-local control into a more compact local command form.

## 9. Conclusion

The HDEC Lane Result Split-Path Registers optimization is effective:

| Item | Result |
|---|---|
| Fmax | Improves from approximately 134 MHz to approximately 143 MHz |
| WNS @150MHz | Improves by approximately +0.476 ns |
| LUT | Reduces by approximately 204 LUT |
| Logic LUT | Reduces by approximately 204 LUT |
| FF | Increases by approximately 91 FF, as expected |
| Verilator regression | 20/20 PASS |
| 150 MHz timing | Still not clean |

The current version is a better baseline than the original Seven-Souls OOC baseline because it improves timing and reduces LUT usage while preserving instruction cycles and functional behavior.

The remaining timing problem is no longer primarily the mixed payload path. The next optimization should focus on:

1. Reducing TOP FSM control fanout.
2. Removing redundant `use_*` control signals from the active P2 capture path.
3. Moving P2 Lane control into a compact lane-local command, such as `lane_op` plus `capture_kind`.
4. Keeping the existing split payload registers for vector, popcount, and clip results.

The next stage should not continue splitting payloads blindly. The better direction is TOP control signal reduction and P2 Lane-local control restructuring.
