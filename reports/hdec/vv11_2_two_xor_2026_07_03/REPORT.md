# VV11-2 Two-XOR Fabric Checkpoint

Date: 2026-07-03
Branch: `VV11-2`
Starting point: `origin/VV11-1`

## Purpose

VV11-1 proved the two-XOR story was implementable, but its area cost was not ideal:
it increased area while keeping PMUL cycles unchanged. VV11-2 therefore keeps the
same data/operator unification direction, but removes unnecessary visible XOR
packing and state-gated input selection.

The intent is not to force every GF(2) operation through a large centralized
shell. The better rule is:

- XOR0: vector contribution / merge XOR, placed in the payload fabric.
- XOR1: row-local diagonal / local fold XOR, placed near the bit-matrix data.
- Direct modular folding should be added later as exponent mapping plus XOR0
  contribution accumulation, instead of widening the current XOR boundary first.

## VV11-1 Analysis

VV11-1 current checkpoint:

| Version | Logic LUT | FF | Fmax MHz | PMUL cycles | Notes |
|---|---:|---:|---:|---:|---|
| VV11 baseline | 4477 | 1426 | 207.684 | 296332 | Baseline from VV11 report |
| VV11-1 iter18 | 4520 | 1431 | 207.684 | 296332 | Two-XOR checkpoint |
| VV11-1 iter19 | 4607 | 1437 | - | - | Rejected product-pair writeback through XOR1 |

Main conclusion:

- The XOR gates themselves are cheap.
- The expensive part is the data boundary around the shared XOR fabric: pack,
  unpack, state gating, and source selection.
- Product-pair writeback through XOR1 is not worth keeping; it increases control
  and writeback boundary cost without cycle benefit.

## VV11-2 Attempts

| Try | Change | Function | Logic LUT | FF | Fmax MHz | PMUL cycles | Decision |
|---|---|---|---:|---:|---:|---:|---|
| try01 | Slim XOR0 from 8x32 pack/unpack to direct 4x64 packet XOR | PASS | 4520 | 1431 | 207.684 | 296332 | No PPA gain |
| try02 | Remove normal-PMUL state-gated XOR1 input mux; let data flow continuously | PASS | 4501 | 1430 | 207.684 | 296332 | Keep |
| try03 | Move leaf lowxor out of XOR1 | PASS | 4518 | 1431 | 207.684 | 296332 | Reject |
| try04 | Make XOR1 a 3-input 8x32 row array | PASS | 4501 | 1430 | 207.684 | 296332 | Final |
| try05 | Compile default XOR1 as 6x32 rows | PASS | 4501 | 1430 | 207.684 | 296332 | Rejected for story; no PPA gain |

Final chosen checkpoint is try04, because it preserves the clean two-array story
while matching the best PPA of try02/try05.

## Final Verification

| Test | Result |
|---|---|
| `xsim_hdec_ecc_diag_mul_v1` | PASS |
| `xsim_hdec_hdc_full_flow_v20` | PASS |
| `xsim_hdec_ecc_pmul_profile_v27` | PASS |
| PMUL wall cycles | 296332 |
| OOC Logic LUT | 4501 |
| OOC FF | 1430 |
| OOC Fmax | 207.684 MHz |
| BRAM / DSP | 4 / 0 |

## Interpretation

Compared with VV11-1, VV11-2 recovers 19 LUT and 1 FF without changing cycles or
timing. Compared with the VV11 baseline, the two-XOR structure still costs 24 LUT
and 4 FF. This is small enough to keep as an architectural checkpoint, but it
also shows that the next step must not add another visible shared boundary.

## Next Step

Implement direct modular folding only after the two-XOR boundary is stable:

1. Keep exponent-position mapping as fixed wiring and small local selectors.
2. Convert folded terms into contribution packets.
3. Accumulate packets through XOR0.
4. Avoid product-pair writeback through XOR1 unless a cycle benefit appears.

The next experiment should compare:

- current direct-fold local accumulation,
- packetized direct folding through XOR0,
- and a hybrid version where only final 233-bit contribution accumulation uses XOR0.

Acceptance should require no Fmax loss below 200 MHz and no Logic LUT increase
over this VV11-2 checkpoint unless PMUL cycles decrease meaningfully.
