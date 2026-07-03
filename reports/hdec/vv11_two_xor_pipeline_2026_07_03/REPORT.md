# VV11 Two-XOR Packet Fabric Iteration Report

Date: 2026-07-03

Vivado route used for all new runs:

```text
D:\vivado2024.2\Vivado\2024.2\bin\vivado.bat
```

## Reference Pattern: AND + POPCOUNT

The successful AND + POPCOUNT reuse does not feed HDC and ECC as semantic
modes into the arithmetic tree. It first normalizes both users into one physical
shape:

```text
matrix_src_a[8][32]
matrix_src_b[8][32]
matrix_product_q[8][32]
```

The tile then only sees eight 32-bit rows. HDC overlap and ECC diagonal windows
differ only in the row-packing layer. The operator outputs natural products,
counts, and parity bits:

```text
matrix_product_o[8][32]
matrix_count_o[8][6]
matrix_parity_o[8]
matrix_parity_lo16_o[8]
matrix_parity_edge8_o[8]
```

The key lesson for XOR is the same: first normalize the data shape, then feed
the operator. Do not put a wide semantic-mode mux in front of the operator and
call that reuse.

## XOR0 Canonical IO

XOR0 is the contribution merge array:

```text
base_packet[4][64]
contribution_packet[4][64]
merged_packet[4][64] = base_packet ^ contribution_packet
```

Canonical packet meaning:

| Field | Meaning |
|---|---|
| `base_packet[lane]` | Current accumulated 64-bit lane value |
| `contribution_packet[lane]` | One normalized 64-bit GF(2) contribution |
| `merged_packet[lane]` | Next accumulated 64-bit lane value |

Users that naturally fit XOR0:

| User | Base packet | Contribution packet | Consumer |
|---|---|---|---|
| HDC HBIND | `hdc_src0_q` | `vrf_rd` | `vec_payload_q` |
| ECC direct reduce accumulation | `hdc_src0_q` | `ecc_direct_reduce_word` | `hdc_src0_q` |
| Explicit `HDEC_ECC_REDUCE` | `ecc_reduce_src0` | `xor1_fold_packet` | VRF write data |
| ECC GF(2) add/sub | `hdc_src0_q` or row base | `vrf_rd` | VRF write data |

Important boundary:

- Direct modular reduction should first produce one contribution packet using
  fixed exponent-aware wiring.
- XOR0 should accumulate that packet.
- Direct modular reduction should not occupy XOR1.

## XOR1 Canonical IO

XOR1 is the local fold array:

```text
fold_a_packet[4][64]
fold_b_packet[4][64]
fold_c_packet[4][64]
fold_d_packet[4][64]
fold_packet[4][64] = fold_a ^ fold_b ^ fold_c ^ fold_d
```

Canonical packet meaning:

| Field | Meaning |
|---|---|
| `fold_*_packet[lane]` | One already aligned 64-bit local fold term |
| `fold_packet[lane]` | Folded 64-bit contribution for a later XOR0 merge |

Users that fit XOR1:

| User | Fold terms | Consumer |
|---|---|---|
| Explicit `HDEC_ECC_REDUCE` | `ecc_reduce_src1/2/3`, zero term | XOR0 contribution |
| Future Karatsuba local fold | aligned local terms | XOR0 or product-pack step |
| Future leaf lowxor pack | aligned local terms | leaf/product scheduler |

Non-user:

- Direct modular reduction accumulation should not use XOR1. It is a streaming
  contribution-packet mapping followed by XOR0 accumulation.
- AND + POPCOUNT parity should not use XOR1 because `count[0]` already carries
  parity.

## Current RTL State

Current experimental RTL adds:

- `hdec_xor0_array_4x64`
- `hdec_xor1_array_4x64`
- `hdec_vector_payload_4x64` XOR0 packet ports:
  `xor0_base_packet_i`, `xor0_contribution_packet_i`,
  `xor0_merged_packet_o`
- explicit reduce folding through XOR1 and XOR0
- direct reduce contribution packet `ecc_direct_reduce_word` accumulated by XOR0

In the latest true-reuse experiment, `i_vec` owns the single physical XOR0
array. Top-level RTL only normalizes users into packets. This matches the
AND + POPCOUNT split: top-level code packs rows or packets, while the operator
only sees one physical data shape.

