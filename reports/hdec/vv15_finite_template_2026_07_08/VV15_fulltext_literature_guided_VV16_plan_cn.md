# VV15 full-text literature guided VV16 plan

## 0. Status

This note is the full-text reading update for the VV15 checkpoint and the
starting plan for VV16.

Local papers read from:

```text
C:\Users\Administrator\Desktop\论文文献\
```

The five PDFs are:

1. Khan and Benaissa, "High-Speed and Low-Latency ECC Processor Implementation Over GF(2^m) on FPGA", 2017.
2. Zeghid et al., "Speed/Area-Efficient ECC Processor Implementation Over GF(2^m) on FPGA via Novel Algorithm-Architecture Co-Design", 2023.
3. Li, Hu and Yang, "High-Performance Pipelined Architecture of Elliptic Curve Scalar Multiplication Over GF(2^m)", 2016.
4. Harb and Jarrah, "FPGA Implementation of the ECC Over GF(2^m) for Small Embedded Applications", 2019.
5. Rashidi, Sayedi and Farashahi, "High-Speed Hardware Architecture of Scalar Multiplication for Binary Elliptic Curve Cryptosystems", 2016.

VV15 current measured checkpoint:

```text
Branch                 : VV15
Main RTL change         : sub-level registered lookahead for diagonal group7 -> next sub group0
PMUL cycles             : 339100
Logic LUT               : 4655
FF                      : 1422
Fmax estimate           : 207.297 MHz
BRAM/DSP                : 4 / 0
Regression              : PMUL profile PASS, reduce/add/HDC checks passed in this run family
```

The important result is not that VV15 is final. It is a low-area checkpoint:
it keeps the shared bit-matrix story and proves that a small scheduling change
can reduce cycles while staying below the stricter `Logic LUT < 4700` gate.

## 1. Current cycle profile and what is really worth attacking

From the VV15 PMUL profile:

```text
PMUL wall cycles                  339100
PMUL field phase                  321308
PMUL add phase                      5656
PMUL copy phase                      705
Affine phase                        7293

S_ECC_LOAD                          3564
S_ECC_DIAG                         11880
S_ECC_LEAF_FOLD                   256608
S_ECC_WRITE_PAIR                   42768
S_ECC_WRITE_DRAIN                   1188
S_ECC_REDUCE                        2821
S_ECC_UOP                           4242
```

The largest bucket is `S_ECC_LEAF_FOLD`, but the right conclusion is more
subtle than "optimize the largest state":

- `S_ECC_LEAF_FOLD` is the best first target because it is linear GF(2)
  folding and already uses the existing 4x64 packet/XOR0 structure. It can be
  rescheduled, tokenized, and hidden behind later diagonal capture without
  adding a new ECC unit.
- `S_ECC_WRITE_PAIR` is the second-best target because it is control and
  writeback overhead. It can be reduced by bypassing or deferring writeback
  locally, not by adding another VRF port.
- `S_ECC_DIAG` is structurally important but currently small in the sampled
  state bucket. Directly duplicating diagonal product hardware would hurt area
  and weaken the HDC/ECC reuse story. VV16 should only widen diagonal work if
  the second product comes from the same matrix cut or from otherwise idle
  control cycles.

Therefore, the VV16 priority should be:

```text
hide or compress leaf folding first
then remove writeback/control bubbles
only then consider diagonal-pair issue, and only if it reuses the same fabric
```

## 2. What the papers actually do when they reduce cycles without blindly adding area

### 2.1 Khan/Benaissa 2017: use pipeline taps and local registers to kill idle cycles

This paper has both a one-multiplier high-performance architecture and a
three-multiplier low-latency architecture. The part relevant to our low-area
constraint is the one-multiplier design, not the three-multiplier extreme.

The useful mechanisms are:

- The multiplier is segmented and pipelined, but the point-multiplication
  schedule is modified so that pipeline latency does not create idle states.
- Intermediate data are tapped from different pipeline stages instead of always
  going through memory read/write.
- Local registers hold the outputs of concurrent square/quad-square/multiply
  operations, reducing pressure on the central memory ports.
- The Moore FSM intentionally introduces one-cycle control delay, then uses
  that delay for intermediate operations through the local registers.
- The accumulator is placed with the memory unit and uses otherwise available
  local storage resources.

Transfer to VV16:

```text
Do not add another reduction accumulator.
Add a tiny fold-token/local-register layer around the existing XOR0 path.
Use diagonal-capture/control delay slots to consume leaf-fold tokens.
Treat fold_token_q as the equivalent of the paper's local pipeline tap.
```

The key lesson is that the scheduler should make local bypass values visible at
the right time. The hardware grows only by the small registers and select bits
needed to expose those values.

