# ECC V3 reuse innovation study

Date: 2026-06-09

Remote branches checked:

- V3 latest: `origin/hdec-ecc-diagonal-parallel-v3` at `51c4132b`
- V2 base: `origin/hdec-ecc-vrf-control-v2` at `2d44e9e3`

V3 only adds `docs/hdec/ecc/ecc_diagonal_popcount_reuse_v3_note.md`.
The RTL is still V2 RTL. This note is an architecture-level response to the
current weakness of the V3 plan: diagonal parity is a clean story, but it still
turns one field multiplication into 511 product-bit reductions and makes true
multi-diagonal parallelism expensive.

## 1. Short verdict

Do not make "4 diagonals in flight" the central V3 contribution. That is a
control/pipeline clean-up, not a new multiplication architecture.

The cleaner V3 story should be:

1. Keep the diagonal/popcount multiplier as the baseline and ablation path.
2. Add on-the-fly modular reduction so diagonal V3 never stores a 511-bit
   raw product unless explicitly requested for debug.
3. Make the main ECC path a `D4` digit-serial GF(2^m) multiplier:
   four bits of the multiplier per iteration, direct modular reduction, no
   carry, no 511 partial-product storage.
4. Reuse HDEC more broadly: Boolean/XOR, HPERM shift-align, VRF registered
   command boundary, and optionally parity taps from the HSIM popcount slice.

In one sentence:

```text
V3 should become an HDEC-native GF(2) vector arithmetic overlay, not only a
popcount-parity diagonal multiplier.
```

## 2. What V3 gets right and where it stalls

The V3 note correctly observes that HSIM/HMATCH and ECC diagonal multiply share
a Boolean-vector reduction form:

```text
HSIM/HMATCH:
  bool[i] = A[i] XOR B[i]
  result  = integer popcount(bool)

ECC diagonal:
  bool[i] = A[i] AND B_window[i]
  result  = parity(bool) = popcount(bool)[0]
```

This is a valid reuse argument. It also matches the existing V1 RTL choice:
generate `ecc_partial_vec = A & B_window` outside the P2 pop slice and feed it
as `src_a`, with `src_b = 0`. That avoids adding a wide AND/XOR mode mux inside
the P2 popcount path.

The problem is not correctness. The problem is granularity:

- A 256x256 raw polynomial product has 511 diagonals.
- Current V1 uses 511 product-bit reductions and writes two 256-bit VRF entries.
- V3 pipelining can reduce a 3-cycle diagonal loop toward 1 diagonal/cycle, but
  it cannot remove the 511-diagonal algorithmic cost.
- True 4-diagonal-per-cycle compute needs roughly four independent 256-bit
  Boolean/reduction datapaths or an equivalent packed-parity network. Metadata
  "in flight" does not create compute parallelism.

So the diagonal path is worth keeping, but it should not be the only V3 plan.

## 3. Timing and area constraints from the current HDEC base

The V2 OOC report is the most relevant timing anchor:

| Snapshot | 200 MHz WNS | Est. Fmax | LUT | FF | Notes |
|---|---:|---:|---:|---:|---|
| ECC V1 final before V2 boundary | -0.166 ns | 193.573 MHz | 5211 | 2952 | Worst path was control into VRF LUTRAM port |
| ECC VRF control V2 | +0.069 ns | 202.799 MHz | 5476 | 3275 | VRF command boundary registered |

Implication:

- Do not re-open a direct combinational path from new ECC scheduler logic to
  VRF LUTRAM ports.
- Do not insert a wide mode mux directly into the hot P2 popcount cone unless
  OOC proves it.
- Prefer local ECC shadow registers plus already-registered VRF commands.
- Preserve balanced stages; previous HDEC timing work showed that making one
  stage smaller can simply move the critical path into the next stage.

## 4. Route A: improve diagonal V3, but cap expectations

This is the safest incremental route.

### A1. Keep V1's partial-vector entry

Prefer:

```text
ecc_partial_vec = A_segment & B_window_segment
pop_src_a       = ecc_partial_vec
pop_src_b       = 0
```

over:

```text
pop_slice mode mux: XOR or AND
```

Reason: the first option keeps the new AND logic outside the established
HSIM/HMATCH P2 path. It still reuses the same popcount/parity backend.

### A2. Add parity taps

The popcount slice currently captures two 32-bit counts per lane. For ECC,
only these bits are needed:

```text
lane_parity = popcount_part_q[0][0] XOR popcount_part_q[1][0]
diag_parity = XOR over four lane_parity values
```

