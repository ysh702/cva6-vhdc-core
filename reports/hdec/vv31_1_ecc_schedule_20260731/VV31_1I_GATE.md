# VV31-1I Unified Independent-Successor Multiply Gate

## Snapshot and scheduling mechanism

VV31-1I extends the accepted VV31-1H schedule by recognizing two point-add
boundaries with the same dependency relation.  At ADD steps 0 and 4, the value
being completed is independent of the operands used by the immediately
following field multiplication.  One common predicate and transition template
therefore launch the corresponding successor operand read before returning to
the ordinary PMUL-step path.

This gate was performed read-only.  No RTL or verification source was changed
while the locked snapshot was simulated and synthesized.

- Git branch: `VV31`
- Git HEAD: `951936a75a70d400aceacf87323f4e3a9f96187a`
- `hdec_top.sv` SHA-256:
  `0be068c1cad4bba5f273dc595d2c44d5a6daa108dae3cab663bbd1d3774260cd`
- Candidate-stage aggregate RTL SHA-256:
  `6ed584448c284581b39c5ad8e97413ce35b1dced4172141e99d3a096110016b0`

The unified template is evaluated as one implementation mechanism inside the
ECC dependency-aware schedule, not as a separate paper-level innovation.

## Candidate functional evidence

The existing candidate-stage run used one newly generated legal random scalar
from the Windows OS cryptographic random source:

- Master seed:
  `fb7efe1e903ab3f2e6b79ac84fde7e67076d4ebd72bd10ef1ce9e30699e7b48d`
- K:
  `0000001610d6ce89d160260571ba9cfcb9e8acfd01126463c629f79530ccd1e5`
- K Hamming weight: `110`
- PMUL cycles: `145976`
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
| VV31-1H to VV31-1I | -932, approximately 0.634% |
| VV31-0 to VV31-1I | -13245, approximately 8.319% |

The candidate preserves the existing computation structure and reduces the
observed schedule by applying the independent-successor launch relation at a
second eligible ADD boundary.

## Matched OOC result

Vivado 2024.2 synthesized `hdec_top` out of context for
`xc7z020clg400-2` under the same 5 ns clock constraint used for VV31-1H.

| Metric | VV31-1H | VV31-1I | 1I versus 1H |
|---|---:|---:|---:|
| PMUL cycles | 146908 | 145976 | -932 |
| Logic LUT | 4746 | 4763 | +17 |
| FF | 1270 | 1273 | +3 |
| BRAM | 4 | 4 | 0 |
| DSP | 0 | 0 | 0 |
| WNS | 0.328 ns | 0.328 ns | 0 |
| Estimated Fmax | 214.041 MHz | 214.041 MHz | 0 |

VV31-1I preserves the complete timing margin, with the worst endpoint at
`group_dist_q_reg[8]/D`.  It is nevertheless 13 Logic LUT above the cumulative
limit of 4750.

## Hierarchical localization

| Hierarchy | 1H LUT | 1I LUT | LUT delta | 1H FF | 1I FF | FF delta |
|---|---:|---:|---:|---:|---:|---:|
| Top-local `(hdec_top)` | 1830 | 1835 | +5 | 966 | 969 | +3 |
| `i_vec` total | 2916 | 2928 | +12 | 304 | 304 | 0 |
| Complete design | 4746 | 4763 | +17 | 1270 | 1273 | +3 |

The common successor-control template adds five top-local LUT and three FF.
Synthesis also increases the vector-payload hierarchy by 12 LUT, producing a
net increase of 17 Logic LUT.  The measured cycle benefit is real for the
tested candidate, but the present implementation does not satisfy the
cumulative area gate.

## Evidence artifacts

- Candidate-stage regression:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1I_stage_20260731`
- Stage manifest SHA-256:
  `1f0561b6ef22d9692b3c98a47f98e9d4f0f3e706cc329924be004a070d41514f`
- Independent HDC full flow:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1I_hdc_full_flow_20260731`
- HDC XSim log SHA-256:
  `4931292bfaca6a3e3ae8a136270ef3b5a56708d8f19954f8a567aacd422ccc72`
- Matched OOC synthesis:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1I_ooc_20260731`
- OOC run-summary SHA-256:
  `85b02f11f5b7d437c233aad561f7bcf4fbf366c3dc776bc51152a7ed3f771597`
- Utilization SHA-256:
  `dccf82e4a9ff4bac0410c257166f32633aa5a6770caa4be493c3156bbdc44599`
- Hierarchical utilization SHA-256:
  `9c63d37a6d6942977d49ff5f4f3c0bf99603a7148cd110323975cf72d6af0c98`

## Gate decision

`REJECTED`

VV31-1I passes the candidate random-K PMUL check and the independent HDC
full-flow check, saves a further 932 PMUL cycles, and preserves timing.  Its
4763 Logic LUT result exceeds the cumulative limit by 13 LUT, so it does not
replace VV31-1H as the cumulative ECC-only scheduling baseline.  A localized
area-reduction variant may retain the second independent-successor boundary
only if it returns the complete design to 4750 Logic LUT or less.
