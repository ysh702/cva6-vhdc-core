# HDEC P2 one-hot lane-local slice Vivado 2024.2 OOC report

## 1. Summary

- Date: 2026-06-06
- Tool: Vivado 2024.2, build 5239630
- Part: `xc7z020clg400-2`
- Top: `hdec_top`
- Mode: `synth_design -mode out_of_context`
- Frequencies: 100, 125, 150, 175, and 200 MHz
- Baseline: `e0925738` from `origin/hdec-p2p3-split-result-payload-v1`
- New branch HEAD: `6437a435` from `origin/hdec-p2-onehot-local-slice-v1`
- New RTL commit: `8bc3f2c9`

The unmodified new RTL does not improve WNS or estimated Fmax. Its timing
results are identical to the baseline at every tested frequency, while its
150 MHz LUT count increases from 5004 to 5457, a delta of +453 LUTs.

Vivado does not preserve four independent copies of the 18-bit
`p2_lane_ctrl_q` in the unmodified design. It produces 23 physical control
register cells, places all of them under lane 0 hierarchy, and shares or
replicates them according to fanout. Shared capture and compute controls drive
loads in all four lanes.

A separate analysis worktree added only:

```systemverilog
(* keep = "true" *) hdec_p2_lane_ctrl_t p2_lane_ctrl_q;
```

This narrow KEEP preserves exactly 72 control registers (18 bits x 4 lanes),
but does not change WNS or estimated Fmax. It increases the 150 MHz LUT count
to 5758 and the number of control sets from 31 to 40. Therefore KEEP is not
recommended.

Overall result: the RTL source removes the previous encoded-control pattern,
but the synthesized implementation does not achieve the intended timing or
area outcome. This version does not avoid the previous LUT-regression class of
failure.

## 2. Method

All runs used the same source list, part, clock constraint form, synthesis
command, and report commands. Each frequency was synthesized independently.
No Verilator, Spike, GCC, or other software toolchain was installed or used.

The comparison script is:

`scripts/vivado/ooc_hdec_p2_onehot_compare.tcl`

Raw reports are under:

`E:\HDEC\cva6-vhdc-core\reports\vivado\ooc_hdec_p2_onehot_compare`

The narrow KEEP run was made in a detached worktree at:

`E:\HDEC\ooc-new-keep-6437a435`

The target branch RTL was not modified.

## 3. Frequency sweep

Estimated Fmax is calculated conservatively as:

`Fmax = 1000 / (period - WNS)` MHz

The baseline and unmodified new version have identical WNS, path delay, logic
delay, route delay, and route ratio.

| Run | MHz | WNS (ns) | TNS (ns) | Failing endpoints | Est. Fmax (MHz) | Data delay (ns) | Logic (ns) | Route (ns) | Route ratio |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 100 | +3.359 | 0.000 | 0 | 150.58 | 6.430 | 3.216 | 3.214 | 49.98% |
| baseline | 125 | +1.359 | 0.000 | 0 | 150.58 | 6.430 | 3.216 | 3.214 | 49.98% |
| baseline | 150 | +0.126 | 0.000 | 0 | 152.88 | 6.330 | 3.206 | 3.124 | 49.35% |
| baseline | 175 | -0.827 | -25.291 | 35 | 152.88 | 6.330 | 3.206 | 3.124 | 49.35% |
| baseline | 200 | -1.541 | -121.613 | 758 | 152.88 | 6.330 | 3.206 | 3.124 | 49.35% |
| new | 100 | +3.359 | 0.000 | 0 | 150.58 | 6.430 | 3.216 | 3.214 | 49.98% |
| new | 125 | +1.359 | 0.000 | 0 | 150.58 | 6.430 | 3.216 | 3.214 | 49.98% |
| new | 150 | +0.126 | 0.000 | 0 | 152.88 | 6.330 | 3.206 | 3.124 | 49.35% |
| new | 175 | -0.827 | -25.167 | 35 | 152.88 | 6.330 | 3.206 | 3.124 | 49.35% |
| new | 200 | -1.541 | -102.374 | 630 | 152.88 | 6.330 | 3.206 | 3.124 | 49.35% |
| new + narrow KEEP | 100 | +3.359 | 0.000 | 0 | 150.58 | 6.430 | 3.216 | 3.214 | 49.98% |
| new + narrow KEEP | 125 | +1.359 | 0.000 | 0 | 150.58 | 6.430 | 3.216 | 3.214 | 49.98% |
| new + narrow KEEP | 150 | +0.126 | 0.000 | 0 | 152.88 | 6.330 | 3.206 | 3.124 | 49.35% |
| new + narrow KEEP | 175 | -0.827 | -24.775 | 35 | 152.88 | 6.330 | 3.206 | 3.124 | 49.35% |
| new + narrow KEEP | 200 | -1.541 | -101.750 | 630 | 152.88 | 6.330 | 3.206 | 3.124 | 49.35% |

TNS at 175/200 MHz is slightly less negative in the new netlists, but WNS and
the maximum achievable clock period are unchanged. This is not an Fmax
improvement.

