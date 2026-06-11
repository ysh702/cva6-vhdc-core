# HDEC ECC V22 Vivado 2024.2 OOC comparison

Date: 2026-06-11
Branch: `hdec-ecc-pointmul-v22`
Commit: `f31fd02b hdec: reuse uop progress for HDC counters`
Part: `xc7z020clg400-2`
Top: `hdec_top`
Constraint: 5.000 ns, OOC synthesis

This report compares the latest remote V22 branch against the Vivado 2022.2 results already stored in `reports/hdec/v22_area_reduction_2022_2/README.md`.

## Source 2022.2 reference

The V22 README records the final retained Vivado 2022.2 point as `round09_hcnt_uop_progress`:

| Version | Vivado | WNS (ns) | Est. Fmax (MHz) | Slice LUT | Logic LUT | LUTRAM | FF | BRAM | DSP | CARRY4 | PMUL cycles | HDC full-flow |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| V22 round09 | 2022.2 | 0.243 | 210.217 | 6429 | 5957 | 472 | 2119 | 0 | 0 | 20 | 6005 | PASS |

## New 2024.2 OOC result

The same V22 HEAD was synthesized locally with Vivado 2024.2:

| Version | Vivado | WNS (ns) | Est. Fmax (MHz) | Slice LUT | Logic LUT | LUTRAM | FF | BRAM | DSP | CARRY4 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| V22 HEAD | 2024.2 | 0.159 | 206.569 | 6258 | 5786 | 472 | 2113 | 0 | 0 | 20 |

Artifacts:

- `ooc_200mhz/run_summary.txt`
- `ooc_200mhz/utilization.rpt`
- `ooc_200mhz/utilization_hier.rpt`
- `ooc_200mhz/timing_top200.csv`
- `ooc_200mhz/timing_summary_top50.rpt`

## Direct tool-version comparison

| Metric | V22 2022.2 round09 | V22 2024.2 HEAD | Delta, 2024.2 - 2022.2 |
|---|---:|---:|---:|
| WNS (ns) | 0.243 | 0.159 | -0.084 |
| Est. Fmax (MHz) | 210.217 | 206.569 | -3.648 |
| Slice LUT | 6429 | 6258 | -171 |
| Logic LUT | 5957 | 5786 | -171 |
| LUTRAM | 472 | 472 | 0 |
| FF | 2119 | 2113 | -6 |
| BRAM | 0 | 0 | 0 |
| DSP | 0 | 0 | 0 |
| CARRY4 | 20 | 20 | 0 |

Interpretation: Vivado 2024.2 maps this V22 RTL smaller than Vivado 2022.2, saving 171 LUT and 6 FF, but reports slightly lower timing margin. The design is still above the 200 MHz target.

## Same-tool context against V21 2024.2

For a same-tool view, compare V22 2024.2 against the V21 2024.2 report:

| Version | Vivado | WNS (ns) | Est. Fmax (MHz) | Slice LUT | Logic LUT | LUTRAM | FF | PMUL cycles |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| V21 report | 2024.2 | 0.293 | 212.450 | 6459 | 5987 | 472 | 2150 | 6005 |
| V22 HEAD | 2024.2 | 0.159 | 206.569 | 6258 | 5786 | 472 | 2113 | not rerun |
| Delta | - | -0.134 | -5.881 | -201 | -201 | 0 | -37 | - |

V22 therefore still provides a real area reduction under Vivado 2024.2: 201 fewer LUT and 37 fewer FF than V21, while staying above 200 MHz.

## Worst path comparison

| Vivado | Worst path class | Startpoint | Endpoint | Data delay (ns) | Logic (ns) | Route (ns) | WNS (ns) |
|---|---|---|---|---:|---:|---:|---:|
| 2022.2 | P2 lane result capture | `uop_p2_q_reg[valid]/C` | `lane_result_q_reg[0][27]/D` | 4.786 | 1.286 | 3.500 | 0.243 |
| 2024.2 | ECC/top control CE | `a_q_reg[2]/C` | `ecc_inv_step_q_reg[0]/CE` | 4.630 | 1.190 | 3.440 | 0.159 |

The top path changes between tool versions. In 2022.2 the retained worst path was the P2 lane-result capture path. In 2024.2 the worst path moves to an ECC control-enable path from command operand state into `ecc_inv_step_q` CE. P2 lane-result paths remain close behind in the top-200 list.

## Conclusion

V22 is valid under Vivado 2024.2 and remains above 200 MHz. The important result is that the area reduction still holds with the newer tool:

- V22 vs V21 under Vivado 2024.2: -201 Slice LUT, -201 Logic LUT, -37 FF.
- V22 2024.2 vs V22 2022.2: -171 Slice LUT, -171 Logic LUT, -6 FF.
- Timing remains acceptable but margin is lower than both V21 2024.2 and V22 2022.2.

For the next optimization pass, the first target under Vivado 2024.2 should be the ECC command/control CE path around `ecc_inv_step_q` and `ecc_dst_q`, while keeping an eye on the P2 lane-result capture path that remains close behind.
