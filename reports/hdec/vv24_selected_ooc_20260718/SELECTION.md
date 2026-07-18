# VV24 selected checkpoint: native XOR1 independent diagonals

## Status

VV24 is accepted against the approved hard gates but remains uncommitted and
unpushed.  The stretch target of 4734 Logic LUT was not reached.

## Selected structure

- One shared `16x16` AND matrix and the existing three-leaf Karatsuba schedule.
- The 256 registered partial products are generated once.
- POPCOUNT independently owns 24 complete diagonals (162 partial products).
- Native XOR1 independently owns 7 complete diagonals (94 partial products).
- The seven XOR1 diagonals are the mirrored lengths 12, 13 and 14 plus the
  length-16 center diagonal; balanced trees use 87 existing two-input nodes.
- All 32 existing eight-bit POPCOUNT slots remain active; eight long-diagonal
  results join two byte counts and use the final count LSB.
- XOR1 mode selection is outside `hdec_xor1_native_224`; every native node body
  is exactly `lhs ^ rhs`.
- No dedicated ECC `AND+XOR`, second reduction tree, total-parity recovery or
  cross-unit diagonal solve remains.

## PPA and cycles

| Metric | VV24 selected | Approved gate |
|---|---:|---:|
| Logic LUT | 4822 | <=4840 hard; <=4734 target |
| FF | 1370 | <=1442 hard; <=1375 target |
| Fmax | 204.040 MHz | >=200 MHz |
| BRAM | 4 | 4 |
| DSP | 0 | 0 |
| PMUL wall cycles | 188224 | <=189412 |

PPA is the wrapper-free `hdec_top` OOC result for `xc7z020clg400-2` at a
5.000 ns constraint.

## Probe record

| Probe | Logic LUT / Fmax | Decision |
|---|---:|---|
| A, 19+12 linear XOR chain | 4868 / 180.963 MHz | Reject |
| A, 19+12 balanced XOR tree | 4868 / 214.041 MHz | Reject: LUT hard cap |
| B, post-AND fixed gather | 4964 / 184.740 MHz | Reject |
| C, 21+10 low-join split | 4864 / 214.041 MHz | Reject: LUT hard cap |
| D, 24+7 native tree | 4821 / 198.728 MHz | Reject: timing |
| D, balanced byte POPCOUNT | 4829 / 200.803 MHz | Pass |
| D, dead-probe cleanup | **4822 / 204.040 MHz** | **Selected** |

## Verification

- Python: 256-term unique ownership, 8-bit exhaustive, 100000 random 32-bit
  carry-less products.
- Native XOR1: 2048 VV22 legacy cycles and 2048 diagonal cycles.
- ECC: diagonal multiply, 4096 diagonal-reduce-map vectors, modular reduction,
  align, add, inversion and full PMUL.
- HDC: full flow, self-learning, HMATCH, HPERM, bit alignment and concurrent
  PMUL-background HDC loop.
- CVXIF/VRF: wrapper smoke transaction and all `hdec_top` tests passed.  The
  wrapper and VRF RTL hashes are unchanged from VV23.
- Structure: one synthesized shared row tile; one RTL matrix-AND generator;
  32 POPCOUNT slots; one native XOR1; no forbidden private-path names.

## Evidence directories

- OOC: `reports/hdec/vv24_selected_ooc_20260718/`
- Regression: `reports/hdec/vv24_selected_regression_20260718/`
- Structure/netlist: `reports/hdec/vv24_selected_structure_20260718/`

## Selected source hashes

| File | Git object hash |
|---|---|
| `core/hdec/rtl/hdec_lane_4x64.sv` | `a30dc0d99448f08110c65ed8a5b417752e92e0f8` |
| `scripts/hdec/vv24_native_xor1_model.py` | `8438e38b3c1d5b861c16f4150cdff83fae5e2fe1` |
| `scripts/hdec/vv24_reuse_structure_check.py` | `73be55bab61bf063a2da15cfc26c7128bde70637` |
| `verif/hdec/tb_hdec_vv24_native_xor1.sv` | `2d230f5ec40f2966a56cab151aa95ea9b499480b` |
| `verif/hdec/tb_hdec_cvxif_smoke_vv24.sv` | `8e6ee92c211c172e94db3a72265bf722663e405e` |

VV24 branch base: `f91deb10` (`VV23` checkpoint).  There is no `origin/VV24`.