## 4. Resource comparison

### 4.1 Representative 150 MHz result

| Metric | Baseline | New | Delta | New + KEEP | KEEP delta vs baseline |
|---|---:|---:|---:|---:|---:|
| Slice LUT | 5004 | 5457 | +453 (+9.05%) | 5758 | +754 (+15.07%) |
| Logic LUT | 4316 | 4769 | +453 (+10.50%) | 5070 | +754 (+17.47%) |
| LUTRAM | 688 | 688 | 0 | 688 | 0 |
| FF | 2188 | 2171 | -17 | 2220 | +32 |
| BRAM tile | 0 | 0 | 0 | 0 | 0 |
| DSP | 0 | 0 | 0 | 0 | 0 |
| CARRY4 | 11 | 11 | 0 | 11 | 0 |
| Control sets | 31 | 31 | 0 | 40 | +9 |
| Estimated on-chip power | 0.131 W | 0.131 W | 0 | 0.132 W | +0.001 W |

The unmodified new version has 17 fewer FFs than the baseline because Vivado
merges the nominal lane-local controls. The KEEP run adds exactly 49 FFs over
the unmodified new run, matching the difference between 72 expected controls
and 23 synthesized control cells.

### 4.2 Resource stability across constraints

| Run | MHz | Slice LUT | Logic LUT | LUTRAM | FF | BRAM | DSP | CARRY4 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 100 | 5004 | 4316 | 688 | 2188 | 0 | 0 | 11 |
| baseline | 125 | 5004 | 4316 | 688 | 2188 | 0 | 0 | 11 |
| baseline | 150 | 5004 | 4316 | 688 | 2188 | 0 | 0 | 11 |
| baseline | 175 | 5011 | 4323 | 688 | 2188 | 0 | 0 | 11 |
| baseline | 200 | 5013 | 4325 | 688 | 2188 | 0 | 0 | 11 |
| new | 100 | 5458 | 4770 | 688 | 2171 | 0 | 0 | 11 |
| new | 125 | 5458 | 4770 | 688 | 2171 | 0 | 0 | 11 |
| new | 150 | 5457 | 4769 | 688 | 2171 | 0 | 0 | 11 |
| new | 175 | 5457 | 4769 | 688 | 2171 | 0 | 0 | 11 |
| new | 200 | 5472 | 4784 | 688 | 2171 | 0 | 0 | 11 |
| new + KEEP | 100 | 5758 | 5070 | 688 | 2220 | 0 | 0 | 11 |
| new + KEEP | 125 | 5758 | 5070 | 688 | 2220 | 0 | 0 | 11 |
| new + KEEP | 150 | 5758 | 5070 | 688 | 2220 | 0 | 0 | 11 |
| new + KEEP | 175 | 5758 | 5070 | 688 | 2220 | 0 | 0 | 11 |
| new + KEEP | 200 | 5774 | 5086 | 688 | 2220 | 0 | 0 | 11 |

The LUT increase is entirely in logic LUTs. LUTRAM, carry logic, BRAM, and DSP
do not change. This points to the one-hot masking/OR structure and repeated
lane-local combinational cones rather than memory inference or arithmetic
resources. The extra +301 LUTs caused by KEEP show that preventing control
sharing also prevents useful logic sharing and replication choices.

## 5. Worst path

At 150 MHz, all three runs have the same worst path:

- Logical source register: `hsim_total_q_reg[0]`
- Reported startpoint pin: `hsim_total_q_reg[0]/C`
- Endpoint: `hmatch_best_dist_q_reg[0]/CE`
- Data path delay: 6.330 ns
- Logic delay: 3.206 ns
- Route delay: 3.124 ns
- Route ratio: 49.35%
- Logic levels: 9
- Main logic: five CARRY4 stages plus LUT logic

The path is an HSim accumulation to HMatch best-distance clock-enable path. It
is not a P2 lane-control-to-payload-capture path. The new hierarchy changes
some reconstructed net names along this cone, but the delay is numerically
identical.

None of the top ten 150 MHz paths contains `p2_lane_ctrl`, `uop_p2`,
`lane_popcnt_q`, `lane_result_q`, or `lane_clip_q`.

Consequently, even a successful P2 control localization would not improve the
reported top-level OOC Fmax unless it also changed this independent HSim/HMatch
critical cone.

## 6. Local control preservation

The control type is 18 bits:

- five one-hot compute flags
- three one-hot capture flags
- two subgroup bits
- four threshold bits
- four permutation-nibble bits

Four lanes therefore imply 72 control FFs if every lane-local copy is retained.

### 6.1 Unmodified new RTL

Vivado produces only 23 matching `p2_lane_ctrl_q_reg` cells, all named under:

`gen_lane[0].i_p2_lane_slice`

Important merged behavior includes:

| Control | Synthesized behavior | Fanout evidence |
|---|---|---:|
| `capture_vec` | one shared register across four lanes | 256 |
| `capture_clip` / `do_clip` | equivalent controls merged | 192 |
| `capture_pop` / `do_popcount_diff` | equivalent controls merged | 316 |
| `subgroup[1:0]` | one shared copy per bit | 128 each |
| `threshold[3:0]` | one shared copy per bit | 64 each |
| `perm_nibble[3:0]` | one logical shared copy per bit | 3 to 10 before load replication |
| `do_counter` | shared source with synthesis-created replicas | up to 133 |
| `do_xor_only` | shared source with synthesis-created replicas | 136 |
| `do_shift` | shared source with one replica | 131 / 113 |

The load report directly shows lane-0 `capture_vec` driving lane-1 payload FF
clock enables and lane-0 `do_popcount_diff` driving lane-1, lane-2, and lane-3
popcount FF clock enables. Therefore the intended four independent local
control banks do not survive synthesis.

The result payload registers themselves do survive per lane:

- 4 x 64-bit `lane_result_q`
- 4 x 7-bit `lane_popcnt_q`
- 4 x 16-bit `lane_clip_q`

Thus local result storage exists, but its capture controls are shared after
synthesis.

### 6.2 Narrow KEEP experiment

The narrow KEEP run produces exactly 72 control FFs with 18 cells under each
of lane 0, lane 1, lane 2, and lane 3.

No preserved control register directly drives a load under another
`gen_lane[N]` hierarchy. Some optimized combinational loads are reconstructed
under `i_vrf`; hierarchy reconstruction means those names are not a reliable
RTL ownership boundary. The direct cross-lane connections seen in the
unmodified run are absent.

However, per-lane fanout is still high:

| Control | Lane-local fanout range |
|---|---:|
| `do_shift` | 288 to 297 |
| `perm_nibble[0]` | 168 to 177 |
| `do_xor_only` | 136 |
| `do_counter` | 112 |
| `do_popcount_diff` | 72 |
| `capture_vec` | 64 |
| `capture_clip` | 16 |

The KEEP run therefore enforces ownership, but does not make every control net
low fanout. More importantly, it adds 301 LUTs over the unmodified new run and
does not improve the worst path.

## 7. High-fanout comparison

Representative top-ten high-fanout nets at 150 MHz:

| Run | Relevant net | Fanout |
|---|---|---:|
| baseline | `i_vrf/lane_shift_valid[0]` | 509 |
| baseline | `uop_p2_q_reg[use_xor]__0` | 290 |
| new | shared `p2_lane_ctrl_q[do_popcount_diff]` | 316 |
| new + KEEP | lane 0 `p2_lane_ctrl_q[do_shift]` | 297 |
| new + KEEP | lane 1 `p2_lane_ctrl_q[do_shift]` | 293 |
| new + KEEP | lane 2 `p2_lane_ctrl_q[do_shift]` | 293 |
| new + KEEP | lane 3 `p2_lane_ctrl_q[do_shift]` | 288 |

The unmodified new version removes the named baseline shared shift/use-xor
controls from the top-ten list, but replaces them with a shared local-slice
popcount control. This is a naming and implementation-shape change, not a
general reduction in high-fanout control pressure.

KEEP removes the explicit cross-lane `do_popcount_diff` driver, but exposes
four high-fanout per-lane shift controls. It does not improve WNS.

## 8. Answer to the a010fdf9 failure question

| Question | Answer |
|---|---|
| Is encoded `lane_ctrl.op` absent? | Yes, in RTL. |
| Is `capture_kind` absent? | Yes. |
| Are P2 encoded equality comparators absent? | Yes, the slice uses one-hot flags and masked OR selection. |
| Is shared TOP control no longer driving payload capture? | Yes at RTL, but no in the unmodified synthesized netlist: equivalent local capture controls are merged across lanes. |
| Does every lane locally store control and result? | Results yes. Controls only after narrow KEEP; not in the unmodified synthesized netlist. |
| Is the previous LUT rebound avoided? | No. The unmodified new run is +453 LUTs at 150 MHz, worse than the cited +329 scale. KEEP reaches +754 LUTs. |

The modification avoids the exact encoded-control mechanism used by the prior
failed approach, but it does not avoid the failure outcome: LUT cost rises
substantially and timing does not improve.

## 9. Recommendation

1. Do not add KEEP to `p2_lane_ctrl_q`. It preserves 72 FFs but increases LUTs
   and control sets without improving WNS or Fmax.
2. Do not retain this RTL on PPA grounds in its current form. Retain it only if
   its architectural clarity has value independent of area and timing.
3. Use `e0925738` as the current PPA baseline.
4. If P2 control localization remains a goal, target only the proven
   high-fanout bits and prefer controlled fanout replication or a smaller
   lane-local capture-enable structure over preserving the full 18-bit bundle.
5. Measure any next P2 experiment against both LUT delta and post-synthesis
   cross-lane load ownership. RTL hierarchy alone is not sufficient evidence.
6. The present overall OOC Fmax limiter is the HSim/HMatch carry/enable cone.
   Improving P2 control alone cannot raise top-level Fmax while that path
   remains at approximately 6.33 ns.

Final decision: the one-hot lane-local slice does not meet the intended PPA
objective, and narrow KEEP should not be applied.
