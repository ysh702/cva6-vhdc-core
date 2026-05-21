# HDEC BMCA HBundle4

## Operator

`hbundle4` adds four consecutive binary HDC hypervectors into one packed 4-bit
counter accumulator.

```
acc[counter_i] = min(acc[counter_i] + HV0[i] + HV1[i] + HV2[i] + HV3[i], 15)
```

`hbundle3` remains as a compatibility instruction. It loads only `row0..row2`;
`row3` stays invalid and is treated as zero by the same four-row BMCA.

## Lane Structure

Each Lane uses the same four-row BMCA as `hsim`, but the input rows are raw HV
bits rather than XOR differences.

For one bit column:

```
cell_A: row0[i] + row1[i] + row2[i] -> lo_a[i], hi_a[i]
cell_B: lo_a[i] + row3[i] + 0       -> lo[i],   hi_b[i]
inc[i] = lo[i] + 2*hi_a[i] + 2*hi_b[i]
```

`inc[i]` ranges from 0 to 4.

## Input Data

For `hbundle4`:

```
row0 = HV[base_hv_slot + 0]
row1 = HV[base_hv_slot + 1]
row2 = HV[base_hv_slot + 2]
row3 = HV[base_hv_slot + 3]
```

The row input path is:

```
VRF HV word
  -> bmca_row_direct_i
  -> BMCA selected row
```

The Boolean/Mask XOR front-end is bypassed.

## Counter Packing

Each 64-bit accumulator word stores 16 packed 4-bit counters:

```
counter_word[ 3: 0] -> counter 0
counter_word[ 7: 4] -> counter 1
...
counter_word[63:60] -> counter 15
```

For subgroup `s` and local counter `n`:

```
bit_index   = 16*s + n
old_counter = old_counter_word[4*n +: 4]
inc         = lo[bit_index] + 2*hi_a[bit_index] + 2*hi_b[bit_index]
new_counter = min(old_counter + inc, 15)
```

The saturating add is Lane-local combinational logic. `hdec_top` only sequences
VRF reads/writes and subgroup selection.

## Width Mapping

- One Lane handles 64 HV bits.
- Four Lanes update one 256-bit chunk.
- Four chunks form one 1024-bit HV.
- One accumulator uses 16 VRF entries:
  - `acc_sel=0`: entries 32..47
  - `acc_sel=1`: entries 48..63

## FSM Dataflow

For each chunk:

1. Clear BMCA row-valid state.
2. Read HV0, load row0.
3. Read HV1, load row1.
4. Read HV2, load row2.
5. For `hbundle4`, read HV3 and load row3.
6. Compress BMCA rows and latch `lo/hi_a/hi_b`.
7. Read and update accumulator subgroup 0.
8. Repeat for subgroups 1..3.
9. Move to next chunk until all four chunks are updated.

## Instruction Semantics

`hbundle4` encoding:

```
funct7 = 000_0011
funct3 = 100
rs1[2:0] = base_hv_slot
rs1[3]   = acc_sel
```

Legal condition:

```
base_hv_slot <= 4
```

Illegal `base_hv_slot > 4` returns `STATUS_ERROR` and does not modify VRF.

`hbundle3` compatibility encoding remains:

```
funct7 = 000_0011
funct3 = 011
base_hv_slot <= 5
```

## Tests

Coverage:

- pre-decode guard for `F7_EXT/F3=100`;
- all-zero HV rows preserve counters;
- all-one HV rows increment every counter by 4;
- mixed rows generate increment 2;
- saturation at 15;
- acc0/acc1 isolation;
- illegal base returns `STATUS_ERROR` and preserves accumulator;
- Python golden checks `inc = lo + 2*hi_a + 2*hi_b`.

## Current Limits

- HBundle4 is the HDC bundle mainline.
- HBundle3 is kept only as compatibility behavior.
- Legacy BADD is not part of this path and is not a Step 1 acceptance target.

## ECC Reserved

Reserved for future documentation.
