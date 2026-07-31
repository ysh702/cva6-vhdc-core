# VV31-1A Cross-Leaf First-Group Prefetch Gate

## Snapshot and scope

VV31-1A evaluates only the current ECC-internal cross-leaf first-group
prefetch implementation.  No RTL was changed during this gate.

- Git HEAD: `951936a75a70d400aceacf87323f4e3a9f96187a`
- `hdec_top.sv` SHA-256:
  `b8002b79d3e93a8a93fdf500e36a90bfe174a1a0691001d1d6a58272dc48da0f`
- Regression aggregate RTL SHA-256:
  `e9e32bdf87ff3f485d9220350f186ded3bc1fdbbd27e9e0a2b1246ebb46b12ca`

## Functional and cycle gate

The Vivado 2024.2 VV30 `stage1` regression passed all seven tests, including
the existing HDC full-flow compatibility test.  The vector bundle used a new
Windows OS-CSPRNG seed:

`3c582a8ab714f811e27d0f9483ffa6640ef763c463881e93a9b04abb7c3fa387`

Four unique legal random K-233 scalars were checked:

| Case | Hamming weight | PMUL cycles | Result |
|---:|---:|---:|---|
| 0 | 118 | 149725 | PASS |
| 1 | 118 | 149725 | PASS |
| 2 | 123 | 149725 | PASS |
| 3 | 123 | 149725 | PASS |

Every result matched the independent reference model.  All four scalars took
exactly 149725 cycles.  Relative to the 159221-cycle VV31-0 baseline, the
implementation removes 9496 cycles, or approximately 5.96%.

## Matched OOC gate

Vivado 2024.2 synthesized `hdec_top` out of context for
`xc7z020clg400-2` with a 5 ns clock:

| Metric | VV31-0 baseline | VV31-1A | Delta |
|---|---:|---:|---:|
| Logic LUT | 4651 | 4939 | +288 |
| FF | 1274 | 1281 | +7 |
| BRAM | 4 | 4 | 0 |
| DSP | 0 | 0 | 0 |
| WNS | 0.328 ns | 0.097 ns | -0.231 ns |
| Estimated Fmax | 214.041 MHz | 203.957 MHz | -10.084 MHz |

The worst endpoint changed to `i_vec/payload_q_reg[0][0]/D`.

The design remains above 200 MHz, but it violates both stage limits:

- Logic LUT must not exceed 4750; observed 4939.
- WNS must not fall below 0.20 ns; observed 0.097 ns.

## Artifacts

- Random regression:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1A_vv30_stage1_20260731`
- Regression manifest:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1A_vv30_stage1_20260731\run_manifest.json`
- OOC synthesis:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1A_ooc_20260731`
- OOC summary:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1A_ooc_20260731\reports\run_summary.txt`

## Gate decision

`REJECTED`

The cross-leaf prefetch produces a reproducible 9496-cycle PMUL reduction and
passes functional regression, so the scheduling opportunity is valid.
However, this combinational implementation is not accepted as the cumulative
VV31 baseline because its LUT and WNS costs exceed the agreed limits.  The
next variant should retain the scheduling relation while registering or
localizing the prefetched operand path.