Expose this as a named `parity_o` sideband. That is clearer in RTL and avoids
spreading `count[0]` assumptions through the scheduler.

### A3. Pipeline issue/result

Replace:

```text
ISSUE -> WAIT -> ACCUM
```

with:

```text
cycle n:   issue k
cycle n+1: issue k+1, collect k
cycle n+2: issue k+2, collect k+1
```

Needed registers:

- `ecc_issue_valid_q`
- `ecc_result_valid_q`
- `ecc_k_pipe_q`
- optional `ecc_last_in_word_pipe_q`

Expected result: diagonal throughput approaches one product bit per cycle after
pipeline fill.

### A4. Do on-the-fly modular reduction

Do not materialize 511 product bits in normal ECC mode.

For a field polynomial:

```text
f(x) = x^m + x^r + 1
```

when product bit `p[k]` arrives:

```text
if k < m:
    R[k] ^= p[k]
else:
    R[k-m] ^= p[k]
    R[k-m+r] ^= p[k]
```

For pentanomials, fold to four low positions. This keeps storage to one
field-sized accumulator and removes the "511 partial products in memory" problem.

### A5. Verdict on Route A

Route A is a good V3.1 patch and a good paper ablation. It is not the most
elegant final ECC integration because the algorithm still spends up to 511
Boolean reductions per multiply.

## 5. Route B: HDEC-native `D4` digit-serial multiplier

This is the recommended main innovation.

Instead of computing product diagonals:

```text
p[k] = parity_i(A[i] & B[k-i])
```

use a digit-serial LFSR/comb multiply:

```text
R = 0
Awork = A
for t in 0..ceil(m/4)-1:
    d = B[4*t +: 4]
    R ^= select(d, Awork, x*Awork, x^2*Awork, x^3*Awork)
    Awork = x^4 * Awork mod f(x)
```

Run it constant-time: never skip an iteration based on `d`.

### Why this fits HDEC

HDEC already has the operators this form wants:

| Need in `D4` multiply | Existing HDEC reuse point |
|---|---|
| field add is XOR | HBIND / Boolean XOR path |
| multiply by `x^4` | HPERM-style 4-bit shift-align, changed to zero-fill plus polynomial fold |
| 256-bit state | one VRF entry = 4 lanes x 64 bits |
| 4-bit digit cadence | existing `hdec_lane_shift_align` is nibble-granular |
| scheduler isolation | V2 registered VRF command boundary |

This changes the reuse story from "ECC borrows HSIM popcount" to:

```text
ECC is a second user of the HDEC lane vector ALU:
XOR, shift-align, VRF, and optional parity/popcount reduction.
```

That is broader and stronger.

### Cycle estimate

For `m = 256`:

| Design | Main loop granularity | Approx compute loop |
|---|---:|---:|
| V1 diagonal, no pipeline | 1 product bit / about 3 cycles | about 1533 cycles plus loads/writes |
| V3 diagonal pipeline | 1 product bit / cycle | about 511 cycles plus loads/writes |
| `D1` bit-serial modular multiply | 1 multiplier bit / cycle | 256 cycles |
| `D4` nibble-serial modular multiply | 4 multiplier bits / cycle | 64 cycles |
| `D8` byte-serial modular multiply | 8 multiplier bits / cycle | 32 cycles, but larger selector/fold logic |

Even if `D4` needs two cycles per digit after conservative staging, it is still
around 128 cycles, which is better than the diagonal pipeline and avoids raw
product storage.

### Hardware sketch

Shadow state:

```text
ecc_a_work_q [255:0]
ecc_b_q      [255:0]
ecc_r_q      [255:0]
ecc_digit_q  [3:0]
ecc_iter_q   [5:0]   // 0..63 for m=256
```

One iteration:

```text
d  = ecc_b_q[3:0]
p0 = d[0] ? ecc_a_work_q        : 0
p1 = d[1] ? xtime(ecc_a_work_q) : 0
p2 = d[2] ? xtime2(ecc_a_work_q): 0
p3 = d[3] ? xtime3(ecc_a_work_q): 0
pp = p0 ^ p1 ^ p2 ^ p3

ecc_r_next      = ecc_r_q ^ pp
ecc_a_work_next = xtime4(ecc_a_work_q)
ecc_b_next      = ecc_b_q >> 4
```

`xtime`, `xtime2`, `xtime3`, and `xtime4` are sparse shift-XOR maps determined
by the irreducible polynomial. For NIST B-233, the reduction polynomial is
`x^233 + x^74 + 1`; for an HDEC-native 256-bit field, choose a sparse
irreducible polynomial and document the security implications.

