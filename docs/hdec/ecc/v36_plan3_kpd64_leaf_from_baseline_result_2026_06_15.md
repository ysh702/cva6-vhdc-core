# V36 Plan 3 Result: 64-bit Leaf From V36 Baseline

Date: 2026-06-15
Tool: Vivado 2022.2
Base RTL: V36 baseline restored at `736c6c42`
Final retained RTL: Plan 3 64-bit ECC leaf

## V36 Trial Rule

All V36 trials were evaluated from the same V36 baseline RTL, not stacked on top of one another.

The flow for each trial was:

```text
restore V36 baseline
apply one plan
run ECC reduce simulation
run ECC point-multiply profile simulation
run HDC standalone full-flow simulation
run ECC point-multiply + background HDC loop simulation
run Vivado 2022.2 OOC synthesis/timing
record result
restore V36 baseline before the next trial
```

After comparing the isolated trials, the final V36 RTL is Plan 3.

## What Changed

Plan 3 changes the ECC Karatsuba leaf from 32-bit to 64-bit.

Baseline:

```text
256 -> 128 -> 64 -> 32
3 Karatsuba levels
27 leaf multiplications
```

Plan 3:

```text
256 -> 128 -> 64
2 Karatsuba levels
9 leaf multiplications
```

Each 64-bit leaf has up to 127 diagonals. The implementation keeps the same 16-diagonal issue width, so one leaf takes 8 diagonal issue cycles. The design still writes the existing 512-bit product accumulator and then uses the existing `ecc_reduce233` path.

This trial does not include Plan 1 overlap and does not include direct mod-233 accumulation. It is an isolated 64-bit leaf experiment.

## V36 Attempt Summary

| Trial | RTL status | Reason |
|---|---|---|
| Plan 1: fold overlap | Evaluated, not retained | Good area efficiency, but 2022.2 OOC timing became much worse |
| Plan 2 first attempt: tail bypass including background flush | Reverted | Broke mixed ECC PMUL + background HDC because the background flush could disturb foreground HDC VRF reads |
| Plan 2 fixed attempt: blocking-only tail bypass | Evaluated, not retained | Functionally correct and timing-neutral, but LUT cost was high |
| Plan 3: 64-bit leaf | Retained | Best cycle reduction with acceptable LUT/FF cost and no 2022.2 timing regression |

The final branch keeps the Plan 3 RTL and uses this document as the consolidated V36 experiment record.

## Functional Checks

| Check | Result | Key data |
|---|---:|---|
| `xsim_hdec_ecc_reduce_v1.tcl` | PASS | ECC reduction correct |
| `xsim_hdec_ecc_pmul_profile_v27.tcl` | PASS | PMUL wall cycles = 190046 |
| `xsim_hdec_hdc_full_flow_v20.tcl` | PASS | HDC standalone correct |
| `xsim_hdec_ecc_pmul_bg_hdc_loop_v31.tcl` | PASS | Mixed ECC PMUL + background HDC correct |

PMUL profile highlights:

```text
PMUL_PROFILE_WALL_CYCLES=190046
PMUL_PROFILE_GF_MUL_STARTS=1203
PMUL_PROFILE_ST_ECC_DIAG_CYCLES=97443
PMUL_PROFILE_ST_ECC_LEAF_FOLD_CYCLES=43308
```

Mixed-flow data:

```text
HDC_FULL_FLOW_STANDALONE_CYCLES=959
PMUL_BG_HDC_LOOP_WALL_CYCLES=246685
PMUL_BG_HDC_LOOP_HDC_ITERS=131
PMUL_BG_HDC_LOOP_EQUIV_HDC_CYCLES=125629
PMUL_BG_HDC_LOOP_STATUS_LOW16=0
```

## Vivado 2022.2 OOC Result

| Version | PMUL cycles | Slice LUT | Logic LUT | LUTRAM | FF | WNS | Fmax est. |
|---|---:|---:|---:|---:|---:|---:|---:|
| V35/V36 baseline, Vivado 2022.2 | 341624 | 6507 | 6035 | 472 | 1807 | -0.059 ns | 197.668 MHz |
| V36 Plan 3, Vivado 2022.2 | 190046 | 7084 | 6612 | 472 | 1953 | -0.054 ns | 197.863 MHz |

Delta versus the Vivado 2022.2 baseline:

