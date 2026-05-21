# HDEC XOR HBind

## Operator

`hbind` binds two 1024-bit HDC hypervectors with bitwise XOR:

```
HVdst = HVsrc0 XOR HVsrc1
```

The operation writes four 256-bit chunks to the destination HV slot and leaves
both sources unchanged.

## Datapath

The real XOR datapath is inside the Lane-local Boolean/Mask core. `hdec_top`
only sequences VRF reads and writes:

1. Read `src0` chunk from all four banks.
2. Read `src1` chunk from all four banks.
3. Enable the Lane Boolean/Mask XOR path.
4. Write the four Lane results into `dst`.
5. Repeat for chunks 0..3.

The Boolean/Mask inputs are operand-isolated when the path is inactive.

## Encoding

```
funct7 = 000_0010
funct3 = 101
rs1[3:0]  = dst_hv_slot
rs1[7:4]  = src0_hv_slot
rs1[11:8] = src1_hv_slot
```

## Tests

`verif/hdec/hbind_test.S` checks XOR correctness across a full 1024-bit HV and
source preservation. `verif/hdec/hdc_pipeline_test.S` uses HBind as the first
stage of the primitive pipeline.

## ECC Reserved

Reserved for future documentation.
