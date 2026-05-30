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
| `S_UOP_P2_LANE` | Drive lane-local compute blocks and register their result into `lane_result_q`. |
| `S_UOP_P3_GLOBAL` | Perform global finish: VRF writeback, HSIM/HMATCH accumulation, best update, HCNTADD pre-read, or HCNTCLIP subgroup pack. |
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

## 4. Unified `lane_result_q`

`lane_result_q` is the 4-lane, 256-bit P2-to-P3 boundary register. Its
interpretation depends on `uop_p3_q.op_type`:

| op_type | `lane_result_q[lid]` content |
|---------|------------------------------|
| HBIND | 64-bit XOR result |
| HSIM/HMATCH | low 7-bit popcount, high bits zero |
| HCNTADD | 64-bit updated packed counter word |
| HCNTCLIP | low 16-bit `clip_bits`, high bits zero |
| HPERM | 64-bit shift-align result |

Only one HDC uop is active at a time in the current controller, so this shared
register does not need tags beyond the uop pipeline registers.

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
| P2-to-P3 `lane_result_q` cut | Implemented as one shared 256-bit register. |
| Lane-local compute boundary | Implemented after review fix; popcount is back in the lane wrapper. |
| Stale flag protection | Initial fix implemented with clean construction; simulation onehot assertion added in P2. |
| HCNTADD pre-read optimization | Implemented as first version: P3 writes current subgroup and pre-reads next subgroup, then skips P1 for the next subgroup. |
| OOC-driven next step | Not implemented in RTL. OOC results must guide whether to optimize timing, cycles, area, or power. |

## 8. Stale UOP Flag Bug Record

The previous bug was:

1. `always_comb` defaulted `uop_p0_n = uop_p0_q`.
2. HCNTADD set `use_counter = 1`.
3. The next HCNTCLIP uop set `use_clip = 1` but inherited stale
   `use_counter = 1`.
4. P2 selected the counter result before clip result because of priority order.
5. HCNTCLIP packed counter data instead of clip bits.

The fix is:

- New uop construction starts with `uop_p0_n = '0`.
- HCNTCLIP next-chunk uop construction also starts from zero.
- P2 has a simulation-only onehot0 assertion over popcount, counter, shift,
  clip, and XOR-only modes.

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

