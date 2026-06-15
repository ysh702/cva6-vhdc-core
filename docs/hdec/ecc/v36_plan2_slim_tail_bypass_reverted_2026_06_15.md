# V36 Plan 2 Reverted Trial: Slim Diagonal Tail Bypass

Date: 2026-06-15
Tool: Vivado 2022.2
Base: `hdec-ecc-pointmul-v36` after Plan 1 commit `52504faf`

## Goal

Plan 2 tried to remove one serialized tail cycle per 32-bit KPD leaf by using the final diagonal flush cycle as the first fold write.

In simple terms, the idea was:

- The last diagonal group already produces the complete 64-bit leaf product.
- Instead of waiting one more cycle before fold word 0, write fold word 0 immediately in the flush cycle.
- Continue fold words 1, 2, and 3 in the normal fold state.

This was expected to reduce the per-leaf schedule from:

```text
4 diagonal cycles + 4 fold cycles
```

to:

```text
4 diagonal cycles + 3 remaining fold cycles
```

## Test Result

The partial result looked promising in isolated ECC tests:

| Test | Result | Key data |
|---|---:|---|
| `xsim_hdec_ecc_reduce_v1.tcl` | PASS | ECC reduction unchanged |
| `xsim_hdec_ecc_pmul_profile_v27.tcl` | PASS | PMUL wall cycles = 277865 |
| `xsim_hdec_hdc_full_flow_v20.tcl` | PASS | HDC standalone still works |
| `xsim_hdec_ecc_pmul_bg_hdc_loop_v31.tcl` | FAIL | Background HDC data mismatches |

The first mixed-flow failure appears immediately after the standalone HDC warm-up:

```text
HDC_FULL_FLOW_STANDALONE_CYCLES=959
Error: V31 HBIND slot2 ones word0 mismatch got=0xfedcba9876543211 expected=0xffffffffffffffff
```

## Analysis

The bypass version was functionally correct when ECC ran alone, and HDC also worked alone. The failure only appeared when ECC point multiplication and background HDC were interleaved.

That means the optimization was not a pure ECC datapath problem. It changed the VRF read/write scheduling pressure during the ECC fold/next-leaf handoff, and that disturbed the background HDC loop's expected register contents.

Because this breaks the required HDC + ECC full-flow correctness check, Plan 2 is not a valid retained optimization.

## Decision

The RTL changes for Plan 2 were reverted back to the V36 known-good baseline after Plan 1.

Retained state:

- Plan 1 partial leaf fold overlap remains the current V36 RTL baseline.
- Plan 2 has no retained RTL changes.
- Plan 2's generated simulation/OOC output directory is kept only as local evidence: `reports/hdec/v36_plan2_slim_tail_bypass_20260615/`

## Current Baseline After Revert

The current retained V36 baseline is still Plan 1:

| Version | PMUL cycles | Logic LUT | LUTRAM | FF | Status |
|---|---:|---:|---:|---:|---|
| V35 Vivado 2022.2 baseline | 341624 | 6035 | 472 | 1807 | PASS |
| V36 Plan 1 retained | 310346 | 6221 | 472 | 1871 | PASS |

Plan 1 improvement versus V35 Vivado 2022.2:

- PMUL cycles: `-31278` cycles
- Logic LUT: `+186`
- LUTRAM: `0`
- FF: `+64`

