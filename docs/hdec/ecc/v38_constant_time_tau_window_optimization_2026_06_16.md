# V38 constant-time tau-window optimization study

Date: 2026-06-16
Branch: `hdec-ecc-pointmul-v38`
Base RTL: V37 one-inversion RTL, with the leading-zero skip reverted
Tool baseline: Vivado 2024.2 XSIM profile

## Non-negotiable constraint

The scalar `K` is treated as a random secret scalar.

Invalid optimizations:

- Changing `K` to a short value such as `3`.
- Skipping leading zero scalar bits.
- Skipping a point-add or point-double state because one scalar bit or digit is
  zero.
- Reporting a variable-time scalar-dependent result as an ECC speedup.

Valid tau-based optimizations must keep a fixed public schedule. The result can
depend on public parameters such as curve, window width, and fixed table shape,
but not on the secret scalar digit values.

## Updated profile baseline

The PMUL profile test now uses a deterministic full-width pseudo-random scalar:

```text
K = 0x000001807641b930b5b5658e21062f9465931d9dfc2010db64170d358aa115a0
bit_length(K) = 233
```

Reference result from the K-233 model:

```text
X = 0x000000f43234b60b69a741092b0bae60cb7bdd1f4f41678ce500a24138589932
Y = 0x000000cd8f8a1c7e66f52b0e7dd4f01c9c9d9c9c74e42ec48eaebd9ffa719484
```

XSIM result:

```text
reports/hdec/v38_rand_scalar_baseline_2026_06_16/xsim_ecc_pmul_profile_v27/xsim.log
```

Key counters:

| Counter | Value |
|---|---:|
| `PMUL_PROFILE_WALL_CYCLES` | 333481 |
| `PMUL_PROFILE_GF_MUL_STARTS` | 1188 |
| `PMUL_PROFILE_GF_MUL_STARTS_ADD` | 1165 |
| `PMUL_PROFILE_SQR_STARTS` | 1633 |
| `PMUL_PROFILE_INV_STARTS` | 1 |
| `PMUL_PROFILE_SUB_ADD_CYCLES` | 309657 |
| `PMUL_PROFILE_SUB_DBL_CYCLES` | 15608 |
| `PMUL_PROFILE_SUB_AFFINE_CYCLES` | 8199 |
| Result | PASS |

This is the correct baseline for further optimization: a full 233-bit scalar
with a fixed 233-round ladder schedule.

## Why ordinary sparse tau-NAF is not enough

Sparse tau-NAF gives a small number of non-zero digits. For the selected
pseudo-random scalar, the reduced tau-NAF model gives:

| Window | Reduced digit length | Non-zero digits | Estimated 5M add multiplications |
|---:|---:|---:|---:|
| 2 | 234 | 78 | 390 |
| 3 | 235 | 60 | 300 |
| 4 | 230 | 46 | 230 |
| 5 | 240 | 40 | 200 |

This is useful for algorithm understanding, but a direct variable-time
implementation would skip zero digits and leak scalar information. So it is not
the RTL target.

## Constant-time residue-window tau method

The hardware-friendly constant-time version uses a residue table modulo
`tau^w`.

For each fixed window:

```text
1. Apply tau exactly w times to the accumulator.
2. Select one table point from a public 2^w-entry table using masked selection.
3. Execute one point-add slot every window.
4. If the selected residue is zero, run the same add schedule as a dummy path
   and mask the architectural writeback.
```

This does not skip scalar zero bits. The number of windows is fixed by `w` and
the curve size, not by the value of `K`.

The reference model now verifies this residue-window method against ordinary
K-233 scalar multiplication.

For 100 random full-width samples:

| Window | Avg windows | Max windows | Avg zero masks | Table entries | Constant-time add slots |
|---:|---:|---:|---:|---:|---:|
| 2 | 116.54 | 118 | 28.85 | 4 | 118 |
| 3 | 77.74 | 79 | 9.37 | 8 | 79 |
| 4 | 58.57 | 59 | 3.12 | 16 | 59 |
| 5 | 46.81 | 47 | 1.60 | 32 | 47 |
| 6 | 39.18 | 40 | 0.65 | 64 | 40 |

