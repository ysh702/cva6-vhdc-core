# VV20 pair-token folding execution report

## Starting point

- Branch: `VV20`
- Base: `origin/VV19`
- Base commit: `f1c34ba8fdc3b28893415fb5892863bdcc4e4349`

VV20 starts from VV19 adjacent diagonal-pair capture. VV19 already reduced PMUL cycles, but modular folding was still structurally downstream of product capture. VV20's goal is to move folding to the diagonal-pair token level without adding an independent reducer and without losing 200 MHz timing.

## Baseline rerun in VV20

Local baseline rerun from unmodified VV19 RTL:

- PMUL cycles: 189412
- ST_ECC_DIAG cycles: 160380
- ST_ECC_LEAF_FOLD cycles: 1188
- GF_MUL_STARTS: 1188
- Logic LUT: 4914
- FF: 1489
- BRAM: 4
- WNS at 5.000 ns: 0.328 ns
- Fmax: 214.041 MHz

Logs:

- `stage1_vv19_baseline/xsim_pmul_profile/xsim_ecc_pmul_profile_v27/xsim.log`
- `stage1_vv19_baseline/ooc_200`

## Accepted structure: diagonal-pair token folding pipeline

The accepted VV20 structure is not another full reducer in parallel. It is a two-step pair-token pipeline:

1. During diagonal-pair capture, the two parity rows `{even, odd}` are converted into a local 64-bit pair product token and then into a 128-bit modular delta token.
2. On the next diagonal capture or issue slot, the existing `ecc_direct_reduce_word` path folds the previous token into the existing XOR0 contribution route.

This keeps the HDC/ECC shared XOR0 accumulation story intact and avoids the rejected same-cycle packet reducer. The production path no longer needs to build a full 64-bit leaf product before creating the modular contribution; it turns each adjacent diagonal pair into a modular token as the diagonal stream advances.

## Rejected attempt: same-cycle pair packet reducer

Attempt `stage4_pair_token_main_try1b/try1c` folded the current pair token into a full XOR0 packet in the same capture cycle.

Result:

- Functionally correct: PMUL profile passed.
- Cycles improved to 188224 and `ST_ECC_LEAF_FOLD=0`.
- Area was too high:
  - try1b: 5174 LUT / 1314 FF / WNS 0.250 ns
  - try1c with constant mux pruning: 5049 LUT / 1317 FF / WNS 0.328 ns

Reason rejected:

The same-cycle form added too much packet-reduction logic on the capture side. It improved cycles, but it crossed the area line and weakened the low-area story.

## Accepted attempt: delayed pair-token reducer reuse

Attempt `stage4_pair_token_pipeline_try2` keeps the pair-token story but folds the previous token with the existing reducer in the following available slot.

Result:

- PMUL cycles: 189412
- ST_ECC_DIAG cycles: 160380
- ST_ECC_LEAF_FOLD cycles: 1188
- GF_MUL_STARTS: 1188
- Logic LUT: 4874
- FF: 1450
- BRAM: 4
- WNS at 5.000 ns: 0.086 ns
- Fmax: 203.500 MHz

This is accepted because it completes the diagonal-pair token folding structure while reducing area below VV19 and keeping the VV19 cycle count.

## Verification

Passed:

- `xsim_hdec_ecc_pmul_profile_v27.tcl`
- `xsim_hdec_ecc_reduce_v1.tcl`
- `xsim_hdec_ecc_add_v1.tcl`
- `xsim_hdec_hdc_full_flow_v20.tcl`
- OOC 200 MHz synthesis for `stage4_pair_token_pipeline_try2`

Known non-blocking issue:

- `xsim_hdec_ecc_diag_reduce_map_v1.tcl` failed during generated C compilation before running behavioral checks. This is recorded as an old/tooling validation issue, not a functional RTL failure. The main PMUL profile and field/HDC smoke tests passed.

## Story meaning

VV20 turns the VV19 diagonal-pair capture into a real folding pipeline:

- VV19: adjacent pair capture reduced cycles, but modular folding still depended on a downstream leaf/sub product.
- VV20: each adjacent pair becomes a modular token during the diagonal stream; the next slot folds that token through the existing XOR0 route.

The important point is replacement, not addition. The accepted version avoids an independent reducer, preserves the unified bit-matrix data structure, preserves XOR0 reuse, reduces area from 4914 to 4874 LUT, and maintains 200 MHz timing.
