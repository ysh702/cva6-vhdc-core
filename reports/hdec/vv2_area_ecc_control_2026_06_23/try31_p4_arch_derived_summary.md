# VV2 try31 P4 response tag derivation

## Change

- Removed the 4-bit `p4_arch_op_q` shadow response tag.
- P4 response now derives HSIM/HMATCH directly from `uop_p3_q.op_type`.
- ECC MAC response is derived from `ecc_mac_q`, which is already the real live flag for the post-reduce shared HBIND accumulation path.

## OOC

Baseline try9:
- Total LUT: 5150
- Logic LUT: 5022
- LUTRAM: 128
- FF: 1839
- Fmax: 210.393 MHz
- PMUL: 190151 cycles

try31:
- Total LUT: 5146
- Logic LUT: 5018
- LUTRAM: 128
- FF: 1836
- Fmax: 210.393 MHz
- PMUL: 190151 cycles

Delta vs try9:
- Total LUT: -4
- Logic LUT: -4
- FF: -3
- PMUL cycles: unchanged

## Verification

- `xsim_hdec_ecc_reduce_v1`: PASS
- `xsim_hdec_ecc_add_v1`: PASS
- `xsim_hdec_ecc_align_v1`: PASS
- `xsim_hdec_hdc_full_flow_v20`: PASS
- `xsim_hdec_hmatch_compare_split`: PASS
- `xsim_hdec_hperm_bit_align`: PASS
- `xsim_hdec_ecc_pmul_profile_v27`: PASS, `PMUL_PROFILE_WALL_CYCLES=190151`
- `xsim_hdec_ecc_pmul_bg_idle_v27`: PASS, `PMUL_BG_IDLE_WALL_CYCLES=190152`
- `xsim_hdec_ecc_pmul_bg_v27`: PASS
- `xsim_hdec_ecc_pmul_bg_hdc_loop_v31`: PASS, `PMUL_BG_HDC_LOOP_WALL_CYCLES=191217`
- `xsim_hdec_hdc_selflearn_v1` UCI HAR: PASS, `2598/2947`, updates `349`
- `xsim_hdec_hdc_selflearn_v1` WISDM: PASS, `1078/1643`, updates `565`

## Rationale

This is a true control-layer cleanup, not a semantic change. The removed tag duplicated information already present at the P4 boundary, so the ISA, HDC AND-overlap/top-k self-learning algorithm, ECC field arithmetic, Montgomery LD scheduling, ITA inversion chain, PMUL cycle count, and shared lane execution story are unchanged.
