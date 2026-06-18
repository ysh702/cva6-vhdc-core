# V47 Stage3 Combo All A

Date: 2026-06-18

Branch: `hdec-ecc-pointmul-v47-combo-isolated`

This experiment combines three V47 Stage3 algorithm-to-hardware optimizations:

1. HDC counter no-saturation.
2. ECC diagonal AND-term enumeration.
3. Bit-plane counter storage with fixed nonzero clip.

## Theory

The three optimizations are not completely the same target.

`bit-plane + fixed nonzero clip` changes the HDC counter representation and removes the dynamic clip compare.

`counter no-saturation` removes the counter overflow protection. In packed-counter form it removed a nibble full-detect path. After bit-plane storage, the remaining overlapping logic is the bit-plane `max_mask` full-detect path, so the gain is expected to be smaller than the isolated packed-counter gain.

`ECC diagonal AND-term enumeration` rewrites the ECC diagonal product parity expression. It is mostly independent from the HDC counter and clip logic, so its gain should mostly add to the HDC gains.

Simple additive ideal from V47 Stage1-D:

| Optimization | Isolated delta vs Stage1-D |
| --- | ---: |
| Bit-plane + fixed nonzero clip | -72 LUT, -4 FF |
| Counter no-saturation | -32 LUT, 0 FF |
| ECC diagonal AND-term enumeration | -10 LUT, 0 FF |
| Ideal full sum | -114 LUT, -4 FF |

V47 Stage1-D baseline was `5710 LUT`, `5582 Logic LUT`, `1723 FF`.

Ideal full-sum target would therefore be `5596 LUT`, `5468 Logic LUT`, `1719 FF`.

## RTL Changes

Counter no-saturation in bit-plane form:

- removed `max_mask = p0 & p1 & p2 & p3`
- changed `carry0 = hv_slice & ~max_mask` to `carry0 = hv_slice`

ECC diagonal product:

- replaced aligned-vector AND + reduction with explicit diagonal term enumeration:
  `parity ^= a_word[i] & b_word[diag_idx - i]`

## Functional Checks

| Test | Result |
| --- | --- |
| `xsim_hdec_hdc_full_flow_v20.tcl` | PASS |
| `xsim_hdec_ecc_diag_mul_v1.tcl` | PASS |
| `xsim_hdec_ecc_reduce_v1.tcl` | PASS |
| `xsim_hdec_ecc_pmul_profile_v27.tcl` | PASS |

ECC point multiplication cycles:

- `PMUL_PROFILE_WALL_CYCLES=190617`
- `PMUL_PROFILE_SAMPLED_CYCLES=190617`

## OOC 200 MHz Result

Command:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\hdec\run_ooc_200.ps1 -Repo (Get-Location).Path -OutDir reports\hdec\v47_stage3_combo_all_a_2026_06_18\ooc_combo_all_a -Label v47_stage3_combo_all_a
```

Result:

| Design | LUT | Logic LUT | LUTRAM | FF | BRAM | DSP | CARRY4 | Fmax MHz | WNS |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| V47 Stage1-D baseline | 5710 | 5582 | 128 | 1723 | 4 | 0 | 13 | 210.393 | 0.247 |
| Ideal additive target | 5596 | 5468 | 128 | 1719 | 4 | 0 | 13 | 210.393 | 0.247 |
| Combo all A measured | 5604 | 5476 | 128 | 1719 | 4 | 0 | 13 | 210.393 | 0.247 |

Delta vs Stage1-D:

- LUT: `-106`
- Logic LUT: `-106`
- FF: `-4`
- Cycle count: unchanged
- Timing: unchanged, still above 200 MHz

Delta vs ideal additive target:

- LUT: `+8`
- Logic LUT: `+8`
- FF: exact match

## Conclusion

The three optimizations can be combined.

The measured result is close to the additive theory, but not exactly equal. The missing 8 LUT are consistent with overlap between bit-plane counter conversion and no-saturation: both touch the same HDC counter update cone, so Vivado cannot preserve the full isolated packed-counter no-saturation delta after the counter has already been rewritten into bit planes.

The ECC diagonal AND-term enumeration is not the source of the gap. It is largely independent from the HDC counter and remains a valid small area win.
