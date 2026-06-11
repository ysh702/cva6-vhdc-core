# HDEC ECC PointMul V23 Optimization Notes

## Run Context

- Branch: `hdec-ecc-pointmul-v23`
- Base remote branch: `origin/hdec-ecc-pointmul-v22`
- Base commit: `f31fd02b hdec: reuse uop progress for HDC counters`
- Vivado: 2024.2
- Part: `xc7z020clg400-2`
- OOC top: `hdec_top`
- OOC target period: 5.000 ns, 200 MHz

## Standing Workflow File

This branch adds `agent.md` at the repository root. It records the repeated V23-style workflow:

- Track ECC cycle count, LUT, FF, ECC completion, HDC regression, and 200 MHz timing.
- Run OOC after every partial RTL trial.
- Run ECC and HDC regressions after every 4 trials.
- In every 4-round loop, try two small optimizations and two large optimizations.
- Keep generated Tcl/report/log artifacts under the project directory, not under `C:`.

## Final Kept RTL Change

The final kept RTL change is a neutral structural cleanup in `core/hdec/rtl/hdec_vrf_64x256.sv`:

- Replaced four handwritten VRF bank arrays with a `generate` loop.
- Storage remains distributed LUTRAM.
- Read latency, write behavior, and external interface are unchanged.
- Vivado 2024.2 OOC PPA is identical to the V23 baseline.

This is kept because it makes the VRF structure regular for later work and did not hurt timing, LUT, FF, cycle count, or regressions.

## Round Summary

| Round | Type | Trial | Decision | WNS ns | Est. Fmax MHz | LUT | Logic LUT | LUTRAM | FF | Top endpoint | Reason |
|---:|---|---|---|---:|---:|---:|---:|---:|---:|---|---|
| 1 | Small | Remove unused `hdec_cnt_array` ports | Kept | 0.159 | 206.569 | 6258 | 5786 | 472 | 2113 | `ecc_inv_step_q_reg[0]/CE` | No PPA change, source cleanup |
| 2 | Small | Remove unused lane `clk_i/rst_ni` ports | Kept | 0.159 | 206.569 | 6258 | 5786 | 472 | 2113 | `ecc_inv_step_q_reg[0]/CE` | No PPA change, source cleanup |
| 3 | Large | Slim lane shell to real operators only | Rejected | 0.243 | 210.217 | 6348 | 5876 | 472 | 2114 | `lane_result_q_reg[0][27]/D` | Timing improved but LUT +90 |
| 4 | Large | Simplify ECC INV start CE assignments | Rejected | 0.243 | 210.217 | 6453 | 5981 | 472 | 2105 | `lane_result_q_reg[0][27]/D` | FF -8 but LUT +195 |
| 5 | Small | Remove unused lane `cnt_valid_i` port | Rejected | 0.248 | 210.438 | 6554 | 6082 | 472 | 2107 | `lane_result_q_reg[0][27]/D` | LUT +296 |
| 6 | Small | Remove unused old lane bool/popcount ports | Rejected | 0.021 | 200.844 | 6434 | 5962 | 472 | 2112 | `st_q_reg[4]/D` | Still passed 200 MHz but LUT +176 |
| 7 | Large | Rewrite VRF banks as generate loop | Kept | 0.159 | 206.569 | 6258 | 5786 | 472 | 2113 | `ecc_inv_step_q_reg[0]/CE` | Exact PPA match, cleaner structure |
| 8 | Large | Rewrite shift-align as coarse/fine window mux | Rejected | 0.287 | 212.179 | 7640 | 7168 | 472 | 2108 | `ecc_dst_q_reg[0]/CE` | Timing improved but LUT +1382 |

## Final OOC Result

Final kept RTL uses round 7 OOC data:

| Metric | Value |
|---|---:|
| WNS | 0.159 ns |
| Estimated Fmax | 206.569 MHz |
| Slice LUT | 6258 |
| Logic LUT | 5786 |
| LUTRAM | 472 |
| FF | 2113 |
| BRAM | 0 |
| DSP | 0 |
| CARRY4 | 20 |
| Worst endpoint | `ecc_inv_step_q_reg[0]/CE` |

Final OOC artifacts are copied to:

- `reports/hdec/v23_optimization/ooc_final_round07_200mhz/`

## Regression Result

Cycle 2 regressions were run after round 8 decisions:

| Test | Result | Cycle data |
|---|---|---:|
| `xsim_hdec_ecc_pmul_v18.tcl` | PASS | `PMUL_CYCLES=6005` |
| `xsim_hdec_hdc_full_flow_v20.tcl` | PASS | N/A |

Regression logs are copied to:

- `reports/hdec/v23_optimization/xsim_cycle2/xsim_ecc_pmul_v18.log`
- `reports/hdec/v23_optimization/xsim_cycle2/xsim_hdc_full_flow_v20.log`

## Main Finding

The V23 trials show that the current Vivado 2024.2 netlist is very sensitive to source-level rewrites. Several changes that look like area cleanups at RTL level caused Vivado to remap control, VRF, or shift logic into larger LUT cones.

In particular:

- Removing tied-off lane ports did not reliably reduce area.
- The explicit coarse/fine shift-align rewrite made timing better but exploded LUT count.
- VRF generate cleanup preserved exact PPA, so it is safe but not an area win.

The next real area-reduction work should target architectural sources of large muxing:

- VRF read/write address and write-data mux structure.
- ECC PMUL micro-op sequencing and field-op issue path.
- Whether HPERM/ECC square can use a narrower operation set without rebuilding a large generic shift mux.