### 2.2 Zeghid et al. 2023: co-design the multiplier radix, the PM loop, and the controller

This paper's central idea is bottom-up algorithm-architecture co-design:
digit-serial multiplier choice, Montgomery point-multiplication scheduling, and
FSM/control are evaluated together by area-delay product.

The useful mechanisms are:

- Field multiplier parallelism is not chosen by maximum speed alone. The digit
  size/radix is selected by area-time or ADP.
- Point addition and doubling are merged into a fixed data-dependency graph.
  Field additions and squarings run concurrently with multiplications, so the
  latency is governed by the multiplier schedule.
- The design explicitly avoids "maximum pipelining" when the area-delay
  balance becomes worse.
- The controller emits a fixed sequence for the legal operation graph rather
  than a general dynamic function.

Transfer to VV16:

```text
Evaluate every schedule by cycles, Logic LUT, Fmax, and ADP-like product.
Use fixed legal KPD64 leaf/path templates rather than dynamic path/sub/group muxing.
Reject any 2x group issue that improves cycles but pushes Logic LUT above 4700.
```

The key lesson is that a small amount of controlled parallelism is useful only
when it improves the whole processor metric, not just a single latency number.

### 2.3 Li/Hu/Yang 2016: absorb addition into the MAC/reduction path and keep the critical path simple

This paper uses one field MAC and one squarer, then carefully places pipeline
registers and schedules the Montgomery loop. The most relevant point is not the
specific Karatsuba multiplier, but the way field addition is absorbed into the
existing MAC/reduction path.

The useful mechanisms are:

- Point-multiplication cycles are lowered by scheduling, while the datapath
  remains compact.
- The finite-field MAC merges addition with final reduction, so addition does
  not add extra cycles and does not become a separate wide datapath.
- The critical path is kept to the multiplier/reduction plus a small XOR and a
  small mux.
- The control sequence is ROM-like and compact; the datapath is reused in
  post-processing as much as possible.
- Deeper pipelining is tested and rejected beyond the point where frequency no
  longer compensates for extra loop cycles.

Transfer to VV16:

```text
Fold contribution must be absorbed into existing XOR0/reduce packet flow.
Do not build a new wide direct group-fold datapath beside the shared matrix.
Keep the new critical path to one small fixed-template select plus XOR0.
```

The key lesson is that linear GF(2) work should be physically placed where XOR
already exists.

### 2.4 Harb/Jarrah 2019: compact embedded ECC through ROM-controlled iterative states

This paper is closest to the "small endpoint" design style. It uses a compact
Lopez-Dahab projective ECC core and an iterative ROM-based state machine.

The useful mechanisms are:

- Point doubling and point addition are expressed as ordered state sequences.
- The state machine supplies ROM addresses that control register reads/writes
  and mux choices.
- Each operation stores only the necessary intermediate values. The authors
  explicitly avoid extra intermediate registers where sharing and state order
  make them unnecessary.
- The scalar multiplier reuses the point-doubling and point-addition state
  machines instead of instantiating independent high-throughput units.
- BRAM/precomputation is avoided in their compact design; the gain comes from
  finite state reuse and careful sequencing.

Transfer to VV16:

```text
Use a finite micro-template sequencer for legal leaf/path folding.
Store only the current fold token and possibly one local packet, not a full side buffer.
Let the existing ECC FSM address the template instead of synthesizing a large dynamic function.
```

The key lesson is that a small controller with fixed templates can reduce both
area and cycle waste if it prevents wide dynamic mux logic.

### 2.5 Rashidi/Sayedi/Farashahi 2016: align dependent paths so shared units finish together

This paper uses three pipelined digit-serial multipliers. The raw number of
multipliers is not transferable to our low-area gate, but the scheduling
principle is valuable.

The useful mechanisms are:

- PA and PD are performed in parallel by three multipliers, but the schedule is
  chosen so the long PA path and shorter PD path finish together.
- Two multipliers are fully utilized and the third is about 90% utilized during
  the Montgomery loop.
- In coordinate conversion, the same three multipliers are shared again, and
  independent multiplications are overlapped with inversion.
- The multiplier itself computes multiplication by powers of the polynomial
  variable through parallel independent structures, reducing critical path
  rather than only increasing raw hardware.
- They discuss clock switching because loop iteration and coordinate conversion
  have different critical paths. We should not adopt clock switching here, but
  the underlying insight is useful: different phases should not be forced into
  the same slow schedule if a simple local schedule split can avoid it.

Transfer to VV16:

```text
Balance the fold producer and consumer so previous-leaf folding completes
by the time the next leaf needs XOR0/reduced state.
Use independent linear subexpressions only when they are fixed templates.
Do not add a second fold datapath unless its utilization is demonstrably high.
```

