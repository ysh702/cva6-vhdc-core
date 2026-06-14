# V33 Full Interleaved Scheduler Implementation Notes

Date: 2026-06-14

Branch: `hdec-ecc-pointmul-v33`

Base RTL before V33-B: V32-B RTL, commit `a1addc1c`

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

## 5. Rejected scheduler-window trials after V33-A

After the first rejected write-pair and leaf-fold attempts, two PMUL scheduler
window variants were tested.

| Trial | Functional result | OOC result | Decision |
| --- | --- | --- | --- |
| 2-bit `credit=3` PMUL step window | PASS, interleaved wall `743342`, HDC iters `439` | Logic LUT `6635`, FF `1812`, Fmax `204.960 MHz` | reject |
| no-new-FF cadence using `ecc_pmul_step_q[1:0]` | PASS, interleaved wall `743351`, HDC iters `439` | Logic LUT `6712`, FF `1807`, Fmax `202.429 MHz` | reject |

Both variants improved the interleaved wall time but made `S_ECC_PMUL_STEP_NEXT`
decode much larger.  The lesson is that adding a new predicate into the PMUL
step scheduler can be worse than adding explicit storage: Vivado expands the
wide PMUL case/decode cone.

## 6. Accepted V33-B RTL: PMUL sub-operation quantum

V33-B keeps a much smaller version of the same idea.  It removes the background
yield check from the non-last branch of `S_ECC_PMUL_STEP_NEXT`:

```systemverilog
ecc_pmul_step_n = ecc_pmul_step_q + 6'd1;
st_n = S_ECC_PMUL_STEP;
```

The design still yields at existing safe boundaries, and V32-B's local
diagonal sidecar still allows true same-cycle progress during foreground HDC.
The accepted change does not add a new FF, a second ECC FSM, a VRF data buffer,
or a resource-mask bus.  It is best described as a shared scheduling quantum:
background ECC is allowed to finish the current PMUL sub-operation instead of
returning to `S_IDLE` after every internal step.

This is intentionally weaker than a full dual-issue arbiter, but it is much
more FPGA-friendly than the rejected credit/cadence trials.

### 6.1 Cycle comparison

| Metric | V33-A / V32-B | V33-B sub-operation quantum |
| --- | ---: | ---: |
| Standalone HDC full-flow cycles | 959 | 959 |
| Blocking PMUL wall cycles | 401971 | 401971 |
| Interleaved PMUL+HDC wall cycles | 754622 | 739940 |
| HDC full-flow iterations before PMUL done | 449 | 436 |
| Equivalent standalone HDC cycles | 430591 | 418124 |
| Equivalent standalone total | 832562 | 820095 |
| Interleaving saved cycles | 77940 | 80155 |

Formula for V33-B:

```text
equivalent_hdc_cycles = 436 * 959 = 418124
standalone_total      = 401971 + 418124 = 820095
saved_cycles          = 820095 - 739940 = 80155
```

Compared with V33-A, V33-B reduces the interleaved wall time by `14682` cycles
and improves the serialized-vs-interleaved saving by `2215` cycles.  The HDC
iteration count is lower because the background PMUL claims a slightly larger
atomic window; the comparison must therefore use the equivalent standalone
total above, not only raw HDC iteration count.

### 6.2 Area/timing comparison

| Version | Logic LUT | Slice LUT | LUTRAM | FF | WNS | Fmax |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| V33-A / V32-B | 5829 | 6301 | 472 | 1795 | 0.243 ns | 210.217 MHz |
| V33-B sub-operation quantum | 5843 | 6315 | 472 | 1803 | 0.247 ns | 210.393 MHz |
| Delta | +14 | +14 | 0 | +8 | +0.004 ns | +0.176 MHz |

The `+14` Logic LUT and `+8` FF are counted in total HDEC area, not in the
strict ECC-only bucket.  Reason: the change does not instantiate an ECC-only
operator or ECC-only storage structure; it changes the shared background-job
scheduling policy around the existing HDC/ECC execution controller.

### 6.3 Validation

| Check | Result |
| --- | --- |
| HDC full flow | PASS |
| Blocking PMUL | PASS, `PMUL_BLOCKING_WALL_CYCLES=401971` |
| Background PMUL + foreground HDC loop | PASS, `PMUL_BG_HDC_LOOP_WALL_CYCLES=739940`, `HDC_ITERS=436` |
| OOC 200 MHz | PASS, WNS `0.247 ns` |

## 7. V33 direction after the accepted quantum

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

## 8. Current kept files

Kept changes:

- `core/hdec/rtl/hdec_top.sv`
- `verif/hdec/tb_hdec_ecc_pmul_bg_hdc_loop_v31.sv`
- `verif/hdec/tb_hdec_ecc_pmul_profile_v27.sv`
- this report

Rejected and reverted:

- write-pair quantum
- detached leaf-fold sidecar
- credit/cadence scheduler windows that widened `S_ECC_PMUL_STEP_NEXT`

The retained V33-B state has one synthesizable RTL change from V32-B: the
non-last PMUL step transition no longer yields immediately to `S_IDLE` when
foreground valid is waiting.  This keeps standalone PMUL unchanged and improves
the interleaved total-cycle comparison with a small total-area cost.
