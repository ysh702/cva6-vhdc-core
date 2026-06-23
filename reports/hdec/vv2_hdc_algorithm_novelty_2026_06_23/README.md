# VV2 HDC Algorithm Novelty Survey and HDC-Only Contribution Points

Date: 2026-06-23

Branch: `hdec-vv2-area-ecc-control`

Scope: this note records the current literature boundary and the safest HDC-only novelty claims for the VV2 HDEC work. It is intentionally a report-only artifact; it does not change RTL, scripts, or experiments.

## 1. Executive conclusion

The current HDC part has publishable innovation potential, but the claim must be positioned carefully.

The unsafe claim is:

> We propose the first binary, low-dimensional, self-learning HDC algorithm.

This is not safe because binary HDC, low-dimensional/quantized HDC, stochastic training, online HDC, adaptive retraining, confidence-threshold updates, and margin-based updates have all appeared in prior work.

The safer and stronger claim is:

> We propose a hardware-constrained 1024-dimensional binary HDC learning flow for edge-side train-and-infer execution. The flow co-designs binary encoding, bounded prototype accumulation, threshold clipping, and Hamming-distance matching with a compact RISC-V HDEC instruction/datapath substrate. Its novelty is not in any single classical HDC primitive, but in turning the full HDC learning flow into a low-storage, low-control, bit-parallel hardware-native algorithm path.

For the full HDEC paper, the strongest overall story remains HDC plus ECC shared binary hardware. However, this note focuses on HDC-only novelty.

## 2. Evidence from the current VV2 branch

The current branch already contains concrete HDC architectural evidence:

- `core/hdec/rtl/hdec_pkg.sv` fixes the HDC vector width to `HDC_BITS = 1024` and maps each HDC hypervector to `HDC_CHUNKS = 4` VRF entries.
- `core/hdec/rtl/hdec_pkg.sv` defines the train/infer-related HDC instructions `HDEC_HCNTADD`, `HDEC_HCNTCLIP`, and `HDEC_HMATCH`.
- `core/hdec/rtl/hdec_resource_pkg.sv` maps each HDC vector to 4 contiguous 256-bit VRF entries and maps the bundle accumulator to `1024 x 4-bit counters`.
- `docs/hdec/hdc_pipeline.md` records a complete primitive flow: `HBind`, `HBundle4`, `HClip`, `HSim`, and `HMatch`.
- `verif/hdec/hdc_e2e_train_infer_test.S` records a ladder-style train-and-infer self-check, including sample encoding, prototype build, and 4-class inference.

This means the design is not just an inference accelerator. It already has a hardware-visible learning path.

## 3. Prior work boundary

### 3.1 Binary and quantized HDC are not new by themselves

QuantHD proposed a quantization framework for HDC and studied binary/ternary quantized associative memory. It also provides accuracy and dimension-scaling results from high dimensions down to low dimensions.

Implication for our paper: do not claim that binary HDC or quantized HDC is new.

Reference: QuantHD, IEEE TCAD, 2020. DOI: `10.1109/TCAD.2019.2954472`.

PDF: <https://par.nsf.gov/servlets/purl/10169532>

### 3.2 Fully binarized HDC with stochastic training has prior art

SearcHD proposed a memory-centric HDC system and includes fully binarized HDC and stochastic training ideas.

Implication for our paper: do not claim that fully binary class hypervectors or stochastic/binary retraining are new in isolation.

Reference: SearcHD, IEEE TCAD, 2020. DOI: `10.1109/TCAD.2019.2952544`.

PDF: <https://par.nsf.gov/servlets/purl/10169538>

### 3.3 Online/adaptive HDC training has prior art

OnlineHD proposed an online HDC learning approach for efficient single-pass learning. AdaptHD studied adaptive efficient training for HDC. Both overlap with broad "self-learning" or "online update" wording.

Implication for our paper: do not simply say "we introduce self-learning HDC". That wording is too broad.

References:

- OnlineHD, DATE 2021. PDF: <https://past.date-conference.com/proceedings-archive/2021/pdf/1078.pdf>
- AdaptHD, BioCAS 2019. PDF: <https://si2.epfl.ch/~demichel/publications/archive/2019/BioCAS_AdaptHD.pdf>

