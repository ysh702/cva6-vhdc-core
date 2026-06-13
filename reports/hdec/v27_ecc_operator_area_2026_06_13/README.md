# V27 ECC operator-area attribution on HDC-only baseline

Date: 2026-06-13
Branch: `hdec-ecc-pointmul-v27`
Tool: Vivado 2024.2
Part: `xc7z020clg400-2`
Top: `hdec_top`
Constraint: 5.000 ns OOC synthesis

## Source artifacts

Formal HDC-only baseline:

- `tmp/hdec_v24_hdc_only_strict_ooc_200/reports/utilization.rpt`
- `tmp/hdec_v24_hdc_only_strict_ooc_200/reports/utilization_hier.rpt`

Formal HDC+ECC baseline:

- `reports/hdec/v23_optimization/ooc_final_round07_200mhz/utilization.rpt`
- `reports/hdec/v23_optimization/ooc_final_round07_200mhz/utilization_hier.rpt`

Clocked cell-name bucket export, generated for this note:

- `reports/hdec/v27_ecc_operator_area_2026_06_13/cell_bucket_clocked.tcl`
- `reports/hdec/v27_ecc_operator_area_2026_06_13/clocked_full/reports/utilization.rpt`
- `reports/hdec/v27_ecc_operator_area_2026_06_13/clocked_full/reports/utilization_hier.rpt`
- `reports/hdec/v27_ecc_operator_area_2026_06_13/clocked_full/reports/bucket_summary.csv`
- `reports/hdec/v27_ecc_operator_area_2026_06_13/clocked_full/reports/leaf_cells.csv`

The clocked bucket run reproduces the formal full-design utilization:

| Design | Slice LUT | Logic LUT | LUTRAM | FF | BRAM | DSP | CARRY4 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| HDC-only strict | 4090 | 3746 | 344 | 1846 | 0 | 0 | 16 |
| HDC+ECC | 6258 | 5786 | 472 | 2113 | 0 | 0 | 20 |
| Delta | +2168 | +2040 | +128 | +267 | 0 | 0 | +4 |

## Exact hierarchy delta

This table is the most defensible post-synthesis area split. Do not add child rows to parent rows; nested `i_shift_align` rows are shown by Vivado under each lane and are already included in the lane row.

| Bucket | Exact delta | ECC-dedicated? | Interpretation |
| --- | ---: | --- | --- |
| `i_vrf` hierarchy | +1309 Logic LUT, +0 FF | No, access/shared-storage tax | The largest cost. ECC adds many read/write address, write-enable, and write-data choices into the shared VRF interface. This is not a standalone ECC arithmetic unit. |
| Lane compute/shift-align hierarchy | +120 Logic LUT, +0 FF | Shared if exposed as HDC primitive | First-level lane hierarchy net growth. The growth is mainly associated with the HPERM/align/spread path that also supports ECC square/spread. |
| P2 popcount slices | -112 Logic LUT, +0 FF | Shared/remapped | This is a hierarchy-report remapping effect: the HDC+ECC version reports 112 fewer Logic LUT inside the P2 popcount slice hierarchy than HDC-only. It does not mean ECC has negative area; it means ECC does not add a second popcount datapath. |
| Shared lane compute net | +8 Logic LUT, +0 FF | Shared | Shift/align growth is almost canceled by popcount remapping. This is a strong reuse result. |
| Top-level ECC control/storage | +723 Logic LUT, +128 LUTRAM, +267 FF | Mostly yes | ECC job control, KPD32 leaf scheduling, product scratch/fold, square/reduce sequencing, inversion schedule, PMUL schedule, and writeback muxing. |
| Total | +2040 Logic LUT, +128 LUTRAM, +267 FF | Mixed | Equal to HDC+ECC minus HDC-only strict. |

The exact Logic-LUT equation is:

`+2040 = +1309 i_vrf + +723 top ECC/control/storage + +120 lane compute - 112 P2 popcount remap`

Therefore, the two dominant buckets are:

- `i_vrf` access/control: `+1309 / +2040 = 64.2%` of the Logic-LUT delta.
- top-level ECC control/storage: `+723 / +2040 = 35.4%` of the Logic-LUT delta.

Together they explain `+2032 / +2040 = 99.6%` of the Logic-LUT delta. The remaining net lane-compute delta is only `+8 Logic LUT`.

## Top-level ECC attribution

Vivado flattens most functions inside `hdec_top`, so the only exact top-level number is:

`+723 Logic LUT, +128 LUTRAM, +267 FF`

The table below attributes that exact top-level delta using the clocked leaf-cell names. Treat the Logic-LUT split as an attribution estimate, not a separate formal Vivado utilization number. The FF split is effectively exact because the named ECC FFs account for almost all of the +267 FF delta.

| ECC bucket inside top | Estimated Logic LUT share | Extra LUTRAM | Extra FF | Notes |
| --- | ---: | ---: | ---: | --- |
| GF multiply KPD32 leaf/control | ~197 | 0 | +176 | `ecc_leaf_*`, `ecc_diag_*`, `ecc_pipe*`, source/dest/fold control. This is not a full standalone field multiplier; the parity/popcount datapath is shared. |
| GF multiply product scratch/fold | ~148 | +128 | 0 | `ecc_product_pair` distributed RAM and product fold/writeback logic. This is the cleanest ECC-only storage cost. |
| Square/spread repeat control | ~30 | 0 | +8 | `ecc_sqr_repeat_*`. Actual spread datapath is the shared HPERM/shift path. |
| Itoh-Tsujii inversion schedule | ~7 | 0 | +4 | `ecc_inv_step_*`. Arithmetic is square/multiply reuse, not separate hardware. |
| Scalar PMUL schedule | ~41 | 0 | +34 | `ecc_pmul_*` bit/subop/control registers. Arithmetic is field-op sequence reuse. |
| Job/status/copy/cycle control | ~98 | 0 | +41 | `ecc_job_*`; includes cycle counter carry chain. |
| Unattributed top mux/reduction/writeback | ~202 | 0 | +4 | Formal residual. Includes opcode/state decode, VRF writeback muxing, fixed reduction XOR fold that Vivado does not preserve as `ecc_reduce233`, and response control. |
| Formal top-level total | +723 | +128 | +267 | Matches hierarchy delta. |