`i_vec` is only the instance name for `hdec_vector_payload_4x64` inside
`hdec_top`. It is the shared 4x64 vector payload shell that stores intermediate
payloads for HBIND, HSIM/HMATCH, HCNTADD, HCNTCLIP, HPERM, the shared
AND+POPCOUNT tile, and the experimental XOR0 array. It is not a new lane
controller, and it must not grow lane-private control state.

The direct reduce path keeps the streaming modular reduction idea:

```text
current folded product word
-> exponent-aware contribution packet
-> XOR0 accumulates into hdc_src0_q
```

It does not reconstruct and store a full 466-bit or 512-bit product before
reduction.

## VV11 Baseline Modular Reduction Boundary

The clean `origin/VV11` baseline already uses a direct contribution-reduction
shape for the PMUL autoreduce path. During `S_ECC_LEAF_FOLD`, the current
folded product words are mapped into `ecc_direct_reduce_word[4][64]`. On the
clock edge, `hdc_src0_q` accumulates that contribution locally:

```text
hdc_src0_q ^= ecc_direct_reduce_word
```

Lane 3 is masked back to the 233-bit field width. The final reduced value is
then written from `hdc_src0_q` in `S_ECC_WRITE_PAIR`.

So VV11 baseline is not a late full-product rebuild followed by a separate
wide reduction. It already performs direct folded contribution accumulation.
The new two-XOR-array work may therefore freeze this baseline modular-reduce
structure and evaluate XOR reuse separately. That is a cleaner experiment:

```text
keep VV11 direct reduce accumulation unchanged
only change whether the HDEC GF(2) XOR sites enter XOR0/XOR1 arrays
```

This restricted XOR-only experiment should first prove that the shared arrays
are real physical reuse, not only a naming story. After the 2026-07-03 user
clarification, a small area tax is acceptable if the reuse story becomes
cleaner and stronger. Streaming overlap can still be revisited as a second-stage
optimization rather than mixing both variables in one RTL change.

## Iteration Results

Baseline is clean `origin/VV11` at commit `cf543cb8`.

| Run | Functional result | Logic LUT | FF | Fmax | Decision |
|---|---|---:|---:|---:|---|
| `vv11_origin_baseline` | reference | 4477 | 1426 | 207.684 MHz | baseline |
| `vv11_xor_iter01` | xsim PASS | 6351 | 1428 | 181.587 MHz | reject: hierarchy/visible fold exploded area |
| `vv11_xor_iter02` | xsim PASS, PMUL 296332 | 5302 | 1425 | 205.086 MHz | reject: wide semantic packet mux |
| `vv11_xor_iter05` | PMUL FAIL | 4150 | 1240 | 207.684 MHz | reject: direct reduce wrongly gated off |
| `vv11_xor_iter06` | reduce/HDC/PMUL PASS | 4962 | 1432 | 207.684 MHz | reject: over LUT/FF gate |
| `vv11_xor_iter07` | reduce/HDC/PMUL PASS | 5064 | 1428 | 203.957 MHz | reject: single direct packet but worse PPA |
| `vv11_xor_iter08` | reduce/HDC/PMUL PASS | 4963 | 1435 | 207.684 MHz | reject: top-level true XOR0 reuse, over gate |
| `vv11_xor_iter09` | reduce/HDC/PMUL PASS | 4546 | 1431 | 207.684 MHz | diagnostic only: HDC local XOR restored |
| `vv11_xor_iter10` | reduce/HDC/PMUL PASS | 4947 | 1432 | 207.684 MHz | true reuse inside `i_vec`, still over gate |
| `vv11_xor_iter11` | reduce/HDC/PMUL PASS | 5035 | 1428 | 207.684 MHz | reject: fixed-base default worsened input cone |
| `vv11_xor_iter12` | reduce/HDC/PMUL PASS | 4947 | 1432 | 207.684 MHz | reject: generate-gated debug split, no PPA gain |
| `vv11_xor_iter13` | reduce/HDC/PMUL PASS | 4745 | 1426 | 207.684 MHz | reject: VV11 reduce restored, HDC XOR0 still over gate |
| `vv11_xor_iter14` | reduce/HDC/PMUL PASS | 4745 | 1426 | 207.684 MHz | reject: direct HDC XOR0 packet, same netlist as iter13 |
| `vv11_xor_iter15` | reduce/HDC/PMUL PASS | 4745 | 1426 | 207.684 MHz | reject: internal HDC packet in `i_vec`, same netlist as iter13 |
| `vv11_xor_iter16` | reduce/HDC/PMUL PASS | 4745 | 1426 | 207.684 MHz | reject: XOR0/XOR1 changed to 8x32 row-matrix arrays, same area |
| `vv11_xor_iter17` | reduce/HDC/PMUL PASS | 4789 | 1432 | 207.684 MHz | reject: moved sub32/leaf lowxor into global XOR1 but area worsened |
| `vv11_xor_iter18` | reduce/HDC/PMUL PASS | 4520 | 1431 | 207.684 MHz | current checkpoint: true row-array reuse with small +43 LUT tax |
| `vv11_xor_iter19` | reduce/HDC/PMUL PASS | 4607 | 1437 | 207.684 MHz | reject: product-pair writeback through XOR1 added too much top logic |

