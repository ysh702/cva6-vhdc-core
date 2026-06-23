# VV3 ECC popcount route and HDC algorithm thinking

Date: 2026-06-23
Branch: hdec-vv3-ecc-popcount-hdc-algo

## 1. Current VV3 candidate kept

The current VV3 RTL candidate is kept as commit `e870e1bc`:

- Change: keep the original ECC diagonal parity route for the low half of each 32x32 leaf, and add a popcount-LSB route for the high half.
- PMUL wall cycles: `190151 -> 158075`, saving `32076` cycles.
- Diagonal state cycles: `96228 -> 64152`, exactly the expected `1/3` diagonal-cycle reduction.
- OOC area: Total LUT `5127 -> 5313`, Logic LUT `4999 -> 5185`, FF `1833 -> 1832`, Fmax `210.393 MHz`.

Conclusion: this is a valid speed candidate, but not an area candidate. It proves that popcount/parity can accelerate polynomial multiplication, but the naive dual-route form costs about `+186` Logic LUT.

## 2. Why the current diagonal method does not fully use HDEC parallelism

For one coefficient of a binary polynomial product:

```
c[k] = parity({ a[i] & b[k-i] | valid i })
```

So every output bit is a GF(2) inner product: many AND terms followed by one parity. Parity can be implemented as XOR reduction, or as `popcount(terms)[0]`.

The current Karatsuba + diagonal implementation computes many such inner products, but each 32x32 leaf still has a diagonal-by-diagonal structure. This is mathematically clean, yet it does not naturally match our strongest HDEC hardware story:

- HDC has wide AND + popcount for overlap score.
- ECC diagonal has many small independent AND + parity cones.
- The naive sharing direction duplicates a second half of diagonal logic, which reduces cycles but increases LUT.

Therefore the better next direction is not "more popcount sidecars". The better direction is to reformulate the 32x32 or 64x64 leaf as a small bilinear circuit whose linear forms, AND products, and recombination are chosen to match our lanes.

## 3. Candidate ECC multiplication algorithms

### 3.1 Shift-XOR / Montgomery-style serial multiplication

This is area-friendly because one shifted partial product is accumulated per step. But it is not a good fit for our goal:

- It uses XOR accumulation heavily.
- It underuses the existing HDC popcount resource.
- It increases or preserves long cycle count.
- It weakens the innovation story because it looks like a conventional bit/digit-serial binary-field multiplier.

### 3.2 Current Karatsuba + diagonal parity

This is our current foundation:

- Karatsuba reduces the number of leaf products.
- Each leaf product is diagonal AND terms plus parity.
- The field product is then folded and reduced.

It is a good correctness and constant-schedule baseline, but the diagonal leaf is not yet HDEC-specific enough.

### 3.3 Mastrovito / bit-parallel polynomial-basis multiplier

Mastrovito-style multipliers combine multiplication and reduction into a matrix-like product. The literature treats the product as AND terms followed by XOR networks, and later work optimizes reduction matrices and intermediate reuse.

This is relevant because it says: instead of first producing a raw 465-bit product and then reducing it, we can precompute which partial products contribute to each reduced output bit.

For HDEC, a full 233-bit bit-parallel Mastrovito multiplier is too large. But a local Mastrovito idea can be used inside a 32x32 or 64x64 leaf: generate only the reduced or fold-needed terms that the next stage uses, not every raw diagonal bit.

### 3.4 Normal basis / Gaussian normal basis

Normal basis is attractive because squaring is just cyclic shift, and adjacent product digits use the same product function with cyclically shifted inputs. This matches pipeline and systolic hardware well.

But adopting it in HDEC would require a representation change or basis-conversion layer. Our ECC point formulas, reduction polynomial, storage layout, and existing tests are all polynomial-basis oriented. So this is a "from-scratch ECC engine" direction, not the best VV3 direction.

### 3.5 Polynomial residue arithmetic

Residue arithmetic splits the product into several independent smaller moduli, computes them in parallel, then recombines. It is theoretically parallel, but it needs residue conversion, multiple residue memories, and recombination control.

This likely increases the exact control/storage area we have been trying to reduce. It is interesting academically, but not the best fit for the current HDEC lane/VRF design.

### 3.6 Peralta/Find-style symmetric bilinear circuits

This is the most promising paper-facing direction.

Binary polynomial multiplication is a bilinear map. It can be implemented as:

```
linear forms of A
linear forms of B
AND products between selected forms
linear recombination by XOR / parity
```

The important point is that the AND gates do not have to be only `a[i] & b[j]`. They can be:

```
(xor of selected a bits) & (xor of selected b bits)
```

Then recombination reconstructs the correct product. Recent circuit-minimization work searches for small Karatsuba-like bilinear circuits with fewer gates and lower depth.

For HDEC, we can make this hardware-aware:

- choose 8x8, 16x16, or 32x32 bilinear kernels whose linear forms fit the 4x64 lanes;
- implement low-Hamming-weight linear forms using the existing lane GF(2) XOR fabric;
- feed the selected AND products into either parity or popcount-LSB;
- choose recombination so output packing matches current product scratch and fold.

This would be a stronger innovation than the naive VV3 sidecar:

