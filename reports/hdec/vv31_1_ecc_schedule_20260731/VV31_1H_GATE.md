# VV31-1H Q(T4)-to-T2 Continuous Read-Stream Gate

## Snapshot and mechanism

VV31-1H combines the accepted VV31-1G3 schedule with a dependency-ahead read
stream between `Q(T4)` and the following `T2` field multiplication.  `Q(T4)`
depends only on `T4`, while `T2` consumes an independent point-coordinate
pair.  The controller therefore uses the two square-read wait slots to fetch
the A and B operands of `T2`, then enters the existing leaf-load path after the
square writeback instead of returning through the ordinary PMUL-step setup.

This gate was read-only.  No RTL or verification source was changed while the
locked snapshot was simulated and synthesized.

- Git branch: `VV31`
- Git HEAD: `951936a75a70d400aceacf87323f4e3a9f96187a`
- `hdec_top.sv` SHA-256:
  `4752137739d8393a4edd7ab59e4568b345f6adece90c6557c4f5401527898327`
- Candidate-stage aggregate RTL SHA-256:
  `250570b32c6336090b0248d98204d339ace366c101d28d323554ae3178cb56d6`

The continuous read stream is an implementation mechanism of the ECC
dependency-aware schedule.  It is not treated as a separate paper-level
innovation.

## Candidate functional evidence

The existing candidate-stage run used one newly generated legal random scalar
from the Windows OS cryptographic random source:

- Master seed:
  `6df3930a365725319d76ef6f2580486dc19b4973faf0bbf78ff5d2b440fb6b72`
- K:
  `0000005a068e45d7b74c04f2d89bc63e9b61c44bfb7b9f67c53882176671b5b7`
- K Hamming weight: `123`
- PMUL cycles: `146908`
- PMUL result: `PASS`

The same stage snapshot passed `baseline_gap`, `hdc_episode`,
`pmul_pipeline_contract`, and `mode_switch`.  The stage manifest remains
`NO_DECISION` because the four planned cross-task test sources are not yet
present.  That runner status is separate from this ECC-only candidate gate.

An independently launched legacy HDC full-flow simulation against the locked
RTL snapshot completed with:

`[HDEC_HDC_FULL_FLOW_V20] PASS`

## Cycle result

| Comparison | Cycle change |
|---|---:|
| VV31-1G3 to VV31-1H | -1165, approximately 0.787% |
| VV31-1F to VV31-1H | -1631, approximately 1.098% |
| VV31-0 to VV31-1H | -12313, approximately 7.733% |

The 1165-cycle reduction is obtained without adding another arithmetic unit or
wide data path.  It converts square-read wait slots into preparation time for
the next independent multiplication.

## Matched OOC result

Vivado 2024.2 synthesized `hdec_top` out of context for
`xc7z020clg400-2` under the same 5 ns clock constraint used by the VV31
baseline and previous candidates.

| Metric | VV31-0 | VV31-1F | VV31-1G3 | VV31-1H | 1H versus 1G3 |
|---|---:|---:|---:|---:|---:|
| PMUL cycles | 159221 | 148539 | 148073 | 146908 | -1165 |
| Logic LUT | 4651 | 4726 | 4740 | 4746 | +6 |
| FF | 1274 | 1272 | 1273 | 1270 | -3 |
| BRAM | 4 | 4 | 4 | 4 | 0 |
| DSP | 0 | 0 | 0 | 0 | 0 |
| WNS | 0.328 ns | 0.328 ns | 0.301 ns | 0.328 ns | +0.027 ns |
| Estimated Fmax | 214.041 MHz | 214.041 MHz | 212.811 MHz | 214.041 MHz | +1.230 MHz |

The worst timing endpoint returns to `group_dist_q_reg[8]/D`.  VV31-1H is four
Logic LUT below the cumulative limit of 4750, its WNS remains above 0.20 ns,
and its estimated Fmax remains above 200 MHz.  The area margin is narrow and
must be rechecked after any subsequent RTL change.

## Hierarchical localization

| Hierarchy | 1F LUT | 1G3 LUT | 1H LUT | 1H versus 1G3 | 1F FF | 1G3 FF | 1H FF | FF delta versus 1G3 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Top-local `(hdec_top)` | 1805 | 1812 | 1830 | +18 | 968 | 969 | 966 | -3 |
| `i_vec` total | 2921 | 2928 | 2916 | -12 | 304 | 304 | 304 | 0 |
| Complete design | 4726 | 4740 | 4746 | +6 | 1272 | 1273 | 1270 | -3 |

The new read-control and transition logic adds 18 top-local LUT relative to
VV31-1G3.  Synthesis reduces the vector-payload hierarchy by 12 LUT, leaving a
net complete-design increase of six LUT and a reduction of three FF.

## Evidence artifacts

- Candidate-stage regression:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1H_stage_20260731`
- Stage manifest SHA-256:
  `9660f0d7838f17818290afc4622eda468c3ec7952640aa6ae0e01af403fcd171`
- Independent HDC full flow:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1H_hdc_full_flow_20260731`
- HDC XSim log SHA-256:
  `1c1631c364dd0510626f2e6494058f74f4cdd27f94b3061d375de45c649ee7ce`
- Matched OOC synthesis:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1H_ooc_20260731`
- OOC run-summary SHA-256:
  `d539acb47e27d0fbc3b2c847d87900a546d3e394b0d5d966b22b8ed963a5609d`
- Hierarchical utilization SHA-256:
  `ac4fc28483022d43331634f778a98a736dd13489d444019cb01ef4033509bde0`

## Gate decision

`ACCEPTED`

VV31-1H preserves the accepted VV31-1G3 mechanisms, passes the one-random-K
PMUL candidate check and the independent HDC full-flow check, reduces PMUL by
a further 1165 cycles, and remains within the cumulative PPA gates at 4746
Logic LUT and 0.328 ns WNS.  It therefore replaces VV31-1G3 as the cumulative
ECC-only scheduling baseline under the current candidate policy.

The ECC-only schedule is not yet frozen.  A combined multi-K regression is
still required before the final scheduling result is used as freeze-level
paper evidence.
