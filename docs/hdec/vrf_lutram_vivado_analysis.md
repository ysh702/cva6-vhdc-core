# VRF LUTRAM Vivado Analysis

Date: 2026-05-27

Repository: `H:\CVA6-HDEC\cva6-vhdc-core`

Branch: `vrf-lutram-inference-v1`

Baseline commit: `1707a6d6`

## A. Current VRF Modification Summary

The current RTL change is limited to:

- `core/hdec/rtl/hdec_vrf_64x256.sv`

The VRF module interface is unchanged. The change rewrites the four 64 x 64 VRF
banks as independent distributed-RAM-friendly arrays, keeps synchronous writes,
keeps 1-cycle registered reads, preserves normal read-after-write forwarding,
and keeps a small sequential init-clear path instead of a reset-time full memory
clear.

No BMCA, Lane, `hdec_top`, CVA6, ECC, or submodule RTL was modified in this
Vivado run.

## B. WSL Verilator Verification Summary

Reported WSL results for this RTL version:

| Check | Result |
|---|---|
| Verilator build | PASS |
| Stage 3 `hdc_inference_test.S` | PASS |
| Stage 4 `hdc_e2e_train_infer_test.S` | PASS, accuracy 8/8 |

Win11 did not run Verilator for this analysis.

## C. Vivado Before/After Comparison

Vivado configuration:

- Vivado: 2022.2
- Part: `xc7z020clg400-2`
- Top: `hdec_top`
- OOC mode: `synth_design -mode out_of_context`
- Main clock: 10.000 ns

| Metric | Before VRF patch | After VRF patch |
|---|---:|---:|
| `hdec_top` LUT | 32,837 | 7,172 |
| `hdec_top` FF | 19,861 | 3,470 |
| `i_vrf` LUT | 30,240 | 4,992 |
| `i_vrf` FF | 16,649 | 265 |
| BRAM | 0 | 0 |
| LUTRAM | 0 | 688 |
| DSP | 0 | 0 |

RAM inference:

- `report_ram_utilization` completed successfully.
- BlockRAM: 0 / 140.
- LUTMs as Distributed RAM: 688 / 17,400, 100% inferred.
- Vivado log reports distributed RAM final mapping for `i_vrf/vrf_b0_reg`
  through `i_vrf/vrf_b3_reg` as 64 x 64 RAM64M-based memories.
- The previous VRF dissolved-into-registers warning was not found in the latest
  Vivado log.

Power estimate at 10 ns:

- Total on-chip power: 0.269 W
- Dynamic power: 0.164 W
- Device static power: 0.105 W
- Confidence: Medium

## D. Hierarchical Resource Table

From `reports/vivado/hdc_only_vrf_lutram/utilization_hdec_top_ooc_hier.rpt`:

| Instance | Module | Total LUTs | Logic LUTs | LUTRAMs | FFs | BRAM | DSP |
|---|---|---:|---:|---:|---:|---:|---:|
| `hdec_top` | top | 7,172 | 6,484 | 688 | 3,470 | 0 | 0 |
| `(hdec_top)` | top-local logic | 167 | 167 | 0 | 2,124 | 0 | 0 |
| `i_vrf` | `hdec_vrf_64x256` | 4,992 | 4,304 | 688 | 265 | 0 | 0 |
| `gen_lane[0].i_lane` | `hdec_lane_4x64` | 481 | 481 | 0 | 270 | 0 | 0 |
| `gen_lane[1].i_lane` | `hdec_lane_4x64__parameterized0` | 539 | 539 | 0 | 271 | 0 | 0 |
| `gen_lane[2].i_lane` | `hdec_lane_4x64__parameterized1` | 498 | 498 | 0 | 270 | 0 | 0 |
| `gen_lane[3].i_lane` | `hdec_lane_4x64__parameterized2` | 495 | 495 | 0 | 270 | 0 | 0 |

Grouped totals:

