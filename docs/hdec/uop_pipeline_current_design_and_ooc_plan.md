# HDEC UOP Pipeline Current Design and OOC Plan

> Date: 2026-05-30
> Branch context: `hdec-uop-pipeline-v1`
> Scope: current unified uop pipeline after pre-commit review fixes. Read this
> document before any post-OOC Codex or Codex App modification.

## 1. Current Final Design

The current HDEC top-level control uses a unified uop pipeline for the main HDC
compute instructions:

- HBIND
- HSIM
- HMATCH
- HCNTADD
- HCNTCLIP
- HPERM

The simple management instructions stay on the fast path:

- VADDR
- VWR64
- VRD64
- HCLR
- HCNTCLR

The old per-instruction active FSM paths have been removed. There are no active
`S_HBIND_*`, `S_HSIM_*`, `S_HPERM_*`, `S_HCNTADD_*`, or `S_HCNTCLIP_*` compute
states in `hdec_top.sv`.

The design is still a Phase-1 transitional top-level controller. It is not yet
the future engine-level arbiter with tag routing, and it does not implement ECC.

## 2. Pipeline Stages

The current control flow is:

| Stage | Role |
|-------|------|
| `S_EXEC` / P0 | Decode instruction and clean-construct a new uop. New uop construction starts from `uop_p0_n = '0`. |
| `S_UOP_P1_RD0` | Issue first VRF read address. For HPERM, compute the wrapped source word address. |
| `S_UOP_P1_RD1` | Capture operand A (`src0_q` or `hperm_a_q`) and issue the second read address. HCNTCLIP is single-source and reuses the same source address. |
| `S_UOP_P2_LANE` | Drive lane-local compute blocks and register typed vector or narrow results. |
| `S_UOP_P3_GLOBAL` | Consume typed results using `p3_action`: VRF writeback, HSIM/HMATCH accumulation, best update, HCNTADD pre-read, or HCNTCLIP subgroup pack. |
| `S_UOP_P4_RESP` | Pack registered scalar response for HSIM/HMATCH or zero response for vector ops. |
| `S_UOP_CLIP_WRITE` | Dedicated HCNTCLIP writeback state after all four subgroups for one output word are packed. |

## 3. Lane-Local Compute Boundary

All real compute datapaths are Lane-local:

- XOR is in `hdec_lane_4x64.sv` through `hdec_lane_boolean_mask`.
- Popcount is HDC-only and is now inside `hdec_lane_4x64.sv`.
- CNT update is in `hdec_cnt_array`, instantiated by `hdec_lane_4x64.sv`.
- Clip compare is in `hdec_lane_clip`, instantiated by `hdec_lane_4x64.sv`.
- Shift-align is in `hdec_lane_shift_align`, instantiated by `hdec_lane_4x64.sv`.

`hdec_top.sv` no longer directly computes `$countones`. It only receives the
lane-local `popcount_count_o` output and stores it into `lane_result_q[lid][6:0]`
for HSIM/HMATCH.

## 4. ISA-guided Lane-local Typed Result Fabric

G++ replaces the previous unified `lane_result_q` boundary with an
ISA-guided typed result fabric. In `S_EXEC`, each HDC custom instruction is
decoded into a compact instruction template carried by `hdec_uop_t`:

- `lane_mode`: selects the lane-local compute result.
- `result_type`: selects the P2 boundary channel.
- `p3_action`: selects how P3 consumes the result.

The template mapping is:

| Instruction | `lane_mode` | `result_type` | `p3_action` |
|-------------|-------------|---------------|-------------|
| HBIND | `HDEC_LANE_MODE_XOR` | `HDEC_RESULT_VECTOR` | `HDEC_P3_VRF_WRITE` |
| HSIM | `HDEC_LANE_MODE_POPCOUNT` | `HDEC_RESULT_NARROW` | `HDEC_P3_SIM_ACCUM` |
| HMATCH | `HDEC_LANE_MODE_POPCOUNT` | `HDEC_RESULT_NARROW` | `HDEC_P3_MATCH_BEST` |
| HCNTADD | `HDEC_LANE_MODE_COUNTER` | `HDEC_RESULT_VECTOR` | `HDEC_P3_VRF_WRITE` |
| HCNTCLIP | `HDEC_LANE_MODE_CLIP` | `HDEC_RESULT_NARROW` | `HDEC_P3_CLIP_PACK` |
| HPERM | `HDEC_LANE_MODE_SHIFT` | `HDEC_RESULT_VECTOR` | `HDEC_P3_VRF_WRITE` |

