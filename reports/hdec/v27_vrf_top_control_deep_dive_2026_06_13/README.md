# V27 deep dive: `i_vrf` logic and top-level ECC control/storage

Date: 2026-06-13
Branch: `hdec-ecc-pointmul-v27`
Baseline: HDC-only strict vs HDC+ECC, Vivado 2024.2, 200 MHz OOC

## Executive conclusion

The ECC area story should now focus on two buckets:

| Bucket | Exact delta vs HDC-only strict | Share of Logic-LUT delta | Meaning |
| --- | ---: | ---: | --- |
| `i_vrf` hierarchy | +1309 Logic LUT, +0 LUTRAM, +0 FF | 64.2% | Shared VRF access/control tax |
| Top-level ECC control/storage | +723 Logic LUT, +128 LUTRAM, +267 FF | 35.4% | ECC long-operation control, product scratch, reduction/writeback |
| Lane compute net | +8 Logic LUT, +0 LUTRAM, +0 FF | 0.4% | Shared compute remapping, effectively flat |
| Total | +2040 Logic LUT, +128 LUTRAM, +267 FF | 100% | Full ECC integration overhead |

Therefore:

1. Do not optimize P2 popcount first. It is already reused.
2. Do not replace the ECC multiplier algorithm first. The arithmetic body is not the dominant overhead.
3. Focus on VRF access structure and long-operation control form.

## `i_vrf` exact facts

Formal hierarchy data:

| Design | `i_vrf` Total LUT | `i_vrf` Logic LUT | `i_vrf` LUTRAM | `i_vrf` FF |
| --- | ---: | ---: | ---: | ---: |
| HDC-only strict | 1796 | 1452 | 344 | 256 |
| HDC+ECC | 3105 | 2761 | 344 | 256 |
| Delta | +1309 | +1309 | 0 | 0 |

This means:

- The VRF storage capacity did not grow.
- The VRF read/output FF count did not grow.
- The entire `i_vrf` delta is combinational control/mux logic around the same shared RAM structure.

`hdec_vrf_64x256.sv` itself is simple: four 64-bit LUTRAM banks, one registered read address per bank, one write address, one write enable, and one write-data bus. The extra LUTs are not caused by adding memory; they are caused by the many sources feeding `vrf_ra_q`, `vrf_wa_q`, `vrf_we_q`, and especially `vrf_wd_q`.

## RTL root cause

HDC already has a canonical uop path:

- `S_UOP_P1_RD0`: read `uop_p0_q.src0_addr`.
- `S_UOP_P1_RD1`: read `uop_p1_q.src1_addr`.
- `S_UOP_P3_GLOBAL`: write `uop_p3_q.dst_addr` from lane/boolean/counter/shift result.

This uop path serves:

- `HBIND`,
- `HSIM`,
- `HMATCH`,
- `HCNTADD`,
- `HCNTCLIP`,
- regular `HPERM`,
- and some ECC operations such as `HDEC_ECC_ADD`, `HDEC_ECC_ALIGN`, ECC MAC after reduce, and many PMUL XOR/add steps.

But large parts of ECC bypass this path and directly drive VRF ports from many states:

| Direct ECC VRF use | Representative states | Why it hurts area |
| --- | --- | --- |
| Field multiply operand reads | `HDEC_ECC_MUL`, `S_ECC_LOAD_A`, `S_ECC_LEAF_FOLD` | Adds many read-address choices: operand A, operand B, next leaf path. |
| Product writeback | `S_ECC_WRITE_PAIR` | Partial-bank writes from `ecc_product_pair_rdata`, unlike normal full-row HDC writes. |
| Reduction read/write | `HDEC_ECC_REDUCE`, `S_ECC_REDUCE_LOAD_LO`, `S_ECC_REDUCE_WRITE` | Adds high-fan-in write-data source `ecc_reduce_result`. |
| Copy row | `S_ECC_INV_COPY_WRITE` | Adds full-row copy source `vrf_rd -> vrf_wd`. |
| Constant row | `S_ECC_PMUL_CONST_WRITE` | Adds zero/one write-data special cases. |
| Square/spread loop | `S_HSPREAD_LO_WRITE`, `S_HSPREAD_HI_WRITE`, `S_ECC_WRITE_DRAIN` | Shared with HDC-style spread, but currently driven by special ECC drain logic. |
| PMUL schedule reads | `S_ECC_PMUL_STEP`, `S_ECC_PMUL_STEP_NEXT` | Many literal/conditional scratch addresses feed `vrf_ra`: `R0X/R1X/T*`, `point+1`, scalar-dependent choices. |