| Group | LUTs | FFs | Notes |
|---|---:|---:|---|
| All lane shells | 2,013 | 1,081 | Sum of four `hdec_lane_4x64` instances |
| All lane-local BMCA | 2,013 | 1,081 | The retained lane hierarchy is BMCA-dominated |
| Shift-align | 0 reported separately | 0 reported separately | No retained `i_shift_align` rows in this synthesized hierarchy |
| Top-local logic | 167 | 2,124 | FSM and top-level state |
| VRF | 4,992 | 265 | Includes 688 LUTRAM and read/write/forwarding logic |

## E. Timing Top20 Summary

At 10 ns, timing is met:

| Metric | Value |
|---|---:|
| WNS | 1.483 ns |
| TNS | 0.000 ns |
| WHS | 0.246 ns |
| THS | 0.000 ns |

Worst setup path:

- Source: `gen_lane[0].i_lane/i_bmca/row1_q_reg[56]/C`
- Destination: `gen_lane[0].i_lane/i_bmca/count_q_reg[8]/D`
- Module: lane-local BMCA
- Requirement: 10.000 ns
- Data path delay: 8.543 ns
- Logic levels: 10 (`CARRY4=2 LUT3=1 LUT5=3 LUT6=4`)

The top setup paths are repeated across the four lane-local BMCA instances. The
critical timing path is no longer related to VRF memory implementation.

## F. Clock Sweep

The sweep used OOC synthesis only, no implementation.

| Clock period | WNS | TNS | Worst path module | Result |
|---:|---:|---:|---|---|
| 10.0 ns | 1.483 ns | 0.000 ns | lane-local BMCA row-to-count path | PASS |
| 7.5 ns | -1.017 ns | -18.146 ns | lane-local BMCA row-to-count path | FAIL |
| 5.0 ns | -3.517 ns | -440.992 ns | lane-local BMCA row-to-count path | FAIL |

The same worst path appears in all three timing reports:

- `gen_lane[0].i_lane/i_bmca/row1_q_reg[56]/C`
- to `gen_lane[0].i_lane/i_bmca/count_q_reg[8]/D`
- data path delay 8.543 ns

## G. BMCA Optimization Recommendation

VRF storage inference is solved for this phase:

- FF count collapsed from 19,861 to 3,470 at the `hdec_top` level.
- `i_vrf` FF count collapsed from 16,649 to 265.
- LUTRAM is now inferred and reported.
- The old dissolved-into-registers warning is gone.

The total `hdec_top` size is now in a reasonable OOC range for `xc7z020clg400-2`:

- 7,172 LUTs, 13.48% of device LUTs.
- 3,470 FFs, 3.26% of device FFs.
- 688 LUTRAMs, 3.95% of available LUT memory.

BMCA is now the dominant retained compute datapath and the clear timing-critical
block:

- All lane-local BMCA instances total 2,013 LUTs and 1,081 FFs.
- The worst setup paths are BMCA row-to-count paths.
- 10 ns passes, but 7.5 ns and 5 ns fail on BMCA.

Recommendation:

- It is reasonable to enter a BMCA optimization phase next.
- Primary target: timing, because BMCA is the limiter below 10 ns.
- Secondary target: area, because BMCA is also the largest retained compute
  block after VRF storage inference.
- For pure area work, note that `i_vrf` still has 4,304 logic LUTs in addition
  to 688 LUTRAMs, so residual VRF read/write/forwarding mux logic may deserve a
  later focused cleanup. Do not mix that with the first BMCA pass.

## H. Git Status

`git status --short` after this analysis:

```text
 M core/hdec/rtl/hdec_vrf_64x256.sv
?? docs/hdec/vrf_lutram_patch_plan_for_wsl.md
?? docs/hdec/vrf_lutram_vivado_analysis.md
?? reports/
?? scripts/
```

This analysis generated reports under:

- `reports/vivado/hdc_only_vrf_lutram/`

No commit or push was performed.
