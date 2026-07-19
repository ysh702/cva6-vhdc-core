# VV25 selection: shared bit-matrix reduction with native XOR1

Date: 2026-07-19

Branch: `VV25`

Selected implementation: **R31 hybrid57 split-CAP**
Retained area-first checkpoint: **R28 hybrid567 split-CAP**

## Selection result

The selected R31 implementation is the best balanced point under the fixed acceptance boundary. It uses 4661 Logic LUT, 1304 FF, 4 BRAM, and 0 DSP, and reaches 214.041 MHz under the 5 ns `hdec_top` OOC constraint. Complete PMUL takes 166840 wall cycles.

R28 remains a valid, non-dominated area-first alternative. It saves 4 LUT (4657 versus 4661), while R31 gains 7.643 MHz (214.041 versus 206.398). Both use 1304 FF and complete PMUL in 166840 cycles. R28 is therefore preserved as a useful method/checkpoint rather than discarded.

## Fixed reuse and algorithm invariants

- A single shared 16x16 AND generates all 256 partial products exactly once.
- ECC and HDC operands are mapped to the same unified 8x32 bit matrix.
- The complete 256-bit AND matrix is consumed once by all 32 existing 8-bit POPCOUNT subcounters. The existing XOR1 fabric receives only fixed parity summaries exposed by those shared POPCOUNT trees; it does not independently reduce a second copy of the 256 raw partial products.
- POPCOUNT and XOR1 cooperate through a 14-node partitioned diagonal reduction. Every diagonal is produced once; there is no overlapping diagonal ownership or total-parity recovery.
- ECC uses 14 nodes selected from the original 224 XOR1 nodes. Each native node remains a mode-free two-input `lhs ^ rhs` cell; only its external operands are selected by mode.
- R31 uses the hybrid57 equivalent equation mapping: the length-5 and length-7 mirror cases use the local-tail form, while the remaining cases use the common pair/short cancellation form. This changes fixed wiring, not the native XOR1 cell.
- Three explicit capture phases (`CAP0/CAP1/CAP2`) replace the runtime diagonal-group register and decode.
- During `CAP2`, the original leaf low-XOR path remains live and the next leaf's A operand is written directly into existing leaf registers. During fold, the next B operand arrives and the sole shared AND is preissued.
- External 32x32 interface, three-leaf Karatsuba decomposition, XOR0, modular-reduction algorithm, HDC instruction behavior, CVXIF, VRF, and unified writeback interface remain unchanged.
- No `bitband_pair`, `diag_aux`, second AND, ECC-private XOR tree, private counter array, or equivalent diagonal-reduction bypass exists.

## Final-equation closure

All eight combinations of the length-5/6/7 equivalent equations were synthesized on the same final main-register-reuse and split-CAP control structure. All use 4 BRAM and 0 DSP and passed the native-XOR1 functional probe.

| Run | Equation mapping | Logic LUT | FF | Fmax (MHz) | Result |
|---|---|---:|---:|---:|---|
| R28 | hybrid567 | **4657** | 1304 | 206.398 | Retained area-first Pareto point; PMUL 166840 |
| R29 | uniform | 4665 | 1304 | 214.041 | Dominated by R31 |
| R30 | hybrid56 | 4662 | 1304 | 214.041 | Dominated by R31 |
| R31 | hybrid57 | **4661** | 1304 | **214.041** | **Selected balanced point; full regression** |
| R32 | hybrid5 | 4663 | 1304 | 214.041 | Dominated by R31 |
| R33 | hybrid6 | 4663 | 1304 | 214.041 | Dominated by R31 |
| R35 | hybrid7 | 4668 | 1304 | 214.041 | Dominated by R31 |
| R36 | hybrid67 | 4666 | 1304 | 214.041 | Dominated by R31 |

R34 (`raw32 token`) is separately retained as a negative structural probe: it reduced FF to 1266 and held 214.041 MHz, but increased Logic LUT to 4735. It violates the `<4700` hard gate and costs 74 LUT more than R31, so it is not selected.

## Preserved method lineage

The following useful ideas remain documented by their models and reports even when they are not the selected RTL:

1. The 47-node byte-equation model established correctness of direct byte equations.
2. The 22-node POPCOUNT-tap model established independent POPCOUNT/XOR1 diagonal ownership without overlap.
3. The 14-node partitioned model reduced the native XOR1 demand while keeping all 32 POPCOUNT slots active.
4. Concurrent leaf low-XOR, fold-time AND preissue, direct reuse of the existing leaf registers, and split capture phases successively removed cycles, sidecar state, and runtime group decoding.
5. Uniform, local-tail, and all hybrid length-5/6/7 equation mappings were retained as measured alternatives, not rejected by intuition alone.

## Comparison with branch baselines