### 3.4 Confidence-threshold and margin-based HDC updates have prior art

There are HDC training works that update the model only when the prediction confidence is low or when the decision margin is not sufficient.

Implication for our paper: if our self-learning rule is based on confidence, margin, or misclassification-triggered updates, we must compare against these ideas and avoid claiming the update trigger itself as entirely new.

References:

- Training a Hyperdimensional Computing Classifier Using a Threshold on Its Confidence, Neural Computation, 2023. arXiv: <https://arxiv.org/abs/2305.19007>
- Margin-Based Training of Hyperdimensional Computing Classifiers, Big Data and Cognitive Computing, 2025. DOI: `10.3390/bdcc9030068`. Link: <https://www.mdpi.com/2504-2289/9/3/68>

### 3.5 Trainable encoders and adaptive HDC learning have prior art

TrainableHD studied trainable encoding and adaptive training for efficient and accurate HDC.

Implication for our paper: do not claim that trainable or adaptive HDC is new unless the exact proposed rule is clearly different.

Reference: TrainableHD, ACM TODAES, 2024. DOI: `10.1145/3665891`.

PDF: <https://par.nsf.gov/servlets/purl/10531073>

### 3.6 HDCU is a good hardware baseline, but not an algorithm-accuracy baseline

The HDCU paper is highly relevant because it is a RISC-V HDC extension supporting both training and inference. However, it is mainly a configurable HDC hardware extension and should be treated as a hardware baseline rather than the main algorithm-accuracy comparison.

Implication for our paper: use HDCU to compare hardware support and train/infer coverage, but use QuantHD/SearcHD/OnlineHD/AdaptHD/TrainableHD-style works to delimit algorithm novelty.

Reference: Configurable Hardware Acceleration for Hyperdimensional Computing Extension on RISC-V, IEEE Transactions on Computers, 2026.

Link: <https://ieeexplore.ieee.org/document/11297171/>

## 4. Suitable HDC-only innovation points

### 4.1 Hardware-constrained 1024D binary HDC learning flow

This is the most suitable HDC-only contribution.

The contribution is not "1024D exists". The contribution is that the algorithm is explicitly constrained by edge hardware:

- 1024-bit binary hypervectors rather than accuracy-first 10000D models.
- 4 chunks per hypervector, matching the 4 x 256-bit VRF execution pattern.
- Prototype learning through bounded per-bit counters instead of large floating-point or high-precision accumulators.
- Threshold clipping into binary class prototypes.
- Hamming-distance matching as the inference primitive.

Suggested claim:

> We formulate a 1024D binary HDC train-and-infer flow whose data representation, prototype accumulation, and matching are all constrained by the target edge-side vector-register organization.

Why this is useful:

- It explains why 1024D is a principled hardware point, not an arbitrary accuracy compromise.
- It distinguishes the work from 10000D software-first HDC.
- It gives a clean bridge from algorithm to RTL.

Required evidence:

- Accuracy curves at `D = 1000/1024/2000/4000/8000/10000`.
- SRAM/cycle/area scaling with dimension.
- Accuracy comparison against software HDC baselines at the same dimension.

### 4.2 Bounded-counter prototype learning for compact on-device training

The current branch maps the bundle accumulator to `1024 x 4-bit counters`. This can be positioned as a compact prototype-learning mechanism for binary HDC.

Suggested claim:

> We replace high-precision prototype accumulation with a bounded low-bit counter-and-clip path, enabling on-device prototype construction with small storage overhead.

Important boundary:

- Majority bundling and threshold clipping are classical HDC operations.
- The contribution is the bounded, hardware-native realization and its measured accuracy/area tradeoff.

Required evidence:

- Compare 4-bit counters with wider counters or software integer counters.
- Show that bounded counters preserve accuracy on target datasets.
- Show the storage reduction versus full integer prototype accumulation.

### 4.3 Train-and-infer unification as an instruction-visible HDC primitive set

The current HDC primitive set is not limited to inference. `HCNTADD`, `HCNTCLIP`, and `HMATCH` form a compact path from sample accumulation to prototype generation and class matching.

Suggested claim:

> We expose HDC training and inference as a small set of instruction-visible primitives, reducing the need for separate training and inference engines.

Why this can stand:

- HDCU also supports training and inference, so "supporting both" is not enough.
- The defensible angle is the compact instruction/data-path formulation for 1024D binary HDC under a small VRF and low-bit accumulator.

Required evidence:

- Instruction count and cycle count for training and inference primitives.
- Comparison with software-only RISC-V HDC.
- Comparison with HDCU at the architectural level where possible.

### 4.4 Self-learning should be claimed only after its exact rule is frozen

If the self-learning rule is just "update after misclassification", "update when confidence is low", or "update when margin is small", it overlaps with prior work.

A safer interim claim is:

> We implement an on-device self-learning path compatible with bounded binary prototypes and low-bit hardware accumulation.

If the final update rule has a specific difference, for example asymmetric prototype updates, bounded counter saturation, data-dependent thresholding, or a hardware-constrained update schedule that is not in prior work, then it can become a stronger HDC algorithm contribution.

Required evidence:

- Pseudocode of the exact update rule.
- Ablation against no-update HDC.
- Ablation against misclassification-only update.
- Ablation against confidence/margin update if applicable.
- Accuracy and update count on each dataset.

## 5. Claims to avoid

Avoid these claims unless new evidence is added:

- "First binary HDC".
- "First low-dimensional HDC".
- "First self-learning HDC".
- "First train-and-infer HDC accelerator".
- "First confidence-based HDC update".
- "First margin-based HDC update".
- "First RISC-V HDC extension supporting training and inference".

These claims are too broad and will likely be challenged by prior work.

## 6. Recommended experimental proof plan

The accuracy proof should be done in Python first, not RTL first.

Python should prove the algorithm:

- Dataset-level accuracy.
- Dimension scaling.
- Update-rule ablation.
- Counter-width sensitivity.
- Random seed stability.

RTL should prove the hardware:

- Bit-exact equivalence to the Python 1024D model.
- Cycle count for `HCNTADD`, `HCNTCLIP`, and `HMATCH`.
- Area/timing/power after synthesis.
- Full train-and-infer hardware correctness.

Recommended table:

| Experiment | Purpose | Expected use in paper |
|---|---|---|
| 1000/1024/2000/4000/8000/10000D Python curve | Show why 1024D is a reasonable edge point | HDC algorithm evaluation |
| No-update vs our update | Show self-learning benefit | HDC algorithm ablation |
| Existing update rule vs our update | Show novelty beyond prior self-learning HDC | HDC algorithm comparison |
| 4-bit vs 8-bit/full counter | Show bounded counter feasibility | Algorithm-hardware co-design |
| Python 1024D vs RTL 1024D | Show bit-exact hardware realization | RTL validation |
| HDC-only vs HDC+ECC | Show system reuse story | Full HDEC contribution |

## 7. Recommended paper wording

Recommended concise contribution statement:

> We propose a hardware-constrained 1024D binary HDC train-and-infer flow for edge devices. The flow maps sample accumulation, prototype binarization, and nearest-class matching onto a compact set of HDEC primitives, using bounded per-bit counters and threshold clipping to avoid high-precision model storage. Unlike software-first high-dimensional HDC, the proposed flow is co-designed with the vector-register layout and bit-parallel datapath, enabling a small-footprint on-device learning path.

Recommended novelty boundary sentence:

> We do not claim novelty for classical HDC binding, bundling, binarization, or Hamming-distance search individually. The novelty lies in their hardware-constrained formulation as a compact 1024D binary learning flow and in the measured algorithm-hardware tradeoff under edge-side storage and cycle constraints.

## 8. Current bottom line

The current HDC-only innovation is real, but it should be framed as algorithm-hardware co-design rather than as a standalone invention of binary/self-learning HDC.

The strongest HDC-only contribution is:

> A 1024D binary HDC train-and-infer flow with bounded-counter prototype learning and threshold-clipped binary class models, designed around a compact VRF/chunk execution pattern for edge-side hardware.

The strongest full-paper contribution remains:

> A shared binary computing substrate where this HDC learning flow and binary-field ECC reuse common bit-vector operations and hardware scheduling resources.

