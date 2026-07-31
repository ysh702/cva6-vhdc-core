# VV31-1B Register-Role-Reuse Prefetch Gate

## Snapshot and scope

VV31-1B retains the cross-leaf first-group prefetch schedule but stores the
early A and B words by reusing the existing `leaf_a`, `leaf_b`, `xor_a`, and
`xor_b` 32-bit registers.  The VRF return no longer directly drives the matrix
input.  No RTL was changed during this gate.

- Git HEAD: `951936a75a70d400aceacf87323f4e3a9f96187a`
- `hdec_top.sv` SHA-256:
  `7e55bab02d21a35497b7799673362cce46a8a478b01fead7b76b95e1fd97eefd`
- Regression aggregate RTL SHA-256:
  `573835dafe42787a6ad5ab8f49d4f7211d03b1c9016efa9c5c0ef6bbb9374115`

## Functional and cycle gate

The Vivado 2024.2 VV30 `stage1` suite passed all seven tests, including HDC
full-flow compatibility.  The run used a new Windows OS-CSPRNG seed:

`ee0b9447c0be501420211d1546bd1a971e000bd7ad9f624f8f56b716aa9cfbe4`

| Case | Hamming weight | PMUL cycles | Result |
|---:|---:|---:|---|
| 0 | 116 | 149725 | PASS |
| 1 | 131 | 149725 | PASS |
| 2 | 113 | 149725 | PASS |
| 3 | 106 | 149725 | PASS |

All four unique legal random K-233 scalars matched the independent reference
model.  The cycle count remains data independent in this run.  Relative to
VV31-0, VV31-1B removes 9496 PMUL cycles, approximately 5.96%, with no loss
relative to VV31-1A.

## Matched OOC gate

Vivado 2024.2 synthesized `hdec_top` out of context for
`xc7z020clg400-2` at 5 ns:

| Metric | VV31-0 | VV31-1A | VV31-1B | 1B versus VV31-0 |
|---|---:|---:|---:|---:|
| Logic LUT | 4651 | 4939 | 4820 | +169 |
| FF | 1274 | 1281 | 1274 | 0 |
| BRAM | 4 | 4 | 4 | 0 |
| DSP | 0 | 0 | 0 | 0 |
| WNS | 0.328 ns | 0.097 ns | 0.328 ns | 0 |
| Estimated Fmax | 214.041 MHz | 203.957 MHz | 214.041 MHz | 0 |

The worst endpoint returns to `group_dist_q_reg[8]/D`.  Register-role reuse
therefore removes all 1A FF growth, recovers the full timing margin, and
reduces the 1A LUT cost by 119.  The remaining 4820 Logic LUT count is still
70 LUT above the agreed 4750 stage limit.

## Artifacts

- Random regression:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1B_vv30_stage1_20260731`
- Regression manifest:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1B_vv30_stage1_20260731\run_manifest.json`
- OOC synthesis:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1B_ooc_20260731`
- OOC summary:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1B_ooc_20260731\reports\run_summary.txt`

## Gate decision

`REJECTED`

VV31-1B verifies that the 9496-cycle gain does not require extra FFs or a
timing penalty.  It is a materially better implementation than VV31-1A, but
it is not yet admitted to the cumulative baseline because its Logic LUT count
remains above 4750.  The next optimization should preserve the registered
operand boundary while reducing the remaining prefetch-control and
input-selection logic by at least 70 LUT.