Static scan of direct `vrf_*` assignments in `hdec_top.sv`:

| Source class | Number of direct `vrf_*` assignment lines |
| --- | ---: |
| ECC-direct states/opcodes | 84 |
| HDC/uop states/opcodes | 35 |
| Shared/mixed states | 25 |

This is not an area number, but it explains the shape of the netlist: ECC adds many direct control alternatives into the same VRF input registers.

## Better form for `i_vrf`

### Best architectural direction: unified VRF request broker

Replace scattered direct assignments with one canonical request bundle:

```systemverilog
typedef struct packed {
    logic valid;
    logic [3:0] rd_mask;
    logic [3:0] wr_mask;
    logic [VRF_IDX_W-1:0] rd_addr;
    logic [VRF_IDX_W-1:0] wr_addr;
    hdec_vrf_wdata_sel_e wdata_sel;
    logic [1:0] lane_pair_sel;
} hdec_vrf_req_t;
```

Then have exactly one place that maps `hdec_vrf_req_t` to:

- `vrf_ra`,
- `vrf_we`,
- `vrf_wa`,
- `vrf_wd`.

This does not magically remove all muxing, but it changes the structure:

- HDC and ECC become clients of the same VRF scheduler.
- PMUL no longer directly drives four lane addresses from many `case` arms.
- The broker becomes the natural point for HDC-foreground/ECC-background arbitration.
- The paper story becomes stronger: ECC is a background client of HDC's VRF substrate, not a pile of ECC-only muxes.

### Concrete reuse opportunities

| Current ECC behavior | Better shared form | HDC benefit | Risk |
| --- | --- | --- | --- |
| `S_ECC_INV_COPY_WRITE` full-row copy | `UOP_VRF_COPY_ROW` | Useful for HDC vector move/scratch management | Adds a new uop but can replace direct ECC copy muxes. |
| `S_ECC_PMUL_CONST_WRITE` zero/one row | `UOP_VRF_CONST_ROW` or reuse `S_CLR` for zero | HDC clear/scratch init can share constant-write path | Constant one is ECC-specific unless HDC gets a useful row-fill primitive. |
| `S_ECC_REDUCE_WRITE` | `UOP_LINEAR_FOLD_WRITE` | HDC compression/projection/hash-like linear fold | Only persuasive if HDC exposes/uses it. |
| `S_HSPREAD_*` | `UOP_BIT_SPREAD_WRITE` | HDC bit-spread/bit-permutation primitive | Good story; may not reduce LUT immediately. |
| PMUL field operation launch | `UOP_GF_MUL`, `UOP_GF_SQR`, `UOP_GF_ADD` descriptors | Shared long-op schedule machinery | Needs careful cycle accounting. |
| Many scalar PMUL address cases | microcoded source/destination descriptors | Same sequencer can drive HDC long ops | ROM/table can cost LUT; must synthesize. |

### What not to do

- Do not edit `hdec_vrf_64x256.sv` first. The memory module is not the problem.
- Do not split VRF into separate HDC/ECC memories; that would kill the reuse story.
- Do not blindly add `keep_hierarchy` around VRF. It may improve attribution but not area.
- Do not replace direct assignments with cosmetically different RTL unless it reduces the number of logical request sources.

## Top-level ECC control/storage facts

Exact top-level delta:

`+723 Logic LUT, +128 LUTRAM, +267 FF`

Clocked cell-name attribution:

| Top-level ECC bucket | Estimated Logic LUT | LUTRAM | FF | Reuse potential |
| --- | ---: | ---: | ---: | --- |
| KPD32 multiply leaf/control | ~197 | 0 | +176 | Medium. The datapath is already shared; control can become field-op uop state. |
| Product scratch/fold | ~148 | +128 | 0 | Low/medium. Can become shared long-op scratchpad, but otherwise ECC-only. |
| Square/spread control | ~30 | 0 | +8 | High for story. Make it HDC bit-spread/linear primitive. |
| Inversion schedule | ~7 | 0 | +4 | Low. Already schedule-only. |
| Scalar PMUL schedule | ~41 | 0 | +34 | High for scheduling story. Candidate for micro-op sequencer. |
| Job/status/copy/cycle | ~98 | 0 | +41 | Medium. Can merge into generic long-op engine/status. |
| Reduction/writeback/top residual | ~202 | 0 | +4 | Medium/high for story if converted to shared linear-fold writeback. |