## Operator-level conclusion

| ECC operation | Dedicated new area | Shared/reused area | Optimization priority |
| --- | --- | --- | --- |
| Field add/sub | No clearly measurable dedicated datapath | Existing XOR/binding lane path and VRF writeback | Low. Do not optimize first. |
| Field multiply | About ~345 top Logic LUT attribution +128 LUTRAM +176 FF for KPD32 leaf/control/product scratch; shared popcount path is -112 Logic LUT by hierarchy | P2 popcount/parity and VRF rows | Medium. Optimize product scratch/fold only if we can make it useful to HDC long ops; otherwise keep it and report honestly. |
| Field square | About ~30 Logic LUT +8 FF for repeat/control | HPERM/spread/shift path, +120 Logic LUT shared lane delta | Low/medium. Make it a named HDC bit-spread/linear-transform primitive rather than shrinking it blindly. |
| Modular reduction | Included in residual ~202 Logic LUT, not separately visible after flattening | XOR fold/writeback path | Medium for story, low for immediate area. Refactor only if it also becomes a reusable HDC linear-fold primitive. |
| Inversion | About ~7 Logic LUT +4 FF schedule-only | Reuses square and multiply | Low. No separate inverter datapath to optimize. |
| Scalar PMUL control | About ~41 Logic LUT +34 FF plus part of residual/state muxing | Reuses field ops | Medium for scheduling story, not area-first. Microcode/background scheduler can improve narrative and possibly reduce control sprawl. |
| VRF access | +1309 Logic LUT, +0 FF, reported separately | Shared storage structure | Highest. This is the real area target. |

## What to optimize next

1. Optimize the shared VRF access path first.
   - The +1309 Logic LUT VRF delta is larger than all named ECC arithmetic/control buckets.
   - Build one HDC-foreground/ECC-background request broker that emits one canonical VRF command bundle.
   - Paper story: ECC does not add a second memory system; it becomes a background client of the HDC VRF scheduler.

2. Keep the arithmetic-operator story, but do not sell it as "zero cost."
   - The P2 popcount result is excellent: ECC multiply uses parity/popcount and the hierarchy does not grow.
   - The shift/spread path grows by +120 Logic LUT; acceptable if it is promoted to an HDC-visible bit-spread/linear-fold primitive.
   - Product scratch is still ECC-only unless generalized.

3. Turn square/reduction into HDC primitives only if they benefit HDC workloads.
   - `BV_SPREAD` can be useful for richer HPERM or bit-level projection.
   - `BV_LINEAR_FOLD` can be useful for HDC compression/projection/hash-style transforms.
   - If no HDC use case is added, reduction remains ECC-only and should be reported as such.

4. Add measurement counters before major RTL rewrites.
   - Count per-cycle resource masks: `VRF_R`, `VRF_W`, `BOOL`, `POP`, `SHIFT`, `CNT`, `CLIP`, `RESP`.
   - This supports the foreground-HDC/background-ECC interleaving claim and identifies how many PMUL cycles can be hidden.

5. Avoid more local syntactic cleanup as the main area strategy.
   - V21/V23 trials showed Vivado often remaps seemingly smaller RTL into larger LUT cones.
   - The next meaningful gains should be architectural: VRF broker, micro-op schedule, and shared primitive definition.

## Recommended paper framing

Use:

> Compared with the HDC-only strict baseline, HDEC adds +2040 Logic LUT, +128 LUTRAM, and +267 FF. A hierarchy-level attribution shows that +1309 Logic LUT comes from shared VRF access/control, while the shared lane compute body grows by only +8 Logic LUT net. The remaining +723 Logic LUT, +128 LUTRAM, and +267 FF are ECC job/control and local product-scratch storage. Thus, the dominant integration cost is not a standalone binary-field datapath, but shared-memory access and long-operation scheduling.

Avoid:

> ECC only costs about 700 LUT.

Better:

> The ECC-hard top-level control/storage cost is about +723 Logic LUT plus +128 LUTRAM and +267 FF, while the largest physical delta is the shared VRF access tax. V27 therefore targets the access/scheduling layer rather than replacing the arithmetic algorithm.

## If exact per-operator Logic LUT is required

The current RTL keeps ECC arithmetic as functions and state cases inside `hdec_top`, so Vivado flattens reduction, writeback muxes, and some KPD32 logic. Exact per-operator Logic LUT numbers require one of these controlled experiments:

1. Put `ecc_reduce233`, KPD32 leaf/fold, and square/spread control into separate measurement-only modules with stable hierarchy.
2. Synthesize feature-ablation variants: no PMUL, no INV, no product scratch, no square-repeat, etc.
3. Keep production RTL unchanged unless the refactor is proven PPA-neutral under the same 200 MHz OOC flow.

For now, the hierarchy delta is exact and publishable; the operator table is a transparent attribution estimate for deciding where to optimize.
