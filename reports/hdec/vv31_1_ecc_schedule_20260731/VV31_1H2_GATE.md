# VV31-1H2 Q(T4)-to-T2 Predicate Cleanup Gate

## Snapshot and intended refinement

VV31-1H2 retains the accepted VV31-1H schedule and removes source-level logic
considered redundant in the `Q(T4)`-to-`T2` transition: the extra job and phase
terms in the prefetch predicate, together with MAC and square-repeat assignments
already guaranteed to be zero at that transition.

This gate was performed read-only.  No RTL or verification source was changed
while the locked snapshot was simulated and synthesized.

- Git branch: `VV31`
- Git HEAD: `951936a75a70d400aceacf87323f4e3a9f96187a`
- `hdec_top.sv` SHA-256:
  `369a066bd533937370feb2f6ed95a67f03c37252f546ca3bbfb39c5361f2175a`
- Candidate-stage aggregate RTL SHA-256:
  `43439936b3bf478893c94c13efae0295f2ce7d45347f73c568a4c3e0f22d1d51`

This is an implementation cleanup candidate, not a paper-level mechanism or
innovation.

## Functional evidence

The existing candidate-stage run used one newly generated legal random scalar
from the Windows OS cryptographic random source:

- Master seed:
  `ceaaeb2c064912467ed9d44755e13184defe6e18178bda2435f67a5dfa7bd91a`
- K:
  `00000004d630fdb3c5f23f27d51fa7737943dc0ea7206e33020bfe5618871bce`
- K Hamming weight: `120`
- PMUL cycles: `146908`
- PMUL result: `PASS`

The same stage snapshot passed `baseline_gap`, `hdc_episode`,
`pmul_pipeline_contract`, and `mode_switch`.  The stage manifest remains
`NO_DECISION` because the four planned cross-task test sources are not yet
present.  That runner status is separate from this ECC-only candidate gate.

An independently launched legacy HDC full-flow simulation against the locked
RTL snapshot completed with:

`[HDEC_HDC_FULL_FLOW_V20] PASS`

The tested PMUL cycle count is identical to VV31-1H, so the intended cleanup
does not change the observed schedule length.

## Matched OOC result

Vivado 2024.2 synthesized `hdec_top` out of context for
`xc7z020clg400-2` under the same 5 ns clock constraint used for VV31-1H.

| Metric | VV31-1H | VV31-1H2 | 1H2 versus 1H |
|---|---:|---:|---:|
| PMUL cycles | 146908 | 146908 | 0 |
| Logic LUT | 4746 | 4771 | +25 |
| FF | 1270 | 1277 | +7 |
| BRAM | 4 | 4 | 0 |
| DSP | 0 | 0 | 0 |
| WNS | 0.328 ns | 0.299 ns | -0.029 ns |
| Estimated Fmax | 214.041 MHz | 212.721 MHz | -1.320 MHz |

VV31-1H2 is 21 Logic LUT above the cumulative limit of 4750.  Its timing still
meets the 0.20 ns WNS and 200 MHz Fmax gates, but both timing metrics are worse
than VV31-1H.  The worst endpoint moves from `group_dist_q_reg[8]/D` to
`ecc_leaf_b_q_reg[0]/CE`.

## Hierarchical localization

| Hierarchy | 1H LUT | 1H2 LUT | LUT delta | 1H FF | 1H2 FF | FF delta |
|---|---:|---:|---:|---:|---:|---:|
| Top-local `(hdec_top)` | 1830 | 1843 | +13 | 966 | 973 | +7 |
| `i_vec` total | 2916 | 2928 | +12 | 304 | 304 | 0 |
| Complete design | 4746 | 4771 | +25 | 1270 | 1277 | +7 |

The source-level deletion does not produce a synthesized-area recovery.  The
matched netlist instead grows in both the top-level control hierarchy and the
vector-payload hierarchy.  This result is sufficient to reject the cleanup as
an accumulated PPA candidate even though the tested functionality and cycle
count are preserved.

## Evidence artifacts

- Candidate-stage regression:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1H2_stage_20260731`
- Stage manifest SHA-256:
  `cde07d9be0b0cc940df1affa0443bf4ec93d66791e228a55948885c691c021`
- Independent HDC full flow:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1H2_hdc_full_flow_20260731`
- HDC XSim log SHA-256:
  `3da7fee250878a9d355cc27209f69317b91c1813c85d793be5314621fe27f32b`
- Matched OOC synthesis:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1H2_ooc_20260731`
- OOC run-summary SHA-256:
  `52422b4f08215f1c9c8640cf9210d9ba473104e661838fb1863f12267573ff1b`
- Hierarchical utilization SHA-256:
  `cd1bcd3d1395aab61619058af93456d158bce59b1783b3d226f7606e083d8320`

## Gate decision

`REJECTED`

VV31-1H2 passes the candidate random-K PMUL check and the independent HDC
full-flow check, and it preserves the 146908-cycle schedule.  It nevertheless
adds 25 Logic LUT and seven FF relative to VV31-1H, exceeds the cumulative area
limit, and slightly reduces timing margin.  It does not replace VV31-1H as the
cumulative ECC-only scheduling baseline.
