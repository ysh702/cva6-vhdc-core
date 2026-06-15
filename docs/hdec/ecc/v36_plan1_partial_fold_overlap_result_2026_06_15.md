# V36 Plan 1 Result: Partial Leaf Compute/Fold Overlap

## RTL Change

Plan 1 keeps the V35 5M point-add formula and changes the KPD32 leaf schedule.

The fold path now latches the completed leaf product and leaf path into a small
fold latch.  During the last fold cycle of a non-final leaf, the next leaf's B
operand is taken directly from `vrf_rd`, allowing the first diagonal issue of
the next leaf to start one cycle earlier.

This is a conservative partial overlap:

```text
old: fold leaf N, then issue all diagonals for leaf N+1
new: fold leaf N, and issue the first diagonal group for leaf N+1 in the last fold cycle
```

It does not add a second product accumulator and does not add a second
`ecc_product_pair` write path.

## Vivado 2022.2 Comparison Against V35 Baseline

| Metric | V35 baseline | V36 Plan 1 | Delta |
| --- | ---: | ---: | ---: |
| PMUL wall cycles | 341624 | 310346 | -31278 |
| Logic LUT | 6035 | 6221 | +186 |
| Slice LUT | 6507 | 6693 | +186 |
| LUTRAM | 472 | 472 | 0 |
| FF | 1807 | 1871 | +64 |
| WNS | -0.059 ns | -1.318 ns | -1.259 ns |
| Fmax estimate | 197.668 MHz | 158.278 MHz | -39.390 MHz |

## Profile Details

```text
PMUL_PROFILE_WALL_CYCLES=310346
PMUL_PROFILE_GF_MUL_STARTS=1203
PMUL_PROFILE_GF_MUL_STARTS_ADD=1165
PMUL_PROFILE_ST_ECC_DIAG_CYCLES=131127
PMUL_PROFILE_ST_ECC_LEAF_FOLD_CYCLES=129924
```

The cycle gain comes from reducing diagonal issue cycles.  Leaf fold cycles are
unchanged because only one diagonal group is overlapped with the last fold
cycle.

## Functional Checks

All required first-round functional checks passed:

```text
HDEC_ECC_REDUCE_V1: PASS
HDEC_ECC_PMUL_PROFILE_V27: PASS
HDEC_HDC_FULL_FLOW_V20: PASS
HDEC_ECC_PMUL_BG_HDC_LOOP_V31: PASS
```

The interleaved ECC/HDC check reported:

```text
HDC_FULL_FLOW_STANDALONE_CYCLES=959
PMUL_BG_HDC_LOOP_WALL_CYCLES=434133
PMUL_BG_HDC_LOOP_HDC_ITERS=201
PMUL_BG_HDC_LOOP_EQUIV_HDC_CYCLES=192759
PMUL_BG_HDC_LOOP_STATUS_LOW16=0
```

## Timing Interpretation

Plan 1 is functionally correct and gives a real cycle reduction, but it is not a
good timing point in Vivado 2022.2.

Worst path:

```text
Source:      ecc_fold_leaf_path_q_reg[5]/C
Destination: ecc_diag16_pipe_q_reg[13]/D
Data delay:  6.315 ns
Logic levels: 8
```

The new direct operand path from fold state into the diagonal parity pipe is too
long.  This confirms that a stronger overlap version should add a register
boundary before the diagonal parity cone, or accept a smaller overlap.

## Decision

Keep this commit as the V36 Plan 1 measured trial.

It is useful because it proves that even a one-diagonal overlap saves about
`31k` cycles.  It is not yet a retained final RTL candidate because the timing
cost is large and the area delta is above the original small-area target.