Initial hard PPA rule after iter12:

```text
A two-XOR-array RTL is not acceptable unless it is <= VV11 baseline area
and improves at least one side of PPA: area or timing.
```

Updated acceptance rule after the 2026-07-03 user clarification:

```text
Small area increase is acceptable if:
  1. both XOR arrays are true physical row-array reuse,
  2. no lane-private control is reintroduced,
  3. xsim, PMUL cycle count, and 200 MHz timing stay clean,
  4. the area tax is small and explained against VV11.
```

By the initial hard rule, iter08/iter10/iter12/iter16/iter17 are structural
proofs only. By the updated rule, iter18 is the first acceptable checkpoint:
it costs +43 LUT (+0.96%) and +5 FF (+0.35%) versus VV11, with unchanged
207.684 MHz estimated Fmax and unchanged `PMUL_PROFILE_WALL_CYCLES=296332`.
Iter19 is kept as a negative datapoint: making XOR1 also serve the 128-bit
product-pair writeback looked semantically clean, but measured worse than
iter18 by +87 LUT and +6 FF.

Key validated xsim lines for the latest true-reuse experiment:

```text
[HDEC_ECC_REDUCE_V1] PASS
[HDEC_HDC_FULL_FLOW_V20] PASS
PMUL_PROFILE_WALL_CYCLES=296332
[HDEC_ECC_PMUL_PROFILE_V27] PASS
```

Key validated xsim lines for the latest XOR-only experiment:

```text
[HDEC_ECC_REDUCE_V1] PASS
[HDEC_HDC_FULL_FLOW_V20] PASS
PMUL_PROFILE_WALL_CYCLES=296332
[HDEC_ECC_PMUL_PROFILE_V27] PASS
```

## XOR Row-Matrix IO Audit

The XOR arrays now have two canonical row-matrix contracts. The 4x64 packet
forms still exist at the top-level boundary because the VRF is four 64-bit
banks, but the arrays themselves see eight 32-bit rows.

XOR0 is a merge array fused into the existing `i_vec` payload data plane:

```text
xor0_base_matrix[8][32]
xor0_contribution_matrix[8][32]
xor0_merged_matrix[8][32]
```

Packet adapters:

| Active request | XOR0 base rows | XOR0 contribution rows | Consumer |
|---|---|---|---|
| HDC HBIND / ECC ADD uop | `hdc_src0_q` packed as 8x32 | `vrf_rd` packed as 8x32 | `i_vec.payload_q` |
| Explicit debug reduce | `ecc_reduce_src0` packed as 8x32 | XOR1 folded contribution packed as 8x32 | `lane_ecc_reduce_word` |

The output is one normalized next-value row matrix. It is not lane-controlled:
all eight rows flow through the same row-wise XOR. Iter18 deliberately keeps
XOR0 inside `i_vec` instead of a separate child module, because iter16/iter17
proved that a visible XOR0 shell costs far more LUTs than the XOR it replaces.
This is still physical reuse: the same row-wise XOR plane feeds HDC HBIND/ECC
ADD uops. The explicit debug reduce path can also use the same format when
`ECC_DEBUG_FIELD_OPS=1`, but that path is not part of the normal PMUL/OOC build.

XOR1 is a local fold array:

```text
xor1_fold_a_matrix[8][32]
xor1_fold_b_matrix[8][32]
xor1_fold_c_matrix[8][32]
xor1_fold_d_matrix[8][32]
xor1_fold_matrix[8][32]
```

