# VV31-1C Direct A/B Register Prefetch Gate

## Snapshot and staged gate

VV31-1C issues A during `CAP2(sub1)` and B during `FOLD(sub1)`.
`CAP1/CAP2(sub2)` place the returned operands directly into the normal A/B
registers, removing the VV31-1B register-role rearrangement.  No RTL was
changed during this gate.

- Git HEAD: `951936a75a70d400aceacf87323f4e3a9f96187a`
- `hdec_top.sv` SHA-256:
  `b8e9ef5e3def00508c1466b05a8455f2c3b4d7e8b685c1501fc7679af69e38d4`
- Stage1 aggregate RTL SHA-256:
  `60e18ca404b35c61533cd896aaf56bb3c991b4e5e5eccd55f2efff5486a67d7d`

The required quick gate passed before OOC was started.  Its fresh random K had
Hamming weight 114, matched the independent reference model, and completed in
149725 cycles.

## Four-random-K functional gate

The Vivado 2024.2 VV30 `stage1` suite passed all seven tests, including HDC
full-flow compatibility.  The stage run used fresh OS-CSPRNG seed:

`bd70aa92dcdfd20b86f25d27df4263e258e5f10b47fa36976b92021ac8aebbd2`

| Case | Hamming weight | PMUL cycles | Result |
|---:|---:|---:|---|
| 0 | 111 | 149725 | PASS |
| 1 | 109 | 149725 | PASS |
| 2 | 126 | 149725 | PASS |
| 3 | 125 | 149725 | PASS |

Every scalar matched the independent reference model.  VV31-1C therefore
preserves the 9496-cycle, approximately 5.96%, PMUL reduction established by
VV31-1A and VV31-1B.

## Matched OOC comparison

Vivado 2024.2 synthesized `hdec_top` out of context for
`xc7z020clg400-2` with a 5 ns clock:

| Metric | VV31-0 | VV31-1B | VV31-1C | 1C versus 1B |
|---|---:|---:|---:|---:|
| PMUL cycles | 159221 | 149725 | 149725 | 0 |
| Logic LUT | 4651 | 4820 | 4852 | +32 |
| FF | 1274 | 1274 | 1274 | 0 |
| BRAM | 4 | 4 | 4 | 0 |
| DSP | 0 | 0 | 0 | 0 |
| WNS | 0.328 ns | 0.328 ns | 0.308 ns | -0.020 ns |
| Estimated Fmax | 214.041 MHz | 214.041 MHz | 213.129 MHz | -0.912 MHz |

VV31-1C is 201 LUT above VV31-0 and 102 LUT above the agreed 4750 limit.
The worst endpoint is `i_vec/payload_q_reg[0][0]/CE`.  Its timing remains
above both the 0.20 ns WNS and 200 MHz gates, but it is slightly worse than
VV31-1B and does not reduce area.

## Artifacts

- Quick gate:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1C_quick_20260731`
- Stage1 regression:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1C_vv30_stage1_20260731`
- Stage1 manifest:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1C_vv30_stage1_20260731\run_manifest.json`
- OOC synthesis:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1C_ooc_20260731`
- OOC summary:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1C_ooc_20260731\reports\run_summary.txt`

## Gate decision

`REJECTED`

VV31-1C is functionally correct and retains the full cycle reduction, but
directly placing the prefetched words into the normal A/B registers increases
Logic LUT by 32 relative to VV31-1B and slightly reduces timing margin.  It
does not become the cumulative VV31 baseline.  VV31-1B remains the better
implementation reference for the next area-reduction variant.
