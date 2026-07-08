# VV20 diagonal-pair token folding plan

## Baseline

- Branch: `VV20`
- Starting point: `origin/VV19`
- Baseline commit: `f1c34ba8fdc3b28893415fb5892863bdcc4e4349`
- Baseline story: VV19 has already reduced PMUL cycles by adjacent diagonal-pair capture, but the modular folding is still structurally downstream of the diagonal product capture. VV20 keeps the VV19 cycle win as the baseline and moves the folding story toward true diagonal-pair-level fold-as-you-compute.

## Hard acceptance targets

- Timing: keep 200 MHz closure.
- Cycles: do not lose the VV19 PMUL cycle level; accepted attempts should keep cycles at or below the VV19 report unless the area/timing evidence makes the trade-off explicitly valuable.
- Area: do not solve the story by adding a second independent reducer. The first goal is to move logic, remove old logic, or share logic. Area should move down from VV19, not up.
- Data structure: preserve the unified bit-matrix / bitband view of product generation and reduction.
- Reuse story: preserve the XOR0 contribution route and HDC/ECC shared accumulation narrative.

## Stage 1: lock the VV19 baseline inside VV20

Use the existing VV19 report as the initial reference, then rerun the local VV20 OOC/profile before accepting RTL changes.

Stage 1 local VV20 rerun result:

- PMUL cycles: 189412
- ST_ECC_DIAG cycles: 160380
- GF_MUL_STARTS: 1188
- Logic LUT: 4914
- FF: 1489
- BRAM: 4
- WNS at 5.000 ns: 0.328 ns
- Fmax: 214.041 MHz
- Status: `HDEC_ECC_PMUL_PROFILE_V27 PASS`
- Profile log: `stage1_vv19_baseline/xsim_pmul_profile/xsim_ecc_pmul_profile_v27/xsim.log`
- OOC output: `stage1_vv19_baseline/ooc_200`

## Stage 2: area audit and production-path trim

VV19 production mode always uses adjacent pair capture. The RTL still carries compatibility structure for debug/non-pair behavior. Stage 2 is allowed to simplify production-only control and remove mux pressure only when the debug path remains guarded by `ECC_DEBUG_FIELD_OPS`.

Accepted only if:

- xsim profile remains correct,
- OOC area does not grow,
- Fmax remains above 200 MHz.

## Stage 3: pair-token folding shadow

Add a small shadow/oracle path that turns each adjacent diagonal pair into a modular folding token at capture time. This is not accepted as the final story by itself; it is only a correctness bridge.

The token must be small and template-driven:

- no wide independent 128-bit product accumulator,
- no second full modular reducer,
- no fully dynamic path/group/sub packet if a fixed pair template is enough.

Stage 3 shadow/oracle result:

- RTL adds a simulation-only `ecc_kpd64_diag_pair_reduce_packet` oracle under `synthesis translate_off`.
- On every adjacent pair capture, the oracle converts `{even_parity_row, odd_parity_row}` directly into a modular reduce packet and XOR-accumulates it per sub-product.
- At `group=6`, the accumulated pair-token packet is compared against the existing leaf/sub reference `ecc_kpd64_leaf_reduce_packet(mask, ecc_diag_sub_delta_w)`.
- Profile result: `HDEC_ECC_PMUL_PROFILE_V27 PASS`, no pair-token mismatch, PMUL cycles remain 189412.
- OOC result: 4914 LUT / 1489 FF / 4 BRAM / WNS 0.328 ns / Fmax 214.041 MHz, proving the oracle is not synthesized into production area.
- Profile log: `stage3_pair_token_shadow/xsim_pmul_profile/xsim_ecc_pmul_profile_v27/xsim.log`
- OOC output: `stage3_pair_token_shadow/ooc_200`

Meaning:

The VV20 route is mathematically viable: a diagonal pair can be folded into the modular contribution stream directly, and the XOR of four pair tokens equals the old leaf/sub folded packet. The remaining work is structural, not mathematical: replace the old production path instead of keeping both paths.

## Stage 4: replace old leaf/sub folding path

Only after the shadow proves equivalence, replace the old downstream fold with the pair-token fold path. This is the real VV20 goal.

Expected structural direction:

- keep VV19 adjacent pair capture,
- fold previous pair token while the next pair is captured,
- route the folded token through the existing XOR0 contribution path,
- delete or synthesize away the old leaf/sub product folding logic in production mode.

Stage 4 accepted result:

- Accepted implementation: delayed pair-token reducer reuse, `stage4_pair_token_pipeline_try2`.
- PMUL cycles: 189412, unchanged from VV19.
- Logic LUT: 4874, down from VV19's 4914.
- FF: 1450, down from VV19's 1489.
- BRAM: 4.
- WNS at 5.000 ns: 0.086 ns.
- Fmax: 203.500 MHz.

Rejected implementation:

- Same-cycle pair packet reducer, `stage4_pair_token_main_try1b/try1c`.
- It reached 188224 cycles and removed `ST_ECC_LEAF_FOLD`, but area was 5174 LUT before mux pruning and 5049 LUT after pruning. This was rejected because it crossed the area line.

## Stage 5: record accepted and rejected attempts

Every attempt must be classified:

- accepted: improves or preserves timing/cycles while reducing area or completing the story,
- rejected: grows area, breaks 200 MHz, breaks profile, or only adds parallel hardware without replacing old logic.

The final VV20 report must include the baseline, accepted deltas, rejected deltas, and a clear statement of whether true diagonal-pair-level fold-as-you-compute has been completed or only shadow-proven.
