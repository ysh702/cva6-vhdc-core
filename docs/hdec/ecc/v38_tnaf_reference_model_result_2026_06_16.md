# V38 K-233 tau-NAF reference model result

Date: 2026-06-16
Branch: `hdec-ecc-pointmul-v38`
Base RTL: V37 one-inversion RTL, commit `6667c004`
New artifact: `scripts/hdec/ecc_k233_tnaf_ref.py`

This is the first implementation step for the V38 Koblitz direction. It does
not modify RTL. It builds a software reference model for K-233 affine point
arithmetic and window tau-adic scalar multiplication.

## What was implemented

The new script implements:

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
- Tau-window point multiplication using precomputed odd multiples.
- Self-checks against ordinary affine scalar multiplication.

This script intentionally starts with unreduced window tau-NAF. It proves the
core algebra first. Solinas partial modular reduction is the next step.

## Verification command

The Windows PATH in this desktop environment does not currently expose
`python`, so this run used the Codex bundled Python runtime:

```powershell
& 'C:\Users\Administrator\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' scripts\hdec\ecc_k233_tnaf_ref.py --samples 100 --seed 37
```

Output summary:

```text
[PASS] K-233 base point, 3G vector, and tau-window equivalence
```

The self-test verifies:

1. The K-233 base point is on the curve.
2. Ordinary affine `3G` equals the current RTL testbench expected result.
3. Window tau multiplication equals ordinary affine multiplication for scalar
   values `0`, `1`, `2`, `3`, `5`, `7`, `0x12345`, and
   `(1 << 232) + 12345`.
4. The tau digits evaluate back to the original scalar in the tau ring.

## Scalar examples

These counts exclude precomputation cost.

| Scalar | Window | Digit length | Nonzero digits | Max digit | Estimated 5M add multiplications |
|---|---:|---:|---:|---:|---:|
| `0x3` | 2 | 6 | 3 | 1 | 15 |
| `0x3` | 3 | 1 | 1 | 3 | 5 |
| `0x3` | 4 | 1 | 1 | 3 | 5 |
| `0x3` | 5 | 1 | 1 | 3 | 5 |
| `0x12345` | 2 | 32 | 11 | 1 | 55 |
| `0x12345` | 3 | 35 | 9 | 3 | 45 |
| `0x12345` | 4 | 34 | 7 | 7 | 35 |
| `0x12345` | 5 | 35 | 7 | 11 | 35 |
| `(1 << 232) + 12345` | 2 | 466 | 91 | 1 | 455 |
| `(1 << 232) + 12345` | 3 | 466 | 65 | 3 | 325 |
| `(1 << 232) + 12345` | 4 | 471 | 53 | 7 | 265 |
| `(1 << 232) + 12345` | 5 | 461 | 45 | 15 | 225 |

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

| Window | Average length | Average nonzero digits | Min nonzero | Max nonzero | Estimated 5M add multiplications | Estimated 8M add multiplications |
|---:|---:|---:|---:|---:|---:|---:|
| 2 | 464.42 | 155.75 | 141 | 171 | 778.75 | 1246.00 |
| 3 | 464.80 | 116.62 | 106 | 127 | 583.10 | 932.96 |
| 4 | 467.10 | 93.96 | 86 | 100 | 469.80 | 751.68 |
| 5 | 466.97 | 78.49 | 72 | 83 | 392.45 | 627.92 |

This already supports the main V38 idea:

```text
current fixed ladder add multiplications: 1165
unreduced w=4 average estimate:          about 470
unreduced w=5 average estimate:          about 392
```

Even before partial modular reduction, the estimated add-side field
multiplication count falls by about:

```text
w=4: (1165 - 470) / 1165 = about 60%
w=5: (1165 - 392) / 1165 = about 66%
```

The cost is more Frobenius steps. In this unreduced model, the digit length is
about 465 to 470, not about 233. But a Frobenius step is coordinate squaring,
and the current RTL profile shows square/spread cycles are tiny compared with
field multiply cycles:

```text
PMUL_PROFILE_ST_HSPREAD_CYCLES = 3266
PMUL_PROFILE_ST_ECC_DIAG_CYCLES + PMUL_PROFILE_ST_ECC_LEAF_FOLD_CYCLES = 288684
```

So the tradeoff still looks promising.

## What this does not prove yet

This reference model does not yet prove a ready-to-RTL implementation.

Open items:

1. It uses affine point arithmetic, while RTL should avoid inversions in the
   main loop.
2. It does not yet implement Solinas partial modular reduction, so the tau
   digit length is about `2m` instead of about `m`.
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

The V38 direction is worth continuing.

The first reference model confirms the most important algebraic point:

```text
tau-window multiplication can reproduce ordinary K-233 scalar multiplication
while replacing many point-add slots with cheap Frobenius square steps.
```

For the next step, I would not touch the RTL yet. The next clean milestone is:

```text
add Solinas partial modular reduction to the Python model
```

Expected effect:

- reduce tau digit length from about `2m` to about `m`,
- move `w=4` average nonzero digits toward roughly `233 / 5 = 47`,
- make the sub-100k-cycle target more realistic,
- clarify the precomputation table size and side-channel cost before RTL work.

After that, we can decide whether V38 RTL should start with:

1. fixed-base K-233 tau-NAF using a small precomputed table, or
2. arbitrary-point tau-NAF with runtime precomputation, or
3. a conservative hybrid that first supports the current profiled base point.
