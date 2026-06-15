# V36 ECC Optimization Plan: Vivado 2022.2 First Round

This document defines the V36 first-round optimization plan.  The immediate
goal is not to force Vivado 2022.2 to pass 200 MHz.  The goal is to measure
each RTL change against the same V35 Vivado 2022.2 baseline, then later rerun
the promising trials in Vivado 2024.2.

## 1. Baseline Brought Forward From V35

Current V36 starts from V35 selected RTL:

```text
commit 4193f204 hdec: select V35 5M point-add optimization
branch hdec-ecc-pointmul-v36
```

V35 selected RTL keeps:

```text
ADD 5M cross-product + selected double XZ
```

This means point-add keeps `T0 = X0*Z1` and `T1 = X1*Z0`, computes
`T6 = T0*T1`, and computes only the selected `X*Z` value still needed by the
following double step.

## 2. V35 Reference Numbers

### Vivado 2024.2 Reference From Existing V35 Report

These numbers are from the V35 report already in the repository.

| Metric | V35 Vivado 2024.2 |
| --- | ---: |
| PMUL wall cycles | 341624 |
| Logic LUT | 5921 |
| FF | 1802 |
| Fmax estimate | 210.217 MHz |
| Notes | selected V35 RTL, `GF_MUL_STARTS_ADD=1165` |

The 2024.2 V35 selected row did not separately record Slice LUT, LUTRAM, or WNS.
The earlier V33 baseline in the same report had LUTRAM `472`; the selected V35
change is formula/control only, so LUTRAM is expected to remain `472`.

### Vivado 2022.2 Local Baseline

This run was generated locally with:

```text
Vivado: H:\SWTOOLS\Vivado\2022.2\bin\vivado.bat
Script: scripts/hdec/ooc_hdec_timing_atlas.tcl
Part: xc7z020clg400-2
Clock: 5.000 ns
Output: reports/hdec/v35_vivado2022_2_compare_20260615/
```

| Metric | V35 Vivado 2022.2 |
| --- | ---: |
| PMUL wall cycles | 341624 |
| Slice LUT | 6507 |
| Logic LUT | 6035 |
| LUTRAM | 472 |
| FF | 1807 |
| CARRY4 | 15 |
| WNS | -0.059 ns |
| Fmax estimate | 197.668 MHz |
| Worst endpoint | `i_vrf/.../WADR3` |

The profile simulation passed:

```text
PMUL_PROFILE_WALL_CYCLES=341624
PMUL_PROFILE_GF_MUL_STARTS=1203
PMUL_PROFILE_GF_MUL_STARTS_ADD=1165
PMUL_PROFILE_ST_ECC_DIAG_CYCLES=162405
PMUL_PROFILE_ST_ECC_LEAF_FOLD_CYCLES=129924
[HDEC_ECC_PMUL_PROFILE_V27] PASS
```

For V36 first-round experiments, compare every result primarily against this
Vivado 2022.2 baseline:

```text
cycles = 341624
Logic LUT = 6035
FF = 1807
Fmax = 197.668 MHz
```

## 3. First-Round Execution Plan

V36 first round has one baseline task and three RTL trial plans.

## Plan 0: Freeze The V36 Baseline

Principle:

Use V35 selected RTL as the starting point and keep both tool references in the
report.  Do not judge early V36 trials by absolute Vivado 2022.2 200 MHz pass or
fail.  Instead, judge whether each trial improves cycles, LUT, FF, or the worst
path relative to V35 under the same 2022.2 tool.

Expected result:

No RTL change.

Success criteria:

```text
xsim PMUL profile remains 341624 cycles
OOC result remains close to 6035 Logic LUT / 1807 FF
```

## Plan 1: One-Entry Partial Leaf Compute/Fold Overlap

This is the first real RTL trial.

Current behavior:

```text
compute leaf N
fold leaf N into ecc_product_pair
then compute leaf N+1
```

The profile shows the current V35 PMUL spends:

```text
diagonal compute cycles = 162405
leaf fold cycles        = 129924
```

So leaf fold is a large visible cost.  Full overlap was already proven fast, but
it was too large.  The V36 version should be smaller.

Proposed behavior:

```text
compute leaf N+1 while folding leaf N
```

But only add one narrow fold latch, not a full ping-pong leaf context.

Suggested extra state:

```text
fold_latch_prod
fold_latch_path
fold_latch_mask
fold_latch_valid
fold_phase
```

The important rule is that fold still uses the existing `ecc_product_pair` write
path.  The trial should not add a second product accumulator and should not steal
the VRF write port.

Why this may work:

The diagonal calculator and the product fold logic are different local blocks.
Today the schedule serializes them.  If we hide one or two fold cycles under the
next leaf's operand-read or diagonal-start window, cycles can drop without
widening the diagonal datapath.

Expected result versus V35 Vivado 2022.2:

| Metric | Expected |
| --- | ---: |
| PMUL cycles | 300k to 325k |
| Cycle improvement | 16k to 42k |
| Logic LUT delta | +50 to +120 |
| Target Logic LUT delta | under +80 |
| FF delta | +40 to +100 |
| Timing risk | medium |

