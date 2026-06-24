# VV4 HDCU-style HPERM64 result

Date: 2026-06-24

Branch: `hdec-vv4-hdcu-hperm64`

Base commit: VV3 `d4e5f21a`

## Conclusion

VV4 try2 is the accepted result.

It replaces the VV3 bit-serial ordinary HDC `HPERM` fallback with a low-area HDCU-style SIMD-64 chunk-buffer implementation.

The important result is unexpected but useful: the new HPERM is both faster than VV3 try79 bit-serial HPERM and smaller in LUT after Vivado synthesis.

## Design

VV3 try79 generated one bit per lane per HPERM cycle. This saved the old parallel shift-align datapath, but dynamic bit writes into `lane_result_q[lane][bit]` created a non-trivial mux network.

VV4 uses a 64-bit chunk-buffer schedule:

1. Keep the existing outer four-row HPERM uop schedule.
2. For each 256-bit row, process one 64-bit lane at a time.
3. For each lane, build a 128-bit `{next_word, cur_word}` window.
4. Stage 1 selects a 72-bit byte window according to `shift[5:3]`.
5. Stage 2 selects the final 64-bit result according to `shift[2:0]`.
6. Write one complete lane result per second cycle.

This means one 256-bit row takes 8 HPERM compute cycles instead of 64 cycles in VV3 try79. It uses one 64-bit lane shifter instead of four full parallel lane shifters.

## Area and timing

| Version | Total LUT | Logic LUT | LUTRAM | FF | Fmax MHz | PMUL cycles | Status |
|---|---:|---:|---:|---:|---:|---:|---|
| VV2 baseline | 5127 | 4999 | 128 | 1833 | 210.393 | 190151 | reference |
| VV3 algorithm body, no HPERM recovery | 5327 | 5327 | 0 | 1687 | 210.393 | 135952 | reference |
| VV3 try79 bit-serial HPERM | 5137 | 5137 | 0 | 1701 | 214.041 | 135952 | previous best |
| VV4 try1 one-cycle 64-bit lane shift | 5154 | 5154 | 0 | 1694 | 171.116 | 135952 | rejected, timing fail |
| VV4 try2 two-stage HPERM64 | 4722 | 4722 | 0 | 1747 | 207.684 | 135952 | accepted |

## Deltas

Compared with "VV3 algorithm body, no HPERM recovery":

- Total LUT: `4722 - 5327 = -605`
- Logic LUT: `4722 - 5327 = -605`
- FF: `1747 - 1687 = +60`
- PMUL cycles: unchanged, `135952`

Compared with final VV3 try79:

- Total LUT: `4722 - 5137 = -415`
- Logic LUT: `4722 - 5137 = -415`
- FF: `1747 - 1701 = +46`
- Fmax: `207.684 MHz`, still above 200 MHz
- PMUL cycles: unchanged, `135952`

Compared with VV2 baseline:

- Total LUT: `4722 - 5127 = -405`
- Logic LUT: `4722 - 4999 = -277`
- LUTRAM: `0 - 128 = -128`
- FF: `1747 - 1833 = -86`
- PMUL cycles: `135952` vs `190151`

## Functional checks

| Test | Result |
|---|---|
| `xsim_hdec_hperm_bit_align` | PASS |
| `xsim_hdec_hdc_full_flow_v20` | PASS |
| `xsim_hdec_ecc_reduce_v1` | PASS |
| `xsim_hdec_ecc_pmul_profile_v27` | PASS, `PMUL_PROFILE_WALL_CYCLES=135952` |

## Why it reduced LUT

The first one-cycle SIMD-64 attempt had low area but failed timing because the full 64-bit variable shift fed `lane_result_q` directly.

The accepted two-stage design splits the shift:

- byte-granularity 72-bit window select in stage 1;
- bit-granularity 0..7 select in stage 2.

This removes the long 64-bit barrel-shift path. It also avoids the VV3 bit-serial dynamic bit write mux, which is why LUT count drops below try79 even though the HPERM throughput improves.

## Paper wording

VV4 can be described as:

> an HDCU-inspired SIMD-64 chunk-buffer permutation unit that replaces bit-serial fallback with byte/bit staged lane rotation.

This is not ECC arithmetic reuse. It is an HDC-side architecture recovery that preserves the VV3 ECC direct-reduced dual-route multiplication while restoring practical HPERM throughput and lowering total LUT.

