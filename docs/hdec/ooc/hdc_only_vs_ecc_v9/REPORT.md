# V9 HDC-only vs HDC+ECC OOC comparison

Vivado: 2024.2  
Part: xc7z020clg400-2  
Clock: 5.000 ns, 200 MHz OOC  
Top: hdec_top  
Branch: hdec-v9-hdc-only-vs-ecc-ppa  
Tag target: 仅HDC对比HDC-ECC多项式乘法

## Purpose

This V9 point is not a rewritten HDEC. It starts from V8 RTL and removes the ECC hardware path so that the same HDC microarchitecture can be compared against V8 HDC+ECC.

Removed from the active design:

- ECC custom instruction entries from `hdec_pkg.sv`.
- ECC decode cases from `hdec_cvxif_wrapper.sv`.
- ECC states from `hdec_top.sv`.
- ECC KPD32/diagonal multiply registers, helper logic, product LUTRAM, and VRF writeback state.
- ECC source muxing into the shared P2 popcount slice.

Kept intentionally:

- V8 HDC pipeline, VRF, HPERM, HMATCH, lane popcount slice, and P4 scalar-response structure.
- VRF physical depth and HDC address layout. Some future-reserved constants/modules still exist in the source tree, but they are not instantiated by `hdec_top` and do not contribute to this OOC utilization.

## Main result

| Version | Fmax est MHz | WNS ns | Worst delay ns | LUT | Logic LUT | LUTRAM | FF | BRAM | DSP | CARRY4 | MUXF7 | ECC_MUL cycles |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| V9 HDC-only | 207.684 | 0.185 | 4.812 | 3687 | 3343 | 344 | 1863 | 0 | 0 | 16 | 257 | N/A |
| V8 HDC+ECC KPD32 | 202.470 | 0.061 | 4.936 | 5172 | 4572 | 600 | 2011 | 0 | 0 | 16 | 3 | 394 |
| ECC increment, V8 - V9 | -5.214 | -0.124 | +0.124 | +1485 | +1229 | +256 | +148 | 0 | 0 | 0 | -254 | +394 |

## Interpretation

Adding the V8 ECC polynomial multiplier costs about +1485 LUT and +148 FF relative to this HDC-only comparison point.

The cleanest part of the increment is the +256 LUTRAM from the ECC product word banks. The remaining +1229 logic LUT is mostly control, VRF port/write muxing, and popcount-source sharing pressure created by the ECC path.

Both versions pass 200 MHz. ECC reduces timing margin by 0.124 ns, from 0.185 ns to 0.061 ns. The critical path class is still the same P2 popcount partial-count path, so ECC does not create a new timing wall, but it makes the existing wall slightly tighter.

## Critical path

| Version | Simple path | Slack ns | Data ns | Logic ns | Route ns | Route ratio | Levels | Endpoint |
|---|---|---:|---:|---:|---:|---:|---:|---|
| V9 HDC-only | lane-local XOR result register to lane-local 32-bit popcount-part register | 0.185 | 4.812 | 1.105 | 3.707 | 0.770 | 5 | `gen_lane[0].i_p2_pop_slice/popcount_part_q_o_reg[0][4]/D` |
| V8 HDC+ECC | lane-local XOR result register to lane-local 32-bit popcount-part register | 0.061 | 4.936 | 1.105 | 3.831 | 0.776 | 5 | `gen_lane[0].i_p2_pop_slice/popcount_part_q_o_reg[0][5]/D` |

In simple words: after removing ECC, the longest HDC path is still the same "one lane's XOR result -> count ones" path, but the route delay is shorter by about 0.124 ns.

## Hierarchical area notes

| Area bucket | V9 HDC-only LUT | V8 HDC+ECC LUT | Delta | Notes |
|---|---:|---:|---:|---|
| Top/control/local memories | 303 logic + 0 LUTRAM | 598 logic + 256 LUTRAM | +551 | ECC FSM/control plus product LUTRAM |
| VRF hierarchy | 1262 logic + 344 LUTRAM | 1926 logic + 344 LUTRAM | +664 | ECC write/read control makes VRF muxing heavier |
| P2 popcount slices total | 1102 logic | 1469 logic | +367 | ECC shared popcount source muxing increases lane pop logic |
| Lane shift/counter/clip total | 676 logic | 579 logic | -97 | Vivado remapping difference, not an ECC feature gain |

The most important practical number is still the total: +1485 LUT and +148 FF for V8 ECC polynomial multiplication support.

## Raw reports

V9 HDC-only:

- `hdc_only_ooc_200/reports/run_summary.txt`
- `hdc_only_ooc_200/reports/timing_summary_top50.rpt`
- `hdc_only_ooc_200/reports/timing_top200.csv`
- `hdc_only_ooc_200/reports/timing_top1000.csv`
- `hdc_only_ooc_200/reports/utilization.rpt`
- `hdc_only_ooc_200/reports/utilization_hier.rpt`

V8 reference:

- `../ecc_kpd32_v8_structural_ppa/round11_single_result_reg/ooc_200/reports/run_summary.txt`
- `../ecc_kpd32_v8_structural_ppa/round11_single_result_reg/ooc_200/reports/utilization.rpt`
- `../ecc_kpd32_v8_structural_ppa/round11_single_result_reg/ooc_200/reports/utilization_hier.rpt`
- `../ecc_kpd32_v8_structural_ppa/REPORT.md`

## Conclusion

V9 gives a clean HDC-only comparison point for the V8 RTL family. Compared with V9, V8 ECC polynomial multiplication support is still within 200 MHz, but its current reuse implementation is not "almost free": it costs about +1.5k LUT and +148 FF.

For the paper/story, this is useful because we can now state the real incremental price of adding ECC to the optimized HDC datapath. For the next optimization round, the biggest ECC-specific reduction targets are:

1. Product storage: remove or shrink the +256 LUTRAM product banks if the final ECC flow can stream/fold more directly.
2. VRF control: reduce ECC-induced read/write muxing so it does not inflate the VRF hierarchy by ~664 logic LUT.
3. Popcount sharing mux: keep the reuse story, but avoid making every HDC popcount lane carry ECC source-selection cost.
