# VV35 no-board functional regression

- Consolidated result: **PASS**
- Unique tests after infrastructure repair: **19**
- Seed: `1f8b456739a723782c9cd16c72b7fcdaabd20658252e1eddaefd0a05ce934075`
- Commit: `ba053f51f26c2be318626ab27a3d830cc5d32a44`
- RTL unchanged: **True**
- Primary full runtime: **2354.9 s**
- Total active runtime including repair and direct supplements: **2414.4 s**

## Random-K PMUL cycle contract

The direct PMUL contract and the background-pipeline contract each completed 16 identical legal random K values. All observed cycle counts were [146908] cycles. Consistency result: **True**.

## Tests

| Test | Result | Suite | Runtime (s) |
|---|---:|---|---:|
| baseline_gap | PASS | full | 59.803 |
| diag_native_map | PASS | full | 15.068 |
| ecc_add_direct | PASS | ecc_direct | 13.707 |
| ecc_inv_direct | PASS | ecc_direct | 13.187 |
| ecc_reduce_direct | PASS | ecc_direct | 13.853 |
| ecc_schedule_trace | PASS | full | 61.902 |
| ecc_state_profile | PASS | full | 62.513 |
| fused_map_unit | PASS | full | 14.538 |
| gfmac_tail_fusion | PASS | full | 403.258 |
| hdc_episode | PASS | full | 17.354 |
| hdc_full_flow | PASS | hdc_direct | 13.447 |
| hperm_contract | PASS | full | 11.748 |
| inv_redirect_contract | PASS | full | 17.989 |
| mode_switch | PASS | full | 60.922 |
| pmul_pipeline_contract | PASS | full | 803.565 |
| pmul_random_k | PASS | full | 772.225 |
| shift_align_basis | PASS | full | 11.336 |
| square_basis | PASS | full | 14.291 |
| vrf_roundtrip | PASS | full | 18.200 |

## Preserved infrastructure failure

The primary full run preserved one failed `hdc_full_flow` launch. Its legacy Tcl used strict Vivado 2024.2 elaboration, which rejected a testbench timescale mixed with synthesizable modules using the simulator default. The test never entered simulation. The repair runner added only `xelab --relax`, kept RTL unchanged, and the exact HDC full-flow contract then passed. This is classified as `TEST_INFRASTRUCTURE_XELAB_TIMESCALE_STRICTNESS`, not an RTL failure.

The ECC direct add, reduction, and inversion contracts were run separately with the identical seed and RTL hash, and are included in the consolidated result.
