# HDEC BMCA HSim

## Operator

`hsim` computes the Hamming distance between two 1024-bit HDC hypervectors:

```
distance = popcount(HVsrc0 XOR HVsrc1)
```

The architectural result is a scalar distance in `result[10:0]`. Legal HDC
vectors are stored as four 256-bit chunks. Each chunk maps to one VRF entry
across four 64-bit banks.

## Lane Structure

Each 64-bit Lane contains:

- Boolean/Mask XOR front-end;
- four-row BMCA row registers;
- 64 independent two-stage 3:2 compressor columns;
- local `count = popcount(lo) + 2*popcount(hi_a) + 2*popcount(hi_b)`.

For column `i`:

```
cell_A: row0[i] + row1[i] + row2[i] -> lo_a[i], hi_a[i]
cell_B: lo_a[i] + row3[i] + 0       -> lo[i],   hi_b[i]
count[i] = lo[i] + 2*hi_a[i] + 2*hi_b[i]
```

The BMCA output is redundant count encoding. `hi_a` and `hi_b` are both weight-2
planes; they are not a binary carry chain.

## Input Data

For SIM, BMCA rows are XOR-diff rows:

```
row0 = query_chunk0 XOR class_chunk0
row1 = query_chunk1 XOR class_chunk1
row2 = query_chunk2 XOR class_chunk2
row3 = query_chunk3 XOR class_chunk3
```

The row input path is:

```
VRF query word + VRF class word
  -> Lane Boolean/Mask XOR
  -> bool_result
  -> BMCA row selected by row_load_sel[1:0]
```

## Width Mapping

- One Lane processes 64 bits.
- Four Lanes process one 256-bit chunk in parallel.
- Four BMCA rows cover four chunks.
- One 4-row BMCA batch covers the full 1024-bit HV pair.

Per Lane count range: `0..256`, requiring 9 bits.
Four-Lane group distance range: `0..1024`, requiring 11 bits.

## FSM Dataflow

`hdec_top` sequences synchronous VRF reads:

1. Clear BMCA row-valid state.
2. For each chunk `0..3`:
   - read query chunk;
   - read class chunk;
   - enable XOR and load BMCA row `chunk[1:0]`.
3. Assert `bmca_compress_valid`.
4. Wait for all Lane `count_valid`.
5. Sum four Lane counts and return the 11-bit distance.

## Instruction Semantics

Current encoding:

```
funct7 = 000_0010
funct3 = 111
rs1[3:0] = src0_hv_slot
rs1[7:4] = src1_hv_slot
```

The instruction returns the Hamming distance. It does not modify VRF.

## Tests

Coverage:

- identical HVs return 0;
- complementary HVs return 1024;
- mixed patterns return expected distances;
- BMCA Python golden checks four-row count equivalence and row3-zero
  degeneration to the old three-row behavior.

## Current Limits

- `hsim` scans one resident HV pair; streaming class memory is not implemented.
- There is no HMatch control in this step.
- BMCA rows are loaded sequentially by `hdec_top`; no engine-level arbiter yet.

## ECC Reserved

Reserved for future documentation.