> HDEC-specific popcount-assisted bilinear leaf multiplication: a GF(2) multiplier leaf co-designed with HDC overlap hardware, where popcount is not bolted on after the fact, but is part of the chosen bilinear decomposition.

## 4. Recommended ECC next step

Do not expand the current sidecar further. Keep `e870e1bc` as evidence:

- It proves the cycle model.
- It gives a measurable speed/area tradeoff.
- It shows exactly where popcount helps and where naive duplication costs area.

The next serious ECC attempt should be a new leaf kernel:

1. Generate candidate 8x8 or 16x16 GF(2) bilinear circuits offline.
2. Score each candidate by HDEC cost, not just gate count:
   - lane XOR form cost;
   - AND count;
   - popcount/parity fan-in shape;
   - recombination cost;
   - product-scratch write compatibility.
3. Replace only the 32x32 diagonal leaf backend first.
4. Keep Montgomery LD, ITA, PMUL schedule, ISA, and field representation unchanged.

Expected result:

- A naive full parallel leaf may reduce more cycles but cost too much LUT.
- A HDEC-aware bilinear leaf may reduce part of the diagonal cycles with less area than the current `+186` LUT sidecar.
- This gives a more defensible novelty claim than "we added popcount".

## 5. HDC algorithm innovation story

AND-overlap alone is not enough to claim a new HDC algorithm. Sparse binary HDC and dot-product/overlap similarity already exist. Binary HDC and hardware-friendly Hamming inference are also known.

A stronger HDC-only algorithm story is:

## Density-Locked Bounded Prototype Learning (DL-BPL)

### Core idea

Each query vector and each class prototype is forced to have a fixed number of ones.

Let:

```
|q| = Kq
|p_c| = Kp
score(c) = popcount(q & p_c)
```

Then:

```
Hamming(q, p_c) = Kq + Kp - 2 * popcount(q & p_c)
```

Because `Kq` and `Kp` are constant across classes, maximizing AND-overlap is exactly equivalent to minimizing Hamming distance. This removes the density bias that otherwise makes overlap unfair when one class prototype has more ones than another.

### Training

For each class:

1. Encode each sample into a fixed-density query hypervector.
2. Add it into small bounded counters.
3. Clip the class counter vector into a fixed-density prototype by selecting the top `Kp` counter positions.
4. Resolve ties deterministically with a fixed seed/permutation so training is repeatable.

### Self-learning

During deployment:

1. Compute best and second-best class scores.
2. If a human label is available, update the true class when prediction is wrong or confidence is low.
3. If no human label is available, update only when the margin is high enough.
4. After updates, reclip the affected class prototype back to fixed density.

Human participation is therefore not per-operation manual control. It is a teacher signal source: initial labels, occasional correction labels, and chosen confidence thresholds. A testbench can emulate the human by providing ground-truth labels at the same points.

### Why this is HDC algorithm innovation

The algorithm changes the HDC learning rule and prototype constraint:

- ordinary binary HDC: majority prototype + Hamming/XOR distance;
- ordinary sparse HDC: sparse overlap/dot product, often sensitive to density choice;
- DL-BPL: bounded counters + fixed-density top-k prototypes + margin-gated self-learning + AND-overlap inference with a Hamming-equivalence proof.

It is not only hardware reuse. The fixed-density constraint is the mathematical reason the AND-overlap score becomes fair and comparable.

### Hardware fit

DL-BPL maps naturally to current HDEC:

- `HCNTADD`: bounded counter update;
- `HCNTCLIP` or software top-k clip: counter-to-prototype binarization;
- `HMATCH/HSIM`: `popcount(query & prototype)`;
- software scheduler: controls training, top-k, and self-learning policy without adding a large hardware controller.

If exact top-k is too expensive in RTL, it can remain software-scheduled. This still counts as the HDC algorithm, because the hardware executes the primitive operations and the software performs the policy.

## 6. Paper-facing claims to use carefully

Safe claims:

- HDEC introduces an HDC-specific fixed-density bounded prototype learning rule that makes AND-overlap mathematically equivalent to Hamming ranking under constant cardinality.
- HDEC uses software-scheduled hardware primitives for training, self-learning, and inference, avoiding a large monolithic HDC controller.
- HDEC explores a popcount-assisted GF(2) multiplication route and shows a measured PMUL cycle reduction when part of diagonal parity is computed through popcount-LSB.
- The next ECC direction is a hardware-aware bilinear leaf, not a conventional shift-XOR multiplier.

Avoid claiming:

- AND-overlap itself is new.
- Binary HDC itself is new.
- Popcount parity is new.
- The current VV3 sidecar is area-optimal.
- Normal-basis multiplication has already been adopted in the RTL.

## 7. Sources checked

- NIST SP 800-186: binary-field ECC domain parameters and field representation context.
- RISC-V bit manipulation extension: carry-less multiplication and population count definitions.
- Reyhani-Masoleh and Hasan, low-complexity polynomial-basis GF(2^m) multipliers.
- Mastrovito multiplier formulations for general irreducible polynomials.
- Find and Peralta, better circuits for binary polynomial multiplication.
- Literature on normal-basis and Gaussian-normal-basis multipliers.
- BinHD, binary HDC density/similarity work, LifeHD, and HDC expressivity analysis.
