# HDEC Shift HPerm

## Operator

`hperm` rotates one 1024-bit HDC hypervector right by a 4-bit-granular amount:

```
HVdst = ROTR(HVsrc, rot_amt)
```

Only `rot_amt[1:0] == 0` is legal in the Phase 1 mainline.

## Datapath

The Lane-local Shift-Align core combines two adjacent 64-bit words:

```
shift = rot_amt[5:2] * 4
result = A                      if shift == 0
result = (A >> shift) | (B << (64 - shift)) otherwise
```

The core is HDC/ECC-agnostic. HDC wrap-around source selection is handled by
`hdec_top`; the core only receives word A, word B, and the 4-bit nibble shift.

## Encoding

```
funct7 = 000_0010
funct3 = 110
rs1[3:0]  = dst_hv_slot
rs1[7:4]  = src_hv_slot
rs1[17:8] = rot_amt[9:0]
```

Illegal cases return `STATUS_ERROR` and do not modify VRF:

- `rot_amt[1:0] != 0`
- `dst_hv_slot == src_hv_slot`

## Tests

`verif/hdec/hperm_test.S` covers legal rotations including 0, 4, 60, 64, 68,
252, 256, 508, and 1020, plus illegal non-nibble shifts and `dst == src`.

## ECC Reserved

Reserved for future documentation.
