# HDEC ECC VRF Control V2 OOC Report

## Scope

This snapshot preserves the V2 control update used as the base for later ECC work.
The goal was to remove the fragile path where growing HDC/ECC scheduling logic
directly drives the VRF LUTRAM ports.

Branch:

- `hdec-ecc-vrf-control-v2`

Base:

- `41b1e71a hdec: add ECC diagonal multiply v1`

Vivado setup:

- Vivado 2024.2
- Part: `xc7z020clg400-2`
- Top: `hdec_top`
- OOC period: `5.000 ns`
- Report directory used during the run:
  `tmp/hdec_ecc_vrf_control_v2_final_ooc_200`

## RTL Change

V2 adds a registered VRF command boundary in `hdec_top.sv`:

- `vrf_ra_q`
- `vrf_we_q`
- `vrf_wa_q`
- `vrf_wd_q`

The VRF now consumes the registered command instead of the wide main-FSM
combinational command. This creates a structural boundary for future ECC V3
scheduling so extra ECC control does not directly stretch the VRF LUTRAM port
path.

V2 also splits HSIM/HMATCH startup into init states:

- `S_HSIM_INIT`
- `S_HMATCH_INIT`

This keeps operand decode and validation out of the hot HMATCH/HSIM uop and CE
cones.

## Validation

Vivado xsim:

- Testbench: `tb_hdec_ecc_diag_mul_v1`
- Result: PASS
- Log archived as `xsim_ecc_diag_mul_v1.log`

Vivado OOC 200 MHz:

| Metric | Value |
|---|---:|
| Period | 5.000 ns |
| WNS | +0.069 ns |
| Worst data delay | 4.960 ns |
| Estimated Fmax | 202.799 MHz |
| Worst endpoint | `lane_result_q_reg[1][23]/D` |

Resource summary:

| Resource | Value |
|---|---:|
| Slice LUTs | 5476 |
| Logic LUTs | 4788 |
| LUTRAM | 688 |
| FF | 3275 |
| BRAM | 0 |
| DSP | 0 |
| CARRY4 | 16 |

## Timing Notes

The old VRF LUTRAM port timing path is no longer present in the top 200 setup
paths. The HMATCH CE paths are also no longer in the top 200 setup paths.

The new worst path is a state/control path into `lane_result_q`, with:

- Data delay: 4.960 ns
- Logic delay: 1.391 ns
- Route delay: 3.569 ns
- Route ratio: 71.956%

The P2 popcount-part paths start around rank 13:

- Data delay: 4.795 ns
- Slack: about +0.202 ns

## Rejected Trial

A lane-local write-enable rewrite for `lane_result_q` was tested but rejected.
It changed the worst path to `uop_p2_q[use_shift] -> lane_result_q`, produced
`WNS=-0.214 ns`, and increased LUT usage to 5579. That trial was not kept.

## Conclusion

V2 is a good base for ECC V3 because it makes the VRF interface timing less
sensitive to future scheduler complexity. The cost is mainly the registered VRF
command boundary, especially the 256-bit write-data command register. That cost
is acceptable because it protects the design from the exact timing pattern that
will otherwise become worse when full ECC scheduling is added.

The next recommended direction is to optimize and parallelize the ECC diagonal
GF(2) multiply kernel before implementing the full scalar point multiplication
controller.
