# HDEC V31 same-cycle interleaving scheduler design

Date: 2026-06-14
Branch: `hdec-ecc-pointmul-v31`
Base snapshot: `hdec-ecc-pointmul-v30` at `8a44ccb0`

## Executive conclusion

V31 should not start by rewriting the whole PMUL controller again. The right
design is a small, explicit foreground/background scheduler:

- HDC remains the foreground architectural stream.
- ECC PMUL becomes a persistent background job.
- The scheduler exposes a compact per-cycle shared-resource mask.
- ECC advances only in cycles where its next micro-step does not conflict with
  the foreground HDC resource mask.
- If HDC uses a required resource, ECC stalls; the stall is counted as real HDC
  occupancy, not artificial polling or idle time.

The key implementation detail is that "same-cycle interleaving" is not just a
control-FSM problem. It also requires a non-overlapping VRF address contract.
The current PMUL workspace uses `VRF[32:63]`, while HDC count accumulation also
uses rows starting at `32` or `48`. Therefore, a true HDC full-flow plus
background ECC PMUL test can corrupt data unless V31 first defines a safe VRF
namespace for the interleaved workload.

My recommendation is:

1. Keep V30 as the area baseline.
2. In V31, first add a report-only/profiling view of resource occupancy.
3. Then implement a narrow resource-mask arbiter around the existing normalized
   `vrf_req` bundle.
4. Only allow ECC sidecar progress in slots that are proven safe for VRF
   latency, lane pipeline ownership, and shared temporary registers.
5. Keep all debug counters optional and synthesis-disabled by default.

This gives the strongest story: the extra control is not ECC-only machinery;
it is a unified HDC resource scheduler that makes the foreground HDC pipeline
observable and shareable.

## Current V30 state

V30 already has useful seeds:

- A single normalized VRF request bundle:
  `vrf_req.ra`, `vrf_req.we`, `vrf_req.wa`, `vrf_req.wd`.
- A background-job flag:
  `ECC_STATUS_BG_BIT=29` and `ecc_job_bg_q`.
- PMUL can be started as a background job through `HDEC_ECC_STATUS`.
- When the top FSM is idle, it can resume a background ECC job.
- At PMUL step boundaries, the current RTL can yield back to `S_IDLE` if a new
  foreground instruction arrives.

But this is still a coarse background mode, not the final interleaving design.
The current behavior is closer to:

> ECC runs when the accelerator is idle, and it yields when HDC arrives.

The target V31 behavior is:

> HDC runs as foreground, and ECC opportunistically advances during internal
> HDC bubbles or non-conflicting operator cycles.

Those are different. V31 must therefore add a second, resource-aware scheduling
layer rather than only adjusting the old `ecc_job_bg_q` checks.

## Hard blocker: VRF namespace conflict

Before implementing arbitration, V31 must fix the address-space story.

The current package documentation says:

- `VRF[0:31]`: HDC vector slots.
- `VRF[32:47]`: HDC bundle accumulator.
- `VRF[48:55]`: reserved HDC scratch/future.
- `VRF[56:63]`: ECC reserved slots.

But the current PMUL RTL reserves much more than `56:63`:

| PMUL row | Meaning |
| ---: | --- |
| 32,34,36 | R0 X/Y/Z |
| 38,40,42 | R1 X/Y/Z |
| 44-62 even | PMUL temporaries T0-T9 |

So PMUL effectively occupies `VRF[32:63]`.

HDC `HCNTADD` and `HCNTCLIP` currently use accumulator bases `32` or `48`.
Therefore, if we run the current HDC full-flow while background PMUL is active,
the two flows are not merely contending for the same physical VRF port; they
are also writing the same architectural rows.

This must be solved first. Otherwise an interleaving demo could pass only for
HBIND-only foreground traffic and fail for the real HDC full-flow.

### Recommended V31 VRF contract

For the interleaved benchmark, define a three-region map:

| Region | Rows | Owner during interleaved run |
| --- | ---: | --- |
| HDC vectors | `0:15` | HDC foreground vectors, up to four 1024-bit slots |
| HDC counters | `16:31` | HDC foreground bundle/count state |
| ECC PMUL workspace | `32:63` | ECC background PMUL |

This keeps the current PMUL workspace unchanged, which avoids retiming or
repacking the ECC scalar multiplication controller. It also keeps the total VRF
size unchanged.

The cost is that the interleaved HDC workload must be restricted to four
foreground vector slots while ECC PMUL is active. That is acceptable for the
V31 proof because the story is not "unlimited HDC storage while ECC runs"; the
story is "a foreground HDC workload can continue while ECC uses otherwise idle
shared compute slots."

Implementation options:

| Option | Area risk | Correctness risk | Recommendation |
| --- | --- | --- | --- |
| Move ECC workspace away from `32:63` | High | Medium | Avoid first. PMUL code assumes many fixed rows. |
| Increase VRF size | Very high | Low | Avoid. It destroys the area story. |
| Remap HDC counter base during interleaved mode | Low/medium | Low if tested | Best first implementation. |
| Require HDC full-flow test to use vector rows `0:15` only | None | Low | Use for V31 benchmark contract. |

The minimal RTL change is to introduce a small `hdc_cnt_base` decode:

```systemverilog
logic [VRF_IDX_W-1:0] hdc_cnt_base0;
logic [VRF_IDX_W-1:0] hdc_cnt_base1;

assign hdc_cnt_base0 = ecc_job_bg_q ? 6'd16 : 6'd32;
assign hdc_cnt_base1 = ecc_job_bg_q ? 6'd24 : 6'd48; // only if bank 1 is needed
```

For the first V31 benchmark, use only one counter base if possible. Supporting
two simultaneous counter banks while ECC owns `32:63` is possible but creates
more pressure on rows `16:31`.

## Resource model

The scheduler should use a narrow resource mask. Do not add a wide table, a
large microcode ROM, or a second full copy of the control FSM.

Proposed resource bits:

| Bit | Resource | Why it matters |
| ---: | --- | --- |
| 0 | `VRF_RA` | One VRF read address is issued per cycle. |
| 1 | `VRF_RD_CONSUME` | Current `vrf_rd` data is being consumed by foreground state. |
| 2 | `VRF_W` | One VRF row writeback bundle per cycle. |
| 3 | `LANE_PIPE` | The shared HDC uop/lane pipeline is occupied. |
| 4 | `BOOL_XOR` | HBIND/GF add uses shared XOR lane path. |
| 5 | `POP` | HSIM/HMATCH/popcount path is occupied. |
| 6 | `SHIFT` | HPERM/spread/square shift path is occupied. |
| 7 | `SCRATCH_ROWBUF` | Shared row buffer such as `hdc_src0_q` is live for HDC. |

This is intentionally small. An 8-bit mask is enough to express the first
correct scheduler, and it is much cheaper than adding per-operator scoreboard
state.

The arbiter rule is:

```systemverilog
ecc_can_fire = ecc_bg_active
            && !valid_i_conflict
            && ((hdc_mask & ecc_next_mask) == '0)
            && vrf_namespace_safe;
```

HDC always has priority. ECC never blocks a valid foreground HDC instruction.

## HDC foreground occupancy

The HDC foreground mask should be derived from the existing FSM state and uop
type. This avoids adding new high-fanout enables.

Useful classification:

