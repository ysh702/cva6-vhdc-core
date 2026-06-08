# HDEC HMATCH compare split on P2 keep baseline

## Run context

- Base commit: `968ff819 hdec: preserve P2 popcount local controls`
- Working branch: `hdec-hmatch-compare-split-p2keep-v1`
- RTL changed: `core/hdec/rtl/hdec_top.sv`
- Added xsim testbench: `verif/hdec/tb_hdec_hmatch_compare_split.sv`
- Added xsim script: `scripts/hdec/xsim_hdec_hmatch_compare_split.tcl`
- Vivado: 2024.2
- Part: `xc7z020clg400-2`
- Top: `hdec_top`
- OOC clock period: 5.000 ns
- OOC output: `E:/HDEC/cva6-vhdc-core/tmp/hdec_hmatch_compare_split_p2keep_candidate/ooc/reports`
- Timing atlas output: top1000 setup paths exported in this directory

## Design change

The split point is at the final HMATCH chunk, after the 4-lane popcount sum is accumulated into the class distance.

Old behavior:

- `hsim_total_q + group_dist` was compared directly with `hmatch_best_dist_q`.
- The compare result directly drove the write enables of all `hmatch_best_dist_q` bits and the best-index update.
- The same compare/CE cone appeared as the top timing path on many bits: bit0, bit1, bit2, bit3, bit4, bit10, etc.

New behavior:

- The final class distance is captured into `hmatch_candidate_dist_q`.
- The compare result is captured into one bit, `hmatch_update_q`.
- The actual best-distance/best-index update happens in the following safe control point.
- For non-last classes, the next class can still be scheduled immediately from P3, so the two-class xsim case remains 34 cycles.

In simple words: the old design used one long compare result to enable many destination registers in the same cycle. The new design first stores "this class wins or not" as one bit, then updates the best result in the next step.

## Vivado xsim

Vivado xsim passed:

| Test | Result |
|---|---:|
| single class max distance | PASS |
| second class exact match | PASS |
| tie keeps first class | PASS |
| illegal num_classes zero | PASS |

The second-class exact-match test is important because it checks that the query address returns to the query base when moving to the next class.

## OOC timing result at 200 MHz constraint

| Version | Top path, simple name | RTL endpoint | Data delay | WNS | Conservative Fmax |
|---|---|---|---:|---:|---:|
| P2 keep baseline `968ff819` | HMATCH current distance compare to best-distance write-enable bits | `hmatch_best_dist_q_reg[0]/CE` | 6.330 ns | -1.541 ns | 152.882 MHz |
| HMATCH compare split candidate | VRF read data to lane popcount capture | `gen_lane[0].i_p2_pop_slice/popcount_q_o_reg[4]/D` | 6.072 ns | -1.075 ns | 164.609 MHz |

Improvement versus P2 keep baseline:

- WNS improves by 0.466 ns.
- Conservative Fmax improves by 11.727 MHz, about 7.7%.
- The old repeated HMATCH best-distance CE path is no longer the top path.

## Representative paths after split

| Rank | Simple path name | Data delay | Logic | Route | Levels | Note |
|---:|---|---:|---:|---:|---:|---|
| 1 | VRF read data to lane0 popcount result bit4 | 6.072 ns | 1.295 ns | 4.777 ns | 7 | Current top path |
| 2 | VRF read data to lane0 popcount result bit5 | 6.072 ns | 1.295 ns | 4.777 ns | 7 | Same P2 popcount cone |
| 3 | VRF read data to lane0 popcount result bit6 | 6.072 ns | 1.295 ns | 4.777 ns | 7 | Same P2 popcount cone |
| 4 | VRF read data to lane1 popcount result bit4 | 6.070 ns | 1.295 ns | 4.775 ns | 7 | Same P2 popcount cone |
| 5 | VRF read data to lane1 popcount result bit5 | 6.070 ns | 1.295 ns | 4.775 ns | 7 | Same P2 popcount cone |
| HMATCH targeted | Current distance compare to one update bit | 5.826 ns | 3.072 ns | 2.754 ns | 9 | Old CE fanout is reduced to one bit |

## Top1000 path atlas

At 5.000 ns, the timing atlas exported 1000 setup paths. 876 of them are still negative slack.

| Path class | Top1000 count | Failing count | Worst rank | Worst delay | Worst slack | Simple meaning |
|---|---:|---:|---:|---:|---:|---|
| P2 popcount capture | 24 | 20 | 1 | 6.072 ns | -1.075 ns | VRF read data goes through lane popcount and is captured |
| HMATCH reduction/compare | 54 | 12 | 13 | 5.826 ns | -0.829 ns | Final class distance compare now drives one update bit |
| VRF/read/writeback | 776 | 776 | 14 | 5.508 ns | -0.511 ns | UOP/read-control selects VRF read address/data register |
| scalar response | 64 | 64 | 790 | 4.956 ns | -0.167 ns | Decode/parameter control drives scalar result register CE |
| other HMATCH control | 4 | 4 | 865 | 4.929 ns | -0.140 ns | Decode/parameter control drives class-slot CE |
| TOP control | 32 | 0 | 917 | 4.539 ns | +0.458 ns | General uop/control register paths |
| P2 lane result capture | 46 | 0 | 955 | 4.308 ns | +0.689 ns | Non-popcount lane result capture |

Important readout:

