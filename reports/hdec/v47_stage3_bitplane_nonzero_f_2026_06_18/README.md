# V47 Stage3 Bit-Plane Nonzero Clip F

Date: 2026-06-18

Baseline: `07c465a0 hdec: add V47 stage1 diagonal XOR fold`

## Goal

Evaluate the bit-plane HDC counter idea as an isolated optimization. This run does not include margin-mask HDC inference or ECC AND reuse.

## RTL Change

- `hdec_cnt_array.sv`
  - Changes the 16 packed 4-bit counters in one 64-bit lane word into four 16-bit bit planes.
  - Counter bits are stored as:
    - `counter_i[15:0]`: bit 0 plane
    - `counter_i[31:16]`: bit 1 plane
    - `counter_i[47:32]`: bit 2 plane
    - `counter_i[63:48]`: bit 3 plane
  - Increment is implemented as vector carry propagation across the bit planes.
- `hdec_lane_clip.sv`
  - Replaces the general 4-bit threshold comparator with fixed nonzero clip:
    - `bits_o = p0 | p1 | p2 | p3`
  - The instruction operand threshold field is ignored in this low-area mode.

## Why This Saves Area

Plain bit-plane storage alone does not save area because Vivado maps the old packed 4-bit increment to nearly the same carry equations. The saving appears only when the HDC algorithm no longer needs an arbitrary threshold comparator.

Here the algorithm is restricted to threshold 1, meaning a dimension becomes 1 when its counter is nonzero. That removes the dynamic threshold compare and allows Vivado to remove the 4-bit `hcntclip_threshold_q` register.

## Functional Status

- HDC full flow: PASS
- ECC point multiplication profile: PASS
- PMUL wall cycles: 190617

## OOC 200 MHz Result

Path: `reports/hdec/v47_stage3_bitplane_nonzero_f_2026_06_18/ooc_bitplane_nonzero_f`

| Version | LUT | Logic LUT | LUTRAM | FF | BRAM | Fmax MHz | WNS ns | PMUL cycles |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| V47 Stage1-D baseline | 5710 | 5582 | 128 | 1723 | 4 | 210.393 | 0.247 | 190617 |
| Bit-plane nonzero F | 5638 | 5510 | 128 | 1719 | 4 | 210.393 | 0.247 | 190617 |
| Delta | -72 | -72 | 0 | -4 | 0 | 0.000 | 0.000 | 0 |

## Caveat

This is a real area win, but it is not a drop-in implementation of arbitrary `HCNTCLIP` thresholds. It is an algorithm-level change: HDC clip is fixed to threshold 1.
