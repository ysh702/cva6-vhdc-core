# HDEC Second Stage RTL Optimization Report

Date: 2026-06-08

Vivado: 2022.2

Device: xc7z020clg400-2

Retained RTL state: trial01 + trial02 only

Target branch: `hdec-second-stage-optimization`

## Objective

This stage optimized the HDEC accelerator RTL for better OOC timing while also
trying to reduce LUT and FF usage. The VRF remains implemented as distributed
LUTRAM. The HDC/ECC same-cycle interleaved lane reuse contract is preserved:
the optimization did not collapse the lane resource gates into one monolithic
operator and did not remove the independent lane-valid controls used by the
counter, shift, clip, XOR, and popcount paths.

## Retained Result

The retained state is trial01 plus trial02.

| Run | WNS ns | Worst data delay ns | Estimated Fmax MHz | Slice LUT | Logic LUT | LUTRAM | FF | CARRY4 | Decision |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Baseline Vivado 2022.2 | -1.014 | 5.660 | 166.279 | 4574 | 3886 | 688 | 2158 | 16 | Reference |
| trial01 P3 dst address precompute | -0.447 | 5.444 | 183.587 | 4565 | 3877 | 688 | 2158 | 14 | Retained |
| trial02 local P2 src0 capture | -0.447 | 5.444 | 183.587 | 4565 | 3877 | 688 | 2156 | 14 | Retained |

The retained design improves estimated Fmax from 166.279 MHz to 183.587 MHz,
reduces Logic LUTs from 3886 to 3877, reduces Slice LUTs from 4574 to 4565,
and reduces FFs from 2158 to 2156. LUTRAM remains unchanged at 688, with zero
BRAM and zero DSP usage.

## Retained RTL Changes

### trial01: P3 destination address precompute

File changed: `core/hdec/rtl/hdec_top.sv`

Change scope:

- Precompute the HCNTADD write destination address in the uop pipeline.
- Precompute the HPERM chunk destination address in the uop pipeline.
- Use `uop_p3_q.dst_addr` during P3 VRF writeback instead of recomputing
  `base + chunk/subgroup` on the global writeback path.
- Carry the next HCNTADD subgroup destination by incrementing `dst_addr`.

Design reason:

The previous P3 writeback path still had address arithmetic inside a global
control/writeback stage. Moving this address arithmetic earlier shortens the
P3 VRF write path and removes redundant late-stage address logic. This is the
main timing win in this stage.

### trial02: Localize P2 `src0` capture into each popcount slice

Files changed:

- `core/hdec/rtl/hdec_top.sv`
- `core/hdec/rtl/hdec_p2_pop_slice.sv`

Change scope:

- Removed the wide top-level `src0_q/src0_n` register array.
- Added a lane-local `src_a_q` inside each `hdec_p2_pop_slice`.
- Connected `src_a_i` directly to `vrf_rd[lid]`; this is intentional because
  the slice captures the first operand at the P1 read boundary, while the VRF
  output advances to the second operand for P2.
- Kept direct 64-bit `$countones` for the retained implementation.

Design reason:

The first operand is only consumed by the per-lane P2 XOR/popcount slice.
Keeping that register local reduces global control/data fanout and lets Vivado
place the operand register near the consuming popcount logic. The retained OOC
result keeps timing unchanged versus trial01 but removes two FFs.

## Retained Timing Shape

The retained OOC run still shows the longest stage is P2 popcount capture:

| Path class | Worst data delay ns | Slack ns | Notes |
|---|---:|---:|---|
| P2 popcount capture | 5.444 | -0.447 | Current worst path |
| HMATCH reduction/compare | 5.233 | -0.236 | Next major pressure point |
| Scalar response/control | 5.039 | -0.250 | Close to 5 ns |
| Other scalar/control | 4.997 | -0.208 | Near target |
| VRF/read/writeback/control | 4.829 | -0.183 | No longer the top path |

This confirms that trial01 moved the original VRF/P3 writeback pressure away
from the top critical path. The remaining imbalance is mainly the P2 popcount
stage, followed by HMATCH accumulation and compare logic.

## Reverted Trials

### trial03: HMATCH budget subtract reuse

Attempt:

- Reused the existing `hmatch_budget_diff` sign/zero result to derive the
  strict `budget > group_dist` condition.
- Replaced the original compare-plus-subtract style with a subtract-derived
  mask.