## Can these become HDC resources?

### Yes, with credible HDC benefit

1. VRF broker / scheduler
   - HDC already has multi-cycle operations.
   - A unified broker can also expose resource masks for interleaving.
   - This is the strongest way to reclassify part of the `i_vrf` logic as HDC/HDEC infrastructure.

2. Bit-spread / linear-fold primitives
   - ECC square and reduction are linear transforms over GF(2).
   - HDC can use bit-spread/permutation/fold for richer projection, compression, or hashing-style transforms.
   - This is a good algorithm-level reuse story if HDC tests include these modes.

3. Long-op sequencer
   - HDC operations such as `HMATCH`, `HCNTADD`, `HCNTCLIP`, and future batched search already need repeated uops.
   - ECC PMUL/INV can be another program on the same sequencer.
   - This directly supports foreground-HDC/background-ECC scheduling.

4. Row copy / row constant / scratch management
   - HDC can benefit from vector move, clear, scratch init.
   - ECC copy/const writes should use this path rather than special states.

### Maybe, but only if measured

1. Product scratch
   - Current `ecc_product_pair` is a clean ECC-only `+128 LUTRAM`.
   - It could become shared long-op scratchpad.
   - Moving it into VRF rows may remove LUTRAM but probably adds cycles and more VRF traffic.
   - This is not the first optimization target.

2. KPD32 leaf registers
   - They are tied to the ECC multiplication schedule.
   - HDC does not naturally need 32-bit KPD leaf selection.
   - Better to present them as compact control for using shared popcount/parity, not as HDC resources.

### No, or not worth forcing

1. Inversion step table
   - Too small to matter.
   - It is already just schedule/control.

2. ECC scalar-bit and point-ladder state
   - These are intrinsically ECC.
   - They should remain honest ECC-specific control.

## Recommended V27 optimization plan

### Phase A: measurement-only

Add counters/resource masks before changing behavior:

- `vrf_r_cycles`
- `vrf_w_cycles`
- `bool_cycles`
- `pop_cycles`
- `shift_cycles`
- `reduce_cycles`
- `ecc_bg_issue_cycles`
- `ecc_bg_stall_vrf`
- `ecc_bg_stall_bool`
- `ecc_bg_tail_cycles`

This quantifies whether PMUL can hide under HDC activity.

### Phase B: shared request broker

Introduce a single VRF request builder with priority:

1. foreground HDC request,
2. background ECC request,
3. idle.

Initially keep behavior equivalent:

- no real interleaving yet,
- no PMUL cycle change target,
- just route existing HDC/ECC VRF actions through one request form.

Acceptance:

- HDC full-flow PASS,
- ECC PMUL PASS,
- 200 MHz PASS,
- ideally reduce or at least not grow LUT.

### Phase C: background ECC scheduler

After the broker exists:

- HDC uses foreground issue.
- ECC PMUL uses background issue.
- If requested resource mask conflicts, ECC waits.
- Report hidden cycles and tail cycles.

This is where the reuse story becomes compelling even if area does not drop much.

### Phase D: top-level control compaction

Only after Phase B/C:

- convert PMUL add/double/affine cases into table-driven micro-ops,
- convert copy/const/reduce/spread into shared uops,
- decide whether product scratch remains ECC-only or becomes shared scratch.

## Paper story after this analysis

The stronger story is not:

> ECC arithmetic is free.

The stronger story is:

> ECC arithmetic is expressed over HDC-native bit-vector primitives, so the shared compute fabric barely grows. The remaining overhead is dominated by shared VRF access and long-operation control. V27 turns those costs into a unified foreground-HDC/background-ECC scheduler, allowing ECC scalar multiplication to progress opportunistically during HDC execution rather than occupying a separate accelerator.

This story is honest with the numbers:

- `i_vrf + top ECC = 99.6%` of Logic-LUT delta.
- shared compute net is only `+8 Logic LUT`.
- `+128 LUTRAM` product scratch remains ECC-only unless generalized.
- `+267 FF` is mainly ECC schedule/state and should be reduced by sequencer reuse only if synthesis confirms it.
