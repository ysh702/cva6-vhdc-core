# VV23 selected checkpoint: direct87 + prefetch CE

## Selection

This is the selected VV23 checkpoint as of 2026-07-17. It restores the
historical direct-87-node XOR1 mapping and the dedicated clock-enable write
style for the two next-leaf prefetch registers.

- Branch: `VV23`
- Base commit: `42279687fb6eddeb248285f66357146f6b927fd1`
- Synthesis top: `hdec_top` (OOC HDEC core; CV-X-IF wrapper and CVA6 excluded)
- Part: `xc7z020clg400-2`
- Constraint: 5.000 ns
- Commit/push: none

## Reproduced results

| Metric | Result |
|---|---:|
| Logic LUT | 4840 |
| FF | 1375 |
| BRAM | 4 |
| DSP | 0 |
| WNS | 0.105 ns |
| Estimated Fmax | 204.290 MHz |
| PMUL wall cycles | 188224 |

Reports:

- OOC: `reports/hdec/vv23_selected_prefetchce_ooc_20260717/`
- PMUL: `reports/hdec/vv23_selected_prefetchce_pmul_20260717/`
- shared XOR1: `reports/hdec/vv23_selected_prefetchce_shared_xor1_20260717/`
- top diagonal multiplication: `reports/hdec/vv23_selected_prefetchce_topdiag_20260717/`

## Reuse boundary evidence

- There is one shared `8 x 32` AND matrix. Each row is formed once as
  `matrix_src_a_i[rid] & matrix_src_b_i[rid]`.
- The same registered matrix feeds all eight complete 32-bit POPCOUNT rows and
  the shared XOR1 diagonal mode.
- The direct-87 mapping places 64 diagonal reduction nodes on the VV22
  low-XOR nodes `160..223`; the remaining 23 use original XOR1 nodes `0..22`.
- Every physical XOR1 node is selected by `diag_mode_i` between the diagonal
  equation and the VV22 legacy equation. No second ECC XOR array is declared.
- Removed VV22 dedicated-path names `bitband_pair_src_b_i` and
  `bitband_pair_parity_o` are absent from the RTL.
- The prefetch CE change only changes the register update structure. It does
  not add an AND, POPCOUNT, XOR1, or ECC compute path.

## Verification reproduced after recovery

- Python model: partition 256, 32 byte counts, 87 XOR1 nodes, 8-bit exhaustive
  65536 cases, and 100000 random 32-bit carry-less multiplications: PASS.
- Shared XOR1 XSim: 2048 VV22 legacy cycles and 2048 diagonal cycles: PASS.
- Top diagonal multiplication XSim: PASS.
- Complete PMUL profile: PASS, 188224 wall cycles.
- `git diff --check`: PASS.

## Source hashes

| File | Git blob hash |
|---|---|
| `core/hdec/rtl/hdec_top.sv` | `593c7221fa1e5364e5231524e89f2d319365e6ed` |
| `core/hdec/rtl/hdec_lane_4x64.sv` | `b9e70ab62014df1db25e238d44def1f0c77028f4` |
| `verif/hdec/tb_hdec_ecc_diag_reduce_map_v1.sv` | `fc874e76c1345977977e60fdb1737055ddc66628` |
| `scripts/hdec/vv23_unified_matrix_model.py` | `c7f9c160de66edea8faeb8309829c5f2ac65a9ff` |

## Audit of apparently smaller alternatives

| Probe | LUT / Fmax (MHz) | Decision |
|---|---:|---|
| XOR1 87-node early map | 4807 / 212.902 | Reject: diagonal nodes were placed on legacy-pruned nodes `0..86`, so the synthesized logic included diagonal-only XOR resources. |
| XOR1 156-node early map | 4815 / 212.902 | Reject: same legacy-pruned-node problem. |
| POPCOUNT chunks-31 | 4825 / 195.160 | Reject: changed the complete eight-row POPCOUNT structure and failed 200 MHz. |
| XOR1 global-224 map | 4826 / 210.128 | Reject under the strict physical-reuse criterion: although represented as one logical XOR1 module, the diagonal network occupied 219 nodes while the production VV22 top retained only nodes `160..223`; most synthesized nodes therefore served only diagonal mode. |
| recovered mixed rollback | 4832 / 195.695 | Reject: not the historical source structure and failed 200 MHz. |
| direct87 + prefetch CE | 4840 / 204.290 | **Selected.** |
| recovered mixed probe | 4842 / 195.963 | Reject: failed 200 MHz. |
| four-leaf dedicated CE | 4851 / 198.491 | Reject: failed 200 MHz. |
| direct87 base | 4852 / 208.681 | Valid strict-reuse fallback, but 12 LUT larger than the selected checkpoint. |

Therefore, 4840 / 204.290 MHz is the smallest already-built checkpoint that
simultaneously preserves the complete POPCOUNT, maps diagonal reduction onto
the production-retained VV22 XOR1 nodes, passes 200 MHz, and keeps PMUL at
188224 cycles.