| Baseline | Logic LUT | FF | Fmax (MHz) | PMUL cycles | R31 change |
|---|---:|---:|---:|---:|---|
| VV22 | 4734 | 1442 | 214.041 | 189412 | -73 LUT, -138 FF, same Fmax, -22572 cycles |
| VV23 | 4840 | 1375 | 204.290 | 188224 | -179 LUT, -71 FF, +9.751 MHz, -21384 cycles |
| VV24 | 4822 | 1370 | 204.040 | 188224 | -161 LUT, -66 FF, +10.001 MHz, -21384 cycles |
| **VV25 R31** | **4661** | **1304** | **214.041** | **166840** | 39 LUT below the hard gate |

## Verification evidence

Current R31 source was restored after the last equation probes and matched the source hash used by the final regression. The restored-source native test reports:

`[VV25_NATIVE_XOR1] PASS legacy_cycles=2048 diag_cycles=2048 native_nodes=224 diag_nodes=14`

Algorithm/structure checks:

- Partitioned model: unified 8x32 layout, 256 unique partial products, 14 mixed bytes, 14 native XOR nodes, 8-bit exhaustive test (65536 pairs), and 100000 random 32-bit tests: PASS.
- Alternative 22-node POPCOUNT-tap and 47-node byte-equation models: the same exhaustive and random tests: PASS.
- RTL structure checker: 8/8 PASS, including single shared AND, complete 32x8 POPCOUNT, original native XOR1, 14 reused nodes, no private reducer, and fold/preissue/register collaboration.
- The synthesized hierarchy inventory contains exactly one `hdec_vector_payload_4x64` (`i_vec`) and one `hdec_gf2_contribution_row_tile_8x32` (`i_vec/i_gf2_contribution_row_tile`); no second ECC row tile or parallel reducer hierarchy is present.
- `git diff --check`: PASS (only line-ending conversion warnings).

The current 19 simulation regression logs under `vv25_r31_final_regression_20260719` all pass:

- native XOR1 legacy and diagonal modes;
- diagonal multiply and 184-cycle ECC multiply;
- 4096-vector diagonal reduction map, ECC reduction, inversion, addition, and alignment;
- full PMUL and PMUL profile (166840 wall cycles);
- background PMUL idle (166841), background PMUL, and PMUL/HDC interleaving (167938);
- HDC full flow and self-learning (`correct=26/32`, `updates=6`);
- all HMATCH compare-split cases, HPERM, shift alignment, and CVXIF smoke.

The self-learning directory contains an earlier backup log from before the fixture was supplied. The current official `xsim.log` uses the fixture and passes; the statement above refers to the 19 current official logs.

## Reports

- Selected OOC: `reports/hdec/vv25_r31_final_ooc_20260719/`
- Selected full regression: `reports/hdec/vv25_r31_final_regression_20260719/`
- Selected synthesized inventory and DCP: `reports/hdec/vv25_r31_final_inventory_20260719/`
- Restored-source native probe: `reports/hdec/vv25_r31_restored_precheck_20260719/`
- Area-first R28 OOC: `reports/hdec/vv25_r28_phasefsm_ooc_20260719/`
- Area-first R28 PMUL/profile: `reports/hdec/vv25_r28_phasefsm_pmul_20260719/`, `reports/hdec/vv25_r28_phasefsm_profile_20260719/`
- Last equation probes: `reports/hdec/vv25_r35_hybrid7_phasefsm_ooc_20260719/`, `reports/hdec/vv25_r36_hybrid67_phasefsm_ooc_20260719/`

## Selected-source SHA-256

```text
07689AA5CBCD38FD30EC07381ADE710E47F87FB1B993A55915FDBF6D99E5100F  core/hdec/rtl/hdec_lane_4x64.sv
43EB1FE7818880FEEDDE6F6931E9CD3AFA320A5BBA47FDDF0AD647001479ECAE  core/hdec/rtl/hdec_top.sv
F3651334F2B23013E09BFD8C0E0F9A2C70AAB03FC9427080293B05A009A6D276  verif/hdec/tb_hdec_vv25_native_xor1.sv
862E833722231F9CB0FE18019C3D0E438255A6815D3ABC249FB6BFDF27A8C081  verif/hdec/tb_hdec_ecc_pmul_profile_v27.sv
81D4A0E51146656DBA605A81DD15C2D9C745420020C7D2050DBAFB40493F975A  scripts/hdec/vv25_partitioned_pop_model.py
DBA094CFD70EBACBC15D2EC0FC6A0D24293F43AA714A8AAD32B56B51440BC924  scripts/hdec/vv25_reuse_structure_check.py
```

## Handoff state

R31 is the source-selected VV25 checkpoint represented by this document. R28 and every explored method remain recoverable from the E:-local reports and the equation records above; generated Vivado/XSim databases and rejected-probe artifacts are intentionally excluded from the source checkpoint.
