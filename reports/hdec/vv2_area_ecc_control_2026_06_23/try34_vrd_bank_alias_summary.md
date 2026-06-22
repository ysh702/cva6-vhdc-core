# VV2 try34 VRD bank alias

## Change

- Removed the 2-bit `bk_q/bk_n` VRD bank shadow register.
- `S_RD_CAPTURE` now selects the read bank directly from `vaddr_bank_q`.
- This is safe because the HDEC unit is not ready during VRD, so a new VADDR cannot be accepted while the VRD transaction is in flight.

## OOC

Baseline try31:
- Total LUT: 5146
- Logic LUT: 5018
- LUTRAM: 128
- FF: 1836
- Fmax: 210.393 MHz
- PMUL: 190151 cycles

try34:
- Total LUT: 5128
- Logic LUT: 5000
- LUTRAM: 128
- FF: 1834
- Fmax: 210.393 MHz
- PMUL: 190151 cycles

Delta vs try31:
- Total LUT: -18
- Logic LUT: -18
- FF: -2
- PMUL cycles: unchanged

Delta vs VV1:
- Total LUT: -67
- Logic LUT: -67
- FF: -43
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

This is a shared control-layer reduction. It does not change the HDC AND-overlap/top-k self-learning algorithm, ECC GF(2^233) arithmetic, Montgomery LD/ITA schedule, PMUL cycle count, ISA, or VRF-visible layout.
