# VV31-1D B-Then-A Cross-Leaf Prefetch Gate

## Snapshot and staged gate

VV31-1D reverses the prefetched operand order.  It issues B during
`CAP2(sub1)` and A during `FOLD(sub1)`.  B is written into the normal B pair
during `CAP1(sub2)`, while A follows the baseline `CAP2` path into the normal A
pair.  The final fold prefetches group 0 of the next leaf.  No RTL was changed
during this gate.

- Git HEAD: `951936a75a70d400aceacf87323f4e3a9f96187a`
- `hdec_top.sv` SHA-256:
  `63a958de831419186195b198a2b62f981d314d7f5c97be434ff4dadff0f075c0`
- Stage1 aggregate RTL SHA-256:
  `f1778623bd60d03dadb754af0106c948371064003ac092605fa714ecc5b34165`

The required quick gate passed first.  Its fresh random K had Hamming weight
122, matched the independent model, and completed in 149725 cycles.

## Four-random-K functional gate

The Vivado 2024.2 VV30 `stage1` suite passed all seven tests, including HDC
full-flow compatibility.  The run used fresh OS-CSPRNG seed:

`c431c428508c73fe468f81b2e3cf8e5777db411fbc9018d321633feb389df76b`

| Case | Hamming weight | PMUL cycles | Result |
|---:|---:|---:|---|
| 0 | 126 | 149725 | PASS |
| 1 | 122 | 149725 | PASS |
| 2 | 102 | 149725 | PASS |
| 3 | 123 | 149725 | PASS |

Every scalar matched the independent reference model and completed in the
same number of cycles.  Relative to VV31-0, VV31-1D removes 9496 PMUL cycles,
approximately 5.96%.

## Matched OOC comparison

Vivado 2024.2 synthesized `hdec_top` out of context for
`xc7z020clg400-2` with a 5 ns clock:

| Metric | VV31-0 | VV31-1B | VV31-1D | 1D versus VV31-0 |
|---|---:|---:|---:|---:|
| PMUL cycles | 159221 | 149725 | 149725 | -9496 |
| Logic LUT | 4651 | 4820 | 4722 | +71 |
| FF | 1274 | 1274 | 1273 | -1 |
| BRAM | 4 | 4 | 4 | 0 |
| DSP | 0 | 0 | 0 | 0 |
| WNS | 0.328 ns | 0.328 ns | 0.328 ns | 0 |
| Estimated Fmax | 214.041 MHz | 214.041 MHz | 214.041 MHz | 0 |

VV31-1D is 28 LUT below the 4750 stage limit and preserves the full entry
timing margin.  The overall worst endpoint remains
`group_dist_q_reg[8]/D`.

## Hierarchical area localization

| Hierarchy | VV31-1B Logic LUT | VV31-1D Logic LUT | Delta | 1B FF | 1D FF | Delta |
|---|---:|---:|---:|---:|---:|---:|
| Top-local `(hdec_top)` | 1873 | 1791 | -82 | 970 | 969 | -1 |
| `i_vec` total | 2947 | 2931 | -16 | 304 | 304 | 0 |
| Complete `hdec_top` | 4820 | 4722 | -98 | 1274 | 1273 | -1 |

Most of the 1B-to-1D saving is therefore localized in top-level prefetch
control and operand selection.  A further 16 LUT reduction appears in the
vector payload hierarchy after synthesis propagation.

## Leaf-register D-cone audit

Both checkpoints were reopened in Vivado 2024.2 and timed explicitly to all
32 A-register D pins and all 32 B-register D pins:

| D cone | VV31-1B worst delay | VV31-1D worst delay | Delay change | 1B slack | 1D slack |
|---|---:|---:|---:|---:|---:|
| `ecc_leaf_a_q[*]/D` | 4.244 ns | 4.090 ns | -0.154 ns | 0.753 ns | 0.907 ns |
| `ecc_leaf_b_q[*]/D` | 4.466 ns | 4.090 ns | -0.376 ns | 0.531 ns | 0.907 ns |

The worst leaf D paths remain six logic levels in both variants.  The
B-then-A ordering reduces routing delay and makes the worst A and B D cones
equal.  In the global timing top-200 report, 121 of the VV31-1B paths traverse
the leaf-register cone, including 96 that traverse the B cone.  VV31-1D has
zero leaf-register-cone paths in its top 200.  The prefetch path is therefore
no longer near the design-level critical region.

## Artifacts

- Quick gate:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1D_quick_20260731`
- Stage1 regression:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1D_vv30_stage1_20260731`
- Stage1 manifest:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1D_vv30_stage1_20260731\run_manifest.json`
- OOC synthesis:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1D_ooc_20260731`
- Leaf D-cone audit:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1D_ooc_20260731\leaf_d_audit`
- Reusable D-cone audit Tcl:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_vv31_schedule_worktree\reports\hdec\vv31_1_ecc_schedule_20260731\vv31_leaf_d_audit.tcl`

## Gate decision

`ACCEPTED`

VV31-1D passes functional, cycle, area, and timing gates.  It retains the full
9496-cycle PMUL reduction with only 71 additional Logic LUT, one fewer FF, and
no WNS or Fmax loss relative to VV31-0.  VV31-1D becomes the cumulative
baseline for the next ECC-internal scheduling optimization.
