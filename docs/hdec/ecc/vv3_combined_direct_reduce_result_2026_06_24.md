# VV3 combined direct-reduce result

Date: 2026-06-24

Branch: `hdec-vv3-combined-direct-reduce`

## Conclusion

VV3 try79 is the current accepted result.

It implements the ECC multiplication direction requested for VV3:

- AND+XOR and AND+popcount-LSB both participate in ECC polynomial multiplication.
- Product accumulation is changed to direct/on-the-fly modular accumulation, so the old full product drain plus later reduce path is removed from the hot PMUL path.
- ECC square is also written as directly reduced GF(2^233) data.
- HDC VV1 self-learning semantics are unchanged: `score = popcount(query & prototype)`.

The main area recovery is architectural: ordinary HDC `HPERM` no longer keeps a full 4x64 parallel barrel-shift datapath. It is converted to a bit-serial fallback state. ECC square/spread and PMUL do not use this slow fallback, so ECC PMUL cycle count is unchanged by the HPERM serialization.

## Corrected target

The cycle target is not a relaxed estimate. It is derived from a Python ideal model for the combined design:

| Model | PMUL wall cycles |
|---|---:|
| VV2 baseline | 190151 |
| AND+XOR plus AND+popcount only | 158075 |
| Direct reduce only, idealized | 179459 |
| Combined direct square/reduce ideal | 135952 |
| Hard target, ideal plus 1% | 137311 |

VV3 try79 reaches the ideal combined target exactly: `135952 cycles`.

## Accepted result

| Metric | VV2 best baseline | VV3 try79 | Target | Status |
|---|---:|---:|---:|---|
| Total LUT | about 5127-5128 | 5137 | <= 5313 | PASS |
| Logic LUT | about 4999-5000 | 5137 | <= 5185 | PASS |
| LUTRAM | 128 | 0 | no growth | PASS |
| FF | 1833 | 1701 | <= 1835 | PASS |
| BRAM | 4 | 4 | no growth | PASS |
| DSP | 0 | 0 | no growth | PASS |
| Fmax estimate | >200 MHz | 214.041 MHz | >=200 MHz | PASS |
| PMUL wall cycles | 190151 | 135952 | <=137311 | PASS |

Compared with VV2, VV3 adds about 137 Logic LUT, but this is still inside the hard area target and is much smaller than the cycle gain. FF decreases by about 132, and LUTRAM drops to zero.

## Functional checks

| Test | Result |
|---|---|
| `xsim_hdec_ecc_pmul_profile_v27` | PASS, `PMUL_PROFILE_WALL_CYCLES=135952` |
| `xsim_hdec_ecc_reduce_v1` | PASS |
| `xsim_hdec_hdc_full_flow_v20` | PASS |
| `xsim_hdec_hperm_bit_align` | PASS |
| `xsim_hdec_hdc_selflearn_v1`, UCI HAR fixture | PASS, `2598/2947`, updates `349` |
| `xsim_hdec_hdc_selflearn_v1`, WISDM fixture | PASS, `1078/1643`, updates `565` |

## What changed in hardware

### ECC multiplication

VV2 stores/interprets a larger polynomial product and then spends a visible tail cost on product drain and reduction. VV3 changes the hot multiplication path into a reduced-field accumulation path:

1. Each local diagonal product still comes from `AND` terms.
2. Parity can come from the original XOR route and the popcount-LSB route.
3. The contribution is folded directly into the GF(2^233) reduced field location.
4. The separate PMUL hot-path reduce tail is eliminated.

This is the key algorithm/hardware co-design point: the mathematical operation is still binary-field multiplication modulo the same irreducible polynomial, but the RTL does not treat "full product first, reduce later" as the physical schedule.

### HDC HPERM

The previous ordinary HDC permutation path kept four 64-bit lane shift-align datapaths. That datapath was expensive and not on the ECC PMUL hot path.

VV3 try79 replaces ordinary `HPERM` with a bit-serial fallback:

- one bit per lane is generated each serial cycle;
- the 4x64 result is accumulated in `lane_result_q`;
- after 64 cycles, the normal writeback path writes the row.

This preserves HDC functionality and frees enough area to keep the new ECC algorithm inside the hard area target. Hot HDC self-learning (`HSIM/HMATCH` AND-overlap, `HBIND`, `HCNTADD`, `HCNTCLIP`) remains parallel.

## Rejected nearby trials

| Trial | Result | Reason rejected |
|---|---|---|
| try67 direct reduce loop | Logic LUT about 6100, Fmax about 188.7 MHz | variable bit-index reduce created huge mux logic |
| try68 no-reset product result | Logic LUT about 5282, Fmax about 194.7 MHz | area improved but timing failed |
| try74 direct reduce through `lane_result_q` | Logic LUT about 8029, Fmax about 155 MHz | shared accumulator became too large |
| try78b half-width HPERM | Logic LUT 5281, FF 1681, Fmax 195.274 MHz | saved some area but missed timing and hard LUT target |
| try79 bit-serial HPERM | Logic LUT 5137, FF 1701, Fmax 214.041 MHz | accepted |

## Paper-facing wording

The VV3 story should not be described as ordinary shift-and-accumulate multiplication. A more accurate phrase is:

> direct reduced bilinear accumulation for binary-field multiplication, co-scheduled over XOR parity and popcount-LSB parity lanes.

For HDC, VV3 keeps the VV1 self-learning algorithm:

> fixed-sparsity top-k prototypes with AND-overlap similarity, implemented as software-scheduled hardware primitives.

The combined HDEC story is:

> HDC and ECC share the lane substrate, but each keeps the physical form that matches its math: HDC uses overlap counting for similarity, while ECC uses bilinear GF(2) product accumulation with direct modular folding.

