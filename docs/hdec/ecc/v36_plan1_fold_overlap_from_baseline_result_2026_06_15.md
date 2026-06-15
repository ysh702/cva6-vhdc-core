# V36 Plan 1 Result: Leaf Fold Overlap From V36 Baseline

Date: 2026-06-15
Tool: Vivado 2022.2
Base RTL: V36 baseline restored at `736c6c42`

## What Changed

Plan 1 overlaps the next leaf's first diagonal issue with the current leaf's final fold cycle.

Baseline per leaf:

```text
4 diagonal issue cycles
+ 1 diagonal flush cycle
+ 4 fold cycles
```

Plan 1 keeps the full fold sequence, but uses fold word 3 to issue the next leaf's first diagonal group. In simple terms, while the old leaf writes its final product contribution, the next leaf starts doing useful multiply work.

This requires a small leaf-product latch and path latch so the fold side can finish the previous leaf while the diagonal side starts the next leaf.

## Functional Checks

| Check | Result | Key data |
|---|---:|---|
| `xsim_hdec_ecc_reduce_v1.tcl` | PASS | ECC reduction correct |
| `xsim_hdec_ecc_pmul_profile_v27.tcl` | PASS | PMUL wall cycles = 310346 |
| `xsim_hdec_hdc_full_flow_v20.tcl` | PASS | HDC standalone correct |
| `xsim_hdec_ecc_pmul_bg_hdc_loop_v31.tcl` | PASS | Mixed ECC PMUL + background HDC correct |

Mixed-flow data:

```text
HDC_FULL_FLOW_STANDALONE_CYCLES=959
PMUL_BG_HDC_LOOP_WALL_CYCLES=434133
PMUL_BG_HDC_LOOP_HDC_ITERS=201
PMUL_BG_HDC_LOOP_EQUIV_HDC_CYCLES=192759
PMUL_BG_HDC_LOOP_STATUS_LOW16=0
```

## Vivado 2022.2 OOC Result

| Version | PMUL cycles | Slice LUT | Logic LUT | LUTRAM | FF | WNS | Fmax est. |
|---|---:|---:|---:|---:|---:|---:|---:|
| V35/V36 baseline, Vivado 2022.2 | 341624 | 6507 | 6035 | 472 | 1807 | -0.059 ns | 197.668 MHz |
| V36 Plan 1, Vivado 2022.2 | 310346 | 6693 | 6221 | 472 | 1871 | -1.318 ns | 158.278 MHz |

Delta versus the Vivado 2022.2 baseline:

| Metric | Delta |
|---|---:|
| PMUL cycles | -31278 |
| Slice LUT | +186 |
| Logic LUT | +186 |
| LUTRAM | 0 |
| FF | +64 |
| Fmax est. | -39.390 MHz |

Worst endpoint:

```text
top_endpoint=ecc_diag16_pipe_q_reg[13]/D
worst_data_delay_ns=6.315
```

## Interpretation

Plan 1 is the better area/performance tradeoff among the two isolated trials so far.

Compared with Plan 2, it saves nearly the same number of PMUL cycles while using far fewer LUTs. It also gives a much better mixed ECC + HDC loop result. The main downside is the 2022.2 OOC timing path into `ecc_diag16_pipe_q`, caused by starting the next leaf's first diagonal group during the previous leaf's final fold cycle.

The next useful refinement is to keep this scheduling idea, but add a cleaner register boundary around the overlapped diagonal issue path so the 2022.2 timing estimate recovers.

## 2024.2 Carry-Forward Reference

The V35/V36 baseline reference already recorded for Vivado 2024.2 is:

| Version | PMUL cycles | Logic LUT | FF | Fmax est. |
|---|---:|---:|---:|---:|
| V35/V36 baseline, Vivado 2024.2 | 341624 | 5921 | 1802 | 210.217 MHz |

Plan 1 should be rerun under Vivado 2024.2 after the tool installation is ready.