Packet adapters:

| Active request | Fold inputs | `xor1_fold_packet` consumer |
|---|---|---|
| Explicit debug reduce | `ecc_reduce_src1`, `ecc_reduce_src2`, `ecc_reduce_src3`, zero | XOR0 contribution |
| PMUL `S_ECC_DIAG_WAIT` sub32 accumulation | current 128-bit accumulator rows plus aligned 64-bit leaf product rows | `ecc_leaf128_prod_n` |
| PMUL lowxor handoff | `ecc_leaf_a_q/ecc_leaf_xor_a_q` and `ecc_leaf_b_q/ecc_leaf_xor_b_q` | next diagonal leaf operands |

Direct modular reduction remains outside XOR1. It creates one aligned
`ecc_direct_reduce_word[4][64]` contribution packet as the product words become
available, then the VV11 local `hdc_src0_q` accumulation boundary consumes that
packet. This keeps the XOR-only experiment isolated. The later "reduce while
computing" attempt should start from this same contribution-packet boundary, not
from a late full-product reduction.

### What "Debug Reduce" Means

`HDEC_ECC_REDUCE` is a standalone debug/verification instruction. It is enabled
only when `ECC_DEBUG_FIELD_OPS=1`; in the normal default build,
`ECC_DEBUG_FIELD_OPS=0`, the instruction returns `STATUS_NOT_IMPLEMENTED` and
the logic is pruned from OOC. It was useful historically for xsim validation of
the GF(2^233) reduction formula and for bring-up of raw field operations.

It is not the PMUL main path. Normal PMUL uses the direct/autoreduce dataflow
around `ecc_direct_reduce_word` and `hdc_src0_q`, so debug reduce should not be
used to justify area in the final architecture story. It can remain as an
optional verification path, but the mandatory two-XOR-array coverage should be
judged on default `ECC_DEBUG_FIELD_OPS=0`.

## Why The Explicit XOR0 Shell Was Too Expensive

The failed runs show that XOR reuse is far more sensitive to boundary cost than
AND+POPCOUNT. The extra LUTs were not mainly in top-level FSM control; they were
in the physical data boundary around `i_vec`.

| Run | Meaning | Total LUT | Top body LUT | `i_vec` LUT | `i_bitmatrix_tile` LUT |
|---|---|---:|---:|---:|---:|
| baseline | clean `origin/VV11` | 4477 | 1628 | 2849 | 346 |
| iter08 | top-level true XOR0 reuse | 4963 | 1631 | 3332 | 398 |
| iter09 | HDC local XOR diagnostic | 4546 | 1629 | 2917 | 346 |
| iter10 | true XOR0 reuse inside `i_vec` | 4947 | 1641 | 3306 | 398 |
| iter11 | fixed-base packet default | 5035 | 1626 | 3409 | 398 |
| iter12 | debug-gated true reuse | 4947 | 1641 | 3306 | 398 |
| iter13 | VV11 reduce restored, HDC XOR0 shared | 4745 | 1628 | 3117 | 398 |
| iter14 | direct HDC XOR0 packet | 4745 | 1628 | 3117 | 398 |
| iter15 | internal HDC packet in `i_vec` | 4745 | 1628 | 3117 | 398 |
| iter16 | XOR0/XOR1 row-matrix arrays | 4745 | 1628 | 3117 | 398 |
| iter17 | XOR1 sub32/leaf lowxor reuse | 4789 | 1653 | 3136 | 398 |
| iter18 | XOR0 fused into `i_vec` row data plane | 4520 | 1652 | 2868 | 346 |

The diagnostic result is decisive: restoring the HDC HBIND local XOR drops the
design to 4546 LUT, close to baseline, but that is not the target architecture
because HDC no longer uses the shared physical XOR0.

The true-reuse result is also decisive: moving the single physical XOR0 into
`i_vec` makes the data boundary cleaner, but only saves 16 LUT versus iter08.
The area increase is still mostly in `i_vec`. The reason is that HDC HBIND
captures `xor0_merged_packet` in the P2-to-P3 hot path, while the same XOR0
input packet must also select ECC direct-reduce contribution packets. Even
though the packet format is normalized, the physical input-selection cone still
reaches the HDC payload capture path.

