# V37 affine batch inversion and ITA evaluation

Date: 2026-06-15
Tool: Vivado 2024.2, xc7z020clg400-2, OOC period 5.000 ns
Base: V35 selected RTL, `ADD 5M cross-product + selected double XZ`

## Goal

This round starts from the V35 baseline and tries to reduce the scalar point
multiplication tail by replacing three final affine inversions with one shared
inversion. The implementation uses the same existing field multiplier, squarer,
and inverter datapath. It does not keep the previous popcount/XOR diagonal
experiment in the RTL.

## Baseline

| Version | PMUL cycles | Logic LUT | FF | WNS(ns) | Fmax(MHz) |
|---|---:|---:|---:|---:|---:|
| V35 selected baseline | 341624 | 5921 | 1802 | 0.243 | 210.217 |

## Attempts

| Attempt | Sim | PMUL cycles | vs V35 | Logic LUT | vs V35 | FF | vs V35 | WNS(ns) | Fmax(MHz) | Decision |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| In-place batch inverse scratch | FAIL | n/a | n/a | n/a | n/a | n/a | n/a | n/a | n/a | Rejected. The existing inverter needs the original source again in later multiply steps, so `src == dst` corrupts the chain. |
| Batch only `R0Z` and `R1Z` inverses | PASS | 337682 | -3942 | n/a | n/a | n/a | n/a | n/a | n/a | Superseded. It reduces affine inversions from 3 to 2, but does not remove the base-x related inverse. |
| Batch `R0Z`, `R1Z`, and base-x inverse | PASS | 333481 | -8143 | 6013 | +92 | 1815 | +13 | 0.247 | 210.393 | Selected as this round's RTL candidate. |

## Selected RTL idea

The selected version uses the standard simultaneous inversion idea:

```text
inv(a), inv(b), inv(c)
=> one inv(a*b*c) plus several field multiplications
```

For the affine tail in this RTL:

```text
T0 = R0Z * R1Z
T2 = T0 * base_x
T3 = inv(T2)

T1 = R1Z * base_x
T1 = T1 * T3        // R0Z^-1
T4 = R0X * T1       // x0

T1 = R0Z * base_x
T1 = T1 * T3        // R1Z^-1
T6 = R1X * T1       // x1

T1 = T0 * T3        // base_x^-1
```

The previous y-recovery path effectively computed:

```text
inv(base_x * (x0 + base_x)) * (x0 + base_x)
```

For the non-exceptional case, this equals:

```text
base_x^-1
```

So the selected version reuses the batched `base_x^-1` and avoids the third
full inversion.

## Simulation profile

Report:
`reports/hdec/v37_affine_batch3_zx_inv_2026_06_15/xsim_ecc_pmul_profile_v27/xsim.log`

| Counter | Value |
|---|---:|
| `PMUL_PROFILE_WALL_CYCLES` | 333481 |
| `PMUL_PROFILE_SUB_ADD_CYCLES` | 309657 |
| `PMUL_PROFILE_SUB_DBL_CYCLES` | 15608 |
| `PMUL_PROFILE_SUB_AFFINE_CYCLES` | 8199 |
| `PMUL_PROFILE_GF_MUL_STARTS` | 1188 |
| `PMUL_PROFILE_GF_MUL_STARTS_ADD` | 1165 |
| `PMUL_PROFILE_GF_MUL_STARTS_AFFINE` | 23 |
| `PMUL_PROFILE_GF_MUL_STARTS_INV_MUL` | 10 |
| `PMUL_PROFILE_SQR_STARTS` | 1633 |
| `PMUL_PROFILE_SQR_STARTS_AFFINE` | 235 |
| `PMUL_PROFILE_SQR_STARTS_INV_SQR` | 232 |
| `PMUL_PROFILE_INV_STARTS` | 1 |
| `PMUL_PROFILE_ST_ECC_DIAG_CYCLES` | 160380 |
| `PMUL_PROFILE_ST_ECC_LEAF_FOLD_CYCLES` | 128304 |

The key result is that the final affine tail now starts one inversion instead
of three. The total point multiplication saves 8143 cycles versus V35.

## OOC result

Reports:

```text
reports/hdec/v37_affine_batch3_zx_inv_2026_06_15/ooc_affine_batch3_zx_inv/reports/run_summary.txt
reports/hdec/v37_affine_batch3_zx_inv_2026_06_15/ooc_affine_batch3_zx_inv/reports/utilization.rpt
```

| Metric | Value |
|---|---:|
| Slice LUT | 6485 |
| Logic LUT | 6013 |
| LUTRAM | 472 |
| FF | 1815 |
| BRAM | 0 |
| DSP | 0 |
| CARRY4 | 13 |
| WNS | 0.247 ns |
| Estimated Fmax | 210.393 MHz |
| Worst endpoint | `lane_result_q_reg[0][14]/D` |

The area increase is small for this project: +92 Logic LUT and +13 FF versus
V35, while the timing margin remains above 200 MHz.

## Risk

This is much safer than changing the per-bit point-add formula, but it still
has correctness risk:

1. The y-recovery cancellation assumes `base_x != 0`.
2. It also assumes the same non-exceptional condition as the old expression:
   `x0 + base_x != 0`.
3. The current regression confirms the profiled scalar test, but more known
   answer tests with different scalars and points are still needed before
   treating it as final cryptographic RTL.

## ITA evaluation

The current inverter is already an Itoh-Tsujii-style fixed square/multiply
chain. It is not an Extended Euclidean inverter.

Evidence in RTL:

```text
ecc_inv_step_has_mul(step)      => multiply on steps 0..9
ecc_inv_step_sqr_repeat(step)   => 232 total squares across one inverse
```

Evidence in this profile:

```text
PMUL_PROFILE_INV_STARTS=1
PMUL_PROFILE_GF_MUL_STARTS_INV_MUL=10
PMUL_PROFILE_SQR_STARTS_INV_SQR=232
```

So one inverse currently costs:

```text
232 field squares + 10 field multiplications
```

This matches the shape of ITA for binary fields: inversion is implemented as
exponentiation with cheap Frobenius squares and a small number of field
multiplications. It does not become "only squares"; multiplications are still
needed to combine exponent blocks.

## ITA direction judgment

Switching to "ITA" as a new algorithm is not the next win, because this RTL is
already using an ITA-like chain. The better immediate ITA-side optimization is
exactly what this round did: reduce the number of inverter invocations.

Possible next steps:

1. Search for a provably better addition chain for `GF(2^233)` inversion. The
   current 10M + 232S chain is already plausible, so any replacement must come
   with a short exponent proof and regression tests.
2. Optimize the square/reduce path. One inverse still spends 2099 cycles in
   inverse-square phase for 232 squares, so a small dedicated linear
   square-reduce path may help if Vivado maps it cheaply.
3. Keep batch inversion for all affine-only or final-normalization cases. This
   is the cleanest low-area win because it changes scheduling and algebra more
   than datapath width.
4. Do not expect this tail-only optimization to reach 100k cycles by itself.
   The profile is still dominated by per-bit point-add field multiplications:
   `PMUL_PROFILE_SUB_ADD_CYCLES=309657`.

References used for the algorithm check:

- Explicit Formulas Database, Lopez-Dahab binary formulas:
  https://www.hyperelliptic.org/EFD/g12o/auto-shortw-lopezdahab.html
- IACR ePrint 2003/264, simultaneous inversions and Montgomery's trick:
  https://eprint.iacr.org/2003/264
- Springer Encyclopedia entry for Itoh-Tsujii inversion:
  https://link.springer.com/rwe/10.1007/978-1-4419-5906-5_34

