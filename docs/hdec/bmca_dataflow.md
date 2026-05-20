# HDEC BMCA Dataflow

## Scope

This note documents the Bit Matrix Compression Array (BMCA) dataflow used by
`hsim` and `hbundle3`.

BMCA is a Lane-local block. It compresses up to three 64-bit rows with 3:2
compressor cells:

```
lo[bit] + 2 * hi[bit] = row0[bit] + row1[bit] + row2[bit]
```

The block has no instruction-level FSM. `hdec_top` owns instruction sequencing,
VRF addressing, and result writeback.

## RTL Blocks

```
hdec_top
  -> hdec_lane_4x64
       -> hdec_lane_boolean_mask
       -> hdec_lane_bmca
            -> 64x hdec_bmca_cell
```

`hdec_lane_bmca` holds three row registers and a 3-bit row-valid mask. Invalid
rows are treated as zero. `compress_valid_i` captures the row count output for
`hsim`; `lo_o` and `hi_o` are also exposed for `hbundle3`.

## Single-Lane 64-Column BMCA Structure

One Lane processes one 64-bit VRF bank word at a time. The Lane-local BMCA views
that word as a 3-row by 64-column bit matrix:

```
          column 0   column 1   ...   column 63
row0_q       r0[0]      r0[1]   ...      r0[63]
row1_q       r1[0]      r1[1]   ...      r1[63]
row2_q       r2[0]      r2[1]   ...      r2[63]
             |          |                  |
          cell[0]    cell[1]            cell[63]
             |          |                  |
            lo[0]      lo[1]  ...       lo[63]
            hi[0]      hi[1]  ...       hi[63]
```

The implementation instantiates 64 identical one-bit 3:2 compressor cells. There
is no carry propagation between columns. Each column is independent and
combinational:

```
lo[i] = row0_eff[i] ^ row1_eff[i] ^ row2_eff[i]
hi[i] = (row0_eff[i] & row1_eff[i]) |
        (row0_eff[i] & row2_eff[i]) |
        (row1_eff[i] & row2_eff[i])
```

`hi[i]` is the majority bit of the three input bits. Numerically:

```
lo[i] + 2 * hi[i] = row0_eff[i] + row1_eff[i] + row2_eff[i]
```

`row*_eff` is either the stored row or zero. If a row has not been loaded,
`row_valid_q` masks it to zero before it reaches the compressor cells.

## hsim Path

`hsim` still computes Hamming distance of two 1024-bit HVs, but it batches rows
through BMCA:

1. `hdec_top` reads matching source words from VRF.
2. `hdec_lane_boolean_mask` computes `src0 XOR src1`.
3. `hdec_lane_4x64` loads the XOR diff into one BMCA row.
4. After the row batch is loaded, BMCA compresses the rows.
5. `count3_o = popcount(lo) + 2 * popcount(hi)` is accumulated in `hdec_top`.

This keeps the real XOR datapath in the Boolean/Mask core and the population
count/compression datapath in Lane-level BMCA.

### hsim Row Loading

For SIM, each BMCA row is not a raw HV word. It is a Query/Class XOR difference
word:

```
row0 = query_word_k     XOR class_word_k
row1 = query_word_k+1   XOR class_word_k+1
row2 = query_word_k+2   XOR class_word_k+2
```

The data path per loaded row is:

```
VRF query word + VRF class word
  -> hdec_lane_boolean_mask in XOR_ONLY mode
  -> bool_result
  -> BMCA row0/row1/row2
```

The row selector `bmca_row_load_sel_i` chooses which row register receives the
current XOR diff. The top-level controller clears the BMCA rows before starting
a batch, then loads up to three rows. If the final batch has fewer than three
rows, missing rows remain invalid and are compressed as zero.

### hsim Output Meaning

For SIM, `lo` and `hi` are an internal compressed representation of three XOR
diff rows. They are reduced to one scalar count:

```
count3 = popcount(lo) + 2 * popcount(hi)
```

Because each column represents one bit position in up to three XOR diff rows,
`count3` equals the total number of mismatched bits in the batch:

```
count3 = popcount(row0) + popcount(row1) + popcount(row2)
```

`hdec_top` accumulates this batch count across all chunks and lanes to form the
final Hamming distance returned by `hsim`.

## hbundle3 Path

`hbundle3` consumes three consecutive HV slots and updates one packed 4-bit
counter accumulator.