### Area/timing expectation

Compared with V1 diagonal shadow state:

- FF is similar or slightly lower: V1 already has `A`, `B`, `B_window`, and
  `ecc_word`; `D4` needs `Awork`, `B`, and `R`.
- LUT increases from masked XOR selection and `xtime4` fold taps, but removes
  pressure to build/shift a 256-bit diagonal window for 511 positions.
- The critical path can be staged as:
  1. digit select and `xtime1/2/3`,
  2. XOR into accumulator and `xtime4` update,
  3. VRF final write.

This is friendlier to 200 MHz than true four-diagonal parallel popcount.

### Why this solves the "511 partial products" issue

The accumulator is field-sized. There is no raw 511-bit product in the normal
path and no per-diagonal output storage. The algorithm computes the modular
field product directly.

For debug or paper comparison, a raw 512-bit version can be retained by making
`R` 512 bits and replacing modular `xtime4` with raw left shift. That should be
a separate debug opcode, not the normal ECC multiply.

## 6. Route C: true high-throughput shared Boolean-reduction engine

This route is only worthwhile if we explicitly improve HDC throughput too.

### C1. Real 4-diagonal parallelism

To compute four full diagonals in one cycle, each output bit needs a different
B window:

```text
k, k+1, k+2, k+3
```

The same A bits are reused, but the design still needs four independent
AND/reduction views of the B window. That implies one of:

- four popcount/parity slices,
- one wider packed-parity reducer,
- or four cycles internally hidden by a deeper lane pipeline.

So this is not a free use of the existing four lanes.

### C2. Make the extra hardware useful for HDC

If we replicate Boolean/reduction hardware, use it for HDC as well:

```text
HDC HMATCH batch mode:
  query chunk is broadcast
  2 or 4 cached prototype chunks are compared in parallel
```

This needs a small prototype window buffer; VRF bandwidth otherwise blocks the
benefit. A two-way batch is likely the sweet spot before a four-way batch.

### C3. Suggested hardware block

Define a shared `hdec_bool_reduce_slice`:

```text
bool_op:
  XOR   -> HDC distance
  AND   -> ECC diagonal parity
  MUXOR -> digit-serial masked XOR contribution

reduce_op:
  COUNT  -> HSIM/HMATCH
  PARITY -> ECC
  PASS   -> HBIND/HDC XOR payload
```

Keep the mode select at the local slice boundary, not at the VRF port boundary.

### C4. Verdict on Route C

This is a strong research branch if the paper needs a high-throughput PPA
point. It is not the best first V3 RTL patch because it adds routing, buffering,
and verification complexity at the same time.

## 7. Recommended V3 roadmap

### Milestone 1: diagonal pipeline plus reduction

Purpose: preserve continuity with current V3 and get a clean ablation.

Deliverables:

- `parity_o` sideband on P2 pop slice.
- ECC k/result alignment queue.
- on-the-fly reduction accumulator.
- OOC 200 MHz and xsim versus Python model.

### Milestone 2: `D4` digit-serial modular multiplier

Purpose: main ECC improvement.

Deliverables:

- Python reference for `D1`, `D4`, and diagonal.
- standalone `ecc_xtime4_fold` module for target polynomial.
- ECC multiply opcode variant or compile-time switch.
- constant-time masked digit selection.
- OOC comparison against Milestone 1.

### Milestone 3: HDC/ECC shared operator refinement

Purpose: make reuse visible, not just rhetorical.

Deliverables:

- `hdec_bool_reduce_slice` interface definition.
- route HSIM/HMATCH through COUNT mode and ECC through PARITY/MUXOR mode.
- no change to VRF command boundary.

### Milestone 4: optional HDC high-throughput batch mode

Purpose: justify extra parallel hardware if Route C is pursued.

Deliverables:

- 2-way HMATCH class-window cache.
- compare one query chunk with two prototype chunks per compute issue.
- show HDC throughput benefit and ECC diagonal benefit with the same added block.

## 8. Side-channel and scheduling notes

For ECC, constant-time matters:

- Do not skip digit iterations when `d == 0`.
- Do not let scalar-dependent control decide whether ECC consumes a shared HDEC
  resource.
- HDC may preempt ECC at micro-op boundaries, but preemption must depend on HDC
  traffic, not secret scalar bits.
- If HDC-visible latency is observable, publish ECC as a background best-effort
  accelerator only after documenting the leakage boundary.

## 9. Literature map