OOC result:

- WNS: -1.126 ns
- Worst data delay: 6.123 ns
- Estimated Fmax: 163.239 MHz
- Logic LUT: 3875
- FF: 2159
- CARRY4: 12
- Worst endpoint: `hmatch_budget_q_reg[10]/D`

Decision:

Reverted. The slight LUT and carry reduction was not worth the severe timing
regression on the HMATCH budget path.

### trial04: Explicit 4x16 popcount tree

Attempt:

- Replaced direct 64-bit `$countones` with four 16-bit counts and an explicit
  reduction tree.

OOC result:

- WNS: -1.052 ns
- Worst data delay: 6.066 ns
- Estimated Fmax: 165.235 MHz
- Logic LUT: 3925
- FF: 2156
- CARRY4: 22
- Worst endpoint: `gen_lane[0].i_p2_pop_slice/popcount_q_o_reg[6]/D`

Decision:

Reverted. Vivado's direct `$countones` mapping is better for this design than
the hand-written 4x16 tree. The explicit tree increased Logic LUTs and CARRY4
usage and made P2 timing much worse.

### trial05: Two-stage P2 popcount pipeline balancing

User-requested design note to preserve in this report:

> 下一步我会针对现在最坏的 P2 popcount 做“流水级拆平”的试验，这正好对应你刚刚强调的阶段时序均衡。这里有个比较清晰的信号：当前最坏路径是 src_a_q -> popcount_q_o，数据延迟 5.444 ns，明显比 HMATCH/标量/P3 写回几类长。所以这轮我会先把 64-bit popcount 切成低 32 位预累加 + 高 32 位延后一拍合并，看看是否能把 P2 长段压到和其他阶段接近。

Attempt:

- Split the 64-bit popcount into low-32 and high-32 partial counts.
- Captured the high-32 count and added a new `S_UOP_P2_POP_FINAL` state.
- Delayed HSIM/HMATCH uops by one additional cycle before P3 so the final
  6-bit + 6-bit merge completed across a stage boundary.

OOC result:

- WNS: -0.450 ns
- Worst data delay: 5.447 ns
- Estimated Fmax: 183.486 MHz
- Slice LUT: 4278
- Logic LUT: 3590
- LUTRAM: 688
- FF: 2184
- CARRY4: 22
- Worst endpoint: `hmatch_budget_q_reg[1]/D`

Decision:

Reverted for the retained branch. This experiment did reduce LUTs
substantially, but it did not improve timing, increased FFs by 28 versus the
retained design, increased CARRY4 usage to 22, and moved the critical path into
the HMATCH budget update. It is a useful future direction only if paired with a
second retiming of the HMATCH P3 accumulation/compare stage.

## Verification

OOC synthesis command used for the retained result:

```text
H:\SWTOOLS\Vivado\2022.2\bin\vivado.bat -mode batch -nojournal -nolog -source scripts/hdec/ooc_hdec_timing_atlas.tcl -tclargs H:\CVA6-HDEC\cva6-vhdc-core H:\CVA6-HDEC\cva6-vhdc-core\tmp\hdec_opt_trial02_local_src0 5.000 trial02_local_src0
```

Vivado xsim command used after the first four RTL trials:

```text
H:\SWTOOLS\Vivado\2022.2\bin\vivado.bat -mode batch -nojournal -nolog -source scripts/hdec/xsim_hdec_hmatch_compare_split.tcl -tclargs H:\CVA6-HDEC\cva6-vhdc-core H:\CVA6-HDEC\cva6-vhdc-core\tmp\hdec_opt_xsim_after4
```

xsim result:

- PASS single class max distance
- PASS second class exact match
- PASS tie keeps first class
- PASS illegal num_classes zero
- All HDEC HMATCH compare-split xsim tests passed.

## Archived Artifacts

This directory contains the retained OOC report artifacts:

- `retained_trial02_run_summary.txt`
- `retained_trial02_utilization.rpt`
- `retained_trial02_utilization_hier.rpt`
- `retained_trial02_timing_summary_top50.rpt`
- `retained_trial02_timing_top200.csv`
- `retained_trial02_xsim_hmatch_compare_split.txt`

It also contains run summaries for reverted attempts:

- `reverted_trial03_run_summary.txt`
- `reverted_trial04_run_summary.txt`
- `reverted_trial05_run_summary.txt`
