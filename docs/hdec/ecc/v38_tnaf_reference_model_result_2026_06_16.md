# V38 K-233 tau-NAF reference model result

Date: 2026-06-16
Branch: `hdec-ecc-pointmul-v38`
Base RTL: V37 one-inversion RTL, commit `6667c004`
New artifact: `scripts/hdec/ecc_k233_tnaf_ref.py`

This is the first implementation step for the V38 Koblitz direction. It does
not modify RTL. It builds a software reference model for K-233 affine point
arithmetic and window tau-adic scalar multiplication.

## What was implemented

The updated script implements:

- GF(2^233) add, multiply, square, reduce, divide, and inverse.
- Affine binary-curve point add/double for:

```text
y^2 + x*y = x^3 + 1
f(x) = x^233 + x^74 + 1
```

- The K-233 base point used by the current HDEC PMUL testbench.
- Ordinary affine binary scalar multiplication.
- Frobenius map:

```text
tau(P) = (x^2, y^2)
```

- Window tau-NAF digit generation for widths 2 through 5.
- Exact lattice reduction of the scalar by the K-233 relation
  `tau^233 - 1`.
- Tau-window point multiplication using precomputed odd multiples.
- Self-checks against ordinary affine scalar multiplication.

The first version intentionally started with unreduced window tau-NAF. This
version adds an exact reduction model using the relation `tau^233(P)=P` for
K-233 points. It is not yet the hardware-friendly Solinas constant-based
partial reduction, but it gives the right algorithm-level target numbers.

## Verification command

The Windows PATH in this desktop environment does not currently expose
`python`, so this run used the Codex bundled Python runtime:

```powershell
& 'C:\Users\Administrator\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' scripts\hdec\ecc_k233_tnaf_ref.py --samples 100 --seed 37
```

Output summary:

```text
[PASS] K-233 base point, 3G vector, tau-window, and reduced tau-window equivalence
```

The self-test verifies:

1. The K-233 base point is on the curve.
2. Ordinary affine `3G` equals the current RTL testbench expected result.
3. `tau^233(P)=P` for the K-233 base point.
4. Window tau multiplication equals ordinary affine multiplication for scalar
   values `0`, `1`, `2`, `3`, `5`, `7`, `0x12345`, and
   `(1 << 232) + 12345`.
5. Reduced-window tau multiplication equals ordinary affine multiplication for
   the same scalar values.
6. The tau digits evaluate back to the original or reduced tau-ring element.

## Scalar examples

These counts exclude precomputation cost. `red_*` columns are after the
`tau^233 - 1` lattice reduction.

| Scalar | Window | Unreduced length | Unreduced weight | Reduced length | Reduced weight | Max digit | Reduced estimated 5M multiplications |
|---|---:|---:|---:|---:|---:|---:|---:|
| `0x3` | 2 | 6 | 3 | 6 | 3 | 1 | 15 |
| `0x3` | 3 | 1 | 1 | 1 | 1 | 3 | 5 |
| `0x3` | 4 | 1 | 1 | 1 | 1 | 3 | 5 |
| `0x3` | 5 | 1 | 1 | 1 | 1 | 3 | 5 |
| `0x12345` | 2 | 32 | 11 | 32 | 11 | 1 | 55 |
| `0x12345` | 3 | 35 | 9 | 35 | 9 | 3 | 45 |
| `0x12345` | 4 | 34 | 7 | 34 | 7 | 7 | 35 |
| `0x12345` | 5 | 35 | 7 | 35 | 7 | 11 | 35 |
| `(1 << 232) + 12345` | 2 | 466 | 91 | 231 | 77 | 1 | 385 |
| `(1 << 232) + 12345` | 3 | 466 | 65 | 228 | 57 | 3 | 285 |
| `(1 << 232) + 12345` | 4 | 471 | 53 | 234 | 43 | 7 | 215 |
| `(1 << 232) + 12345` | 5 | 461 | 45 | 233 | 41 | 15 | 205 |