| HDC state class | Example states | Foreground resources |
| --- | --- | --- |
| Decode/issue | `S_EXEC` | Depends on opcode; often `VRF_RA` or `VRF_W`. |
| VRF read address | `S_UOP_P1_RD0`, `S_UOP_P1_RD1` | `VRF_RA`, `LANE_PIPE`. |
| VRF read wait bubble | `S_UOP_P1_RD0_WAIT`, `S_UOP_P1_RD1_WAIT` | Usually no new write; may be safe for ECC read injection if next-cycle data ownership is handled. |
| Lane compute | `S_UOP_P2_LANE` plus `p2_lane_compute_q` | `LANE_PIPE`, plus `BOOL_XOR`/`POP`/`SHIFT`/`CNT`/`CLIP`. |
| Global/writeback | `S_UOP_P3_GLOBAL`, `S_UOP_CLIP_WRITE` | Often `VRF_W`; sometimes `VRF_RA`. |
| Response | `S_UOP_P4_RESP`, `S_RESULT` | Response path only; ECC can run if it does not need the host result path. |
| Clear | `S_CLR` | `VRF_W`; ECC writes must stall. ECC local compute might fire. |

The important discovery is that VRF wait states are not simply idle. Because
the VRF has registered reads and the top also registers `vrf_ra_q`, a read
address issued during a foreground wait cycle can affect the intermediate
`vrf_rd` value in a later cycle. That can be useful, but only if the ECC
sidecar has a matching capture slot and the foreground does not need that
intermediate data.

So V31 should not naively say "WAIT equals free." It should define a small
table of proven-safe slots:

| Slot kind | First V31 action |
| --- | --- |
| Foreground response cycles | Allow ECC non-response micro-step. |
| Foreground VRF write cycles | Allow ECC local KPD compute only; no ECC write. |
| Foreground VRF read wait bubbles | Allow ECC read only after a waveform/test proves the next data consumer is ECC, not HDC. |
| Foreground lane compute cycles | Stall ECC if it needs lane/pop/shift/XOR. Allow ECC local KPD issue only if no shared popcount path is used. |

This conservative policy is the best way to preserve 200 MHz.

## ECC background micro-engine

The cleanest architecture is not to let the global `st_q` be both HDC and ECC.
Use:

- `hdc_st_q`: the existing foreground state, effectively the current `st_q`.
- `ecc_bg_st_q`: a small background ECC state cursor for PMUL/inversion/field
  substeps.
- Existing ECC PMUL registers:
  `ecc_pmul_ctrl_q`, `ecc_pmul_subop_q`, `ecc_pmul_step_q`,
  `ecc_pmul_bit_q`, source/destination registers, and field-op registers.

The background engine emits an `ecc_req` bundle:

```systemverilog
typedef struct packed {
    logic        valid;
    logic [7:0]  mask;
    hdec_vrf_req_t vrf;
    logic        advance;
} hdec_sched_req_t;
```

The foreground emits `hdc_req` in the same normalized shape. The broker selects:

```systemverilog
if (hdc_req.valid) begin
    final_vrf_req = hdc_req.vrf;
end else if (ecc_can_fire) begin
    final_vrf_req = ecc_req.vrf;
end else begin
    final_vrf_req = '0;
end
```

For sidecar cycles where HDC has no VRF request but still owns other resources,
the broker can allow `ecc_req.vrf` if the masks do not conflict.

Do not build a large "PMUL microcode ROM" in V31. Prior experiments already
showed that table-like PMUL rewrites can make Vivado build worse mux cones.
Keep the current case-based PMUL sequencing and add a narrow `ecc_can_advance`
gate.

## Shared temporary-register hazard

Several current ECC states reuse HDC-oriented temporaries:

- `hdc_src0_q` is used as a row buffer in HDC uops, spread, and reduction.
- `lane_result_q` and lane payload registers are shared by HBIND/HPERM/HCNTADD.
- `uop_p0_q` through `uop_p3_q` are a single shared uop pipeline.

Therefore, V31 must not allow ECC to sidecar any micro-step that writes these
registers while the HDC foreground still needs them.

First implementation rule:

| ECC micro-step family | Can run during HDC active? | Reason |
| --- | --- | --- |
| PMUL step decode only | Yes, if it only updates ECC PMUL registers | No datapath conflict. |
| KPD diagonal local issue | Maybe | Safe only if it does not use shared popcount/lane payload. |
| ECC VRF read address | Maybe | Needs VRF bubble proof and sidecar capture. |
| ECC VRF writeback | Usually no | Single VRF write bundle; foreground writes take priority. |
| ECC square/spread | No in first version | Uses HPERM/spread and `hdc_src0_q`. |
| ECC GF add via uop pipeline | No in first version | Uses shared uop/lane pipeline. |
| ECC reduce | No in first version unless isolated | Uses `hdc_src0_q` row buffer. |

