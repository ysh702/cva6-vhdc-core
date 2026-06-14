# V31 interleaved scheduler try

Date: 2026-06-14

## Goal

Prototype a low-area same-cycle interleaving path where a background ECC PMUL
job can make progress while foreground HDC work repeatedly runs.  The target is
to keep standalone ECC PMUL unchanged, keep 200 MHz timing, and avoid turning
the scheduler into a large ECC-only control block.

## Kept RTL shape

- Remap HDC counter banks while an ECC background job is active:
  - normal HDC counters: rows `32` and `48`
  - background-PMUL interleave counters: rows `16` and `24`
- Add one thin state, `S_ECC_BG_DISPATCH`, entered from `S_RESULT` when a
  background ECC job is active.
- Remove the old idle-only background dispatch path from `S_IDLE`.  This avoids
  duplicating background entry logic in both `S_IDLE` and `S_RESULT`.
- Clear `ecc_job_bg` when the background job completes, so HDC counter remap
  returns to the normal namespace after PMUL completion.

This is an instruction-boundary interleaving prototype, not a full dual-context
operator scheduler yet.  It proves the low-area control entry and VRF namespace
split needed by the next resource-level scheduler.

## Simulation

Final kept version: `v31_result_only_dispatch`.

| Test | Result | Key number |
| --- | --- | --- |
| `xsim_hdec_hdc_full_flow_v20.tcl` | PASS | unchanged HDC full flow |
| `xsim_hdec_ecc_pmul_wall_v27.tcl` | PASS | `PMUL_BLOCKING_WALL_CYCLES=401971` |
| `xsim_hdec_ecc_pmul_bg_hdc_loop_v31.tcl` | PASS | `PMUL_BG_HDC_LOOP_WALL_CYCLES=424499`, `HDC_ITERS=20` |
| `xsim_hdec_ecc_pmul_bg_idle_v27.tcl` | PASS | `PMUL_BG_IDLE_WALL_CYCLES=401972` |
| `xsim_hdec_ecc_pmul_bg_v27.tcl` | PASS | legacy bg smoke test |

The new V31 loop starts PMUL as a background job, repeatedly runs a foreground
HDC sequence using slots `2/3`, and verifies both foreground HDC results and the
PMUL `3G` result.

## OOC comparison

Baseline is V30 `ooc_debug_ops_param`.

| Version | Logic LUT | Slice LUT | LUTRAM | FF | WNS | Fmax |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| V30 baseline | 5838 | 6310 | 472 | 1800 | 0.247 | 210.393 MHz |
| V31 result-only dispatch | 5847 | 6319 | 472 | 1799 | 0.247 | 210.393 MHz |

Delta versus V30: `+9` Logic LUT, `+9` Slice LUT, `-1` FF, unchanged timing.

## Failed alternatives

| Attempt | Simulation | OOC | Reason rejected |
| --- | --- | --- | --- |
| Direct `S_RESULT -> ECC step` | PASS | Logic LUT `6864`, FF `1827`, WNS `0.117` | Merged result return and ECC control cones; too much area. |
| Separate `S_ECC_BG_DISPATCH` plus idle dispatch | PASS | Logic LUT `5961` | Correct, but still `+123` Logic LUT. |
| Same plus bg-clear | PASS | Logic LUT `5936` | Better, but still `+98` Logic LUT. |
| Packed counter-base function | FAIL | not kept | Broke HCNTCLIP counter reads in xsim. |
| `bg_slice` one-FF scheduler | PASS | Logic LUT `6734`, WNS `0.121` | `ready_o` became part of the scheduler hot path; area/timing worsened. |

## Design note

The result-only dispatch version is intentionally narrow.  It does not yet
perform true operator-level arbitration inside a long HDC instruction.  The
next version should keep this namespace split, then move from
instruction-boundary dispatch to a small resource-availability model for
VRF/popcount/XOR/shift/counter use.  The area lesson from this run is clear:
avoid feeding background scheduler conditions into `ready_o` or the normal HDC
decode hot path.
