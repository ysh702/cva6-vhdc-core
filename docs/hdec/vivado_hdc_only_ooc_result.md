# Vivado HDC-only OOC Synthesis Result

Date: 2026-05-26
Repository: `H:\CVA6-HDEC\cva6-vhdc-core`

## 1. Git Baseline

- Branch: `hdec-phase1`
- Commit: `1707a6d6`
- Tag at HEAD: `hdec-phase1-hdc-baseline-pre-ecc`

`git status --short` after this run:

```text
?? docs/hdec/vivado_hdc_only_ooc_plan.md
?? docs/hdec/vivado_hdc_only_ooc_result.md
?? docs/hdec/win11_codex_vivado_check.md
?? reports/
?? scripts/
```

No RTL, submodule, or committed files were modified.

## 2. Run Configuration

- Vivado executable: `H:\SWTOOLS\Vivado\2022.2\bin\vivado.bat`
- Vivado version: `Vivado v2022.2 (64-bit)`
- SW Build: `3671981`
- IP Build: `3669848`
- FPGA part: `xc7z020clg400-2`
- OOC top: `hdec_top`
- Clock: `clk_i`, 10.000 ns, 100 MHz
- Mode: `synth_design -mode out_of_context`
- Implementation was not run.

## 3. RTL Files Read

```text
core/hdec/rtl/hdec_pkg.sv
core/hdec/rtl/hdec_resource_pkg.sv
core/hdec/rtl/hdec_lane_boolean_mask.sv
core/hdec/rtl/hdec_bmca_cell.sv
core/hdec/rtl/hdec_lane_shift_align.sv
core/hdec/rtl/hdec_lane_addsub_counter.sv
core/hdec/rtl/hdec_lane_clip.sv
core/hdec/rtl/hdec_lane_bmca.sv
core/hdec/rtl/hdec_lane_4x64.sv
core/hdec/rtl/hdec_vrf_64x256.sv
core/hdec/rtl/hdec_top.sv
```

Full CVA6, CV-X-IF wrapper, ECC, implementation, and Verilator were not run.

## 4. Vivado Result

Vivado batch completed successfully.

Key output:

```text
Synthesis finished with 0 errors, 0 critical warnings and 389 warnings.
synth_design completed successfully
report_power completed successfully
The checkpoint 'H:/CVA6-HDEC/cva6-vhdc-core/reports/vivado/hdc_only/hdec_top_ooc_synth.dcp' has been generated.
```

Warnings to keep in mind:

- Vivado reported no write access to the local Tcl store under `C:\Users\Lenovo\AppData\Roaming\Xilinx`; it fell back to the installation area.
- OOC timing reported `HD.CLK_SRC` is not set for `clk_i`, which affects clock delay/skew estimation in OOC mode.
- The VRF arrays were dissolved into registers, not inferred as BRAM. Vivado warning: RAM `vrf_b0_reg`/`vrf_b1_reg`/`vrf_b2_reg`/`vrf_b3_reg` implemented in registers.

## 5. Utilization

From `reports/vivado/hdc_only/utilization_hdec_top_ooc.rpt`:

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 32,837 | 53,200 | 61.72% |
| Slice Registers / FF | 19,861 | 106,400 | 18.67% |
| Block RAM Tile | 0 | 140 | 0.00% |
| DSPs | 0 | 220 | 0.00% |

## 6. Timing

From `reports/vivado/hdc_only/timing_hdec_top_ooc.rpt`:

| Metric | Value |
|---|---:|
| WNS | 1.483 ns |
| TNS | 0.000 ns |
| Failing setup endpoints | 0 |
| WHS | 0.246 ns |
| THS | 0.000 ns |
| Failing hold endpoints | 0 |

All user specified timing constraints are met for the synthesized OOC netlist.

Worst setup path summary:

