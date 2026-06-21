# V161 Clip Threshold Prune Result

## Change

Current HDC counter clip is the low-area non-zero predicate:

```text
4-bit counter != 0 -> 1
4-bit counter == 0 -> 0
```

The ISA operand still carries a threshold field for compatibility, but this RTL
mode has already fixed the effective threshold to 1. This change removes the
unused `hcntclip_threshold_q/n` state and the unused `clip_threshold_i` ports in
`hdec_lane_4x64` and `hdec_lane_clip`.

## Verification

Vivado xsim:

| Test | Result |
| --- | --- |
| `xsim_hdec_hdc_full_flow_v20` | PASS |
| `xsim_hdec_ecc_reduce_v1` | PASS |
| `xsim_hdec_ecc_pmul_profile_v27` | PASS, `PMUL_PROFILE_WALL_CYCLES=190151` |

OOC synthesis, Vivado 2024.2, `xc7z020clg400-2`, 5 ns:

| Metric | V161 |
| --- | ---: |
| Slice LUT / Total LUT | 5195 |
| Logic LUT | 5067 |
| LUTRAM | 128 |
| FF | 1877 |
| WNS | 0.247 ns |
| Fmax estimate | 210.393 MHz |

## Decision

Keep as a no-regression semantic cleanup. Final mapped area is unchanged, but
the RTL no longer stores or routes a field that the current clip algorithm does
not use. Synthesis warnings drop from 119 to 115.
