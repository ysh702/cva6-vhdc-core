# VV22 CV-X-IF standalone HDC/ECC reuse recalculation

## 口径

本轮重新按用户要求计算：

- HDEC 使用完整 CV-X-IF-style wrapper。
- 分立 HDC accelerator 和分立 ECC accelerator 也各自使用同一类 CV-X-IF-style wrapper。
- 主线 RTL 不改动；HDC-only/ECC-only 是临时 measurement worktree probe。
- HDC 用到的共享结构不计入严格 ECC-exclusive 面积。

## Final recorded numbers for VV22

These are the final numbers to cite with the current VV22 RTL checkpoint:

- Current RTL checkpoint: `4eedb0e5 VV21 area reuse shell compact checkpoint`
- Full HDEC + CV-X-IF wrapper: `4836 Logic LUT / 1610 FF / 4 BRAM / 0 DSP`
- Standalone HDC + standalone ECC with duplicated CV-X-IF wrappers: `5940 Logic LUT / 2535 FF / 8 BRAM / 0 DSP`
- HDEC saving vs standalone total: `1104 Logic LUT`, `925 FF`, `4 BRAM`
- Strict ECC-only area in HDEC: about `608 Logic LUT equivalent`
- Strict ECC-only FF in HDEC: `413 FF`
- Strict ECC-only share of HDEC: about `12.57% Logic LUT equivalent`, `25.65% FF`

measurement-only concrete top:

- `reports/hdec/vv22_reuse_measure_2026_07_09/cvxif_measure_src/hdec_cvxif_measure_top.sv`
- `reports/hdec/vv22_reuse_measure_2026_07_09/cvxif_measure_src/ooc_hdec_cvxif_measure.tcl`

## Wrapper-level OOC area

| Configuration | Logic LUT | FF | BRAM | DSP | Fmax_est |
|---|---:|---:|---:|---:|---:|
| Full HDEC + CV-X-IF wrapper | 4836 | 1610 | 4 | 0 | 214.041 MHz |
| Standalone HDC + CV-X-IF wrapper | 2458 | 1150 | 4 | 0 | 207.684 MHz |
| Standalone ECC + CV-X-IF wrapper | 3482 | 1385 | 4 | 0 | 228.102 MHz |
| Standalone HDC + standalone ECC | 5940 | 2535 | 8 | 0 | n/a |

Reuse saving under this fairer standalone interface口径:

- Logic LUT saved: `5940 - 4836 = 1104`
- LUT saving vs standalone total: `1104 / 5940 = 18.59%`
- FF saved: `2535 - 1610 = 925`
- BRAM saved: `8 - 4 = 4`, i.e. HDEC keeps one shared VRF rather than two independent VRFs.

## Hierarchy split

| Configuration | Total LUT | Wrapper local LUT | `i_hdec_top` LUT | `i_hdec_top` local LUT | `i_vec` LUT | row-tile LUT | VRF BRAM |
|---|---:|---:|---:|---:|---:|---:|---:|
| Full HDEC + wrapper | 4836 | 16 | 4820 | 2083 | 2737 | 448 | 4 |
| Standalone HDC + wrapper | 2458 | 14 | 2444 | 1001 | 1443 | 256 | 4 |
| Standalone ECC + wrapper | 3482 | 15 | 3467 | 1379 | 2088 | 88 | 4 |

## ECC area accounting

Do not use `Full HDEC - HDC-only` as ECC-exclusive area. That number is:

- Incremental upper bound: `4836 - 2458 = 2378 Logic LUT`
- Share of HDEC: `2378 / 4836 = 49.17%`

This is too broad because it includes shared data-structure uplift, shared scheduler glue, packet routing, and matrix integration.

A stricter hierarchy-level top-shell delta is:

- Top/control delta: `(16 - 14) + (2083 - 1001) = 1084 Logic LUT`
- Share of HDEC: `1084 / 4836 = 22.42%`

This is still conservative because the delta includes shared integration logic, not only ECC-private control.

The name-bucket probe gives a strict lower-bound style view. It is cell-name based and counts LUT cells before physical LUT packing, so it should be treated as attribution evidence rather than the final utilization table.

| Bucket | LUT cells | FF cells | MUXF cells | Interpretation |
|---|---:|---:|---:|---|
| `ecc_private_pmul_job_control` | 152 | 53 | 33 | PMUL/job controller certainly ECC-private |
| `ecc_private_field_control` | 120 | 26 | 1 | field-op control certainly ECC-private |
| `ecc_matrix_integration` | 388 | 334 | 0 | ECC matrix/folding integration; better reported separately, not HDC-owned |

Internal control-only audit, not the final paper-facing ECC-only area:

- Raw named LUT cells: `152 + 120 = 272`
- Normalized Logic-LUT equivalent: about `251`
- Share of full HDEC wrapper area: about `251 / 4836 = 5.19%`

Final ECC-only area used for reporting, including ECC matrix/folding integration because HDC does not use this logic:

- Raw named LUT cells: `272 + 388 = 660`
- Normalized Logic-LUT equivalent: about `608`
- FF: `53 + 26 + 334 = 413`
- Share of full HDEC wrapper area: about `608 / 4836 = 12.57%`

Recommended paper wording:

- Use `4836 Logic LUT / 4 BRAM` for HDEC with CV-X-IF wrapper.
- Use `5940 Logic LUT / 8 BRAM` for separate HDC+ECC accelerators with duplicated CV-X-IF wrappers.
- Report strict ECC-only area in HDEC as about `608 Logic LUT equivalent / 413 FF`, i.e. `12.57% / 25.65%` of the full HDEC wrapper area.
- State that this ECC-only area includes ECC matrix/folding integration, but excludes VRF, `i_vec`, row tile, XOR0/shared packet path, CV-X-IF wrapper, and HDC-used control/data structures.
- Avoid calling the broad `2378 LUT` delta ECC-exclusive; call it only the ECC-enabled incremental upper bound.