The key lesson is that good scheduling aligns completion times across paths,
instead of letting one short path idle or adding hardware for a path that will
mostly wait.

## 3. Synthesis: principles for VV16

The five papers converge on the same architecture-level lesson:

```text
low area + lower cycles comes from useful reuse, local bypass, and fixed schedules
not from building a second generic datapath
```

VV16 should follow these rules:

1. Reuse XOR0 as the only reduced-field accumulator.
2. Reuse the bit-matrix AND/parity path as the only product-generation fabric.
3. Convert dynamic fold logic into legal-path micro-templates.
4. Introduce only local token/register state whose utilization is high.
5. Use capture/control slots that already exist before adding new issue width.
6. Measure every step against `Logic LUT < 4700`, `Fmax >= 200 MHz`, PMUL cycle
   reduction, and regression correctness.

This also preserves the paper story:

```text
HDC/ECC share one bit-matrix data substrate
ECC multiplication uses the shared matrix product path
ECC reduction is scheduled as matrix-template folding
XOR0 remains the shared GF(2) accumulation point
cycle reduction comes from schedule/dataflow co-design, not duplicate ECC units
```

## 4. VV16 proposed architecture: fold-shadow micro-scheduler

The first VV16 attempt should not be another VV14-1-style group-level dynamic
direct fold. The new target is a `fold-shadow micro-scheduler`.

### 4.1 Main idea

Current leaf-level folding uses:

```text
ecc_kpd64_fold_word_contrib(mask, half_word, leaf128_product)
ecc_kpd64_fold_reduce_packet(mask, fold_word, leaf128_product)
ecc_kpd64_leaf_reduce_packet(mask, leaf128_product)
S_ECC_LEAF_FOLD
XOR0 accumulation / product pair writeback
```

VV16 should split this work into small fold tokens:

```text
fold_token = {leaf_path_template, fold_word_idx, leaf128_product or selected word slice}
```

Then consume one token during later diagonal-capture/control windows when XOR0
is otherwise available:

```text
capture current/next diagonal product
+ consume previous leaf's fixed fold token through XOR0
```

The fold token should use the existing `ecc_kpd64_fold_reduce_packet` style,
but with a fixed legal path template selected by leaf path. The important area
optimization is to avoid evaluating a fully dynamic mask/sub/group function in
the hot path.

### 4.2 Why this differs from VV14-1

VV14-1 tried:

```text
diagonal group parity row
-> dynamic direct leaf-delta matrix
-> dynamic group-level modular folding packet
-> XOR0
```

That proved correctness but made wide mux/XOR logic too heavy. VV16 instead
tries:

```text
completed leaf/sub product
-> fixed fold-word token
-> scheduled through existing XOR0 during later capture/control slots
```

This is less aggressive than true same-cycle diagonal-group folding, but it is
more likely to reduce both area and cycles because:

- the fold transform is already proven by the leaf reducer;
- only one fold word is active per token;
- the legal path template is finite;
- the XOR0 accumulator is reused;
- no new diagonal AND/parity fabric is added.

### 4.3 Expected first-order cycle effect

`S_ECC_LEAF_FOLD` is currently 256608 sampled cycles. It cannot all disappear
in one step because final flush, write hazards, and reduced-result visibility
still matter. But even hiding one fold word per following capture/control slot
can convert a large part of leaf-fold drain into background work.

Near-term target:

```text
VV15                 : 339100 cycles, 4655 Logic LUT
VV16-A target         : 315k-325k cycles, Logic LUT <= 4700, Fmax >= 200 MHz
VV16-B stretch target : 300k-315k cycles, Logic LUT <= 4700, Fmax >= 200 MHz
Do not accept         : lower cycles with Logic LUT > 4700 or Fmax < 200 MHz
```

The target is intentionally conservative. The purpose is to find a schedule
that scales, not a one-off cycle win that recreates VV14-1's area problem.

## 5. Concrete VV16 implementation phases

### Phase A: template equivalence guard

Before changing the scheduler, add a verification-only equivalence check:

```text
for every legal KPD64 leaf path
for fold_word = 0..3
for directed/random leaf128 products
    template_fold_packet(path, fold_word, leaf128)
    must equal current ecc_kpd64_fold_reduce_packet(mask(path), fold_word, leaf128)
```

This can start as a small SystemVerilog testbench or an internal assertion under
debug guard. No synthesis result is meaningful until this equivalence passes.

Acceptance:

```text
reduce regression PASS
add regression PASS
PMUL profile PASS
HDC full flow PASS
```

### Phase B: one-token shadow fold

Add minimal state:

```text
ecc_fold_shadow_valid_q
ecc_fold_shadow_word_q
ecc_fold_shadow_path_q
ecc_fold_shadow_leaf128_q
```