Instruction parameter:

```
rs1[2:0] = base_hv_slot
rs1[3]   = acc_sel
```

Legal condition:

```
base_hv_slot <= 5
```

Illegal `base_hv_slot > 5` returns `STATUS_ERROR` and does not modify VRF.

For each 256-bit chunk:

1. `hdec_top` clears BMCA row state.
2. It reads `HV[base+0]`, `HV[base+1]`, and `HV[base+2]`.
3. Each row is loaded directly into BMCA, bypassing the XOR front-end.
4. BMCA produces `lo` and `hi`.
5. `hdec_top` latches `lo` and `hi`.
6. Four accumulator subgroups are updated, one 64-bit word per subgroup.

The accumulator base is selected by `acc_sel`:

```
acc_sel = 0 -> VRF entries 32..47
acc_sel = 1 -> VRF entries 48..63
```

Each 64-bit accumulator word holds 16 packed 4-bit counters. For bit position
`n` within a 16-bit subgroup:

```
inc = {hi[n], lo[n]}
new_counter = saturating_add_4bit(old_counter, inc)
```

The saturating counter tail is implemented in `hdec_lane_4x64`, not in
`hdec_top`. `hdec_top` only selects subgroups, supplies the old counter word from
VRF, and writes the Lane result back.

### hbundle3 Row Loading

For Bundle, each BMCA row is a raw HV bit word. It does not pass through the
Query/Class XOR front-end:

```
row0 = HV[base_hv_slot + 0]
row1 = HV[base_hv_slot + 1]
row2 = HV[base_hv_slot + 2]
```

The data path per loaded row is:

```
VRF HV word
  -> bmca_row_direct_i
  -> BMCA row0/row1/row2
```

`bmca_row_use_direct_i` selects this direct path. The Boolean/Mask core is not
used for Bundle row loading, so Bundle does not compute XOR differences.

### hbundle3 Output Meaning

For Bundle, BMCA `lo/hi` are not reduced to a scalar popcount. They are kept as
per-bit 2-bit increments:

```
inc[i] = lo[i] + 2 * hi[i]
```

Since the BMCA inputs are three raw HV bits, `inc[i]` is the number of asserted
HV bits in that bit position:

```
inc[i] = HV0[i] + HV1[i] + HV2[i]
```

The possible increment values are:

| row0[i] + row1[i] + row2[i] | hi[i] | lo[i] | inc[i] |
|-----------------------------|-------|-------|--------|
| 0                           | 0     | 0     | 0      |
| 1                           | 0     | 1     | 1      |
| 2                           | 1     | 0     | 2      |
| 3                           | 1     | 1     | 3      |

### Packed 4-Bit Counter Update

Each accumulator word is 64 bits and stores 16 packed 4-bit counters:

```
counter_word[ 3: 0] -> counter 0
counter_word[ 7: 4] -> counter 1
...
counter_word[63:60] -> counter 15
```

One BMCA result covers 64 bit positions. `hbundle3` updates it as four 16-bit
subgroups. For subgroup `s` in `0..3` and local counter `n` in `0..15`:

```
bit_index   = 16 * s + n
old_counter = old_counter_word[4*n +: 4]
inc         = lo[bit_index] + 2 * hi[bit_index]
new_counter = min(old_counter + inc, 15)
```

The RTL computes the same operation with a 5-bit temporary sum:

```
sum = {1'b0, old_counter} + {3'b000, inc}
new_counter = sum[4] ? 4'hF : sum[3:0]
```

The four subgroup writes map one 64-bit Lane word at a time into the selected
bundle accumulator. `acc_sel=0` updates entries 32..47; `acc_sel=1` updates
entries 48..63.

## SIM vs Bundle Matrix Difference

The same BMCA hardware is reused, but the input matrix has different meaning:

| Field | SIM (`hsim`) | Bundle (`hbundle3`) |
|-------|--------------|---------------------|
| row source | Query/Class XOR diff | raw HV bits |
| row0 | `query0 XOR class0` | `HV[base+0]` |
| row1 | `query1 XOR class1` | `HV[base+1]` |
| row2 | `query2 XOR class2` | `HV[base+2]` |
| missing row | zero via row-valid mask | not used for legal `hbundle3` |
| Boolean/Mask core | active, XOR_ONLY | bypassed |
| BMCA direct path | inactive | active |