The following papers and source pages were checked as the literature base. The
first group is directly about binary-field ECC/GF(2^m) arithmetic; the second
group supports the HDC reuse story.

| # | Source | Why it matters here |
|---:|---|---|
| 1 | Pusuluri et al., 2026, "An area-efficient and low-latency GF(2m) multiplier for FPGA applications", Integration, [ScienceDirect](https://www.sciencedirect.com/science/article/abs/pii/S0167926026001240) | Recent FPGA GF(2^m) multiplier; confirms multiplication dominates ECC cost and sparse-polynomial reduction is central. |
| 2 | Bahri et al., 2026, "Advanced VLSI ECDSA design for real-time blockchain-based IoT system applications", [Springer](https://link.springer.com/article/10.1007/s44291-026-00172-4) | Full ECDSA over GF(2^163); useful system-level area/frequency comparison. |
| 3 | Kumari et al., 2025, "An Efficient Hardware Implementation of Elliptic Curve Point Multiplication over GF(2^m) on FPGA", [arXiv](https://arxiv.org/abs/2506.12359) | Recent ECPM design using hybrid Karatsuba; multiplier is the bottleneck. |
| 4 | Kumari et al., 2025, "Efficient Hardware Implementation of Modular Multiplier over GF(2m) on FPGA", [arXiv](https://arxiv.org/abs/2506.09464) | Hybrid conventional/Karatsuba modular multiplier for NIST B-163/233/283/571. |
| 5 | Gupta et al., 2025, "A Comparison of 163-bit Hybrid Karatsuba Multiplier and Word-Serial Multipliers for ECC Processors", [ResearchGate page](https://www.researchgate.net/publication/389428629_A_Comparison_of_163-Bit_Hybrid_Karatsuba_Multiplier_and_Word-Serial_Multipliers_for_ECC_Processors) | Shows the area/speed tradeoff between word-serial and Karatsuba styles. |
| 6 | Zhao et al., 2024, "High-performance unified modular multiplication algorithm and hardware architecture over GF(2^m)", Integration, [ScienceDirect](https://www.sciencedirect.com/science/article/pii/S0167926023001669) | Unified NIST-field support; relevant to configurable reduction. |
| 7 | Aljaedi et al., 2024, "FPGA implementation of elliptic-curve point multiplication over GF(2^233) using Booth polynomial multiplier", IEEE Access, [QUB/DOI](https://pure.qub.ac.uk/en/publications/fpga-implementation-of-elliptic-curve-point-multiplication-over-g/) | Booth/digit-serial style validates the Route B direction. |
| 8 | Zhang et al., 2024, "Modular Inversion Architecture on GF(2^m) Based Optimal Exponentiation Blocks", [BIT journal page](https://journal.bit.edu.cn/zr/en/article/doi/10.15918/j.tbit1001-0645.2024.061) | ITA inversion uses multiplication/exponentiation blocks; useful for later ECC stack. |
| 9 | Aftowicz et al., 2024, "Non-Profiled Unsupervised Horizontal Iterative Attack against Hardware ECSM", [MDPI](https://www.mdpi.com/1999-5903/16/2/45) | Reminds that Montgomery ladder regularity is not enough if microarchitecture leaks. |
| 10 | Ibrahim and Gebali, 2024, "Enhancing Field Multiplication in IoT Nodes with Limited Resources", [MDPI](https://www.mdpi.com/2076-3417/14/10/4085) | Surveys bit-parallel/serial/digit-serial/systolic tradeoffs for GF(2^m). |
| 11 | Rashid et al., 2023, "Throughput/Area-Efficient Accelerator of ECPM over GF(2^233) on FPGA", [MDPI](https://www.mdpi.com/2079-9292/12/17/3611) | Area/throughput comparison point for binary-field ECPM. |
| 12 | Arif et al., 2023, "A Unified Point Multiplication Architecture of Weierstrass, Edward and Huff Curves on FPGA", [MDPI](https://www.mdpi.com/2076-3417/13/7/4194) | Unified curve architecture; useful when arguing algorithm-level flexibility. |
| 13 | Aljaedi et al., 2023, "An Optimized Flexible Accelerator for ECPM over NIST Binary Fields", [MDPI](https://www.mdpi.com/2076-3417/13/19/10882) | Flexible NIST binary-field accelerator; supports configurable-field discussion. |
| 14 | "Digit-Size Selection for FPGA Implementation of Generic Digit-Serial Multiplication over GF(2m)", 2023, [ResearchGate page](https://www.researchgate.net/publication/375055630_Digit-Size_Selection_for_FPGA_Implementation_of_Generic_Digit-Serial_Multiplication_Over_GF2m) | Directly relevant to choosing D=4 versus D=8. |
| 15 | "Low-complexity systolic array structure for field multiplication in resource-constrained IoT nodes", 2023, [PDF](https://dspace.library.uvic.ca/server/api/core/bitstreams/d07f3028-2510-40c8-a3c8-c82bce103b5c/content) | Low-complexity systolic alternative; useful as Route C comparator. |
| 16 | Nadikuda and Boppana, 2022, "An area-time efficient point-multiplication architecture for ECC over GF(2^m) using polynomial basis", [ScienceDirect](https://www.sciencedirect.com/science/article/abs/pii/S0141933122000813) | Polynomial-basis ECPM area-time baseline. |
| 17 | "Low-latency area-efficient systolic bit-parallel GF(2^m) multiplier for a narrow class of trinomials", 2021, [ScienceDirect](https://www.sciencedirect.com/science/article/abs/pii/S0026269221002615) | Systolic bit-parallel design; useful for high-throughput but higher-area comparison. |
| 18 | "Efficient Fault Detection Architecture of Bit-Parallel Multiplier in Polynomial Basis of GF(2^m) Using BCH Code", 2022, [arXiv](https://arxiv.org/abs/2209.13388) | Reliability/fault-detection angle if ECC hardware becomes security-critical. |
| 19 | Kwon, 2014, "A survey of bit-parallel GF(2^n) multipliers", [ScienceDirect](https://www.sciencedirect.com/science/article/pii/S107157971400121X) | Foundational taxonomy for Mastrovito, bit-parallel, and polynomial-basis multipliers. |
| 20 | Zhang and Parhi, "Systematic design of original and modified Mastrovito multipliers", [University of Minnesota page](https://experts.umn.edu/en/publications/systematic-design-of-original-and-modified-mastrovito-multipliers/) | Foundation for matrix/convolution view; useful to avoid overclaiming "diagonal addition" as new math. |
| 21 | Chen et al., 2023, "Sparsity Controllable HDC for Genome Sequence Matching Acceleration", [IBM Research](https://research.ibm.com/publications/sparsity-controllable-hyperdimensional-computing-for-genome-sequence-matching-acceleration) | HDC accelerators depend on chunked similarity search and hardware-friendly reductions. |
| 22 | Asghari and Le Beux, 2024, "A General Purpose HDC Accelerator for Edge Computing", [CoLab/IEEE metadata](https://colab.ws/articles/10.1109%2Fnewcas58973.2024.10666335) | General-purpose FPGA HDC ISA/coprocessor framing. |
| 23 | Peitzsch et al., 2023, "Multiarchitecture Hardware Acceleration of HDC", [NSF SHREC](https://www.nsf-shrec.org/publications/multiarchitecture-hardware-acceleration-hyperdimensional-computing) | Supports multiarchitecture HDC acceleration and Hamming-heavy workloads. |
| 24 | Chen et al., 2024, "HDReason: Algorithm-Hardware Codesign for Hyperdimensional Knowledge Graph Reasoning", [arXiv](https://arxiv.org/abs/2403.05763) | Recent FPGA HDC co-design; useful for arguing reusable HDC datapath evolution. |
| 25 | Xu et al., 2025, "HPVM-HDC", ISCA 2025, [PDF](https://www.russelarbore.com/ISCA2025_HPVM-HDC_CameraReady.pdf) | HDC acceleration as a heterogeneous programming target; supports keeping HDC first-class. |
| 26 | Wang et al., 2024, "A Computing-in-Memory-based One-Class HDC Model", [arXiv](https://arxiv.org/abs/2311.17852) | Shows HDC speed/energy comes from moving Boolean similarity near storage. |

## 10. Final recommendation

For the next V3 RTL branch, implement two things in this order:

```text
1. Diagonal pipeline + on-the-fly reduction
2. D4 digit-serial modular multiply
```

Then compare:

```text
cycles, LUT, FF, WNS, HDC HSIM/HMATCH regression, and leakage-sensitive control
```

If the `D4` engine hits the expected 64-128 cycle range at roughly V1-like area,
it should become the main ECC multiplier. The diagonal popcount engine should
remain as a nice proof that HSIM popcount can compute GF(2) dot-product parity,
but the final "elegant ECC inside HDEC" story is stronger when ECC reuses the
whole HDEC vector lane: VRF, XOR, shift-align, and reduction.
