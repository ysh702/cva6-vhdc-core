# VV31-1G ADD-Step T1.A Prefetch Gate

## Snapshot and mechanism

VV31-1G extends the accepted VV31-1F schedule in ADD step 0.  While T0 is
written back, the controller prefetches T1.A and bypasses the intervening
`STEP_NEXT/PMUL_STEP` path.  No RTL or verification source was modified during
this gate.

- Git HEAD: `951936a75a70d400aceacf87323f4e3a9f96187a`
- `hdec_top.sv` SHA-256:
  `f1149e5dab28e29119bab17b81233e177fef3a25af24e389a8e94bbb4d485dc7`
- Candidate-stage aggregate RTL SHA-256:
  `e9e2551c35126c9636be6d8b1846304aafa068bf479e9abf8b1618666ad4b72e`

## Candidate functional evidence

The candidate-stage run used one new legal random K generated from Windows
OS-CSPRNG seed:

`5b0722adb3e0d77e0f6d5bb40ca7fcb16272c40ac857bff342d632bce0c86b8a`

| K Hamming weight | PMUL cycles | Result |
|---:|---:|---|
| 109 | 148073 | PASS |

The PMUL result matched the independent reference model.  The available VV31
baseline-gap, HDC-episode, PMUL-pipeline, and mode-switch tests also passed.
The stage manifest remains `NO_DECISION` because four planned cross-task test
sources are not yet present; that status is separate from the completed
candidate PMUL check.

An independent legacy HDC full-flow compatibility test was then run against
the same RTL snapshot and completed with:

`[HDEC_HDC_FULL_FLOW_V20] PASS`

## Cycle comparison

| Comparison | Cycle change |
|---|---:|
| VV31-1F to VV31-1G | -466 |
| VV31-0 to VV31-1G | -11148, approximately 7.00% |

The 466-cycle difference is consistent with one bypassed control cycle for
each applicable ADD-step transition.

## Matched OOC result

Vivado 2024.2 synthesized `hdec_top` out of context for
`xc7z020clg400-2` with a 5 ns clock:

| Metric | VV31-0 | VV31-1F | VV31-1G | 1G versus 1F |
|---|---:|---:|---:|---:|
| PMUL cycles | 159221 | 148539 | 148073 | -466 |
| Logic LUT | 4651 | 4726 | 4768 | +42 |
| FF | 1274 | 1272 | 1276 | +4 |
| BRAM | 4 | 4 | 4 | 0 |
| DSP | 0 | 0 | 0 | 0 |
| WNS | 0.328 ns | 0.328 ns | 0.328 ns | 0 |
| Estimated Fmax | 214.041 MHz | 214.041 MHz | 214.041 MHz | 0 |

The worst endpoint remains `group_dist_q_reg[8]/D`.  VV31-1G preserves the
complete timing margin, but its 4768 Logic LUT count is 18 LUT above the
agreed cumulative limit of 4750.

## Hierarchical LUT and FF localization

| Hierarchy | VV31-1F LUT | VV31-1G LUT | LUT delta | 1F FF | 1G FF | FF delta |
|---|---:|---:|---:|---:|---:|---:|
| Top-local `(hdec_top)` | 1805 | 1826 | +21 | 968 | 972 | +4 |
| `i_vec` total | 2921 | 2942 | +21 | 304 | 304 | 0 |
| Complete design | 4726 | 4768 | +42 | 1272 | 1276 | +4 |

The cost is split evenly between top-level prefetch and control logic and
synthesis propagation into the vector payload hierarchy.

## Artifacts

- Candidate-stage regression:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1G_stage_20260731`
- Candidate manifest:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1G_stage_20260731\run_manifest.json`
- Independent HDC full flow:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1G_hdc_full_flow_20260731`
- Matched OOC synthesis:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1G_ooc_20260731`
- OOC summary:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1G_ooc_20260731\reports\run_summary.txt`

## Gate decision

`REJECTED`

VV31-1G is functionally correct for the candidate random K, preserves HDC
compatibility, removes another 466 PMUL cycles, and has no timing loss.
However, it exceeds the 4750 Logic LUT limit by 18 LUT and therefore does not
replace VV31-1F as the cumulative ECC-only baseline.  A localized
area-reduction variant may retain the dependency-ahead scheduling relation
only if it returns the complete design to 4750 LUT or less.
