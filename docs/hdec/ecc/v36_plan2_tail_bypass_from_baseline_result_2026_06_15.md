# V36 Plan 2 Result: Tail Bypass From V36 Baseline

Date: 2026-06-15
Tool: Vivado 2022.2
Base RTL: V36 baseline restored at `736c6c42`

## What Changed

Plan 2 removes one serialized cycle between the last diagonal issue and fold word 0.

Baseline per leaf:

```text
4 diagonal issue cycles
+ 1 diagonal flush cycle
+ 4 fold cycles
```

Plan 2 per blocking ECC leaf:

```text
4 diagonal issue cycles
+ flush cycle also writes fold word 0
+ 3 remaining fold cycles
```

The first attempted version also applied this during background ECC sidecar flush. That broke the mixed ECC + HDC test because it could overwrite the foreground HDC VRF read request. The retained Plan 2 version only bypasses the blocking `S_ECC_DIAG_WAIT` path; background sidecar flush remains baseline-compatible.

## Functional Checks

| Check | Result | Key data |
|---|---:|---|
| `xsim_hdec_ecc_reduce_v1.tcl` | PASS | ECC reduction correct |
| `xsim_hdec_ecc_pmul_profile_v27.tcl` | PASS | PMUL wall cycles = 309143 |
| `xsim_hdec_hdc_full_flow_v20.tcl` | PASS | HDC standalone correct |
| `xsim_hdec_ecc_pmul_bg_hdc_loop_v31.tcl` | PASS | Mixed ECC PMUL + background HDC correct |

Mixed-flow data:

```text
HDC_FULL_FLOW_STANDALONE_CYCLES=959
PMUL_BG_HDC_LOOP_WALL_CYCLES=620698
PMUL_BG_HDC_LOOP_HDC_ITERS=366
PMUL_BG_HDC_LOOP_EQUIV_HDC_CYCLES=350994
PMUL_BG_HDC_LOOP_STATUS_LOW16=0
```

## Vivado 2022.2 OOC Result

| Version | PMUL cycles | Slice LUT | Logic LUT | LUTRAM | FF | WNS | Fmax est. |
|---|---:|---:|---:|---:|---:|---:|---:|
| V35/V36 baseline, Vivado 2022.2 | 341624 | 6507 | 6035 | 472 | 1807 | -0.059 ns | 197.668 MHz |
| V36 Plan 2, Vivado 2022.2 | 309143 | 7364 | 6892 | 472 | 1808 | -0.061 ns | 197.589 MHz |

Delta versus the Vivado 2022.2 baseline:

| Metric | Delta |
|---|---:|
| PMUL cycles | -32481 |
| Slice LUT | +857 |
| Logic LUT | +857 |
| LUTRAM | 0 |
| FF | +1 |
| Fmax est. | -0.079 MHz |

Worst endpoint:

```text
top_endpoint=st_q_reg[3]/D
worst_data_delay_ns=5.058
```

## Interpretation

Plan 2 is functionally valid after restricting the bypass to blocking ECC execution.

The cycle gain is real and close to Plan 1's gain, but the area cost is much higher than expected. The likely reason is that fold word 0 now needs to choose between the registered leaf product and the just-flushed leaf product, adding a wide mux/fanout path into the fold contribution logic.

This means Plan 2 is a useful timing-neutral cycle optimization, but not the best area/performance tradeoff so far.

## 2024.2 Carry-Forward Reference

The V35/V36 baseline reference already recorded for Vivado 2024.2 is:

| Version | PMUL cycles | Logic LUT | FF | Fmax est. |
|---|---:|---:|---:|---:|
| V35/V36 baseline, Vivado 2024.2 | 341624 | 5921 | 1802 | 210.217 MHz |

Plan 2 should be rerun under Vivado 2024.2 after the tool installation is ready.