```text
Slack (MET): 1.483 ns
Source:      gen_lane[0].i_lane/i_bmca/row1_q_reg[56]/C
Destination: gen_lane[0].i_lane/i_bmca/count_q_reg[8]/D
Path Group:  clk_i
Path Type:   Setup (Max at Slow Process Corner)
Requirement: 10.000 ns
Data Path Delay: 8.543 ns
Logic: 1.991 ns, Route: 6.552 ns
Logic Levels: 10 (CARRY4=2 LUT3=1 LUT5=3 LUT6=4)
```

## 7. Power

Power report generated:

- `reports/vivado/hdc_only/power_hdec_top_ooc.rpt`

Summary:

| Metric | Value |
|---|---:|
| Total On-Chip Power | 0.792 W |
| Dynamic Power | 0.679 W |
| Device Static Power | 0.114 W |
| Junction Temperature | 34.1 C |
| Confidence Level | Medium |

Power is vectorless and post-synthesis only, so it should be treated as an early estimate.

## 8. Generated Artifacts

- Tcl script: `scripts/vivado/hdec_hdc_ooc_synth.tcl`
- Utilization: `reports/vivado/hdc_only/utilization_hdec_top_ooc.rpt`
- Timing: `reports/vivado/hdc_only/timing_hdec_top_ooc.rpt`
- Power: `reports/vivado/hdc_only/power_hdec_top_ooc.rpt`
- Checkpoint: `reports/vivado/hdc_only/hdec_top_ooc_synth.dcp`

## 9. Notes / Next Questions

- The first HDC-only OOC synthesis proves `hdec_top` can synthesize directly despite its package enum top port.
- The largest resource block is the VRF, which Vivado implemented in registers. A later explicit RTL design step may evaluate BRAM/LUTRAM-friendly VRF structure, but no RTL changes were made here.
- OOC clock source modeling can be improved later by setting `HD.CLK_SRC` when the intended top-level clocking context is known.

## 10. Hierarchical Utilization Diagnosis

This diagnosis was run from the existing synthesized checkpoint only:

```text
open_checkpoint reports/vivado/hdc_only/hdec_top_ooc_synth.dcp
report_utilization -hierarchical -hierarchical_depth 10
report_timing_summary -max_paths 20
report_ram_utilization
```

No `synth_design`, implementation, Verilator, full CVA6 flow, ECC flow, or RTL edit was run.

Generated diagnostic artifacts:

- Tcl: `scripts/vivado/hdec_hdc_ooc_analyze_util.tcl`
- Hierarchical utilization: `reports/vivado/hdc_only/utilization_hdec_top_ooc_hier.rpt`
- Top-20 timing: `reports/vivado/hdc_only/timing_hdec_top_ooc_top20.rpt`
- RAM report: `reports/vivado/hdc_only/ram_hdec_top_ooc.rpt`
- RAM status: `reports/vivado/hdc_only/ram_hdec_top_ooc_status.txt`

### Top 10 Largest Instances by LUT

| Rank | Instance | Module | LUTs | FFs |
|---:|---|---|---:|---:|
| 1 | `hdec_top` | top | 32,837 | 19,861 |
| 2 | `i_vrf` | `hdec_vrf_64x256` | 30,240 | 16,649 |
| 3 | `gen_lane[0].i_lane` | `hdec_lane_4x64` | 665 | 270 |
| 4 | `gen_lane[2].i_lane` | `hdec_lane_4x64__parameterized1` | 619 | 271 |
| 5 | `gen_lane[3].i_lane` | `hdec_lane_4x64__parameterized2` | 598 | 270 |
| 6 | `gen_lane[1].i_lane` | `hdec_lane_4x64__parameterized0` | 560 | 270 |
| 7 | `gen_lane[2].i_lane/i_bmca` | `hdec_lane_bmca_0` | 547 | 271 |
| 8 | `gen_lane[0].i_lane/i_bmca` | `hdec_lane_bmca_4` | 493 | 270 |
| 9 | `gen_lane[1].i_lane/i_bmca` | `hdec_lane_bmca_2` | 488 | 270 |
| 10 | `gen_lane[3].i_lane/i_bmca` | `hdec_lane_bmca` | 481 | 270 |

