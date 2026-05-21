# HDEC HClip

## Operator

`hclip` binarizes one packed 4-bit counter accumulator into a 1024-bit HDC
hypervector:

```
HVdst[i] = accumulator[i] >= threshold
```

`threshold` is a 4-bit scalar immediate. `threshold=0` is legal and produces an
all-one output for every processed counter.

## Datapath

Each Lane uses a pure combinational Clip core:

- input: one 64-bit packed counter word;
- structure: 16 parallel 4-bit comparators;
- output: 16 packed predicate bits.

`hdec_top` reads four accumulator subgroups for each chunk, packs the four
16-bit predicate slices into one 64-bit Lane word, and writes the destination
HV chunk. The compare operation itself is not implemented in `hdec_top`.

## Encoding

```
funct7 = 000_0011
funct3 = 000
rs1[2:0] = dst_hv_slot
rs1[3]   = acc_sel
rs1[7:4] = threshold
```

Accumulator mapping:

- `acc_sel=0`: VRF entries 32..47
- `acc_sel=1`: VRF entries 48..63

## Tests

Coverage:

- directed threshold values 0, 1, 8, and 15 in `test_clip.py`;
- all-equal counter words for all thresholds;
- random packed counter words;
- assembly checks for threshold 0, threshold 8, threshold 15, acc0/acc1
  isolation, and source counter preservation.

## ECC Reserved

Reserved for future documentation.
