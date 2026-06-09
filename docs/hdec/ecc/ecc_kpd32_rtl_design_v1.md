# ECC KPD32 RTL design v1

Date: 2026-06-09
Base branch: `hdec-ecc-diagonal-parallel-v3`

## Goal

Replace the V1/V3 one-full-diagonal-at-a-time raw GF(2) multiplier with a
Karatsuba-packed diagonal multiplier while keeping the existing instruction
contract:

```text
HDEC_ECC_MUL(rs1):
  rs1[17:12] = dst VRF entry
  rs1[11:6]  = A source VRF entry
  rs1[5:0]   = B source VRF entry

Output:
  dst     = product[255:0]
  dst + 1 = product[511:256]
```

This first RTL milestone still returns the raw 512-bit polynomial product so it
can be checked by the existing `tb_hdec_ecc_diag_mul_v1` tests. Modular
reduction can be added as a later fold mode without changing the KPD32 leaf
engine.

## Existing V3 path

The current ECC multiply loop is:

```text
k = 0..510
  B_window = shifted/reversed full-width diagonal window
  partial_vec[255:0] = A[255:0] & B_window[255:0]
  feed 4 x 64-bit partials into hdec_p2_pop_slice
  XOR all eight 32-bit popcount parity bits
  write one product bit into ecc_word_q
```

This reuses HDC popcount, but only produces one product bit per popcount issue.

## KPD32 path

KPD32 uses three Karatsuba levels:

```text
256 -> 128 -> 64 -> 32
```

There are 27 leaf multiplications. Each leaf is a 32x32 GF(2) polynomial
multiply, and each 32x32 multiply still uses diagonal parity:

```text
leaf_p[k] = parity_i(a_leaf[i] & b_leaf[k-i]), k=0..62
```

The HDEC popcount slice already exposes two 32-bit popcount partials per lane:

```text
4 lanes * 2 halves = 8 independent 32-bit parity reducers
```

One KPD32 issue therefore computes eight leaf diagonals:

```text
lane0 = {partial_1, partial_0}
lane1 = {partial_3, partial_2}
lane2 = {partial_5, partial_4}
lane3 = {partial_7, partial_6}
```

Then:

```text
partial_j -> XOR with 0 -> popcount[0] -> leaf parity bit j
```

## Pipeline split

The first implementation uses the existing ECC FSM slots and keeps the compute
split close to the HDEC P2/P3 style:

| Stage | State | Work |
|---|---|---|
| P0 | `S_ECC_KPD32_FORM` | Build one 32-bit Karatsuba leaf pair |
| P1 | `S_ECC_DIAG_ISSUE` | Generate eight 32-bit diagonal partials and issue popcount |
| P2 | `hdec_p2_pop_slice` | Existing 2x32 `$countones` per lane |
| P3a | `S_ECC_DIAG_ACCUM` | Store returned eight parity bits into the 64-bit leaf product |
| P3b | `S_ECC_LEAF_FOLD` | Fold one completed leaf product into the raw 512-bit product |

The popcount tree is not duplicated and is still the same two 32-bit
`$countones` structure used by HSIM/HMATCH. The only popcount-slice boundary
change is that `src_b_i` is captured beside `src_a_i`. This keeps HSIM/HMATCH
semantics unchanged, but it removes the fragile old behavior where ECC had to
hold a combinational zero on `src_b_i` during the popcount capture cycle.

## Scheduler

The nested loop is:

```text
leaf_id   = 0..26
diag_base = 0,8,16,...,56
```

Each leaf has 63 diagonals. The last group at `diag_base=56` produces valid
diagonals 56..62; diagonal 63 is masked off.

Total packed-popcount issues:

```text
27 * 8 = 216
```

The current RTL uses one leaf-form cycle, eight packed-popcount issue cycles,
two drain/capture cycles, and one leaf-fold cycle per leaf. That is roughly
`27 * 12 + 8 writeback = 332` cycles for the raw 512-bit product, before any
future modular-reduction stage.

## Recomposition

Karatsuba recomposition is a GF(2) linear map. For a 32-bit leaf bit
`leaf_p[k]`, the hardware computes one to eight raw product bit offsets.

At each Karatsuba level with half-width `h`:

```text
z0 leaf contributes at offsets {0, h}
z1 leaf contributes at offsets {h}
z2 leaf contributes at offsets {h, 2h}
```

The three levels use:

```text
h = 128, 64, 32
```

Offsets are summed across levels. Duplicate offsets cancel because the field is
GF(2). The RTL stores the 63 valid diagonal parity bits into
`ecc_leaf_prod_q[62:0]`, then folds that 64-bit leaf product into
`ecc_product_q` using constant 32-bit-aligned shift masks selected by
`leaf_id`.

## Hardware delta estimate

Removed or no longer used:

- 256-bit `ecc_b_window_q`
- 64-bit `ecc_word_q`
- full-width 511-step diagonal counter semantics

Added:

- 512-bit raw product accumulator
- 32-bit `ecc_leaf_a_q`
- 32-bit `ecc_leaf_b_q`
- 64-bit `ecc_leaf_prod_q`
- 5-bit `leaf_id`
- 6-bit `diag_base`
- one two-stage `diag_base` tag for returned popcount metadata
- 8 x 32-bit diagonal partial generation
- 64-bit `src_b_q` per `hdec_p2_pop_slice` lane

The popcount hardware is not duplicated. VRF remains behind the V2 registered
command boundary. The `src_b_q` addition is a timing/correctness boundary
register, not a new popcount datapath.

## Timing notes

The design intentionally keeps heavy blocks apart:

- leaf-form XOR is in a separate state from popcount issue;
- the popcount tree is unchanged, and both XOR operands are captured before the
  popcount tree;
- recomposition/fold happens after the full 64-bit leaf product is captured,
  not in the same cycle as diagonal partial generation;
- final VRF writes are still done through `vrf_we_q/vrf_wa_q/vrf_wd_q`.

Vivado 2022.2 OOC, `xc7z020clg400-2`, 5.0 ns:

| RTL | WNS | Fmax estimate | Slice LUTs | Slice registers |
|---|---:|---:|---:|---:|
| V3 baseline | +0.202 ns | 208.420 MHz | 5491 | 3274 |
| KPD32 v1 | +0.331 ns | 214.179 MHz | 6386 | 3861 |

The final KPD32 v1 worst path is `lane_popcnt_part_q -> group_dist_q`, not the
ECC fold path. If future ECC reduction makes P3 fold critical, split
`S_ECC_LEAF_FOLD` into two word groups or fold directly into reduction words.
