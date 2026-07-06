# VV13 Leaf-Level Contribution Packet Reduction

## Baseline

- Branch base: `VV12`
- Safe commit: `3a0f1344` (`VV13 leaf-level contribution packet reduction`)
- Target: start moving ECC modular reduction from a local fold-tree description toward a fixed contribution-packet form, while preserving the VV12/VV11 reuse story and keeping `Logic LUT < 4700`.

## Implemented Design

VV13 does not use dynamic per-diagonal bit indexing. Instead, each 64x64 leaf still produces a local product, and the reduction logic now builds one fixed 4x64 contribution packet for the whole leaf:

```text
leaf product
-> four fixed fold packets
-> one 4x64 leaf contribution packet
-> XOR0 / field packet accumulation
```

This keeps the direct modular-folding idea, but avoids a large dynamic `result[index] ^= bit` network. In hardware terms, the accepted version uses fixed slicing and fixed concatenation patterns, then accumulates the resulting 4x64 packet through the shared GF(2) packet path.

## Accepted Result

| Candidate | Logic LUT | Total LUT | FF | Fmax | PMUL cycles | BRAM | DSP | Status |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| VV12 baseline | 4645 | 4645 | 1434 | 207.684 MHz | 392560 | 4 | 0 | reference |
| VV13 accepted | 4677 | 4677 | 1436 | 207.684 MHz | 392560 | 4 | 0 | accepted |

Passed checks:

- `xsim_hdec_ecc_diag_mul_v1`
- `xsim_hdec_ecc_reduce_v1`
- `xsim_hdec_ecc_pmul_profile_v27`
- `xsim_hdec_hdc_full_flow_v20`

## Rejected Attempts

### Candidate 1: dynamic diagonal-level packet

Attempted form:

```text
diagonal parity bit
-> dynamic exponent index
-> packet[index] ^= bit
-> XOR0 accumulation
```

This was functionally correct, but synthesis exploded:

| Candidate | Logic LUT | FF | Fmax | Status |
|---|---:|---:|---:|---|
| dynamic diagonal packet | 12034 | 1313 | 31.733 MHz | rejected |

Reason: dynamic bit placement creates a very wide decoder/mux network. This is not acceptable for the HDEC low-area story.

### Candidate 5: explicit full leaf formula

Attempted to manually expand the full leaf packet formula from eight raw words. Functional tests passed, but OOC was worse than the accepted version:

| Candidate | Logic LUT | FF | Fmax | PMUL cycles | Status |
|---|---:|---:|---:|---:|---|
| explicit leaf packet | 4709 | 1434 | 207.684 MHz | 392560 | rejected |

Reason: the hand-expanded expression crossed the `4700` LUT hard gate and was larger than the accepted fixed fold-packet composition.

## Current Interpretation

VV13 is a stage victory, not the final diagonal-level on-the-fly reduction:

- Completed: fixed leaf-level contribution packet reduction.
- Preserved: direct modular folding and PMUL cycle count.
- Avoided: dynamic exponent-index write networks.
- Not yet completed: true diagonal-bit-level `parity -> fixed coordinate contribution -> XOR0` reduction.

Future work, if continued, should use fixed tables or fixed group-level coordinate maps. Dynamic bit indexing must remain rejected.