Initial schedule:

```text
on leaf product complete:
    enqueue fold_word 0
during following diagonal-capture/control-safe slot:
    send fold_word token through existing XOR0 packet path
    advance fold_word
after fold_word 3:
    clear valid
```

Rules:

- The token may not consume XOR0 in cycles where another reduced update is
  architecturally required.
- If a hazard exists, fall back to the existing `S_ECC_LEAF_FOLD` drain.
- Keep final flush behavior explicit; do not assume the next leaf exists.
- Do not add another packet accumulator.

Expected result:

```text
some leaf-fold cycles move into otherwise useful capture/control cycles
area growth limited to one leaf token and small control
```

### Phase C: fixed-path template specialization

Once Phase B is correct, replace dynamic mask selection with a finite template:

```text
9 legal leaf paths
4 fold_word positions
fixed lane placement for 4x64 packet
```

Implementation preference:

```text
case (leaf_path_id)
  legal_path_0: fixed shifts/XORs
  ...
endcase
```

or a compact constant-control function if Vivado maps it better. The goal is
not to create a large ROM table. The goal is to prevent synthesis from building
a general path/sub/group mux network.

Acceptance:

```text
Logic LUT must not exceed Phase B.
Fmax must stay >= 200 MHz.
Template and current fold reducer must remain equivalent.
```

### Phase D: write-pair bypass

After fold hiding, attack `S_ECC_WRITE_PAIR`.

Try a one-entry local result bypass:

```text
pending_write_valid_q
pending_write_addr_q
pending_write_packet_q
```

If the next ECC load reads the same logical destination before the pair has
been physically written, feed it from the pending write value. This follows the
same paper lesson as local pipeline taps: avoid a memory round trip when the
producer value is already local.

Rules:

- Do not add a second VRF write port.
- Do not duplicate the full product-pair buffer.
- Flush pending writes only at architectural boundaries.

Acceptance:

```text
PMUL cycles drop in S_ECC_WRITE_PAIR or copy/add phase
no HDC-visible semantic change
Logic LUT <= 4700
```

### Phase E: only then evaluate diagonal-pair issue

A group-pair or diagonal-pair design is allowed only if it reuses the same
bit-matrix fabric. The first acceptable form is not "two full group products".
The acceptable form is:

```text
one matrix payload cut
two fixed linear observations of that payload
one shared XOR0/token consumer
```

Reject immediately if the implementation duplicates the AND/parity plane or
adds a second wide direct fold packet.

## 6. Anti-patterns to avoid

1. Do not return to a fully dynamic direct group-fold packet.
2. Do not add a second XOR0 accumulator.
3. Do not duplicate diagonal AND/parity fabric.
4. Do not add broad path/sub/group muxing in front of the reducer.
5. Do not accept a cycle win that pushes Logic LUT above 4700.
6. Do not use clock switching or multi-frequency control in this CVA6/HDEC
   integration path.
7. Do not add BRAM/precomputation for this step; it weakens the HDC/ECC shared
   matrix story.

## 7. First VV16 experiment checklist

1. Start from pushed VV15.
2. Add fold-template equivalence guard.
3. Implement one-token shadow fold with fallback to existing `S_ECC_LEAF_FOLD`.
4. Run:

```text
xsim reduce
xsim add
xsim hdc_full
xsim pmul_profile
Vivado OOC hdec_top at 5 ns
```

5. Record:

```text
PMUL wall cycles
state bucket cycles
Logic LUT
FF
Fmax estimate
top timing endpoint
```

6. Decide:

```text
accept if cycles reduce and Logic LUT <= 4700 and Fmax >= 200 MHz
iterate template/control if area rises
abandon if it recreates VV14-1 dynamic mux growth
```

## 8. Paper-facing story if VV16 succeeds

If VV16 works, the manuscript story becomes much stronger:

```text
Existing ECC hardware literature lowers latency by careful schedule/dataflow co-design:
pipeline taps, local registers, ROM-like micro-control, fixed DFGs, and high-utilization shared units.

Our contribution transfers that principle into an HDC/ECC shared bit-matrix processor:
ECC multiplication and modular reduction are not standalone accelerators.
They are scheduled as bit-matrix products and fixed GF(2) folding templates over the same XOR0 fabric.
```

The novelty should be framed as:

```text
unified HDC/ECC bit-matrix substrate
+ finite-template modular folding
+ shadow scheduling of linear reduction tokens
+ low-area reuse of XOR0 and existing packet lanes
```

This is more defensible than claiming that VV14-1 already completed ideal
diagonal-group fusion. VV14-1 proved the mathematical feasibility. VV15/VV16
should turn it into a low-area, schedule-driven architecture.