Each lane produces two typed outputs:

- vector channel: 64-bit XOR, CNT update, or shift-align result.
- narrow channel: 7-bit popcount zero-extended to 16 bits, or 16-bit clip bits.

P2 holds both channels by default and updates only the channel selected by
`result_type`:

- `lane_vec_result_q[4][64]` for vector results.
- `lane_narrow_result_q[4][16]` for narrow results.

P2 no longer contains a top-level multi-operator result mux. P3 no longer
interprets one shared result register; it consumes vector or narrow data
according to `p3_action`.

## 5. `src0_q`

`src0_q` is the operand-A register required by the single-read-port VRF:

- 64-bit per lane.
- 256-bit total.
- Captures the first source read while the second source is issued.
- Feeds XOR-based HBIND/HSIM/HMATCH in P2.

This is not a free resource. It is the current cost of supporting two-source
Lane operations with a single-read-port VRF. Future optimization directions are:

- Scheme A: banked VRF dual-source read, if area and power are acceptable.
- Scheme B: query/prototype split, where hot inference query and prototype
  traffic are separated to reduce read pressure.

Neither scheme is implemented in the current version.

## 6. Popcount Current State

The active popcount is:

- HDC-only.
- Lane-local in `hdec_lane_4x64.sv`.
- Input: 64-bit XOR diff from the lane boolean/mask path.
- Output: 7-bit `$countones`.
- One active popcount implementation only.

The current design has no ECC mux, no carry-cut, and no parity mode. The
`hdec_lane_popcount_compressor.sv` source may remain as a future reference, but
it is not the active datapath. Future ECC integration must re-evaluate whether
to use an explicit compressor tree, carry-cut, or parity mode.

## 7. Seven Design Ideas: Current Status

| Idea | Current status |
|------|----------------|
| Unified uop pipeline | Implemented for HBIND/HSIM/HMATCH/HCNTADD/HCNTCLIP/HPERM. |
| Clean uop construction | Implemented: new uops are constructed from zero in `S_EXEC`; HCNTCLIP next-chunk uop is also clean-built. |
| P2-to-P3 typed result cut | Implemented as vector/narrow result registers; no shared top-level result mux. |
| Lane-local compute boundary | Implemented after review fix; popcount is back in the lane wrapper. |
| Stale flag protection | Initial fix implemented with clean construction; simulation onehot assertion added in P2. |
| HCNTADD pre-read optimization | Implemented as first version: P3 writes current subgroup and pre-reads next subgroup, then skips P1 for the next subgroup. |
| OOC-driven next step | Not implemented in RTL. OOC results must guide whether to optimize timing, cycles, area, or power. |

## 8. Stale UOP Flag Bug Record

The previous bug was in the pre-G++ `use_*` control scheme:

1. `always_comb` defaulted `uop_p0_n = uop_p0_q`.
2. HCNTADD set `use_counter = 1`.
3. The next HCNTCLIP uop set `use_clip = 1` but inherited stale
   `use_counter = 1`.
4. P2 selected the counter result before clip result because of priority order.
5. HCNTCLIP packed counter data instead of clip bits.

The original fix was:

- New uop construction starts with `uop_p0_n = '0`.
- HCNTCLIP next-chunk uop construction also starts from zero.
- P2 has a simulation-only onehot0 assertion over popcount, counter, shift,
  clip, and XOR-only modes.

G++ removes `use_xor/use_popcount/use_counter/use_clip/use_shift` from
`hdec_uop_t`. The active control is now the decode-generated template:
`lane_mode`, `result_type`, and `p3_action`. P2 assertions check template
consistency instead of one-hot `use_*` flags.

## 9. Latency Table

Cycle counts are instruction-level estimates from the uop-pipeline review
baseline. Use them as comparison inputs for OOC analysis, not as an isolated
success metric.

| Instruction | Old baseline | Current uop pipeline | Delta | Note |
|-------------|--------------|----------------------|-------|------|
| VADDR | 3 | 3 | 0 | Fast path |
| VWR64 | 3 | 3 | 0 | Fast path |
| VRD64 | 4 | 4 | 0 | Fast path |
| HCLR | 7 | 7 | 0 | Fast path |
| HCNTCLR | 19 | 19 | 0 | Fast path |
| HBIND | 12 | 20 | +8 | UOP staging |
| HSIM | 12 | 20 | +8 | UOP staging |
| HMATCH (4-class) | 48 | 52 | +4 | Class loop amortizes overhead |
| HCNTADD | 51 | 44 | -7 | Pre-read offsets pipeline cost |
| HCNTCLIP | about 37 | about 58 | +21 | Dedicated write state plus staging |
| HPERM | 12 | 20 | +8 | UOP staging |

