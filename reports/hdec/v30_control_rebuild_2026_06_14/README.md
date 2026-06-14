# HDEC V30 control rebuild snapshot

Date: 2026-06-14
Branch: `hdec-ecc-pointmul-v30`
Tool: Vivado 2024.2
Part: `xc7z020clg400-2`
Top: `hdec_top`
Constraint: 5.000 ns OOC synthesis

## Scope

V30 is the area-story cleanup snapshot before the full same-cycle HDC/ECC
interleaving scheduler. It keeps the PMUL product path enabled, removes
default product-area cost from debug/profiling-only ECC field operations, and
keeps the existing background-job hook as a seed for V31.

V30 should not be described as a complete foreground-HDC/background-ECC
interleaving scheduler. It supports a background ECC job mode, but the current
RTL does not yet contain a resource-mask arbiter that lets ECC advance on every
cycle where the HDC foreground leaves a required shared operator idle.

## RTL commits

The V30 snapshot is built on these commits:

| Commit | Change | Purpose |
| --- | --- | --- |
| `d871e54c` | Trim VRF writeback control | Removes the registered VRF writeback pipeline while keeping timing stable. |
| `2e7a70f1` | Make ECC cycle counter optional | Removes profiling counter logic from the default product configuration. |
| `45cb4059` | Gate ECC debug field ops | Makes debug/single-field ECC opcodes verification-only by default. |

## Current OOC result

Source:

- `reports/hdec/v30_control_rebuild_2026_06_14/ooc_debug_ops_param/reports/run_summary.txt`
- `reports/hdec/v30_control_rebuild_2026_06_14/ooc_debug_ops_param/reports/utilization.rpt`

| Metric | V30 current |
| --- | ---: |
| Slice LUT | 6310 |
| Logic LUT | 5838 |
| LUTRAM | 472 |
| FF | 1800 |
| CARRY4 | 13 |
| WNS @ 200 MHz | 0.247 ns |
| Estimated Fmax | 210.393 MHz |

## ECC-only attribution under the V30 story

The paper-facing V30 attribution intentionally removes blocks that can be
framed as HDC/shared infrastructure from the ECC-only bucket. Therefore VRF,
P2 popcount, HPERM/shift, lane-shared logic, and generic top control are not
counted as ECC-only.

Strict ECC-only buckets:

- `ecc_inversion_schedule`
- `ecc_job_status_copy_cycle`
- `ecc_mul_kpd32_control`
- `ecc_mul_product_scratch_fold`
- `ecc_pointmul_schedule`
- `ecc_square_spread_control`

Source:

- `reports/hdec/v30_control_rebuild_2026_06_14/clocked_bucket_debug_ops_param/reports/bucket_summary.csv`

| Resource | Total | Strict ECC-only | Ratio |
| --- | ---: | ---: | ---: |
| Logic LUT | 5838 | 843 | 14.44% |
| Slice LUT estimate | 6310 | 971 | 15.39% |
| FF | 1800 | 251 | 13.94% |

The Slice-LUT estimate counts `843` ECC-only Logic LUT plus `128` ECC-only
LUTRAM from product scratch storage. The raw bucket CSV reports `256` RAM
cells for `ecc_mul_product_scratch_fold`, but the exact HDC-only versus
HDC+ECC delta established in the earlier operator-area report is `+128`
LUTRAM, so `+128` is the defensible ECC-only LUTRAM count.

## Validation

Source:

- `reports/hdec/v30_control_rebuild_2026_06_14/xsim_debug_ops_param/xsim_ecc_pmul_wall_v27/xsim.log`
- `reports/hdec/v30_control_rebuild_2026_06_14/xsim_debug_ops_param/xsim_hdc_full_flow_v20/xsim.log`

| Test | Result |
| --- | --- |
| ECC PMUL wall test | PASS |
| PMUL blocking wall cycles | 401971 |
| PMUL status cycle field | 0, because `ECC_STATUS_CYCLE_COUNT=0` by default |
| HDC full flow | PASS |

Debug-only ECC field-op tests pass when `ECC_DEBUG_FIELD_OPS=1`, but those
paths are not included in the default product-area story.

## V31 handoff

V31 should implement the real interleaving story:

1. HDC stays the foreground owner of architectural instructions.
2. ECC PMUL becomes a persistent background job.
3. Each HDC micro-cycle exposes a compact resource-occupancy mask.
4. Each ECC micro-step exposes the shared resources it needs.
5. ECC advances only when its required resource mask does not conflict with the
   foreground HDC mask.
6. If HDC occupies a required resource, ECC waits without adding fake idle
   cycles.

The evaluation target is:

`standalone ECC PMUL + N standalone HDC full-flow iterations`

versus:

`HDC full-flow repeated as foreground until one background ECC PMUL completes`.

The useful result is not only ECC wall time. The key metric is how many HDC
iterations are completed while ECC is hidden in the background, and how much
total wall time is saved compared with serialized execution.