The current RTL profile uses scalar `3`, but the RTL ladder still executes a
fixed 233-bit schedule. That is why the current measured add-side multiply
count is:

```text
GF_MUL_STARTS_ADD = 233 * 5 = 1165
```

For scalar `3`, a window tau method can represent the scalar as one nonzero
digit when `w >= 3`. That is a huge win for this test vector, but it must not be
mistaken for a complete cryptographic design. A real implementation needs a
policy for arbitrary scalars, precomputation, table selection, and side-channel
behavior.

## Random 233-bit scalar statistics

The script sampled 100 deterministic random 233-bit scalars with seed 37.

Unreduced window tau-NAF:

| Window | Average length | Average nonzero digits | Min nonzero | Max nonzero | Estimated 5M add multiplications | Estimated 8M add multiplications |
|---:|---:|---:|---:|---:|---:|---:|
| 2 | 464.42 | 155.75 | 141 | 171 | 778.75 | 1246.00 |
| 3 | 464.80 | 116.62 | 106 | 127 | 583.10 | 932.96 |
| 4 | 467.10 | 93.96 | 86 | 100 | 469.80 | 751.68 |
| 5 | 466.97 | 78.49 | 72 | 83 | 392.45 | 627.92 |

Reduced by the `tau^233 - 1` lattice:

| Window | Average length | Average nonzero digits | Min nonzero | Max nonzero | Estimated 5M add multiplications | Estimated 8M add multiplications |
|---:|---:|---:|---:|---:|---:|---:|
| 2 | 231.80 | 78.05 | 65 | 90 | 390.25 | 624.40 |
| 3 | 232.00 | 58.76 | 51 | 65 | 293.80 | 470.08 |
| 4 | 233.61 | 47.82 | 42 | 54 | 239.10 | 382.56 |
| 5 | 233.51 | 39.63 | 36 | 43 | 198.15 | 317.04 |

This strongly supports the main V38 idea:

```text
current fixed ladder add multiplications: 1165
reduced w=4 average estimate:            about 239 if the add formula stays 5M
reduced w=5 average estimate:            about 198 if the add formula stays 5M
```

After reduction, the estimated add-side field multiplication count falls by
about:

```text
w=4: (1165 - 239) / 1165 = about 79.5%
w=5: (1165 - 198) / 1165 = about 83.0%
```

The cost is more Frobenius steps. In this reduced model, the digit length is
now about 232 to 234 after reduction. A Frobenius step is coordinate squaring,
and the current RTL profile shows square/spread cycles are tiny compared with
field multiply cycles:

```text
PMUL_PROFILE_ST_HSPREAD_CYCLES = 3266
PMUL_PROFILE_ST_ECC_DIAG_CYCLES + PMUL_PROFILE_ST_ECC_LEAF_FOLD_CYCLES = 288684
```

So the tradeoff still looks promising.

## Cycle estimate against V37

The measured V37 profile gives:

```text
wall cycles                  = 333481
point-add subop cycles        = 309657
point-adds in fixed ladder    = 233
average current 5M add path   = 309657 / 233 = about 1329 cycles
final affine tail             = 8199 cycles
hspread cycles per square     = 3266 / 1633 = about 2 cycles
```

For tau-NAF, a rough variable-time estimate is:

```text
nonzero_digits * point_add_cost
+ digit_length * tau_square_cost
+ final_affine_tail
+ precompute_cost
```

For `tau_square_cost`, this document uses a deliberately simple low estimate:
two coordinate squares per tau step, about four cycles using the current
`HSPREAD` counter. This is not a final RTL schedule, but it is enough to show
whether the method has order-of-magnitude potential.

Runtime precomputation is small compared with the main loop:

```text
w=4 table: P, 3P, 5P, 7P      => 2P + 3 extra point additions
w=5 table: P..15P odd points  => 2P + 7 extra point additions
```

