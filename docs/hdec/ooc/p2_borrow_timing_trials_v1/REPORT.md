# HDEC P2 popcount split / borrow-timing trials

Date: 2026-06-08
Vivado: 2024.2
Part: xc7z020clg400-2
Clock target: 200 MHz, 5.000 ns
Top: hdec_top
Branch: hdec-p2-hmatch-200mhz-v1

## Short conclusion

The 200 MHz blocker was originally the lane-local P2 XOR + 64-bit popcount path.

Pure expression reshaping does not solve it. Explicit 16x4 or 2x32 popcount structures are worse than Vivado's original 64-bit `$countones` mapping.

The useful structure is:

1. P2 computes two 32-bit partial popcounts per lane and registers them.
2. P3_GLOBAL sums the 8 partial counts into a registered `group_dist_q`.
3. New P3_ACCUM uses `group_dist_q` to update HSIM/HMATCH state.

This removes the original P2 popcount wall and moves the design to about 198 MHz OOC. It costs one extra cycle per HSIM/HMATCH chunk.

The current worktree is kept at the trial12 structure, not the later one-hot or predecoded-flag attempts.

## Trial Summary

| Trial | Main change | WNS ns | Worst delay ns | Est. Fmax MHz | LUT | Logic LUT | LUTRAM | FF | CARRY4 | Keep? |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| trial04 | HMATCH minus-one baseline, original P2 popcount | -0.447 | 5.444 | 183.587 | 4468 | 3780 | 688 | 2054 | 12 | baseline |
| trial08 | P1_RD1 pre-XOR through same-address VRF comb read | -0.413 | 5.410 | 184.740 | 4666 | 3978 | 688 | 2054 | 12 | no |
| trial09 | trial08 + precompute 8x8-bit popcount partials in P1 | -0.755 | 5.752 | 173.762 | 4507 | 3819 | 688 | 2182 | 20 | no |
| trial10 | P2 outputs two 32-bit partial popcounts, P3 does partial sum + HMATCH | -1.218 | 6.215 | 160.823 | 4160 | 3472 | 688 | 2075 | 20 | no |
| trial11 | P2-only 2x32 popcount tree, no extra stage | -0.864 | 5.878 | 170.532 | 4480 | 3792 | 688 | 2054 | 20 | no |
| trial12 | P2 partials + P3 group_dist register + P3_ACCUM | -0.051 | 4.701 | 197.981 | 4505 | 3817 | 688 | 2080 | 16 | best |
| trial13 | trial12 + forced one-hot FSM | -0.240 | 5.029 | 190.840 | 4405 | 3717 | 688 | 2080 | 16 | no |
| trial14 | trial12 + P3 is_hmatch predecode flag | -0.053 | 4.703 | 197.902 | 4649 | 3961 | 688 | 2082 | 16 | no |

## Key Path Movement

| Version | Simple path name | Delay ns | Meaning |
|---|---:|---:|---|
| trial04 | VRF data -> XOR/popcount -> lane popcount register | 5.444 | Original P2 wall |
| trial10 | partial popcount register -> group distance + HMATCH update | 6.215 | P3 became too heavy |
| trial11 | 2x32 popcount tree -> lane popcount register | 5.878 | Expression-only split was worse |
| trial12 | uop/control -> VRF LUTRAM read port | 4.701 | P2 wall removed; new near-200 path is VRF/control |

## Current Interpretation

The user-proposed idea was correct in spirit: split the popcount work across pipeline boundaries. The working boundary is not P1/P2, because P1 needs a LUTRAM combinational read for the second operand and that path is too long. The working boundary is P2/P3 plus a new global accumulator stage.

The remaining 0.051 ns miss in trial12 is not the popcount tree anymore. It is a VRF/control path from uop/control state into LUTRAM read inputs. That is the next target if strict 200 MHz OOC closure is required.

## Cost

Compared with trial04:

- LUT: +37
- Logic LUT: +37
- FF: +26
- LUTRAM: unchanged
- BRAM/DSP: unchanged at 0
- CARRY4: +4
- Timing: 183.6 MHz -> 198.0 MHz estimated

The cost is modest, but HSIM/HMATCH gets one extra cycle per chunk because `group_dist_q` is now a registered stage.

## Archived OOC Artifacts

The following Vivado OOC artifacts are stored with this report:

- `ooc_results/trial04_hmatch_minus1_budget_200`: baseline 200 MHz OOC result before the P2 partial-popcount split.
- `ooc_results/trial12_p2_partial_p3accum_200`: retained 200 MHz OOC result for the current RTL.

Each archived result includes:

- `run_summary.txt`
- `timing_summary_top50.rpt`
- `timing_top200.csv`
- `utilization.rpt`
- `utilization_hier.rpt`
- the generated 5.000 ns XDC used by the OOC run