| Metric | Delta |
|---|---:|
| PMUL cycles | -151578 |
| Slice LUT | +577 |
| Logic LUT | +577 |
| LUTRAM | 0 |
| FF | +146 |
| Fmax est. | +0.195 MHz |

Worst endpoint:

```text
top_endpoint=ecc_diag16_pipe_q_reg[11]/D
worst_data_delay_ns=5.051
```

## All Vivado 2022.2 Trial Data

| Trial | Functional result | PMUL cycles | Mixed PMUL+HDC wall cycles | HDC iters | Slice LUT | Logic LUT | LUTRAM | FF | WNS | Fmax est. |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| V35/V36 baseline | PASS | 341624 | not rerun in this trial set | not rerun | 6507 | 6035 | 472 | 1807 | -0.059 ns | 197.668 MHz |
| Plan 1 fold overlap | PASS | 310346 | 434133 | 201 | 6693 | 6221 | 472 | 1871 | -1.318 ns | 158.278 MHz |
| Plan 2 fixed tail bypass | PASS | 309143 | 620698 | 366 | 7364 | 6892 | 472 | 1808 | -0.061 ns | 197.589 MHz |
| Plan 3 64-bit leaf | PASS | 190046 | 246685 | 131 | 7084 | 6612 | 472 | 1953 | -0.054 ns | 197.863 MHz |

Delta versus the Vivado 2022.2 baseline:

| Trial | PMUL cycle delta | Slice LUT delta | Logic LUT delta | LUTRAM delta | FF delta | Fmax delta |
|---|---:|---:|---:|---:|---:|---:|
| Plan 1 fold overlap | -31278 | +186 | +186 | 0 | +64 | -39.390 MHz |
| Plan 2 fixed tail bypass | -32481 | +857 | +857 | 0 | +1 | -0.079 MHz |
| Plan 3 64-bit leaf | -151578 | +577 | +577 | 0 | +146 | +0.195 MHz |

Simulation coverage for every retained/evaluated trial:

| Trial | ECC reduce | ECC PMUL profile | HDC full flow | ECC PMUL + background HDC |
|---|---|---|---|---|
| Plan 1 fold overlap | PASS | PASS | PASS | PASS |
| Plan 2 fixed tail bypass | PASS | PASS | PASS | PASS |
| Plan 3 64-bit leaf | PASS | PASS | PASS | PASS |

Raw report directories:

```text
reports/hdec/v36_plan1_fold_overlap_from_baseline_20260615/
reports/hdec/v36_plan2_tail_bypass_from_baseline_20260615/
reports/hdec/v36_plan3_kpd64_leaf_from_baseline_20260615/
```

## Comparison With Earlier Isolated Plans

| Trial | PMUL cycles | Logic LUT delta | FF delta | Fmax est. | Main tradeoff |
|---|---:|---:|---:|---:|---|
| Plan 1 fold overlap | 310346 | +186 | +64 | 158.278 MHz | Area efficient, but poor 2022.2 timing |
| Plan 2 tail bypass | 309143 | +857 | +1 | 197.589 MHz | Timing neutral, but LUT-heavy |
| Plan 3 64-bit leaf | 190046 | +577 | +146 | 197.863 MHz | Best cycle gain with acceptable area |

## Interpretation

Plan 3 is the strongest isolated result so far.

It cuts the leaf count from 27 to 9, so the PMUL cycle reduction is much larger than Plan 1 or Plan 2. The 64-bit diagonal datapath is wider, but the total LUT increase remains moderate because the scheduler, fold bookkeeping, and leaf iteration count shrink heavily.

This also confirms that the 64-bit leaf direction is more promising than only squeezing the 32-bit leaf schedule. The next useful refinement is to combine Plan 3 with a clean overlap or direct mod-233 accumulation, but that should be treated as a new isolated plan from the same V36 baseline.

For V36, the retained final RTL is Plan 3 only. Plan 1 and Plan 2 remain documented experiments, not stacked RTL changes.

## 2024.2 Carry-Forward Reference

The V35/V36 baseline reference already recorded for Vivado 2024.2 is:

| Version | PMUL cycles | Logic LUT | FF | Fmax est. |
|---|---:|---:|---:|---:|
| V35/V36 baseline, Vivado 2024.2 | 341624 | 5921 | 1802 | 210.217 MHz |

Plan 3 should be rerun under Vivado 2024.2 after the tool installation is ready.