If the base point is fixed, the table can be fixed or loaded and the runtime
precompute term can be close to zero. If arbitrary input points must be
supported, the runtime precompute term must be paid.

| Window | Add cost model | Main add cycles | Tau square cycles | Affine tail | Runtime precompute | Estimated total |
|---:|---|---:|---:|---:|---:|---:|
| 4 | 5M/current add path | 63545 | 934 | 8199 | 3987 | 76665 |
| 4 | 8M mixed-add estimate | 101672 | 934 | 8199 | 6380 | 117185 |
| 5 | 5M/current add path | 52664 | 934 | 8199 | 9303 | 71100 |
| 5 | 8M mixed-add estimate | 84262 | 934 | 8199 | 14882 | 108277 |

If precomputed odd multiples are fixed and do not need runtime construction,
the same estimates become roughly:

| Window | Add cost model | Estimated total without runtime precompute |
|---:|---|---:|
| 4 | 5M/current add path | 72678 |
| 4 | 8M mixed-add estimate | 110805 |
| 5 | 5M/current add path | 61797 |
| 5 | 8M mixed-add estimate | 93395 |

So the honest conclusion is:

```text
fixed-base or reusable-table tau-NAF:  sub-100k looks realistic
arbitrary-point tau-NAF with 5M add:   sub-100k looks realistic
arbitrary-point tau-NAF with 8M add:   close to 100k, may need multiplier/tail help
```

The largest uncertainty is not the tau-NAF digit count. That part now looks
good. The largest uncertainty is the exact projective/mixed point-add formula
that can be mapped onto the current RTL without increasing area too much.

## What this does not prove yet

This reference model does not yet prove a ready-to-RTL implementation.

Open items:

1. It uses affine point arithmetic, while RTL should avoid inversions in the
   main loop.
2. It uses an exact lattice reduction model, not yet the hardware-friendly
   Solinas constant-time partial reduction sequence.
3. It assumes odd multiples can be precomputed or selected.
4. Window `w=5` has fewer additions, but needs a larger odd-multiple table up
   to `15P`.
5. The current RTL add formula is a special 5M path. A window tau implementation
   may need a mixed-add formula that costs more, for example 5M to 8M depending
   on coordinate choices and whether precomputed points have `Z=1`.
6. Constant-time behavior needs a separate decision. A variable-time tau-NAF
   loop is fast but may leak scalar information. A fixed schedule with masked
   table selection is safer but adds cycles and control.

## Current judgment

The V38 direction is worth continuing and is now the strongest known route
toward the user's 100k-cycle target.

The first reference model confirms the most important algebraic point:

```text
reduced tau-window multiplication can reproduce ordinary K-233 scalar
multiplication while replacing most point-add slots with cheap Frobenius square
steps.
```

For the next step, I would still avoid a full RTL rewrite until the point-add
formula is chosen. The next clean milestone is:

```text
choose and verify the projective/mixed tau-NAF point-add formula
```

Expected effect:

- preserve the reduced `w=4` or `w=5` digit counts,
- decide whether the runtime add path is closer to 5M or 8M,
- make the sub-100k-cycle target more realistic,
- clarify the precomputation table size and side-channel cost before RTL work.

After that, we can decide whether V38 RTL should start with:

1. fixed-base K-233 tau-NAF using a small precomputed table, or
2. arbitrary-point tau-NAF with runtime precomputation, or
3. a conservative hybrid that first supports the current profiled base point.

## References

- Standard curve database, NIST K-233:
  https://std.neuromancer.sk/nist/K-233/
- IACR ePrint 2021/171, window tau-NAF precomputation on Koblitz curves:
  https://eprint.iacr.org/2021/171
- Waterloo CACR 2007-18, scalar multiplication on Koblitz curves:
  https://cacr.uwaterloo.ca/techreports/2007/cacr2007-18.pdf