So the constant-time add-slot count can shrink from 233 to:

```text
w=4: 59 fixed add slots
w=5: 47 fixed add slots
w=6: 40 fixed add slots
```

The zero masks do not reduce the schedule. They only say how often the selected
residue is the neutral table entry; hardware still runs a dummy add slot.

## Cycle estimates

Measured current add path:

```text
current add subop cycles = 309657
current fixed add slots  = 233
average add slot         = 309657 / 233 = 1329 cycles
```

The current 5M differential add is not automatically reusable as a general
tau-window mixed add. Therefore estimates use two models:

- optimistic 5M-compatible add: 1329 cycles per add slot
- conservative 8M mixed add: about `1329 * 8 / 5 = 2126` cycles per add slot

Tau cost is small relative to field multiplication. The current profile shows
`1633` square starts and `3266` HSPREAD cycles, about 2 cycles per square start.
Even if tau on projective coordinates needs 3 coordinate squares per tau step,
the full 233 tau steps are about:

```text
233 * 3 * 2 = 1398 cycles
```

Estimated runtime without table precomputation:

| Window | Table entries | Add slots | 5M-compatible estimate | 8M mixed-add estimate |
|---:|---:|---:|---:|---:|
| 3 | 8 | 79 | ~114k | ~178k |
| 4 | 16 | 59 | ~88k | ~135k |
| 5 | 32 | 47 | ~72k | ~110k |
| 6 | 64 | 40 | ~63k | ~95k |

These include the current affine tail estimate of 8199 cycles and the tau
square estimate above.

If arbitrary-base runtime table generation is required, add approximately
`(2^w - 1)` point-add-like slots for table setup. That changes the picture:

| Window | Runtime table add slots | 5M-compatible total with setup | 8M mixed-add total with setup |
|---:|---:|---:|---:|
| 3 | 7 | ~123k | ~193k |
| 4 | 15 | ~108k | ~167k |
| 5 | 31 | ~113k | ~176k |
| 6 | 63 | ~147k | ~229k |

So the best route depends on whether the base point is fixed/reusable:

- fixed-base or reusable table: `w=4` or `w=5` is the best first RTL target.
- arbitrary-base with runtime table: `w=4` is the sanest area/performance
  compromise; `w=5` starts paying too much setup.

## RTL implications

The current PMUL loop is an XZ differential ladder. It only keeps enough
information for the current fixed-difference add/double schedule. It does not
directly maintain the general projective point state needed by a tau-window
mixed add.

Therefore tau-window is not a one-line state-machine edit. The next RTL step is
to add a new projective/mixed point-add microprogram and then drive it from a
fixed window scheduler.

Minimum viable hardware direction:

1. Keep the existing binary ladder as the default arbitrary-point path.
2. Add an experimental K-233 tau-window path guarded by a separate mode bit or
   build parameter.
3. Start with `w=4`, because it needs only 16 table entries and 59 fixed add
   slots.
4. Store or load the residue table as point pairs. A 16-entry affine table is
   16 * 2 * 233 = 7456 data bits before packing.
5. Use masked table selection. Do not branch on the secret residue mask.
6. For residue mask zero, execute a dummy add schedule and mask architectural
   writeback.
7. Measure the mixed-add formula first. If it is near 8M, combine with D2/D3
   multiplier work before expecting a stable sub-100k result.

## Current judgment

The honest lower bound is no longer the false 11k result from a short scalar.
With a fixed full-width schedule, tau-window can still plausibly reduce the PMUL
from 333k to:

```text
~88k if w=4 can reuse a 5M-like add and the table is fixed/reusable
~108k if w=4 needs runtime table setup but keeps a 5M-like add
~110k if w=5 uses an 8M mixed add and the table is fixed/reusable
~95k if w=6 uses an 8M mixed add and the table is fixed/reusable, but area risk is high
```

The best next RTL target is:

```text
w=4 constant-time residue-window tau path
+ projective/mixed point-add microprogram
+ masked 16-entry table selection
```

This is the first tau direction that both has large cycle potential and obeys
the no-scalar-dependent-skipping rule.