The output interpretation is also different:

| Field | SIM (`hsim`) | Bundle (`hbundle3`) |
|-------|--------------|---------------------|
| `lo/hi` meaning | compressed mismatch bits | per-bit vote count encoding |
| reduction | `popcount(lo) + 2*popcount(hi)` | no global popcount |
| architectural result | scalar Hamming distance | updated packed 4-bit counters |
| `hdec_top` role | accumulate scalar count | sequence subgroup writes |
| Lane tail role | BMCA count output | saturating packed counter update |

## Synchronous VRF Timing

The VRF read path is synchronous with one-cycle latency. The BMCA users preserve
that timing by splitting each read and consume step:

```
RD_HVx       -> drive vrf_ra
LOAD_ROWx    -> consume vrf_rd and load BMCA row
```

For accumulator update, each subgroup state writes the current subgroup while
also driving the read address for the next subgroup. The following subgroup then
uses the freshly returned `vrf_rd`.

## Operand Isolation

Inactive BMCA and bundle-tail inputs are held at zero or stable selected values
at the Lane wrapper boundary:

- Boolean/Mask inputs are gated by `bool_valid_i`.
- BMCA loads only when `bmca_row_load_valid_i` is asserted.
- The bundle-tail old counter and `lo/hi` subgroup inputs are zeroed unless
  `bundle_valid_i` is asserted.

## Verification Coverage

Python golden coverage in `verif/hdec/test_bmca.py` checks:

- BMCA cell truth table.
- `lo + 2*hi` equivalence to three input bits.
- `count3` equivalence to the sum of row popcounts.
- invalid rows treated as zero.
- packed counter subgroup update.
- 4-bit saturation behavior.

Assembly coverage in `verif/hdec/hbundle3_test.S` checks:

- pre-implementation guard against accidental default `vwr64` behavior;
- all-zero rows;
- all-one rows;
- mixed row increments;
- saturation and accumulator isolation;
- `acc_sel` behavior;
- illegal `base_hv_slot > 5` status and no accumulator modification.

## Figure Guidance for Research Writing

Recommended figures for papers or slides:

1. Single-Lane BMCA microarchitecture:
   - Draw three horizontal 64-bit row registers: `row0`, `row1`, `row2`.
   - Draw 64 vertical columns below them.
   - In each column, show one 3:2 compressor cell.
   - Show two 64-bit output rails: `lo[63:0]` and `hi[63:0]`.
   - Annotate one expanded column with:
     `lo[i] = row0[i] XOR row1[i] XOR row2[i]` and
     `hi[i] = majority(row0[i], row1[i], row2[i])`.

2. SIM dataflow overlay:
   - On the left, draw Query VRF words and Class VRF words.
   - Feed each pair into an XOR block labeled Boolean/Mask Core.
   - Feed three XOR diff rows into BMCA `row0/row1/row2`.
   - On the right, show `lo/hi -> popcount(lo) + 2*popcount(hi) -> count3`.
   - Label the final accumulation as Hamming-distance accumulation.

3. Bundle dataflow overlay:
   - On the left, draw raw `HV0/HV1/HV2` words.
   - Feed them directly into BMCA rows with no XOR block in the active path.
   - On the right, show `lo/hi -> inc[i] = lo[i] + 2*hi[i]`.
   - Then draw 16 packed 4-bit counters in a 64-bit word and a saturating add
     tail: `min(old + inc, 15)`.

4. Reuse comparison figure:
   - Use the same central BMCA block in both SIM and Bundle panels.
   - Highlight that only the row source and output interpretation differ.
   - Keep future ECC as a gray dashed box or callout, not as an implemented
     datapath.

Avoid drawing BMCA as a scalar popcount-only unit. The key research message is
that the 64-column 3:2 bit-matrix structure is reused: SIM reduces its output to
a scalar distance, while Bundle preserves per-bit vote counts for packed
counter updates.

## Future ECC Reservation

Future ECC can reuse the same 3:2 compression idea for carry-save style partial
product reduction or SAIR-related accumulation. This Phase 1 document is only a
reservation note:

- no ECC controller is implemented here;
- no ECC Shadow RF access is implemented here;
- no ECC scheduling, tag routing, or field arithmetic is implemented here;
- BMCA is documented as reusable Lane-local compressor structure, not as a
  complete ECC datapath.