The pre-commit review fixes do not intentionally change latency.

## 10. Vivado OOC Judgment Standard

Do not blindly shorten the critical path. Do not blindly add more pipeline
stages. Evaluate all of:

- Fmax
- cycles
- cycles x clock period
- area
- power
- workload-level total time

Guideline:

| Fmax | Judgment | Priority |
|------|----------|----------|
| `< 150 MHz` | Timing is insufficient | Optimize real critical path first |
| `150-200 MHz` | Medium | Decide using total time |
| `200-250 MHz` | Good | Be cautious about further pipeline cuts |
| `250-300 MHz` | Very good | Prefer cycles, area, and power |
| `> 300 MHz` | Excellent | Stop blindly cutting pipeline; consider reducing over-staging |

Core formulas:

```text
instruction_time = cycles / Fmax
benchmark_time   = total_cycles / Fmax
speedup          = old_time / new_time
```

## 11. Post-OOC Modification Plan

After OOC, Codex must read this document first and then decide from evidence:

- If Fmax is below 150-200 MHz, inspect the real critical path before changing
  RTL.
- If the critical path is in P2 lane popcount, consider internal popcount
  staging or a different popcount tree.
- If the critical path is in HMATCH P3, consider splitting only the HMATCH
  global reduction path without penalizing HBIND/HPERM.
- If Fmax is already 200-250 MHz, first compute cycles x clock period.
- If Fmax is at least 250 MHz, do not blindly split P3; prefer reducing cycles,
  such as HBIND/HPERM bypass or HCNTCLIP latency optimization.
- Any optimization must compare old and new total benchmark time, not just Fmax.

## 12. Optional Optimizations Not Implemented Now

These are explicitly deferred:

- Banked VRF dual-source read.
- Query/prototype split.
- HBIND / HPERM fast bypass.
- HCNTCLIP latency optimization.
- ECC carry-cut / parity mode.
- Explicit compressor tree for ECC.

## 13. Non-Goals for Current Version

The current version does not modify:

- ISA encoding.
- CV-X-IF wrapper.
- VRF structure.
- Counter bit-width.
- HPERM 4-bit-granularity semantics.
- ECC datapath.

## 14. G++ OOC Follow-up Notes

G++ targets the current Vivado OOC worst path through `S_UOP_P2_LANE` into the
low bits of the old shared result register. The root cause was not only
popcount arithmetic depth; the old top-level result boundary forced XOR,
popcount, CNT, clip, and shift results through one 4×64-bit result selection
network, and narrow popcount/clip results were mixed into the full vector path.

The new structure keeps the same instruction latency and pipeline staging:

- Custom instruction decode creates an instruction template once in `S_EXEC`.
- The template travels with the uop through P1/P2/P3.
- Lane-local typed result selection uses only `lane_mode`.
- P2 captures either vector or narrow results according to `result_type`.
- P3 consumes the selected channel according to `p3_action`.

Low-power measures:

- Lane inputs are operand-isolated by `lane_mode`.
- Non-active P2 result channel holds its previous value.
- Narrow ops do not update the 4×64-bit vector result registers.
- Vector ops do not update the 4×16-bit narrow result registers.

Small-area measures:

- The previous shared vector-width result register is replaced by
  `lane_vec_result_q[4][64]`.
- Only `lane_narrow_result_q[4][16]` is added for narrow popcount/clip data.
- No per-op 4×64-bit result register sets are introduced.
- No duplicate popcount, CNT, shift-align, or clip compute units are added.

Unchanged boundaries:

- ISA encoding is unchanged.
- CV-X-IF wrapper is unchanged.
- VRF structure is unchanged.
- Counter bit-width is unchanged.
- HPERM remains 4-bit granular.
- ECC mux/carry-cut/parity behavior is not implemented.

Post-G++ OOC should check:

- Whether 150 MHz passes.
- LUT/FF delta from the extra narrow result channel and template bits.
- Dynamic-power change from channel holds and operand isolation.
- Whether the worst path moved out of P2 result capture.
- Whether cycles and Fmax improve without changing instruction latency.