What to watch:

If the design starts adding wide muxes around `ecc_product_pair`, this trial
should be stopped or reduced.  The point is to add a small queue, not another
multiplier or another product RAM.

## Plan 2: Slim Diagonal Tail Bypass

This is the second small-area trial.

Existing V35 trial history:

```text
Diagonal tail bypass v1:
PMUL cycles 363199
cycle delta -38772 versus V33 baseline
Logic LUT delta +119
```

It was rejected because `+119 LUT` was slightly above the small-increase target.
For V36, the goal is not to reuse that full version directly.  The goal is to
make a smaller version that only handles the common PMUL field-multiply tail.

Principle:

The KPD32 diagonal path has a small pipeline tail before leaf fold can consume
the completed product.  If the final diagonal result is already known, some of
the wait/drain behavior can be bypassed or merged into the next fold step.

Expected result versus V35 Vivado 2022.2:

| Metric | Expected |
| --- | ---: |
| PMUL cycles | 310k to 330k |
| Cycle improvement | 12k to 32k |
| Logic LUT delta | +50 to +110 |
| Target Logic LUT delta | under +90 |
| FF delta | +5 to +25 |
| Timing risk | low to medium |

Why this is worth trying:

It is less ambitious than full compute/fold overlap.  It may not save as many
cycles, but it is easier to isolate and easier to revert if the area grows.

What to watch:

Do not generalize the bypass to every ECC mode first.  Start with the PMUL
field path.  If the common case gives a good result, then decide whether the
same structure is worth extending.

## Plan 3: KPD64 With 8 Diagonals Per Cycle

This is the wider multiplier-structure trial.  It should run after Plan 1 or
Plan 2, not before them.

Existing V35 trial history:

```text
KPD64 64-bit leaf, 16 diagonals/cycle:
PMUL cycles 221035
cycle delta -180936 versus V33 baseline
Logic LUT delta +1059
FF 1960
Fmax 193.761 MHz in Vivado 2024.2
```

The full version proved the speed idea, but the 64-bit diagonal parity cone was
too wide and too expensive.

Proposed V36 behavior:

```text
256 -> 128 -> 64
3^2 = 9 leaves
8 diagonals per cycle, not 16
```

Why this may work:

Going from 27 leaves to 9 leaves saves a lot of fold and bookkeeping.  Reducing
the issue width from 16 diagonals to 8 diagonals cuts the local 64-bit
AND/XOR-reduction pressure.  It will not be as fast as full KPD64, but it may
recover timing and reduce area.

Expected result versus V35 Vivado 2022.2:

| Metric | Expected |
| --- | ---: |
| PMUL cycles | 260k to 310k |
| Cycle improvement | 32k to 82k |
| Logic LUT delta | +200 to +600 |
| Stretch Logic LUT target | under +250 |
| FF delta | +50 to +180 |
| Timing risk | high |

Why this is not Plan 1:

Even the narrowed version changes the multiplier structure deeply.  It is more
likely to exceed the small-area goal than Plan 1 or Plan 2.  It is still worth
testing because it can show whether the 64-bit leaf idea has a practical
middle point between KPD32 and full KPD64.

## 4. Deferred Ideas

### Direct Reduced Accumulation

Do not execute this in the first V36 round.

It has already been tested once:

```text
PMUL cycles 391919
cycle delta -10052 versus V33 baseline
Logic LUT delta +769
```

The idea is mathematically clean, but the current RTL creates a large dynamic
XOR/mux network when each leaf contribution is folded directly into a reduced
233-bit accumulator.  The existing `ecc_product_pair` LUTRAM is not the main
cost.  The dynamic reduced fold network is the cost.

### Full D4 Digit-Serial Multiplier

Do not execute this in the first V36 round.

It was very fast, but too large:

```text
PMUL cycles 126259
Logic LUT delta +1911
FF 2537
```

A future D2-lite version may be useful, but only if it reuses existing VRF,
lane, or `ecc_product_pair` state and avoids new full-width `Awork`, `Bwork`,
and `Acc` registers.

## 5. Recommended Order

The planned V36 order is:

```text
0. Freeze and document V35/V36 baseline numbers.
1. Implement one-entry partial leaf compute/fold overlap.
2. If Plan 1 is too large, try slim diagonal tail bypass.
3. If small-area plans are not enough, try KPD64 with 8 diagonals/cycle.
```

Expected best-case first-round outcome:

```text
V35 2022.2 baseline:
  341624 cycles, 6035 Logic LUT, 1807 FF

Good V36 small-area result:
  300k to 325k cycles
  +50 to +100 Logic LUT
  +10 to +100 FF

Aggressive V36 KPD64-8 result:
  260k to 310k cycles
  +200 to +600 Logic LUT
  +50 to +180 FF
```

The most important comparison for now is not absolute Fmax.  The useful
question is:

```text
Against Vivado 2022.2 V35, how many cycles did we save, and how much LUT/FF did
we pay?
```

After Vivado 2024.2 is available, rerun only the promising V36 states in the
same 2024.2 flow.
