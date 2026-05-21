# HDEC HMatch

## Operator

`hmatch` searches a resident class range and returns the nearest HDC class by
Hamming distance. It is implemented with the `HDEC_HSEARCH` encoding.

For each class:

```
distance = popcount(HVquery XOR HVclass)
```

The result layout is fixed:

```
result[10:0]  = min_distance
result[18:11] = min_index
result[63:19] = 0
```

`min_index` is the relative index within the searched class range. Ties keep
the first class encountered.

## Datapath

HMatch does not add Lane hardware. It reuses the HSim path:

```
VRF query/class words
  -> Boolean/Mask XOR
  -> BMCA row load
  -> BMCA count
  -> top-level scalar min comparator
```

`hdec_top` only loops over class slots and tracks the best scalar result.

## Encoding

```
funct7 = 000_0011
funct3 = 001
rs1[3:0]  = query_hv_slot
rs1[7:4]  = class_base_slot
rs1[15:8] = num_classes
```

Parameter checks:

- `num_classes > 0`
- `class_base_slot + num_classes - 1 <= 7`

Illegal parameters return `STATUS_ERROR` before entering the VRF search loop.

## Tests

`verif/hdec/hmatch_test.S` covers:

- nearest class selection;
- tie behavior;
- non-zero minimum distance;
- `num_classes=0` error;
- class range overflow error and VRF preservation.

## ECC Reserved

Reserved for future documentation.
