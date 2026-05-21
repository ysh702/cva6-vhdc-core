# HDEC HDC Primitive Pipeline

## Scope

The Phase 1 HDC primitive pipeline is resident in the HDEC VRF and uses the
current transitional `hdec_top` controller. It validates that the implemented
primitive instructions can be composed without a standalone HDC engine yet.

## Pipeline

`verif/hdec/hdc_pipeline_test.S` exercises:

1. `HBind`: create `HV2 = HV0 XOR HV1`.
2. `HBundle4`: accumulate `HV2..HV5` into accumulator 0.
3. `HClip`: threshold accumulator 0 into `HV6`.
4. `HSim`: compare `HV6` against a reference HV.
5. `HMatch`: search a resident class range and return the nearest class.

The test intentionally reuses the same VRF-resident data across stages.

## Data Layout

- HV slots use entries `slot*4 .. slot*4+3`.
- Accumulator 0 uses entries 32..47.
- Accumulator 1 uses entries 48..63.
- Each 256-bit chunk maps to four 64-bit Lane banks.

## Current Controller Shape

The current design is still transitional:

- `hdec_top` parses instruction parameters and sequences VRF access;
- Lane modules hold the real combinational datapaths;
- there is no engine-level arbiter or tag routing in Phase 1.

## Verification

The final Phase 1 regression includes Python golden tests, Verilator build, and
assembly simulation logs for individual primitives plus the full pipeline.
Every simulation command passes a non-zero `+tohost_addr` extracted from the ELF.

## ECC Reserved

Reserved for future documentation.