### Top 10 Largest Instances by FF

| Rank | Instance | Module | LUTs | FFs |
|---:|---|---|---:|---:|
| 1 | `hdec_top` | top | 32,837 | 19,861 |
| 2 | `i_vrf` | `hdec_vrf_64x256` | 30,240 | 16,649 |
| 3 | `(hdec_top)` | top-local logic | 155 | 2,131 |
| 4 | `gen_lane[2].i_lane` | `hdec_lane_4x64__parameterized1` | 619 | 271 |
| 5 | `gen_lane[2].i_lane/i_bmca` | `hdec_lane_bmca_0` | 547 | 271 |
| 6 | `gen_lane[0].i_lane` | `hdec_lane_4x64` | 665 | 270 |
| 7 | `gen_lane[0].i_lane/i_bmca` | `hdec_lane_bmca_4` | 493 | 270 |
| 8 | `gen_lane[1].i_lane` | `hdec_lane_4x64__parameterized0` | 560 | 270 |
| 9 | `gen_lane[1].i_lane/i_bmca` | `hdec_lane_bmca_2` | 488 | 270 |
| 10 | `gen_lane[3].i_lane` | `hdec_lane_4x64__parameterized2` | 598 | 270 |

### VRF Resource Contribution

`i_vrf` dominates the synthesized design:

| Block | LUTs | LUT Share | FFs | FF Share | BRAM | LUTRAM |
|---|---:|---:|---:|---:|---:|---:|
| Total `hdec_top` | 32,837 | 100.0% | 19,861 | 100.0% | 0 | 0 |
| `i_vrf` | 30,240 | 92.1% | 16,649 | 83.8% | 0 | 0 |

`report_ram_utilization` completed successfully and reported:

```text
BlockRAM:                 0 / 140, 0.00%
LUTMs as Distributed RAM: 0 / 17400, 0.00%
```

This confirms the previous synthesis warning: the VRF arrays were not inferred as BRAM or LUTRAM; they were dissolved into registers/logic.

### Lane/BMCA Resource Contribution

The four lane shells together are much smaller than the VRF:

| Block Group | LUTs | LUT Share | FFs | FF Share |
|---|---:|---:|---:|---:|
| All four `hdec_lane_4x64` instances | 2,442 | 7.4% | 1,081 | 5.4% |
| All four lane `i_bmca` instances | 2,009 | 6.1% | 1,081 | 5.4% |
| All four lane `i_shift_align` instances | 433 | 1.3% | 0 | 0.0% |

Within the lane shells, BMCA is the main registered block. The shift-align blocks contribute LUTs only in this report, and the lane FF count is effectively BMCA row/count state.

### Does VRF Register Implementation Explain the Resource Spike?

Yes. The register-implemented VRF explains most of the high resource usage:

- 92.1% of total LUTs are under `i_vrf`.
- 83.8% of total FFs are under `i_vrf`.
- RAM utilization reports zero BRAM and zero LUTRAM.
- Vivado explicitly warned that `vrf_b0_reg` through `vrf_b3_reg` were dissolved into registers.

The lane/BMCA datapath is visible but secondary. The next optimization target should be the VRF storage inference/architecture, not BMCA first.

### Recommended Next Step

Do not blindly patch RTL. The next safe step is a design review of `hdec_vrf_64x256.sv` against Vivado memory inference rules:

- Check whether the init-clear behavior, write-forwarding, multiple banks in one process, and automatic read address declarations prevent BRAM/LUTRAM inference.
- Decide explicitly whether Phase V2 wants BRAM, LUTRAM, or register-file semantics.
- If BRAM/LUTRAM is desired, make a separate, reviewable RTL change with a small VRF-only OOC baseline before re-running full `hdec_top` OOC synthesis.
