# HDEC ECC V21 10-round area/timing timebox

Date: 2026-06-11
Branch: `hdec-ecc-pointmul-v21`
Base: `hdec-ecc-pointmul-v20` / `512e61c5`
Vivado: 2024.2
Part: `xc7z020clg400-2`
Top: `hdec_top`
Constraint: 5.000 ns, OOC synthesis

## Final result

V21 keeps the V20 x-only PMUL timing/area baseline unchanged while removing source-level dead state from the top FSM.

| Version | WNS (ns) | Est. Fmax (MHz) | Slice LUT | Logic LUT | LUTRAM | FF | BRAM | DSP | CARRY4 | PMUL cycles | HDC xsim |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| V20 baseline | 0.293 | 212.450 | 6459 | 5987 | 472 | 2150 | 0 | 0 | 20 | 6005 | PASS |
| V21 final | 0.293 | 212.450 | 6459 | 5987 | 472 | 2150 | 0 | 0 | 20 | 6005 | PASS |

Final OOC artifacts:

- `ooc_200mhz/run_summary.txt`
- `ooc_200mhz/utilization.rpt`
- `ooc_200mhz/utilization_hier.rpt`
- `ooc_200mhz/timing_top200.csv`
- `ooc_200mhz/timing_summary_top50.rpt`

Final xsim artifacts:

- `xsim/ecc_pmul_xsim.log`
- `xsim/hdc_full_flow_xsim.log`

## Final kept RTL changes

1. Removed unused ECC copy-source bookkeeping and unused VRF reset port from the previous V21 checkpoint.
2. Removed unused top-level `operand_b` mirror register `b_q/b_n`.
3. Removed unused HCNTADD mirror chunk register `hcntadd_chunk_q/hcntadd_chunk_n`; next HCNTADD chunk is generated directly from `uop_p3_q.chunk_idx + 1`.

These changes do not reduce post-synthesis LUT/FF because Vivado was already removing the dead sequential elements, but they reduce source-level control clutter before the next optimization version.

## 10-round summary

| Round | Attempt | OOC result | Decision |
|---:|---|---|---|
| 1 | Remove unused ECC copy enum/state together | 6874 LUT, 2149 FF, 204.792 MHz | Reverted: LUT +415 |
| 2 | Remove unused VRF reset port | 6459 LUT, 2150 FF, 212.450 MHz | Kept |
| 3 | Remove only unused ECC copy-source register | 6459 LUT, 2150 FF, 212.450 MHz | Kept |
| 4 | Stage HPERM shift into low-bit/nibble shift | 6750 LUT, 2154 FF, 211.640 MHz | Reverted: area increased |
| 5 | Replace `$countones` with explicit 4-bit popcount tree | 6863 LUT, 2159 FF, 214.041 MHz | Reverted: timing slightly better but area too high |
| 6 | Try VRF combinational read plus registered output | 6459 LUT, 2150 FF, 212.450 MHz | Reverted: no benefit, more complex code |
| 7 | Remove ECC job-kind register | 6595 LUT, 2142 FF, 210.970 MHz | Reverted: LUT +136 |
| 8 | Remove counter-array clear/update ports and top cnt-valid path | 6605 LUT, 2150 FF, 199.124 MHz | Reverted: below 200 MHz |
| 9 | Remove unused top-level `b_q/b_n` operand mirror | 6459 LUT, 2150 FF, 212.450 MHz | Kept |
| 10 | Remove unused HCNTADD chunk mirror register | 6459 LUT, 2150 FF, 212.450 MHz | Kept |

Note: an intermediate attempt to remove `hcntclip_chunk_q` was rejected before retention because it is still functionally used by HCNTCLIP cross-chunk writeback scheduling.

## Final top paths at 200 MHz

| Rank | Simple path name | Startpoint | Endpoint | Data delay (ns) | Slack (ns) |
|---:|---|---|---|---:|---:|
| 1 | FSM state to VRF read address lane0 | `st_q_reg[2]_rep__0/C` | `vrf_ra_q_reg[0][5]/D` | 4.704 | 0.293 |
| 2 | FSM state to VRF read address lane1 | `st_q_reg[2]_rep__0/C` | `vrf_ra_q_reg[1][5]/D` | 4.704 | 0.293 |
| 3 | FSM state to VRF read address lane2 | `st_q_reg[2]_rep__0/C` | `vrf_ra_q_reg[2][5]/D` | 4.704 | 0.293 |
| 4 | FSM state to VRF read address lane3 | `st_q_reg[2]_rep__0/C` | `vrf_ra_q_reg[3][5]/D` | 4.704 | 0.293 |
| 5 | P2 popcount result to group distance bit8 | `gen_lane[0].i_p2_pop_slice/popcount_part_q_o_reg[0][0]/C` | `group_dist_q_reg[8]/D` | 4.700 | 0.298 |
| 6 | P2 popcount result to group distance bit7 | `gen_lane[0].i_p2_pop_slice/popcount_part_q_o_reg[0][0]/C` | `group_dist_q_reg[7]/D` | 4.600 | 0.397 |

## Conclusion

This V21 timebox did not find a safe large area reduction. The useful result is that several tempting edits were tested and rejected with evidence. The current best checkpoint remains above 200 MHz, keeps PMUL at 6005 cycles, and has a cleaner control-state source base for the next version.

The remaining timing wall is still the VRF read/writeback address/control path, with P2 popcount accumulation close behind but still under 5 ns.
