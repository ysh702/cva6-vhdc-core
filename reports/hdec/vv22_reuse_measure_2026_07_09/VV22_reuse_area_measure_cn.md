# VV22 reuse and standalone-area measurement

## Baseline

- Branch: `VV22`
- RTL commit: `4eedb0e5 VV21 area reuse shell compact checkpoint`
- Top used for OOC: `hdec_top`
- Device/constraint: `xc7z020clg400-2`, 5 ns
- Measurement date: 2026-07-09

The accepted HDEC area baseline is measured at `hdec_top`, consistent with the previous VV21/VV22 OOC flow. If an outer CV-X-IF wrapper is included, the separate-HDC plus separate-ECC comparison would duplicate that shell, so the reuse advantage would not decrease.

## Functional and cycle checks

| Test | Result | Key numbers |
|---|---:|---|
| `xsim_hdec_hdc_full_flow_v20` | PASS | `[HDEC_HDC_FULL_FLOW_V20] PASS` |
| `xsim_hdec_ecc_pmul_profile_v27` | PASS | `PMUL_PROFILE_WALL_CYCLES=189412`, `PMUL_PROFILE_GF_MUL_STARTS=1188`, `PMUL_PROFILE_SUB_ZERO_CYCLES=0` |

## OOC area summary

| Configuration | Logic LUT | FF | BRAM | DSP | Fmax_est |
|---|---:|---:|---:|---:|---:|
| Full HDEC | 4734 | 1442 | 4 | 0 | 214.041 MHz |
| HDC-only probe | 2441 | 984 | 4 | 0 | 207.684 MHz |
| ECC-only probe | 3459 | 1219 | 4 | 0 | 226.296 MHz |
| Separate HDC + separate ECC | 5900 | 2203 | 8 | 0 | n/a |

The HDC-only probe keeps the HDC vector/payload/VRF path and disables ECC PMUL/status plus ECC reduce packet logic. The ECC-only probe keeps the CVA6-style command shell, VRF, 4x64 packet, bit-matrix row tile, XOR0 packet, and PMUL FSM, while disabling external HDC instructions. These probes are measurement worktrees only, not functional branch changes.

## Hierarchy split

| Configuration | Total LUT | Top-shell LUT | `i_vec` LUT | Row-tile LUT | VRF BRAM |
|---|---:|---:|---:|---:|---:|
| Full HDEC | 4734 | 1799 | 2935 | 768 | 4 |
| HDC-only probe | 2441 | 974 | 1467 | 256 | 4 |
| ECC-only probe | 3459 | 1196 | 2263 | 88 | 4 |

## Reuse-degree accounting

Strict ECC-exclusive area should not include the shared VRF, shared `i_vec`, shared bit-matrix row tile, or shared XOR0 packet path. Under that strict accounting:

- Strict ECC-exclusive top-shell/control area: `1799 - 974 = 825 Logic LUT`
- Strict ECC-exclusive share of HDEC: `825 / 4734 = 17.43%`

For completeness, the total incremental overhead of enabling ECC relative to the HDC-only probe is:

- Incremental HDEC-over-HDC overhead: `4734 - 2441 = 2293 Logic LUT`
- Incremental share of HDEC: `2293 / 4734 = 48.44%`

This larger incremental number is not strict ECC-exclusive area because it includes shared data-structure uplift in `i_vec` and the bit-matrix packet path.

Separate accelerator comparison:

- Separate HDC-only accelerator: `2441 Logic LUT`, `984 FF`, `4 BRAM`
- Separate ECC-only accelerator: `3459 Logic LUT`, `1219 FF`, `4 BRAM`
- Separate total: `5900 Logic LUT`, `2203 FF`, `8 BRAM`
- Full HDEC saved versus separate total: `5900 - 4734 = 1166 Logic LUT`
- Saved share versus separate total: `1166 / 5900 = 19.76%`

The dominant reuse benefit comes from not duplicating the CVA6-style top shell, VRF, payload packet path, row-tile interface, and packet accumulator infrastructure. The strict ECC-private part is therefore substantially smaller than the total ECC functionality that HDEC exposes.

