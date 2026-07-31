# VV31-1J Unified LOAD_A_WAIT2 Initialization Gate

## Snapshot and intended refinement

VV31-1J preserves the 145976-cycle dual-window schedule of VV31-1I and routes
the initialization of both independent-successor field multiplications through
the existing `LOAD_A_WAIT2` path.  The intent is to replace boundary-specific
initialization with one common entry sequence while retaining the two early-read
windows.

This gate was performed read-only.  No RTL or verification source was changed
while the locked snapshot was simulated and synthesized.

- Git branch: `VV31`
- Git HEAD: `951936a75a70d400aceacf87323f4e3a9f96187a`
- `hdec_top.sv` SHA-256:
  `f95a38e3f177cdfad70403a7665c743b256ba56fc12a716c8bab165051a06cc1`
- Candidate-stage aggregate RTL SHA-256:
  `68921b126be7995dd3a05be0aa842a6f77cbd38980d6442e78f478bf4a5f800b`

The common initialization path is an implementation experiment within the ECC
dependency-aware schedule.  It is not a separate paper-level innovation.

## Candidate functional evidence

The existing candidate-stage run used one newly generated legal random scalar
from the Windows OS cryptographic random source:

- Master seed:
  `a89db4256cd37d9c8321755f3570356db66612589499d3cb90dd107273b4dacf`
- K:
  `0000004b76070e5adcd536e317a0ad4be9c49d0766bc4519082ab6953e1b8f2b`
- K Hamming weight: `115`
- PMUL cycles: `145976`
- PMUL result: `PASS`

The same stage snapshot passed `baseline_gap`, `hdc_episode`,
`pmul_pipeline_contract`, and `mode_switch`.  The stage manifest remains
`NO_DECISION` because the four planned cross-task test sources are not yet
present.  That runner status is separate from this ECC-only candidate gate.

An independently launched legacy HDC full-flow simulation against the locked
RTL snapshot completed with:

`[HDEC_HDC_FULL_FLOW_V20] PASS`

The observed PMUL schedule is unchanged from VV31-1I and remains 932 cycles
shorter than the accepted VV31-1H baseline.

## Matched OOC result

Vivado 2024.2 synthesized `hdec_top` out of context for
`xc7z020clg400-2` under the same 5 ns clock constraint used for VV31-1H and
VV31-1I.

| Metric | VV31-1H | VV31-1I | VV31-1J | 1J versus 1I | 1J versus 1H |
|---|---:|---:|---:|---:|---:|
| PMUL cycles | 146908 | 145976 | 145976 | 0 | -932 |
| Logic LUT | 4746 | 4763 | 4926 | +163 | +180 |
| FF | 1270 | 1273 | 1277 | +4 | +7 |
| BRAM | 4 | 4 | 4 | 0 | 0 |
| DSP | 0 | 0 | 0 | 0 | 0 |
| WNS | 0.328 ns | 0.328 ns | 0.289 ns | -0.039 ns | -0.039 ns |
| Estimated Fmax | 214.041 MHz | 214.041 MHz | 212.269 MHz | -1.772 MHz | -1.772 MHz |

VV31-1J remains above the 0.20 ns WNS and 200 MHz Fmax gates, but it is 176
Logic LUT above the cumulative area limit of 4750.  The worst endpoint moves
to `ecc_leaf_b_q_reg[0]/CE`.

## Hierarchical localization

| Hierarchy | 1H LUT | 1I LUT | 1J LUT | 1J versus 1I | 1H FF | 1I FF | 1J FF | FF delta versus 1I |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Top-local `(hdec_top)` | 1830 | 1835 | 1965 | +130 | 966 | 969 | 973 | +4 |
| `i_vec` total | 2916 | 2928 | 2961 | +33 | 304 | 304 | 304 | 0 |
| Complete design | 4746 | 4763 | 4926 | +163 | 1270 | 1273 | 1277 | +4 |

The common `LOAD_A_WAIT2` initialization does not reduce the synthesized
selection structure.  Relative to VV31-1I, the top-level hierarchy grows by
130 LUT and the vector-payload hierarchy grows by 33 LUT.  The source-level
unification therefore expands, rather than compresses, the matched netlist.

## Evidence artifacts

- Candidate-stage regression:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1J_stage_20260731`
- Stage manifest SHA-256:
  `7c14da2a5e20653e21fac5b25c528039660a65bd75b7d60360f58ebd735be4b6`
- Independent HDC full flow:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1J_hdc_full_flow_20260731`
- HDC XSim log SHA-256:
  `3a859a60e71ee899a5bfc607a0099a49166bb185b2ab015971396cf5a0c02c4e`
- Matched OOC synthesis:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1J_ooc_20260731`
- OOC run-summary SHA-256:
  `6ba6b7feb34fae193aa2f4f822badacffb62204ef7a964ba53377062ceacf955`
- Utilization SHA-256:
  `825b0a2899e062e700f1588d732c187700cb3fb27316ace44b16ac9d47bcb6bb`
- Hierarchical utilization SHA-256:
  `31baec53c42d85c9ef307e3d3085e48007cc88e75b4b468c633cb2347a8a2ccf`

## Gate decision

`REJECTED`

VV31-1J passes the candidate random-K PMUL check and independent HDC full-flow
check, and it preserves the 145976-cycle dual-window schedule.  Its matched
netlist is 163 LUT larger than VV31-1I and 180 LUT larger than VV31-1H, with a
small timing-margin reduction.  It does not replace VV31-1H as the cumulative
ECC-only scheduling baseline, and this common-initialization form should not be
carried forward as the area-reduction solution for the second window.