This sounds conservative, but it is intentional. The first working V31 should
prove correctness and timing before widening the safe slot set.

## Proposed implementation phases

### Phase V31-A: measurement harness

No behavioral change.

Add optional counters under a synthesis parameter such as:

```systemverilog
parameter bit HDEC_INTERLEAVE_PROFILE = 1'b0
```

Counters:

- HDC foreground active cycles.
- HDC resource mask histogram.
- ECC background runnable cycles.
- ECC background fired cycles.
- ECC stall by reason:
  `VRF_RA`, `VRF_W`, `LANE_PIPE`, `SHIFT`, `POP`, `ROWBUF`, namespace conflict.
- Completed foreground HDC full-flow iterations before ECC PMUL completes.

Default product synthesis should set this parameter to `0`, so the counters do
not affect the area story.

### Phase V31-B: VRF namespace-safe HDC benchmark

Modify or add a dedicated testbench:

- Start background PMUL with `ECC_STATUS_BG_BIT=1`.
- Run HDC full-flow repeatedly as the foreground.
- Use only HDC vector rows `0:15`.
- Move HDC count accumulator rows to `16:31` while background PMUL owns
  `32:63`.
- Poll ECC status only after each HDC full-flow iteration, or use a direct TB
  observation for done. Do not count repeated polling as useful HDC work.

This phase proves that the benchmark itself is valid.

### Phase V31-C: coarse safe-slot sidecar

Allow ECC to advance only in a tiny set of safe cycles:

- `S_RESULT` and response-only cycles.
- Foreground cycles with no VRF write and no lane pipeline ownership.
- Selected local ECC compute cycles that do not write shared row buffers.

Expected benefit is modest, but area risk is low.

### Phase V31-D: VRF bubble stealing

After waveform proof, allow ECC reads during foreground VRF wait bubbles where
the intermediate `vrf_rd` value is not consumed by HDC.

This is where the real "same-cycle" story becomes visible: ECC can use cycles
that were structurally present because of HDC's registered VRF latency.

### Phase V31-E: widened operator sharing

Only after V31-C/D pass simulation and OOC:

- Allow ECC GF add micro-steps to use the lane XOR path when foreground HDC is
  not using `LANE_PIPE`.
- Allow square/spread when foreground HDC is not using `SHIFT` and row-buffer
  ownership is free.
- Consider a tiny `rowbuf_owner_q` bit if needed. Avoid adding a second 256-bit
  row buffer unless the cycle savings justify the FF cost.

## Expected PPA impact

The first useful RTL change should be small:

| Item | Expected cost |
| --- | ---: |
| 8-bit HDC resource mask | Small LUT decode |
| 8-bit ECC next mask | Small LUT decode |
| `ecc_can_fire` gate | Small LUT cone |
| `ecc_bg_st_q` if separate from `st_q` | About 6-7 FF |
| Optional profiling counters | Zero in default product build |

The scheduler must avoid:

- Large PMUL microcode ROMs.
- Widening the main FSM encoding.
- Routing ECC through P2 popcount if timing is not proven.
- Adding a second full VRF port.
- Adding a second 256-bit row buffer by default.
- Adding another complete uop pipeline.

The V30 area target is:

| Metric | V30 |
| --- | ---: |
| Slice LUT | 6310 |
| Logic LUT | 5838 |
| FF | 1800 |
| WNS @ 200 MHz | 0.247 ns |

For V31, a practical first acceptance threshold is:

- `WNS >= 0` at 200 MHz.
- Logic LUT increase ideally under `+50`.
- FF increase ideally under `+50` in the product build.
- Strict ECC-only attribution should not rise materially; scheduler logic
  should be described as HDC/shared resource scheduling infrastructure.

