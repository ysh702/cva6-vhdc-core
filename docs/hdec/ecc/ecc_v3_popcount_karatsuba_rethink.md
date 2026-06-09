# ECC V3 popcount-Karatsuba rethink

Date: 2026-06-09

This note revises the earlier `D4` digit-serial recommendation. `D4` is a good
engineering fallback, but it is not the best research direction for HDEC because
it weakens the central reuse story: current HDC cost is dominated by
XOR/popcount similarity, not by shift/XOR accumulation.

## Recommended method: KPD32

KPD32 means:

```text
Karatsuba decomposition
+ packed 32-bit diagonal parity leaves
+ on-the-fly Karatsuba recomposition/reduction
```

It keeps the user's diagonal-addition idea, but changes the multiplication
algorithm and the HDEC operator granularity.

## Core idea

Split a 256-bit field element into eight 32-bit limbs:

```text
A = A7 || A6 || ... || A0
B = B7 || B6 || ... || B0
```

Use three recursive Karatsuba levels:

```text
256 -> 128 -> 64 -> 32
```

This produces:

```text
3^3 = 27
```

leaf multiplications. Each leaf is a 32x32 binary polynomial multiply. The leaf
operands are XOR-linear combinations of the original 32-bit limbs.

Each 32x32 leaf is still computed by diagonal parity:

```text
leaf_p[k] = parity_i(a_leaf[i] & b_leaf[k-i]), k=0..62
```

But HDEC computes eight leaf diagonals per cycle:

```text
4 lanes * 2 half-lane popcounts = 8 x 32-bit parity reductions
```

This matches the existing `hdec_p2_pop_slice`, which already produces two
32-bit popcount partials per 64-bit lane.

## Why this is better than current diagonal V3

Current full-width diagonal V3:

```text
511 full 256-bit diagonal reductions
```

KPD32:

```text
27 leaves * ceil(63 / 8) cycles = 216 packed-popcount cycles
```

There is extra work for leaf-form generation and recomposition/reduction, so a
realistic first RTL target is:

```text
about 230-280 cycles per modular multiply
```

That is not as fast as a dedicated full parallel multiplier, but it is much more
HDEC-native than a shift/window scanner and much more area-friendly than
replicating four complete 256-bit popcount engines.

## Operator change

Do not add a full independent ECC multiplier.

Add a packed parity mode around the existing popcount slice:

```text
input lane 0: {diag1_partial[31:0], diag0_partial[31:0]}
input lane 1: {diag3_partial[31:0], diag2_partial[31:0]}
input lane 2: {diag5_partial[31:0], diag4_partial[31:0]}
input lane 3: {diag7_partial[31:0], diag6_partial[31:0]}

existing popcount_part_q_o[lane][half][0] -> parity
```

Useful RTL sideband:

```text
half_parity_o[1:0] = {
  popcount_part_q_o[1][0],
  popcount_part_q_o[0][0]
}
```

HSIM/HMATCH still uses the full counts. ECC consumes the LSB parity sideband.

## Storage strategy

Do not store 511 raw partial-product bits.

Each produced leaf parity bit is immediately sent to a linear fold engine:

```text
(leaf_id, local_diag_k, parity_bit)
  -> Karatsuba recomposition raw offsets
  -> modular reduction targets
  -> XOR into 256-bit result accumulator R
```

Because all operations are over GF(2), this is a static linear map. It can be
implemented as shift/offset metadata plus sparse one-hot updates, not as a huge
512-bit product store.

If timing is tight, fold eight parities over two local P3 cycles. The multiplier
would still remain below the full diagonal pipeline cycle count.

## Why this is a real innovation candidate

Karatsuba is known. Diagonal parity is known. The possible contribution is their
HDEC-specific fusion:

```text
Use Karatsuba to reduce binary-field multiplication to many small leaves,
choose the leaf size to exactly match HDEC's 2x32 popcount half-slices,
and perform recomposition/reduction on the fly inside the shared HDC popcount
datapath.
```

This is not "shift and accumulate". It is a popcount-centric binary-polynomial
multiplier whose parallelism comes from the existing HDC similarity hardware.

## ITA / squaring fit

For Itoh-Tsujii inversion:

- Squaring remains a linear bit-interleave/reduction map; HPERM/shift-align can
  implement or assist this.
- Multiplication remains the expensive non-linear operation inside exponentiation
  blocks; KPD32 targets exactly that.
- Recent optimal-exponentiation-block work suggests grouping squaring chains and
  multiplications carefully. KPD32 can be the multiply primitive while HPERM-like
  square maps handle the linear powers.

## First RTL milestone

1. Add `half_parity_o` sideband to `hdec_p2_pop_slice`.
2. Add `ecc_kpd32_leaf_form_gen` for 27 Karatsuba leaf operand pairs.
3. Add `ecc_packed_diag8_window_gen` to produce eight 32-bit diagonal vectors.
4. Add `ecc_kpd32_fold_accum` to map leaf parity bits into the reduced result.
5. Compare against:
   - V1/V3 full diagonal pipeline,
   - KPD64, using 9 leaves and 4 full lanes,
   - D4 digit-serial fallback.

Expected best research point:

```text
KPD32: best HDC-popcount reuse and strongest novelty
KPD64: simpler control but lower packed-popcount utilization
D4: fastest simple fallback but weakest popcount-reuse story
```