Iter11 tried to make the packet shape more explicit by defaulting XOR0 base to
`hdc_src0_q` and selecting only the contribution packet. That worsened OOC area
to 5035 LUT, so the RTL was reverted to the iter10 packet selection form. The
lesson is that inactive packets should remain don't-care at the combinational
boundary; forcing a default packet can make the data cone more real, not less.

Iter12 moved the explicit debug-reduce XOR1 instance and packet selection into a
compile-time `ECC_DEBUG_FIELD_OPS` generate branch. This kept strict debug
reuse for `HDEC_ECC_REDUCE` and preserved PMUL streaming direct reduce, but OOC
area stayed exactly at 4947 LUT. Therefore the default OOC excess is not caused
by an unpruned debug XOR1 cone; it is the true shared datapath cone around the
4x64 payload shell.

Iter13 froze modular reduction back to the VV11 baseline accumulation boundary:
`hdc_src0_q` again accumulates `ecc_direct_reduce_word` locally, while XOR0
serves HDC HBIND and debug explicit reduce. This dropped area from 4947 to 4745
LUT and restored FF to the baseline 1426, but it still missed the 4477 LUT gate
by 268 LUT and did not improve timing.

Iter14 removed the default-path XOR0 request mux by directly driving the HDC
base/contribution packet from `hdc_src0_q` and `vrf_rd`. Iter15 went one step
further and, when `ECC_DEBUG_FIELD_OPS=0`, made `i_vec` form the HDC XOR0 packet
internally from the existing `bool_src_a_i/b_i` ports while tying the external
packet ports to zero. Vivado produced the same 4745-LUT netlist for iter13,
iter14, and iter15. That means the latest failure is not a top-level packet mux
artifact. The cost is the physical boundary of replacing VV11's local
`bool_xor_word` payload expression with an explicit shared XOR0 array shell.

Iter16 changed the physical XOR array format from 4x64 lane packets to the same
8x32 row-matrix shape used by the successful AND + POPCOUNT tile:

```text
XOR0:
  base_matrix[8][32] ^ contribution_matrix[8][32] -> merged_matrix[8][32]

XOR1:
  fold_a/b/c/d_matrix[8][32] -> fold_matrix[8][32]
```

The arrays no longer see lane IDs or HDC/ECC modes. The remaining 4x64 forms
are fixed pack/unpack adapters outside the arrays. Functionally, this is the
right direction, but the measured area is still 4745 LUT. Therefore matrix
format alone is necessary but not sufficient: the design must also remove
enough existing local XOR logic to pay for the explicit shared array boundary.

Iter17 then moved `ecc_kpd64_sub32_accum` and the two PMUL leaf lowxor handoffs
into the global XOR1 matrix. Functionally it was correct, but area worsened to
4789 LUT. This proved that moving a small ECC XOR family into a new visible
array boundary is also not enough; the deleted local XORs were still cheaper
than the added boundary and adapter logic.

Iter18 is the turning point. It removed the separate XOR0 child shell and fused
the XOR0 row array into `hdec_vector_payload_4x64` next to the existing
bitmatrix tile:

```text
for each row:
  xor0_merged_matrix[row] =
      xor0_base_matrix[row] ^ xor0_contribution_matrix[row]
```

This keeps the unified 8x32 data format and true physical row-array reuse, but
lets Vivado absorb the XOR0 rows into the same payload next-value cone that VV11
already used for `bool_xor_word`. The result is 4520 LUT, 1431 FF, and unchanged
207.684 MHz estimated Fmax. The remaining tax versus baseline is only +43 LUT
and +5 FF, which is now small enough to support the stronger reuse story.

## Reframed XOR Data-Format Audit

The area rule is stricter than "two arrays exist":

```text
removed local XOR area > added array/boundary/adapter area
```

The array must not decide what its input means. It should only receive one
canonical row-matrix shape. The user or operation-specific work belongs in
fixed adapters before or after the arrays.