If the first scheduler attempt costs more than about `+100` Logic LUT, it
should be treated as a failed architecture and rolled back.

## Evaluation method

The comparison must use wall cycles, not the old 16-bit status field.

Definitions:

- `T_ecc_alone`: wall cycles for one blocking ECC PMUL.
- `T_hdc_one`: wall cycles for one standalone HDC full-flow iteration.
- `N`: number of HDC full-flow iterations completed before background PMUL is
  done.
- `T_serial = T_ecc_alone + N * T_hdc_one`.
- `T_interleaved`: wall cycles from starting background PMUL to completing the
  Nth foreground HDC iteration and observing PMUL done.
- `saved = T_serial - T_interleaved`.
- `hidden_fraction = saved / T_ecc_alone`.

The headline should be:

> While HDC continues its foreground workload, ECC scalar multiplication is
> advanced in cycles where the HDC pipeline leaves shared operators idle. The
> measured saved cycles quantify hidden ECC progress, while any ECC wall-time
> extension is attributable to real HDC resource occupancy.

This avoids overclaiming. If HDC is shift-heavy, ECC square/spread will stall.
If HDC is popcount-heavy, ECC multiply may lose opportunities. That is a
feature of the resource-aware story, not a bug.

## Required tests

Add tests in this order:

1. `tb_hdec_ecc_pmul_wall_v31`
   - Confirms blocking PMUL unchanged from V30.
2. `tb_hdec_hdc_full_flow_v31`
   - Confirms remapped HDC full-flow works without ECC.
3. `tb_hdec_ecc_pmul_bg_hdc_loop_v31`
   - Starts background PMUL, then loops HDC full-flow until PMUL done.
4. `tb_hdec_interleave_scoreboard_v31`
   - Asserts no VRF namespace overlap between foreground HDC rows and ECC PMUL
     rows.
5. `tb_hdec_interleave_mask_v31`
   - Asserts ECC fires only when `(hdc_mask & ecc_mask) == 0`.

OOC runs:

- V31 product build with profiling off.
- V31 profiling build only if needed for measurements.
- Compare both against V30 `ooc_debug_ops_param`.

## Paper-story framing

V30 already makes the area story cleaner:

- Strict ECC-only Logic LUT is about 14.44% of the product build.
- Strict ECC-only FF is about 13.94%.
- VRF, popcount, shift, and generic control can be framed as HDC/shared
  infrastructure.

V31 should add the time-domain story:

> HDEC does not merely share hardware statically. It also shares time. HDC is
> the foreground workload, and ECC scalar multiplication is scheduled as a
> background job that advances only in cycles where HDC does not occupy the
> required VRF, lane, popcount, or shift resource. This converts the shared
> control logic from an integration overhead into a useful interleaving
> scheduler.

The strongest final figure would be:

| Design | Total LUT | ECC-only LUT | FF | PMUL alone | HDC iterations hidden | Serialized cycles | Interleaved cycles | Saved |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| V30 | 6310 | 971 Slice-LUT estimate | 1800 | measured wall cycles | 0 | baseline | baseline | 0 |
| V31 | target near V30 | target near V30 | target near V30 | unchanged or near unchanged | measured | measured | measured | measured |

This is the cleanest combined story:

- Area: ECC-only cost is small after shared infrastructure is counted properly.
- Time: ECC PMUL can progress behind HDC instead of requiring fully serialized
  accelerator time.
- Security: scalar multiplication algorithm remains constant-pattern
  Montgomery ladder style; no skipping zero bits or unsafe scalar-dependent
  shortcuts.

## Immediate next action

Do not implement the full arbiter in one patch. The first V31 RTL patch should
be:

1. Add an interleaved-mode VRF map for the HDC full-flow test.
2. Add a no-behavior-change resource-mask profiler under a disabled-by-default
   parameter.
3. Run simulation and OOC.

Only after that should V31 enable `ecc_can_fire` for a small safe-slot set.
