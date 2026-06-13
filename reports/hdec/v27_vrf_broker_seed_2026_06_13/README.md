# V27 VRF Broker Seed and Background PMUL Scheduling

Date: 2026-06-13

## What changed

V27 first normalizes all top-level VRF read/write controls into one request bundle:

- `hdec_vrf_req_t vrf_req`
- Existing `vrf_ra/we/wa/wd` are driven once at the end of the main combinational FSM.
- This is behavior-equivalent, but gives later HDC foreground / ECC background arbitration a single broker point.

V27 then adds an opt-in ECC background job mode:

- `HDEC_ECC_STATUS` bit 29 starts PMUL/INV as a background job.
- Default PMUL/INV start semantics are unchanged, so old blocking software/tests still see the original result path.
- When background PMUL is active, `S_IDLE` gives priority to any foreground command. If no command is waiting, ECC resumes.
- PMUL yields at `S_ECC_PMUL_STEP_NEXT` boundaries, letting HDC commands use the shared VRF/lane resources between ECC slices.

V27 also adds one accepted PMUL-cycle optimization:

- ECC diagonal multiplication now computes the 8 diagonal parities directly with XOR-reduction.
- This keeps every scalar bit in the Montgomery/Lopez-Dahab ladder; it does not skip `k=0` bits.
- It removes the two popcount-pipeline drain states from each KPD32 leaf path, so each field multiply saves `27 * 2 = 54` cycles.

## Validation

Functional regressions:

- `xsim_hdec_ecc_pmul_wall_v27`: PASS.
- `xsim_hdec_hdc_full_flow_v20`: PASS.
- `xsim_hdec_ecc_pmul_profile_v27`: PASS.

Corrected PMUL accounting:

- `PMUL_BLOCKING_WALL_CYCLES=518287` after direct diagonal parity.
- `PMUL_BLOCKING_STATUS_LOW16=59533`.
- Earlier `6005` was only the low 16 bits of the internal status counter, not the full scalar point multiplication latency.
- The pre-parity-bypass wall-cycle baseline was `595831`, so the accepted optimization saves `77544` cycles, about `13.0%`.

Current profile after direct diagonal parity:

| Profile item | Count |
|---|---:|
| total sampled cycles | 518287 |
| PMUL ADD subop cycles | 483242 |
| PMUL DBL subop cycles | 15608 |
| affine/recovery cycles | 19420 |
| GF multiply starts | 1436 |
| GF multiply starts inside ADD | 1398 |
| square starts | 2097 |

New interleaving test:

- `xsim_hdec_ecc_pmul_bg_v27`: PASS.
- Scenario: start background PMUL for scalar `3`, run foreground HDC slot writes, `HBIND`, and `HSIM`, then poll for PMUL completion and check the final `3G` coordinates.

Note: earlier background PMUL wall-count logs were polluted by the old 16-bit status-counter interpretation and should not be used for paper numbers. Use the wall-cycle testbench counters above.

Rejected cycle-reduction attempts:

- Leading-zero skip was rejected for the main LD path because it changes the fixed 233-bit ladder schedule and leaks/changes scalar-bit timing behavior.
- Replacing `X0Z0 * X1Z1` with cross-product reuse inside differential ADD was rejected because `3G` correctness failed in xsim.

## OOC resource impact

Vivado 2024.2, `xc7z020clg400-2`, OOC 200 MHz target.

| Design point | Slice LUT | Logic LUT | LUTRAM | FF | WNS | Fmax est. |
|---|---:|---:|---:|---:|---:|---:|
| V27 broker seed only | 6258 | 5786 | 472 | 2113 | 0.159 ns | 206.569 MHz |
| V27 background scheduler | 6378 | 5906 | 472 | 2113 | 0.243 ns | 210.217 MHz |
| V27 direct diagonal parity | 6394 | 5922 | 472 | 2118 | 0.247 ns | 210.393 MHz |
| Background scheduler delta vs broker seed | +120 | +120 | +0 | +0 | +0.084 ns | +3.648 MHz |
| Direct parity delta vs background scheduler | +16 | +16 | +0 | +5 | +0.004 ns | +0.176 MHz |

Interpretation:

- The normalized VRF broker seed itself is area-neutral after synthesis.
- The first real background scheduler costs about `+120 Logic LUT` and no additional reported FF/LUTRAM.
- The accepted diagonal-parity bypass costs only `+16 Logic LUT` and `+5 FF`, while saving `77544` PMUL wall cycles.
- This is now a concrete "unified scheduling infrastructure" cost, not just a narrative claim.

## Next optimization targets

1. Algorithm-level PMUL reduction without skipping scalar zeros:
   - a Koblitz-curve tau/NAF path is the strongest candidate if we are willing to add a new scalar representation and point-add schedule;
   - a fixed-base signing-only window path is also plausible, but needs table-storage and full correctness accounting.
2. Microarchitecture PMUL reduction:
   - continue reducing per-field-multiply cycles without duplicating a full multiplier;
   - measure whether wider diagonal issue, partial leaf unrolling, or faster fold/writeback has better cycle/LUT tradeoff than direct parity.
3. Background scheduling:
   - keep PMUL-only latency measurements separate from HDC/ECC interleaving wall-time measurements.
   - add a stress test with repeated foreground HDC commands and compare `standalone HDC + standalone PMUL` versus interleaved wall time.
