# VV31-1E First-Leaf Group-0 Prefetch Gate

## Snapshot and mechanism

VV31-1E extends the accepted VV31-1D schedule at the first leaf.  Except for
the residue-seed-from-VRF and MAC paths, `LOAD_A_WAIT` issues B early,
`LOAD_B_WAIT` captures B, and `LOAD_B` launches group 0 of the first leaf
before entering `CAP0`.  No RTL was changed during this gate.

- Git HEAD: `951936a75a70d400aceacf87323f4e3a9f96187a`
- `hdec_top.sv` SHA-256:
  `3729125eac49ef92b78a9118b8868b91eaa724d762bcf3eb09d9d8ff80b40fc8`
- Stage1 aggregate RTL SHA-256:
  `e26a8af5fa0ddb6ef4250acc75dd79c4a47ea8c46490b2029534b2fc24c319e8`

## Staged functional gate

The required VV30 quick gate passed first.  Its fresh random K had Hamming
weight 110, matched the independent model, and completed in exactly 148539
cycles.

The subsequent Vivado 2024.2 VV30 `stage1` suite passed all seven tests,
including HDC full-flow compatibility.  The run used fresh OS-CSPRNG seed:

`75bca7b61768e770d1174f2d4a3a4e247e4c55e496fd28682303ecf7c82dc308`

| Case | Hamming weight | PMUL cycles | Result |
|---:|---:|---:|---|
| 0 | 115 | 148539 | PASS |
| 1 | 120 | 148539 | PASS |
| 2 | 103 | 148539 | PASS |
| 3 | 129 | 148539 | PASS |

All four results matched the independent reference model and had identical
cycle counts.

## Measured cycle saving

VV31-1E measures 148539 cycles rather than the 149725 cycles of VV31-1D:

| Comparison | Measured reduction |
|---|---:|
| VV31-1D to VV31-1E | 1186 cycles |
| VV31-0 to VV31-1E | 10682 cycles, approximately 6.71% |

The 1186-cycle difference is exact in the quick run and all four stage runs.
It corresponds to 593 eligible first-leaf launches with two nonproductive
wait or issue cycles removed per launch.  The residue-seed-from-VRF and MAC
exceptions remain on their original paths.

## Matched OOC result

Vivado 2024.2 synthesized `hdec_top` out of context for
`xc7z020clg400-2` with a 5 ns clock:

| Metric | VV31-0 | VV31-1D | VV31-1E | 1E versus 1D |
|---|---:|---:|---:|---:|
| PMUL cycles | 159221 | 149725 | 148539 | -1186 |
| Logic LUT | 4651 | 4722 | 4866 | +144 |
| FF | 1274 | 1273 | 1274 | +1 |
| BRAM | 4 | 4 | 4 | 0 |
| DSP | 0 | 0 | 0 | 0 |
| WNS | 0.328 ns | 0.328 ns | 0.325 ns | -0.003 ns |
| Estimated Fmax | 214.041 MHz | 214.041 MHz | 213.904 MHz | -0.137 MHz |

VV31-1E remains above 200 MHz and the 0.20 ns WNS limit.  Its 4866 Logic LUT
count, however, is 116 LUT above the cumulative 4750 limit.

The hierarchical report localizes the 1D-to-1E growth:

| Hierarchy | VV31-1D LUT | VV31-1E LUT | Delta |
|---|---:|---:|---:|
| Top-local `(hdec_top)` | 1791 | 1795 | +4 |
| `i_vec` total | 2931 | 3071 | +140 |
| Complete design | 4722 | 4866 | +144 |

Most of the cost is therefore created by the additional first-group producer
at the vector payload boundary, rather than by the early-read controller
itself.

## Artifacts

- Quick gate:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1E_quick_20260731`
- Stage1 regression:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1E_vv30_stage1_20260731`
- Stage1 manifest:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1E_vv30_stage1_20260731\run_manifest.json`
- OOC synthesis:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1E_ooc_20260731`
- OOC summary:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1E_ooc_20260731\reports\run_summary.txt`

## Gate decision

`REJECTED`

The first-leaf scheduling relation is functionally valid and reproducibly
removes 1186 cycles.  The current implementation is not admitted to the
cumulative baseline because it exceeds the 4750 Logic LUT limit.  VV31-1D
remains the accepted baseline.  A future 1E variant would need to preserve the
early B capture while eliminating the extra vector-payload input selection.