- If the current P2 popcount wall is fixed, HMATCH update is the next single named path at 5.826 ns.
- After HMATCH update, the next large family is VRF read/control at 5.508 ns.
- After those, scalar response CE paths are just under 5 ns data delay and still show small negative slack in OOC.
- Non-popcount lane-result paths are already positive slack in this run.

## Paths to keep tracking next

| Track item | Current delay | Current slack | Why it matters |
|---|---:|---:|---|
| VRF read data to lane popcount capture | 6.072 ns | -1.075 ns | Current top wall |
| HMATCH total distance to update bit | 5.826 ns | -0.829 ns | First non-P2 wall after this split |
| UOP read-control to VRF read data register | 5.508 ns | -0.511 ns | Large family: 776 failing top1000 paths |
| Decode/parameter control to `res_q` CE | 4.956 ns | -0.167 ns | Scalar response CE family |
| Decode/parameter control to HMATCH candidate/class CE | 4.951/4.929 ns | -0.162/-0.140 ns | Added HMATCH split bookkeeping |

## Resource comparison

| Version | Slice LUT | Logic LUT | LUTRAM | FF | BRAM | DSP | CARRY4 |
|---|---:|---:|---:|---:|---:|---:|---:|
| P2 keep baseline `968ff819` | 4918 | 4230 | 688 | 2190 | 0 | 0 | 11 |
| HMATCH compare split candidate | 5105 | 4417 | 688 | 2201 | 0 | 0 | 11 |
| Delta | +187 | +187 | 0 | +11 | 0 | 0 | 0 |

Resource judgment:

- FF increase is exactly the expected shape: one `hmatch_update_q` bit plus 11 candidate-distance bits, with synthesis optimization leaving +11 FF overall.
- LUTRAM, BRAM, DSP, and CARRY4 do not increase.
- LUT increases by 187, mainly in top-level HMATCH/control muxing. This is much smaller than the earlier +329 LUT class of failed encoded-control attempts, but it is still a real cost.

## P2 local control preservation

| Signal | Copies | Fanout per copy | Judgment |
|---|---:|---:|---|
| lane-local `pop_q` | 4 | 8 | Preserved |
| lane-local `xor_q` | 4 | 1 | Preserved |
| top-to-lane `p1_pop_d` | 1 | 4 | Only drives the four local lane registers |
| top-to-lane `p1_xor_d` | 1 | 4 | Only drives the four local lane registers |

P2 is still fixed. The local `pop_q` was not merged back into one shared register.

## Conclusion

This split does what it was supposed to do on timing: it removes the old HMATCH best-distance CE multi-bit wall from the top path and moves the top path back to P2 popcount capture.

The cost is moderate:

- Timing improves clearly: 152.882 MHz to 164.609 MHz conservative Fmax.
- FF increase is minimal: +11.
- LUT increase is +187, not zero, but much better than the previous +329-style failed attempt.

Recommendation: keep this candidate as the current best HMATCH timing split candidate, but do not call it final until we decide whether +187 LUT is acceptable. If LUT must be reduced further, the next experiment should target the P4/best-update muxing and response muxing, not P2.

## RTL optimization candidates not implemented here

These are candidates for the next branch only. They were not implemented in this branch.

| Candidate | Expected timing effect | Expected LUT/FF effect | Risk |
|---|---|---|---|
| Reuse `hsim_total_q` as the pending HMATCH candidate distance and remove `hmatch_candidate_dist_q` | Removes the secondary candidate-distance CE paths; HMATCH update path should stay similar | Saves about 11 FF; likely saves some LUT from candidate mux/CE logic | Need verify that `hsim_total_q` is reset in the next-class P1 stage before the next accumulation |
| Precompute HPERM/normal VRF read addresses into existing uop address fields, then make P1 read-address assignment mostly unconditional | Should reduce the `uop_p0_q[op_type] -> VRF read data register` family at 5.508 ns | Uses existing uop fields, so FF should not increase; LUT should drop by removing op_type/base-add muxing from the read-address cycle | Must preserve HPERM two-read behavior |
| Simplify scalar response handling so one result register path is used when possible | May reduce the `a_q[8] -> res_q/CE` family near 4.956 ns | Could reduce 64 response FF plus output muxing if `scalar_response_q` can be merged safely | Needs careful xsim because fast result and P4 scalar result currently use different registers |
| Split or specialize the generic popcount compressor for P2-only popcount | May slightly improve the current 6.072 ns P2 popcount path if generic mode logic was not fully optimized | Could save small LUT if unused CSA/mode logic leaves residue | Vivado may already optimize this; benefit is uncertain |
| Narrow the P2 local-control preservation attributes | Might improve placement/routing of the current route-heavy P2 path | No direct FF/LUT saving expected | Risk of Vivado merging the four local `pop_q` copies again, so this is timing-only and should be tried last |

Best next experiment:

1. First remove `hmatch_candidate_dist_q` by keeping the final class distance in `hsim_total_q` until the next safe update point. This directly targets the +11 FF and the added HMATCH CE paths.
2. Then precompute VRF read addresses into existing uop fields to reduce the 5.508 ns VRF read-control family without adding registers.
3. Only after those two, look at the popcount/VRF data path itself. The current top path is route-dominated, so a pure RTL expression rewrite may not be enough unless it also reduces the read-address/control mux pressure around VRF.