| XOR user | Natural row-matrix view | Candidate array | Adapter outside array |
|---|---|---|---|
| HDC HBIND / ECC ADD uop | two 8x32 operand rows | XOR0 | pack `hdc_src0_q` and `vrf_rd` into rows |
| explicit debug reduce | one base matrix plus folded contribution matrix | XOR1 then XOR0 | fixed pack/unpack for `ecc_reduce_src*` |
| PMUL direct reduce accumulation | accumulator rows plus exponent-mapped contribution rows | XOR0 | fixed exponent-aware contribution mapper; no mode inside XOR0 |
| `ecc_kpd64_leaf_lowxor_pack` | low row and high row of one 64-bit leaf | XOR0 or XOR1 | fixed row selection for `lo` and `hi` |
| `ecc_kpd64_sub32_accum` | four 32-bit accumulator rows plus aligned subproduct rows | XOR0 | fixed contribution rows for each `sub_idx` |
| `ecc_kpd64_select(lo, hi, path)` | one of `lo`, `hi`, or `lo ^ hi` | XOR1 only for the `lo ^ hi` term | path selects rows before/after the array |
| square/direct fixed reduction XORs | reduced field rows plus fixed shifted rows | XOR0/XOR1 only if scheduled as row contributions | fixed exponent wiring, no barrel shifter |

Iter18 now covers HDC HBIND/ECC ADD through XOR0 and PMUL diagonal sub32
accumulation plus the leaf lowxor handoff through XOR1. When
`ECC_DEBUG_FIELD_OPS=1`, the optional explicit reduce instruction also uses
XOR1 plus XOR0, but that debug path is not counted as mandatory default-build
coverage. PMUL still contains local XOR expressions in `ecc_kpd64_leaf_lowxor_pack`
for VRF leaf selection, `ecc_kpd64_fold_word_contrib`, direct-reduce contribution
construction/accumulation, product-pair writeback, and square reduction. Those
remaining families are the next candidates, but they must be moved only if their
adapters do not break the small-tax property.

Iter19 tested one of those candidates: product-pair writeback. It was functionally
correct, but OOC worsened to 4607 LUT and 1437 FF, so it was reverted. This is
now evidence that "all XORs through XOR1" is not automatically a good physical
reuse rule.

The rule remains the VV5 rule: avoid VV2/VV3/VV4-style lane-private control.
`sub_idx` or `path` may choose fixed row adapters, but the XOR arrays themselves
must stay pure row-wise operators.

This is the hardware difference between:

```text
good semantic shape:
  all users can be described as base ^ contribution

not yet good physical reuse:
  a visible 4x64 XOR0 shell adds more boundary than the XORs it deletes
```

Iter18 keeps the good semantic shape and removes the bad shell boundary by
placing XOR0 directly in the row-matrix payload data plane.

## Current Conclusion

Iter18 is the current checkpoint. The two-array data formats are now clear and
measured:

```text
XOR0: 8x32 base/contribution merge rows, fused into the i_vec payload plane
XOR1: 8x32 aligned local fold rows, instantiated as hdec_xor1_matrix_8x32
```

Measured against clean `origin/VV11`:

```text
baseline: 4477 LUT, 1426 FF, 207.684 MHz
iter18:   4520 LUT, 1431 FF, 207.684 MHz
delta:     +43 LUT,   +5 FF, same timing
```

This is not an area win yet, but it is a credible reuse checkpoint under the
updated rule: the story is stronger, the reuse is physical, the lane-control
lesson from VV5 is preserved, and the area tax is small enough to explain.

The current mandatory coverage is therefore:

```text
covered:
  XOR0: HDC HBIND / ECC ADD uop base ^ contribution
  XOR1: PMUL sub32 accumulation and first leaf lowxor handoff
  optional debug: HDEC_ECC_REDUCE when ECC_DEBUG_FIELD_OPS=1

not yet covered:
  PMUL leaf select lowxor from VRF read
  product-pair writeback XOR, tested in iter19 and rejected
  direct-reduce contribution construction and local accumulation
  square-reduce XOR network
  bitmatrix parity reductions, which are part of AND+POPCOUNT rather than XOR0/XOR1
```

The next useful experiment is not another semantic mux reshuffle. It should be
one of these two:

1. Try to move one larger remaining ECC XOR family into the row format while
   keeping the iter18 small-tax boundary. The best candidates are the VRF leaf
   select/lowxor family and direct-reduce contribution construction.
2. Start the modular-reduction overlap attempt from the existing
   `ecc_direct_reduce_word[4][64]` contribution-packet boundary. Keep VV11's
   direct accumulation as the control result until the overlap version proves a
   timing or area benefit.

Both paths must keep VV5's rule: four lanes are fixed compute slices, with no
lane-private control state.
