# V33 Full Interleaved Scheduler Implementation Notes

Date: 2026-06-14

Branch: `hdec-ecc-pointmul-v33`

Base RTL kept after this round: V32-B RTL, commit `a1addc1c`

## 1. Accepted measurement update

V33-A adds measurement output to the existing background PMUL + foreground HDC
loop testbench.  It does not change synthesizable RTL.

Current clean baseline after reverting rejected RTL trials:

| Metric | Value |
| --- | ---: |
| Standalone HDC full-flow cycles | 959 |
| Blocking PMUL wall cycles | 401971 |
| Interleaved PMUL+HDC wall cycles | 754622 |
| HDC full-flow iterations before PMUL done | 449 |
| Equivalent standalone HDC cycles | 430591 |
| Equivalent standalone total | 832562 |
| Interleaving saved cycles | 77940 |
| OOC Logic LUT | 5829 |
| OOC FF | 1795 |
| OOC WNS | 0.243 ns |
| OOC Fmax | 210.217 MHz |

Formula:

```text
equivalent_hdc_cycles = 449 * 959 = 430591
standalone_total      = 401971 + 430591 = 832562
saved_cycles          = 832562 - 754622 = 77940
```

This is the first precise V33 comparison point using the user's intended
evaluation method.

## 2. PMUL profile buckets

V33-A also extends the PMUL profile testbench with state buckets.  Current
blocking PMUL profile:

| Bucket | Cycles |
| --- | ---: |
| `PMUL_PROFILE_WALL_CYCLES` | 401971 |
| `PMUL_PROFILE_PHASE_PMUL_FIELD_CYCLES` | 373951 |
| `PMUL_PROFILE_PHASE_PMUL_ADD_CYCLES` | 4949 |
| `PMUL_PROFILE_PHASE_PMUL_COPY_CYCLES` | 470 |
| `PMUL_PROFILE_ST_ECC_LOAD_CYCLES` | 5744 |
| `PMUL_PROFILE_ST_ECC_DIAG_CYCLES` | 193860 |
| `PMUL_PROFILE_ST_ECC_LEAF_FOLD_CYCLES` | 155088 |
| `PMUL_PROFILE_ST_ECC_WRITE_PAIR_CYCLES` | 5744 |
| `PMUL_PROFILE_ST_ECC_WRITE_DRAIN_CYCLES` | 7066 |
| `PMUL_PROFILE_ST_ECC_REDUCE_CYCLES` | 14132 |
| `PMUL_PROFILE_ST_HSPREAD_CYCLES` | 4194 |
| `PMUL_PROFILE_ST_ECC_UOP_CYCLES` | 4949 |

Conclusion: V33 should not start with UOP/lane scheduling.  The dominant
remaining work is still the GF field path, especially diagonal and leaf-fold
cycles.

## 3. Rejected RTL trial B: write-pair quantum

Trial B tried to turn `S_ECC_WRITE_PAIR` into a tiny suspend/resume background
write quantum.

Reason for trying:

- `S_ECC_WRITE_PAIR` does not depend on `vrf_rd` latency.
- It uses ECC product RAM and the existing VRF write port.
- It looked like a safe low-area first VRF-write bubble-stealing step.

Observed results:

| Variant | Result |
| --- | --- |
| Direct yield from `S_ECC_WRITE_PAIR` to `S_IDLE` | HDC foreground corruption |
| Dispatch-mediated resume | PMUL starved; timeout after 2000 HDC full-flow iterations |

Decision: rejected and reverted.

Lesson: a one-cycle write quantum is too fine-grained.  It can either disturb
the foreground handshake cadence or let foreground HDC starve background ECC.
V33 needs bounded atomic ECC progress windows, not arbitrary one-state slicing.

## 4. Rejected RTL trial C: local leaf-fold sidecar

Trial C split the local product-pair part of `S_ECC_LEAF_FOLD` into a sidecar.
The intent was to hide the local product fold while leaving next-leaf VRF load
on the existing coarse path.

Reason for trying:

- Leaf fold accounts for `155088` PMUL cycles.
- The product-pair fold itself is local to ECC product RAM.
- It does not require HDC lane, HDC row buffer, or a new wide data mux.

Observed results:

| Test | Result |
| --- | --- |
| Blocking PMUL | PASS, `PMUL_BLOCKING_WALL_CYCLES=401971` |
| Interleaved PMUL+HDC | timeout after 2000 HDC full-flow iterations, status `0x44` |

Decision: rejected and reverted.

Lesson: product fold and next-leaf VRF prefetch are logically separable, but
splitting them without a progress guarantee makes ECC too dependent on sparse
resume opportunities.  The design remained functionally safe for standalone
PMUL but failed the interleaved throughput goal.

## 5. V33-D direction after the rejected trials

The next RTL direction must satisfy all of these constraints:

1. Keep V32-B local diagonal sidecar.
2. Do not slice ECC into single-cycle quanta without a progress budget.
3. Do not yield inside a VRF read-latency pair.
4. Keep `ready_o = (st_q == S_IDLE)`.
5. Keep all foreground-HDC entry decisions out of the decode hot path.
6. Avoid wide duplicate VRF request or data buffers.

The better next structure is an atomic leaf-window scheduler:

```text
HDC foreground has priority at instruction boundaries.
ECC background can still claim a bounded atomic field window.
Inside that window:
  VRF read/request/capture pairs are not split.
  local diagonal sidecar still runs in same cycle with HDC where possible.
  local fold may only be hidden if the next load/capture pair is guaranteed.
At safe leaf or field-operation boundaries:
  scheduler yields back to HDC if foreground is waiting.
```

This is less aggressive than a full resource-mask arbiter, but it avoids both
failure modes seen in this round:

- too fine a quantum starves ECC;
- detached local fold starves the next VRF load.

## 6. Current kept files

Kept changes:

- `verif/hdec/tb_hdec_ecc_pmul_bg_hdc_loop_v31.sv`
- `verif/hdec/tb_hdec_ecc_pmul_profile_v27.sv`
- this report

Rejected and reverted:

- all V33-B/V33-C synthesizable changes in `core/hdec/rtl/hdec_top.sv`

The retained V33-A state has no synthesizable RTL delta from V32-B, and the
OOC result confirms the same area/timing point: Logic LUT 5829, FF 1795,
Fmax 210.217 MHz.
