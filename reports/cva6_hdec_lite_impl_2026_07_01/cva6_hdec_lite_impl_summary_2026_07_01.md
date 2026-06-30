# VV7 Lightweight CVA6+HDEC Integration Report

Date: 2026-07-01

## Purpose

This run records a lightweight CVA6+HDEC integration on Zynq-7020. The goal is to keep the RISC-V/CV-X-IF path and HDEC coprocessor present while reducing the surrounding CVA6 configuration enough to study processor-level integration pressure on the small FPGA.

This is not the main HDEC accelerator PPA result. The main accelerator result remains the standalone HDEC core / monitor flow that closes at 200 MHz. This VV7 run is integration evidence for a lightweight CVA6 profile.

## Flow

- Vivado: 2024.2
- Device: `xc7z020clg400-2`
- Top wrapper: `cva6_hdec_lite_impl_wrapper`
- Clock target: 5.000 ns / 200 MHz
- Clocking: external `clk_pad_i` drives one `BUFG`, then `clk_core` drives CVA6/HDEC
- CV-X-IF: enabled
- HDEC: integrated through the CV-X-IF coprocessor path
- Flow stages: `synth_design -> opt_design -> place_design -> phys_opt_design -> route_design`

## Lightweight CVA6 Configuration Intent

The lightweight profile keeps the architectural path needed to elaborate and implement CVA6 with HDEC:

- RV64 core integration
- CV-X-IF enabled
- HDEC coprocessor enabled
- FPGA memory mapping
- reduced cache, scoreboard, branch-prediction, PMP, MMU, FPU, and performance-counter pressure where possible

The purpose is not to claim a production CVA6 configuration, but to provide a smaller embedded-profile integration point for HDEC on Zynq-7020.

## Post-Route Resource Usage

| Metric | Value | Device Usage |
|---|---:|---:|
| Slice LUTs | 16024 | 30.12% |
| LUT as Logic | 15614 | 29.35% |
| LUT as Memory | 410 | 2.36% |
| Slice Registers | 6534 | 6.14% |
| Block RAM Tile | 12 | 8.57% |
| DSPs | 16 | 7.27% |
| Bonded IOB | 18 | 14.40% |
| BUFGCTRL | 1 | 3.13% |

The DSP usage comes from the lightweight CVA6 system, not from HDEC. The HDEC hierarchy itself remains DSP-free.

## HDEC Hierarchical Usage Inside Lightweight CVA6

| Hierarchy | LUT | FF | BRAM | DSP |
|---|---:|---:|---:|---:|
| `gen_hdec_coprocessor.i_hdec_coprocessor` | 4662 | 1535 | 4 | 0 |

## Post-Route Timing

| Metric | Value |
|---|---:|
| Target clock period | 5.000 ns |
| Target frequency | 200 MHz |
| WNS | -9.159 ns |
| TNS | -51983.428 ns |
| Failing endpoints | 11384 |
| Worst data path delay | 14.040 ns |
| Worst path logic delay | 4.534 ns |
| Worst path route delay | 9.506 ns |
| Rough equivalent worst-path frequency | about 70.6 MHz |

The post-route timing limit is dominated by CVA6-side paths, especially issue/read-operands/ALU and related control paths. This run should therefore be used as processor-integration evidence rather than as the primary 200-MHz HDEC accelerator result.

## Vectorless Power Estimate

| Metric | Value |
|---|---:|
| Total on-chip power | 0.330 W |
| Dynamic power | 0.220 W |
| Device static power | 0.110 W |
| Junction temperature | 28.8 C |
| Clock power | 0.050 W |
| Slice logic power | 0.040 W |
| Signal power | 0.060 W |
| Block RAM power | 0.057 W |
| DSP power | 0.000 W |
| VCCINT current estimate | 0.214 A |
| VCCAUX current estimate | 0.011 A |
| VCCBRAM current estimate | 0.003 A |

This is a Vivado post-route vectorless estimate. It should not be presented as board-measured power.

## Files

- `cv64a6_hdec_lite_config_pkg.sv`: lightweight CVA6 configuration package.
- `cva6_hdec_lite_impl_wrapper.sv`: top wrapper for the lightweight implementation check.
- `cva6_hdec_lite_impl.xdc`: 5 ns implementation constraint.
- `run_cva6_hdec_lite_impl.tcl`: reproducible Vivado implementation flow.
- `impl_zynq7020_lite_bufg/*.rpt`: post-synth/place/route utilization, timing, clocking, power, fanout, and methodology reports.

Large Vivado checkpoints and project/cache files are intentionally not part of the committed VV7 handoff.

