# V38 RTL scalar leading-zero skip result

Date: 2026-06-16
Branch: `hdec-ecc-pointmul-v38`
Base RTL: V37 one-inversion RTL, commit `6667c004`
Selected RTL file: `core/hdec/rtl/hdec_top.sv`
Tool: Vivado 2024.2, OOC target period 5.000 ns, part `xc7z020clg400-2`

## Goal

This RTL round starts from the V37 one-inversion PMUL datapath and tries to
reduce the scalar point multiplication wall cycles with a very small control
change.

The V37 PMUL controller always starts the Montgomery-style XZ loop at bit 232.
For the current profile scalar `0x3`, that means most of the point loop is spent
processing leading zero scalar bits. The selected V38 RTL scans down to the
first non-zero scalar bit before entering the normal add/double sequence.

This is not the full tau-NAF RTL implementation. It keeps the existing V37
point-add, point-double, field multiplier, squarer, and one-inversion affine
tail.

## Selected RTL

The selected version changes only `S_ECC_PMUL_READ_SCALAR` during
`ECC_PMUL_CTRL_INIT`:

1. If the current scalar bit is one, start the existing point-add path.
2. If an upper scalar chunk is zero, jump over it.
3. Otherwise scan down one bit per read.
4. If all bits are zero, go directly to the zero-output tail.

Selected skip boundaries:

```text
232 -> 191 if scalar[232:192] is zero
191 -> 127 if scalar[191:128] is zero
127 ->  63 if scalar[127:64]  is zero
 63 ->  31 if scalar[63:32]   is zero
 31 ->  15 if scalar[31:16]   is zero
```

This was the best measured point in this round. Adding the next `15 -> 7`
boundary looked attractive in simulation, but it made the 2024.2 OOC result much
worse.

## Result Summary

Baseline numbers come from the V37 one-inversion report. All V38 attempts below
were measured on top of V37.

| Version | Sim | Cycles | Delta vs V37 | Logic LUT | Delta vs V37 | FF | Delta vs V37 | WNS(ns) | Fmax(MHz) | Decision |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| V37 one inversion | PASS | 333481 | 0 | 6013 | 0 | 1815 | 0 | 0.247 | 210.393 | Baseline |
| One-bit leading-zero scan | PASS | 11467 | -322014 | 5999 | -14 | 1812 | -3 | 0.123 | 205.044 | Good, superseded |
| Word skip only | PASS | 11135 | -322346 | 6098 | +85 | 1814 | -1 | 0.126 | 205.170 | Good, superseded |
| Word skip plus `63 -> 31` | PASS | 11073 | -322408 | 6083 | +70 | 1814 | -1 | 0.132 | 205.423 | Good, superseded |
| Word skip plus `63 -> 31 -> 15` | PASS | 11043 | -322438 | 6068 | +55 | 1812 | -3 | 0.136 | 205.592 | Selected |
| Add `15 -> 7` | PASS | 11029 | -322452 | 6944 | +931 | 1819 | +4 | -0.468 | 182.882 | Rejected |
| Wider priority encoder | PASS | 11005 | -322476 | 6235 | +222 | 1808 | -7 | -0.263 | 190.006 | Rejected |
| Full low-word skip | PASS | 11021 | -322460 | 6133 | +120 | 1810 | -5 | -0.466 | 182.949 | Rejected |
| Earlier hierarchical skip | PASS | 11021 | -322460 | 6048 | +35 | 1805 | -10 | -0.330 | 187.617 | Rejected |
| Fold0 bypass experiment | FAIL | 10576-like | n/a | n/a | n/a | n/a | n/a | n/a | n/a | Rejected, result mismatch |

The selected version reduces the current profile from 333481 cycles to 11043
cycles, a reduction of 322438 cycles, while keeping positive 200 MHz OOC timing.
The selected OOC area is 6068 Logic LUT and 1812 FF. Relative to V37 this is
only +55 Logic LUT and -3 FF.

## Selected Profile

Simulation log:

```text
reports/hdec/v38_scalar_word_plus32_16_skip_2026_06_16/xsim_ecc_pmul_profile_v27/xsim.log
```

Key counters:

| Counter | Value |
|---|---:|
| `PMUL_PROFILE_WALL_CYCLES` | 11043 |
| `PMUL_PROFILE_STATUS_LOW16` | 0 |
| `PMUL_PROFILE_SUB_INIT_CYCLES` | 55 |
| `PMUL_PROFILE_SUB_ADD_CYCLES` | 2658 |
| `PMUL_PROFILE_SUB_DBL_CYCLES` | 131 |
| `PMUL_PROFILE_SUB_AFFINE_CYCLES` | 8199 |
| `PMUL_PROFILE_GF_MUL_STARTS` | 33 |
| `PMUL_PROFILE_GF_MUL_STARTS_ADD` | 10 |
| `PMUL_PROFILE_GF_MUL_STARTS_AFFINE` | 23 |
| `PMUL_PROFILE_GF_MUL_STARTS_INV_MUL` | 10 |
| `PMUL_PROFILE_SQR_STARTS` | 247 |
| `PMUL_PROFILE_INV_STARTS` | 1 |
| `PMUL_PROFILE_ST_ECC_DIAG_CYCLES` | 4455 |
| `PMUL_PROFILE_ST_ECC_LEAF_FOLD_CYCLES` | 3564 |
| `PMUL_PROFILE_ST_ECC_REDUCE_CYCLES` | 1120 |
| Result | PASS |

After this change the current scalar `0x3` profile is no longer dominated by
233 fixed point-loop iterations. It is dominated by the final affine recovery
tail:

```text
SUB_AFFINE = 8199 / 11043 = 74.2%
```

The add loop uses only:

```text
GF_MUL_STARTS_ADD = 10 = 2 scalar bits * 5 field multiplies
```

That matches the selected 5M add formula from V35 and confirms that the loop is
now running only for the useful scalar bits in this profile.

## Selected OOC

OOC reports:

```text
reports/hdec/v38_scalar_word_plus32_16_skip_2026_06_16/ooc_scalar_word_plus32_16_skip/reports/run_summary.txt
reports/hdec/v38_scalar_word_plus32_16_skip_2026_06_16/ooc_scalar_word_plus32_16_skip/reports/utilization.rpt
```

OOC summary:

| Metric | Value |
|---|---:|
| WNS(ns) | 0.136 |
| Fmax estimate(MHz) | 205.592 |
| Slice LUTs | 6540 |
| Logic LUT | 6068 |
| LUTRAM | 472 |
| FF | 1812 |
| BRAM | 0 |
| DSP | 0 |
| CARRY4 | 25 |
| Worst endpoint | `ecc_pmul_step_q_reg[0]/CE` |

## Important Limits

This is a variable-time scalar-length optimization. It leaks at least the
position of the highest non-zero scalar bit, plus some coarse zero-chunk
information from the skip boundaries. If PMUL is used with secret scalars in a
side-channel-sensitive setting, this path needs either a constant-time mode or a
different masked/windowed design.

This optimization also does not reduce the full-width worst case where bit 232
is already set. Its large gain on the current profile comes from the current
test scalar being `0x3`.

For a true worst-case ECC scalar speedup, the next RTL work should change the
point-multiplication algorithm rather than only trimming leading zero bits. The
most plausible next directions are:

1. A hardware-friendly tau-NAF or fixed-base Koblitz path with precomputed odd
   multiples.
2. A mixed-coordinate add path that can use tau/Frobenius steps without carrying
   the same XZ ladder dependency.
3. A smaller affine-tail redesign, because after this skip the affine recovery
   tail is the largest measured block in the current scalar `0x3` profile.
