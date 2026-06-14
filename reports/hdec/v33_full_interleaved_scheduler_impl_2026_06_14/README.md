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

### 6.4 Rejected V33-C extensions after the accepted quantum

After V33-B, two more aggressive same-cycle sidecar directions were tested.
Both are rejected.

#### Leaf-fold sidecar

Goal: move the local `S_ECC_LEAF_FOLD` product accumulation into foreground HDC
uop gaps while keeping HDC as the foreground owner.

| Variant | Functional result | Decision |
| --- | --- | --- |
| Direct leaf-fold sidecar | timeout after 2000 HDC full-flow iterations, PMUL remained active |
| Guarded sidecar with fallback to coarse ECC | interleaved PMUL completed, but Y result mismatched |
| Simple-uop-only / HBIND-only windows | interleaved PMUL completed, but the same Y mismatch remained |

Reason for rejection: the leaf-fold datapath is not just local arithmetic.  Its
state is coupled to product-pair order, next-leaf VRF capture, and final write
sequencing.  Splitting only the visible local fold creates a fragile partial
state that can pass blocking PMUL but fail under real HDC foreground pressure.

#### Write-pair sidecar

Goal: hide `S_ECC_WRITE_PAIR` during the read half of foreground HDC uop states
by using the apparently-free VRF write port.

| Metric | V33-B kept version | Write-pair sidecar trial |
| --- | ---: | ---: |
| HDC full-flow cycles | 959 | 959 |
| Blocking PMUL wall cycles | 401971 | 401971 |
| Interleaved PMUL+HDC wall cycles | 739940 | 741603 |
| HDC iterations before PMUL done | 436 | 438 |
| Equivalent standalone total | 820095 | 822013 |
| Interleaving saved cycles | 80155 | 80410 |
| OOC Logic LUT | 5843 | 6116 |
| OOC FF | 1803 | 1807 |
| OOC WNS | 0.247 ns | 0.247 ns |

The sidecar was functionally correct, but it cost `+273` Logic LUT over V33-B
for only `+255` more saved cycles in the serialized-vs-interleaved comparison.
The reason is structural: stealing the VRF write slot wires ECC product-pair
data and write enables into the main VRF write mux, so Vivado expands a wide
control/data cone rather than only adding a tiny FSM.

Decision: do not keep leaf-fold or write-pair sidecars in this area-constrained
version.  The wider rule is that V33 should avoid stealing the VRF write port
unless the VRF write mux itself is redesigned.

### 6.5 Accepted V33-C RTL: ECC load-read sidecar

V33-C adds a smaller and more structured sidecar before the diagonal multiply.
When background ECC has already issued the A operand VRF read and foreground
HDC is waiting, `S_ECC_LOAD_A_WAIT` yields to `S_IDLE`.  The shared scheduler
then captures A, issues the B read through the existing 6-bit VRF read address,
captures B, and starts the already-accepted diagonal sidecar.

This keeps the wide VRF write path owned by the main FSM.  The only borrowed
resource is the narrow read address path, and the local state is a 4-state
load-read micro-FSM.

#### Cycle comparison

| Metric | V33-B sub-operation quantum | V33-C load-read sidecar |
| --- | ---: | ---: |
| Standalone HDC full-flow cycles | 959 | 959 |
| Blocking PMUL wall cycles | 401971 | 401971 |
| Interleaved PMUL+HDC wall cycles | 739940 | 734243 |
| HDC full-flow iterations before PMUL done | 436 | 436 |
| Equivalent standalone HDC cycles | 418124 | 418124 |
| Equivalent standalone total | 820095 | 820095 |
| Interleaving saved cycles | 80155 | 85852 |

Formula for V33-C:

```text
equivalent_hdc_cycles = 436 * 959 = 418124
standalone_total      = 401971 + 418124 = 820095
saved_cycles          = 820095 - 734243 = 85852
```

Compared with V33-B, V33-C reduces interleaved wall time by `5697` cycles with
the same number of foreground HDC full-flow iterations.

#### Area/timing comparison

| Version | Logic LUT | Slice LUT | LUTRAM | FF | WNS | Fmax |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| V33-B sub-operation quantum | 5843 | 6315 | 472 | 1803 | 0.247 ns | 210.393 MHz |
| V33-C load-read sidecar | 5887 | 6359 | 472 | 1801 | 0.243 ns | 210.217 MHz |
| Delta | +44 | +44 | 0 | -2 | -0.004 ns | -0.176 MHz |

The `+44` Logic LUT is a total/shared scheduler cost, not an ECC-only operator
cost.  It implements the foreground/background read-sidecar control around the
existing VRF and diagonal pipeline.  FF decreases by 2 after Vivado
optimization.

#### Validation

| Check | Result |
| --- | --- |
| HDC full flow | PASS |
| Blocking PMUL | PASS, `PMUL_BLOCKING_WALL_CYCLES=401971` |
| Background PMUL + foreground HDC loop | PASS, `PMUL_BG_HDC_LOOP_WALL_CYCLES=734243`, `HDC_ITERS=436` |
| OOC 200 MHz | PASS, WNS `0.243 ns` |

#### Rejected follow-up tweaks

| Trial | Result | Decision |
| --- | --- | --- |
| Unguarded `S_RESULT` dispatch bypass | HDC and blocking PMUL passed, but background PMUL timed out after 2000 HDC iterations with status `0x44` | reject |
| Phase-safe `S_RESULT` dispatch bypass | Functional, but interleaved wall stayed `739940` cycles | reject |
| Forced sequential encoding for load-read sidecar FSM | OOC worsened to `6107` Logic LUT and `1810` FF | reject |

## 7. V33 direction after the accepted quantum

The next RTL direction must satisfy all of these constraints:

1. Keep V32-B local diagonal sidecar.
2. Keep V33-C load-read sidecar as the safe narrow-port interleaving layer.
3. Do not slice ECC into single-cycle quanta without a progress budget.
4. Do not yield inside a VRF read-latency pair unless the capture side is
   explicitly owned by a sidecar state.
5. Keep `ready_o = (st_q == S_IDLE)`.
6. Keep all foreground-HDC entry decisions out of the decode hot path.
7. Avoid wide duplicate VRF request or data buffers.
8. Avoid stealing the VRF write port unless the VRF write mux itself is
   redesigned; a sidecar bolted onto the existing write mux is too expensive.

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
- result-dispatch bypasses that either timed out or gave no cycle gain
- forced sequential encoding for the load-read sidecar FSM

The retained V33-C state has two synthesizable scheduling changes above V32-B:

- V33-B: the non-last PMUL step transition no longer yields immediately to
  `S_IDLE` when foreground valid is waiting.
- V33-C: the first ECC operand-load pair can be hidden under the foreground HDC
  instruction prologue using the narrow VRF read address path.

Both keep standalone PMUL unchanged and improve the interleaved total-cycle
comparison with a small total/shared scheduler area cost.
