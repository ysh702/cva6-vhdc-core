# HDEC ECC KPD32 V5 HDC Alignment Report

## Scope

This snapshot preserves the V5 fix after the KPD32 popcount-Karatsuba ECC
multiplier was added in V4.

Branch:

- `hdec-ecc-kpd32-v5`

Base:

- `cc7cda24 hdec: add KPD32 popcount Karatsuba ECC multiplier`

Fix commit:

- `f02d842d hdec: align HDC popcount operand issue`

Vivado setup:

- Vivado 2022.2
- Part: `xc7z020clg400-2`
- Top: `hdec_top`
- OOC period: `5.000 ns`

## RTL Change

The failure was caused by issuing the HDC XOR/popcount operation one pipeline
stage too early after the VRF command path was registered. With the registered
VRF command and the registered VRF read output, `src1` is valid in
`S_UOP_P2_LANE`, while the previous issue logic still used the P1 uop timing.

V5 keeps the existing XOR + popcount slice structure and changes only the issue
alignment around it:

- Cache HDC `src0` into `hdc_src0_q` in `S_UOP_P1_RD1`.
- Issue HDC XOR/popcount in `S_UOP_P2_LANE`, when `vrf_rd` carries `src1`.
- Feed the popcount slice with `hdc_src0_q ^ vrf_rd` for HDC operations.
- Add `S_UOP_P3_POP_CAPTURE` so `group_dist_sum` is captured before HSIM/HMATCH
  accumulation and budget update.

The extra capture state avoids a direct
`popcount_part_q -> group_dist_sum -> hsim_total/hmatch_budget` critical path.

## Functional Validation

Vivado xsim passed the available dedicated HDEC testbenches:

| Testbench | Result |
|---|---|
| `tb_hdec_hmatch_compare_split` | PASS |
| `tb_hdec_ecc_diag_mul_v1` | PASS |

Key HMATCH results:

| Case | Result |
|---|---:|
| Single class max distance | `0x0000000000000400` |
| Second class exact match | `0x0000000000000800` |
| Tie keeps first class | `0x0000000000000000` |
| Illegal num_classes zero | `0x0000000000000002` |

Archived logs:

- `xsim_hmatch_compare_split.log`
- `xsim_ecc_diag_mul_v1.log`

## OOC Timing

Vivado OOC at 200 MHz passed:

| Metric | Value |
|---|---:|
| Period | 5.000 ns |
| WNS | +0.326 ns |
| Worst data delay | 4.700 ns |
| Estimated Fmax | 213.950 MHz |
| Worst endpoint | `group_dist_q_reg[8]/D` |

The worst path is again the normal HDC popcount aggregation path:

```text
gen_lane[0].i_p2_pop_slice/popcount_part_q_o_reg[0][0]/C
  -> group_dist_q_reg[8]/D
```

This confirms that the HDC alignment fix did not push the HSIM/HMATCH budget
update back onto the critical path.

## Resource Summary

| Resource | Value |
|---|---:|
| Slice LUTs | 6769 |
| Logic LUTs | 6081 |
| LUTRAM | 688 |
| FF | 4117 |
| BRAM | 0 |
| DSP | 0 |
| F7 Muxes | 64 |
| CARRY4 | 18 |

Hierarchy summary:

| Instance | Total LUTs | Logic LUTs | LUTRAM | FF |
|---|---:|---:|---:|---:|
| `hdec_top` | 6769 | 6081 | 688 | 4117 |
| top-local logic | 2422 | 2422 | 0 | 3280 |
| 4x `hdec_p2_pop_slice` | 1150 | 1150 | 0 | 568 |
| `hdec_vrf_64x256` | 3197 | 2509 | 688 | 269 |

Archived OOC reports:

- `run_summary.txt`
- `timing_top200.csv`
- `utilization.rpt`
- `utilization_hier.rpt`
