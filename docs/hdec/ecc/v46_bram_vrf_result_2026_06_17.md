# V46 BRAM VRF result

Date: 2026-06-17

Branch intent:

- `hdec-ecc-pointmul-v45` keeps the pre-BRAM LUTRAM baseline at commit `e7649cd9`.
- `hdec-ecc-pointmul-v46` moves the VRF toward a BRAM-native implementation and keeps the supporting reports in the branch.

## RTL change

The selected V46 implementation changes the 4-bank 64 x 256 VRF from distributed RAM to block RAM:

- `core/hdec/rtl/hdec_vrf_64x256.sv`
  - `ram_style` is changed to `block`.
  - VRF read data becomes a 2-cycle path: BRAM output is captured first, then exported to the top level.
- `core/hdec/rtl/hdec_top.sv`
  - Explicit VRF read users are adjusted for the extra cycle.
  - ECC load, reduce, scalar-read, inverse-copy, generic read, and selected HDC uop reads get a second wait state.
  - Several ECC paths issue the next VRF read address early, so part of the BRAM latency is hidden instead of paid as pure idle time.
  - VRF write enable is decoded directly from the architectural state. This removes the wide `vrf_req.we` control fan-in from the critical write-enable path and fixed the BRAM WEBWE timing failure seen in earlier BRAM attempts.

The key hardware idea is that BRAM should not be used as a slower LUTRAM drop-in. Its fixed registered read behavior is accepted, then the surrounding state machine is moved to prefetch the next row wherever the ECC/HDC schedule already knows the next address.

## Selected OOC data

Selected report directory:

`reports/hdec/v45_bram_vrf_2cycle_overlap_wedecode_2026_06_17`

| Version | VRF style | WNS ns | Fmax MHz | Total LUT | Logic LUT | LUTRAM | FF | BRAM36 | ECC PMUL cycles |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| V45 current recheck | LUTRAM | 0.247 | 210.393 | 6037 | 5565 | 472 | 1968 | 0 | 183793 |
| V46 selected | BRAM | 0.247 | 210.393 | 5796 | 5668 | 128 | 1714 | 4 | 190617 |
| Delta | BRAM - LUTRAM | 0.000 | 0.000 | -241 | +103 | -344 | -254 | +4 | +6824 |

V46 keeps the 200 MHz timing target while trading 4 BRAM36 for lower LUTRAM and FF usage. The total LUT count is lower than the V45 LUTRAM baseline, even though some logic LUT rises because the control has to adapt to BRAM read latency.

## Hierarchy snapshot

From `utilization_hier.rpt`:

| Block | Total LUT | Logic LUT | LUTRAM | FF | BRAM36 | Comment |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `hdec_top` total | 5796 | 5668 | 128 | 1714 | 4 | Full OOC design |
| top-level logic bucket | 1806 | 1678 | 128 | 1409 | 0 | Control, state, product storage, shared orchestration |
| four lanes total | 767 | 767 | 0 | 305 | 0 | Shared HDC/ECC lane operators |
| `i_vrf` | 3223 | 3223 | 0 | 0 | 4 | BRAM VRF wrapper and memory inference |

The `i_vrf` logic LUT number is Vivado's synthesized wrapper/control cost around inferred BRAMs; the actual storage moved to 4 RAMB36 blocks.

## Simulation evidence

All selected V46 checks passed:

- HDC full flow: `reports/hdec/v45_bram_vrf_2cycle_overlap_wedecode_2026_06_17/xsim_hdc_full_flow_v20/xsim_hdc_full_flow_v20/xsim.log`
  - `[HDEC_HDC_FULL_FLOW_V20] PASS`
- ECC reduction: `reports/hdec/v45_bram_vrf_2cycle_overlap_wedecode_2026_06_17/xsim_ecc_reduce_v1/xsim_ecc_reduce_v1/xsim.log`
  - `[HDEC_ECC_REDUCE_V1] PASS`
- ECC point multiplication profile: `reports/hdec/v45_bram_vrf_2cycle_overlap_wedecode_2026_06_17/xsim_ecc_pmul_profile_v27/xsim_ecc_pmul_profile_v27/xsim.log`
  - `[HDEC_ECC_PMUL_PROFILE_V27] PASS`
  - `PMUL_PROFILE_WALL_CYCLES=190617`
  - `PMUL_PROFILE_PHASE_PMUL_FIELD_CYCLES=172085`
  - `PMUL_PROFILE_PHASE_PMUL_ADD_CYCLES=5656`
  - `PMUL_PROFILE_PHASE_INV_SQR_CYCLES=2563`
  - `PMUL_PROFILE_PHASE_INV_MUL_CYCLES=1340`
  - `PMUL_PROFILE_PHASE_PMUL_COPY_CYCLES=705`

## Rejected BRAM attempts

These routes were measured but not selected:

| Attempt | Result | Reason rejected |
| --- | --- | --- |
| naive BRAM VRF | Total LUT 5871, WNS -0.837 ns, Fmax about 171 MHz | Timing failed because LUTRAM-style scheduling was kept around a BRAM read path |
| 2-cycle leaf prefetch | Total LUT 5936, WNS 0.088 ns, PMUL 195333 cycles | Timing passed, but area and cycle cost were both worse than selected V46 |
| 2-cycle overlap before write-enable decode | Total LUT 5922, WNS -0.003 ns, PMUL 190617 cycles | Nearly worked, but BRAM write-enable path still failed 200 MHz |
| 6-bit state encoding attempt | Total LUT 6971 | State encoding change enlarged control badly |
| src1 top-cache attempt | Total LUT 6813, WNS -0.127 ns | Extra capture/control structure made both area and timing worse |

## Takeaway

The useful V46 lesson is not simply "VRF to BRAM". The area win appears only after the architecture is made BRAM-aware:

1. Accept the 2-cycle read behavior.
2. Hide read latency with early row issue on deterministic ECC/HDC paths.
3. Decode write enables directly from compact state meaning instead of carrying a wide generic write-enable request through the main control bundle.

This branch is therefore the BRAM-native checkpoint, and V47 should use it as the base for ECC-exclusive area attribution.
