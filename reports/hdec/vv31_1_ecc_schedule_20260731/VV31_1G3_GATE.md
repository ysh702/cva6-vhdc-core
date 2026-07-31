# VV31-1G3 T1.A Prefetch Cleanup Gate

## Snapshot and mechanism

VV31-1G3 retains VV31-1G's dependency-ahead T1.A prefetch, restores the
required `src_a` assignment, simplifies the prefetch condition, and removes
duplicate MAC and square assignments.  The gate was performed read-only: no
RTL or verification source was changed while the snapshot was simulated and
synthesized.

- Git branch: `VV31`
- Git HEAD: `951936a75a70d400aceacf87323f4e3a9f96187a`
- `hdec_top.sv` SHA-256:
  `6d9ff2843a0cca35f3565f383f0e683bb23ff512c91dec39747f90a382e16c7d`
- Candidate-stage aggregate RTL SHA-256:
  `8391aa1336c0226f12c506979b1444e5ea8c562effd0923ce409c0c44c63ec4c`

This is an implementation refinement of the ECC dependency-aware schedule,
not a separate paper-level innovation.

## Candidate functional evidence

The existing candidate-stage run used one newly generated legal random scalar
from the Windows OS cryptographic random source:

- Master seed:
  `d6266b5bc53362e6322c9ec24395541b4ce5894a8dacb443745b7095c4d7ec6a`
- K:
  `0000007d1dbef0e9b348d93c2545dda28975f7b46e38333389bdddd29c701381`
- K Hamming weight: `122`
- PMUL cycles: `148073`
- PMUL result: `PASS`

The same stage snapshot also passed `baseline_gap`, `hdc_episode`,
`pmul_pipeline_contract`, and `mode_switch`.  The stage manifest remains
`NO_DECISION` because four planned cross-task test sources are not yet
present.  That runner status is separate from this ECC-only candidate gate.

An independently launched legacy HDC full-flow simulation against the locked
RTL snapshot completed with:

`[HDEC_HDC_FULL_FLOW_V20] PASS`

## Cycle result

| Comparison | Cycle change |
|---|---:|
| VV31-1F to VV31-1G3 | -466, approximately 0.314% |
| VV31-0 to VV31-1G3 | -11148, approximately 7.002% |

VV31-1G3 therefore preserves VV31-1G's 148073-cycle PMUL result while reducing
the implementation cost that caused VV31-1G to fail its area gate.

## Matched OOC result

Vivado 2024.2 synthesized `hdec_top` out of context for
`xc7z020clg400-2` under the same 5 ns clock constraint used by the VV31
baseline and previous candidates.

| Metric | VV31-0 | VV31-1F | VV31-1G | VV31-1G3 | 1G3 versus 1F | 1G3 versus 1G |
|---|---:|---:|---:|---:|---:|---:|
| PMUL cycles | 159221 | 148539 | 148073 | 148073 | -466 | 0 |
| Logic LUT | 4651 | 4726 | 4768 | 4740 | +14 | -28 |
| FF | 1274 | 1272 | 1276 | 1273 | +1 | -3 |
| BRAM | 4 | 4 | 4 | 4 | 0 | 0 |
| DSP | 0 | 0 | 0 | 0 | 0 | 0 |
| WNS | 0.328 ns | 0.328 ns | 0.328 ns | 0.301 ns | -0.027 ns | -0.027 ns |
| Estimated Fmax | 214.041 MHz | 214.041 MHz | 214.041 MHz | 212.811 MHz | -1.230 MHz | -1.230 MHz |

The worst timing endpoint is `ecc_leaf_b_q_reg[0]/CE`.  VV31-1G3 is 10 Logic
LUT below the cumulative limit of 4750, its WNS remains above 0.20 ns, and its
estimated Fmax remains above 200 MHz.

## Hierarchical localization

| Hierarchy | 1F LUT | 1G LUT | 1G3 LUT | 1G3 versus 1F | 1G3 versus 1G | 1F FF | 1G FF | 1G3 FF |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Top-local `(hdec_top)` | 1805 | 1826 | 1812 | +7 | -14 | 968 | 972 | 969 |
| `i_vec` total | 2921 | 2942 | 2928 | +7 | -14 | 304 | 304 | 304 |
| Complete design | 4726 | 4768 | 4740 | +14 | -28 | 1272 | 1276 | 1273 |

The cleanup removes 14 LUT from both the top-level control hierarchy and the
vector-payload hierarchy relative to VV31-1G.  The accepted mechanism's net
cost relative to VV31-1F is seven LUT in each hierarchy and one top-level FF.

## Evidence artifacts

- Candidate-stage regression:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1G3_stage_20260731`
- Stage manifest SHA-256:
  `99070c18b3c68b18fd5d3cb747a632186fb1238f02fe6a1037f66a6a5b17a507`
- Independent HDC full flow:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1G3_hdc_full_flow_20260731`
- HDC XSim log SHA-256:
  `168f739b2656b16f6b9613e9731ba95fc758b85f660c2d3a8cb007500c78855d`
- Matched OOC synthesis:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1G3_ooc_20260731`
- OOC run-summary SHA-256:
  `c5558ba462b7fc3d0ec5e91908380a2b5302ea3fa9c635f60e0b74516b1c5469`
- Hierarchical utilization SHA-256:
  `9ca1e855894180644aaa312dc10d84cc44a86bcdd1ee2e78c1ed2ce0fca3595b`

## Gate decision

`ACCEPTED`

VV31-1G3 preserves the 466-cycle gain of the dependency-ahead T1.A prefetch,
passes the one-random-K PMUL candidate check and the independent HDC full-flow
check, and returns the complete design to 4740 Logic LUT.  It therefore
replaces VV31-1F as the cumulative ECC-only scheduling baseline under the
current candidate policy.

The ECC-only schedule is not yet frozen.  A combined multi-K regression is
still required before the final ECC scheduling result is used as freeze-level
paper evidence.
