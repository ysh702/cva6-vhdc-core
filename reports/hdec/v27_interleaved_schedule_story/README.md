# V27 foreground HDC / background ECC interleaving story

Date: 2026-06-13
Branch: hdec-ecc-pointmul-v27

## Current facts

- `PMUL_CYCLES=6005` is the current RTL-reported latency for one complete ECC scalar point multiplication macro-job, not one field multiply.
- The current RTL/testbench target is a K-233 / sect233k1-style binary curve over `GF(2^233)`.
- The reduction polynomial used by the current RTL is `f(x)=x^233+x^74+1`.
- The current PMUL implementation runs a fixed 233-bit scalar-point-multiply flow: init, scalar-bit loop, final affine recovery, and writeback.
- At 200 MHz, 6005 cycles is about 30.0 us.

## Signature boundary

For an ECDSA-like signing flow, the accelerator contribution can be framed as:

1. HDEC computes the dominant curve operation: one scalar point multiplication `kG`.
2. CPU software finishes the scalar-domain signature arithmetic: hash handling, modulo-order arithmetic, modular inverse, modular multiply/add, and formatting.

That boundary is reasonable because the remaining signature arithmetic is carry-propagating integer arithmetic modulo the group order, while the current HDEC datapath is built around binary-field vector/bit operations.

Important wording:

- Signing usually needs one ephemeral scalar multiplication `kG` plus scalar arithmetic.
- Key generation also needs one scalar multiplication `dG`.
- Verification usually needs two scalar multiplications or a combined multi-scalar multiplication, so it should not be described as the same one-PMUL flow unless implemented separately.

## Better story than area-only reuse

The V25/V26 area-only reuse story is weak if ECC still accounts for roughly one third of the integrated area and repeated area optimization does not move the needle. V27 should pivot from:

> "ECC is cheap because it reuses HDC hardware."

to:

> "ECC latency is hidden behind foreground HDC execution through opportunistic same-cycle scheduling, while HDC remains the priority workload."

This turns the claim from pure area reduction into latency hiding and QoS:

- HDC is the foreground workload and should not slow down.
- ECC PMUL is a background job.
- Each cycle, ECC may issue one micro-op only when its resource mask does not conflict with the HDC micro-op for that cycle.
- If HDC needs the same operator or VRF port, ECC waits.
- The paper metric becomes hidden ECC cycles, tail latency, and total saved cycles, not only LUT reduction.

## Sequential vs interleaved model

Let:

- `T_HDC` be the cycle count of a repeated HDC workload.
- `T_PMUL = 6005` be one standalone ECC scalar point multiplication.
- `I_HDC` be the number of ECC-compatible idle or non-conflicting slots inside the HDC workload.

Sequential execution:

```text
T_seq = T_HDC + T_PMUL
```

Idealized interleaved execution:

```text
T_int = T_HDC + max(0, T_PMUL - I_HDC)
saved_cycles = T_seq - T_int = min(T_PMUL, I_HDC)
hidden_ratio = saved_cycles / T_PMUL
```

If the HDC stream is long enough and exposes at least 6005 compatible slots, then one full ECC PMUL can be completely hidden:

```text
T_int ~= T_HDC
hidden_ratio ~= 100%
```

If the HDC stream exposes fewer slots, the remaining ECC tail is:

```text
ECC_tail = T_PMUL - I_HDC
```

The real implementation should refine `I_HDC` by resource class rather than treating every idle slot as equal.

## Resource mask idea

Track each cycle with a compact resource mask. A first practical mask can include:

- `VRF_R`: vector register-file read address/bank use
- `VRF_W`: vector register-file write use
- `BOOL`: XOR/AND-style boolean datapath
- `POP`: popcount datapath
- `SHIFT`: permutation/shift datapath
- `CNT`: counter update datapath
- `CLIP`: clipping datapath
- `RESP`: response/status/writeback path

HDC receives priority. ECC can issue only when:

```text
(hdc_mask & ecc_mask) == 0
```

and the required VRF bank/port constraints are also satisfied.

This gives a clean RTL and paper story:

1. The scheduler is deterministic.
2. HDC latency is protected.
3. ECC progress is opportunistic but measurable.
4. The same integrated accelerator can report both foreground HDC throughput and background ECC completion time.

## Existing HDC cycle anchors

Current performance parser anchors the HDC operations as:

| Operation | Current latency model |
| --- | ---: |
| `VADDR` | 3 cycles |
| `VWR64` | 3 cycles |
| `VRD64` | 4 cycles |
| `HCLR` | 7 cycles |
| `HCNTCLR` | 19 cycles |
| `HBIND` | 15 cycles |
| `HPERM` | 15 cycles |
| `HSIM` | 18 cycles |
| `HCNTADD` | 63 cycles |
| `HCNTCLIP` | 39 cycles |
| `HMATCH(N)` | `3 + 15*N` cycles |

These are enough to build a first workload-level estimate before changing RTL.

## Measurement plan

For each HDC workload, report four cycle counts:

1. `T_HDC`: HDC-only workload.
2. `T_PMUL`: ECC PMUL-only, currently 6005 cycles.
3. `T_seq = T_HDC + T_PMUL`: serialized baseline.
4. `T_int`: same HDC workload with one background ECC PMUL enabled.

Then report:

```text
saved_cycles = T_seq - T_int
hidden_ratio = saved_cycles / 6005
HDC_slowdown = (T_HDC_interleaved - T_HDC) / T_HDC
ECC_tail = T_int - T_HDC
```

The target claim should be:

- `HDC_slowdown` is zero or near zero because HDC has priority.
- A large fraction of the 6005 PMUL cycles is hidden during realistic repeated HDC workloads.
- Area overhead is acceptable because it buys background security work without adding visible foreground latency.

## RTL milestones

1. Add measurement-only resource masks and counters around the existing HDC FSM.
2. Estimate hidden slots for representative HDC loops without changing behavior.
3. Split ECC PMUL into resumable micro-ops with explicit resource masks.
4. Add HDC-priority arbitration: foreground HDC issue first, background ECC issue only on non-conflict cycles.
5. Add counters:
   - `ecc_bg_issue_cycles`
   - `ecc_bg_stall_hdc_priority`
   - `ecc_bg_stall_vrf_r`
   - `ecc_bg_stall_vrf_w`
   - `ecc_bg_stall_bool_pop`
   - `ecc_bg_stall_shift_cnt_clip`
   - `ecc_bg_tail_cycles`
6. Run PMUL-only, HDC-only, serialized, and interleaved tests.

## Risks

- The current top-level FSM is monolithic, so V27 needs scheduler refactoring rather than a small local patch.
- The VRF is likely the tightest shared resource. It has limited per-bank read addressing, so many ECC field steps may stall behind HDC memory traffic.
- The current field multiply/reduce flow may not have enough independent work to issue during every HDC cycle without careful micro-op decomposition.
- ECC scheduling must avoid scalar-dependent timing leakage. The PMUL loop should remain fixed length, and scalar bits must not create observable variable resource use beyond the externally imposed HDC preemption.

## Recommended paper framing

Use two connected claims:

1. Structural compatibility: binary-field ECC maps onto HDC-style bit-vector operations and can share the vector/boolean/popcount-oriented substrate.
2. Temporal compatibility: HDC workloads are repetitive and bursty, exposing non-conflicting cycle slots where ECC can make background progress.

The stronger contribution is not "ECC is almost free in area." It is:

> A foreground-HDC/background-ECC accelerator that turns repeated HDC execution into a latency-hiding substrate for scalar point multiplication, preserving HDC service latency while reducing the combined HDC+ECC wall-clock cycles.

