# Hardware-Reuse Literature Survey: LUT/FF Reporting

Date: 2026-06-13
Local repo: `E:\HDEC\cva6-vhdc-core\tmp\hdec_v15_pointmul_worktree`

## Local HDEC Context Read First

Recent local reports use a stricter resource-accounting policy than many papers:

- `agent.md` requires every meaningful optimization to track `Slice LUT`, `Logic LUT`, `LUTRAM`, `FF`, `BRAM`, `DSP`, `CARRY4`, timing, ECC cycles, and HDC regression status.
- `reports/hdec/v23_optimization/README.md` keeps/rejects trials using both LUT and FF, and separates `Logic LUT` from `LUTRAM`.
- `reports/hdec/v22_vivado2024_2_compare/README.md` compares V21/V22 with the same Vivado version and reports `Slice LUT`, `Logic LUT`, `LUTRAM`, and `FF`.
- `reports/hdec/v22_area_reduction_2022_2/README.md` shows that an apparent LUT win with FF growth is still discussed explicitly; it does not hide FF.
- `reports/hdec/v21_10round_area_timebox/README.md` rejects edits that improve one metric but increase area or break timing.

This means HDEC already has the right local table shape for a paper-style comparison.

## Direct Answer

For an HDC/ECC hardware-reuse paper, the defensible comparison is **full top-level resource usage**, not only `Logic LUT`.

Use:

1. HDC-only top: all resources after synthesis/implementation.
2. HDC+ECC shared/integrated top: all resources after synthesis/implementation.
3. Optional but very useful: ECC-only accelerator and naive `HDC-only + ECC-only` sum, to show the benefit of reuse.

Report at least:

- `Slice LUT`
- `Logic LUT`
- `LUTRAM`
- `FF`
- `BRAM`
- `DSP`
- `CARRY4`
- `WNS/Fmax`
- HDC and ECC correctness/performance metrics

Then headline the overhead as:

- `Delta Slice LUT`
- `Delta FF`
- `Delta BRAM/DSP`
- `Delta WNS/Fmax`

Use `Logic LUT` as a diagnostic subcolumn, not as the only area number. Ignoring FF would be hard to defend because many reuse designs reduce combinational logic by adding state, scheduling, operand registers, memories, DSPs, or routing pressure.

## Paper Evidence

### 1. Cryptensor: CNN + Lattice-Cryptography Polynomial Convolution

Source:
https://www.researchgate.net/publication/366382440_Cryptensor_A_Resource-Shared_Co-processor_to_Accelerate_Convolutional_Neural_Network_and_Polynomial_Convolution

Relevant behavior:

- This is the closest match to the HDEC story: CNN and cryptographic polynomial convolution are expressed as GEMM and mapped to the same accelerator.
- The paper explicitly says separate AI and cryptography accelerators increase area, and that the proposed co-processor supports polynomial convolution without additional hardware resources.
- Its implementation table reports total accelerator resources: `DSP`, `BRAM`, `LUT`, `FF`, frequency, and memory bandwidth.
- Its comparison table includes `LUT` and `FF` where prior works expose them, and uses `GOPS/kLUT` as a secondary efficiency metric.

Conclusion for HDEC:

- This supports comparing **whole accelerator/top resources**.
- It does not justify ignoring FF. FF is central to their argument because they reduce operand registers and explicitly report FF.

### 2. FPGA Accelerator for Homomorphic Encrypted Sparse CNN Inference

Source:
https://par.nsf.gov/servlets/purl/10336849

Relevant behavior:

- The accelerator targets homomorphic encrypted CNN inference.
- The resource table is titled accelerator resource consumption and reports `LUT`, `FF`, `BRAM`, `URAM`, `DSP`, and frequency for `Accel-L`, `Accel-M`, and `Accel-S`.
- The comparison section then discusses performance against privacy-preserving CNN baselines.

Conclusion for HDEC:

- For AI+crypto accelerators, papers report the whole accelerator resource vector.
- They do not reduce the comparison to logic LUT alone.

### 3. Bandwidth-Efficient Homomorphic Encrypted Matrix-Vector Multiplication Accelerator

Source:
https://par.nsf.gov/servlets/purl/10440494

Relevant behavior:

- The benchmarks are fully connected layers from AlexNet, VGG, RNN-T, and Deep Speech 2 under homomorphic encryption.
- The evaluation states the FPGA capacity in `LUTs`, `FFs`, SRAM, and DSPs.
- The resource table reports `kLUT`, `kFF`, `BRAM`, `URAM`, `DSP`, and frequency for different HE parameter sets.
- It also explains what LUTs are used for, e.g. modular adders.

Conclusion for HDEC:

- Even when the algorithmic headline is encrypted neural-network computation, the hardware result is a full resource table including FF.

### 4. SAFE: Homomorphic Encryption Accelerator for Vertical Federated Learning

Source:
https://renxuanle.github.io/pub/safe-tcad-2024.pdf

Relevant behavior:

- SAFE is a homomorphic matrix-vector accelerator used for vertical federated learning.
- The table "Resource Utilization on the Xilinx VU9P FPGA" reports module and total resource usage across `LUT`, `FF`, `BRAM`, `URAM`, and `DSP`.
- The authors tune the design to balance BRAM, URAM, and LUT utilization below a threshold.

Conclusion for HDEC:

- Resource-reuse and system-integration papers treat FF and memory resources as part of the area story.
- A paper table should show total top/module resources rather than only logic LUT.

### 5. Efficient Quantization and Data Access for Homomorphic Encrypted CNNs

Source:
https://www.mdpi.com/2079-9292/14/3/464

Relevant behavior:

- This is an HE-CNN acceleration paper that compares against the sparse HE-CNN accelerator above.
- Its comparison table uses `LUT/FF/DSP` as a compact resource row and also lists `BRAM/URAM`.
- It compares a full design against a prior full accelerator, not a logic-only subresource.

Conclusion for HDEC:

- Compact paper tables sometimes compress columns into `LUT/FF/DSP`, but FF remains visible.

### 6. A Framework for Generating Accelerators for Homomorphic Encryption Operations on FPGAs

Source:
https://par.nsf.gov/servlets/purl/10544906

Relevant behavior:

- The generated HE accelerator table reports `DSP`, `URAM`, `BRAM`, `LUT`, and `FF`.
- The discussion explicitly observes that LUT and FF consumption is relatively low compared with available resources.

Conclusion for HDEC:

- Even generator/framework papers report FF, not just LUT.
- They may discuss which resource is limiting, but the raw table still keeps the full resource vector.

### 7. NTTGen: Low-Latency NTT Implementations on FPGA

Source:
https://par.nsf.gov/servlets/purl/10336851

Relevant behavior:

- NTTGen is adjacent rather than AI-specific, but NTT is central to HE/PQC and the paper studies reusable NTT building blocks.
- Its state-of-the-art comparison table reports `LUT`, `FF`, `DSP`, `BRAM`, frequency, and latency.
- Its interconnect comparison table reports `LUT`, `FF`, and `BRAM`.

Conclusion for HDEC:

- For reusable datapath/interconnect components, FF is part of the comparison.
- If HDEC claims reuse inside a datapath, a module-level breakdown may be useful, but should still include FF.

### 8. Unified FFT/NTT Accelerator

Source:
https://arxiv.org/html/2504.11124v1

Relevant behavior:

- This is a cross-domain reuse paper: the same accelerator supports complex FFT and NTT for ML-KEM/ML-DSA.
- The implementation table reports `LUT / FF / DSP / BRAM`, cycle count, and latency for each mode.
- The state-of-the-art table also compares `LUT / FF / DSP / BRAM`.

Conclusion for HDEC:

- This is directly relevant to "one datapath reused for two domains".
- The resource accounting is mode/full-design based, and FF is never omitted.

### 9. FPT: Fixed-Point Accelerator for Torus Fully Homomorphic Encryption

Source:
https://arxiv.org/pdf/2211.13696

Relevant behavior:

- FPT supports a variety of TFHE applications by using parameter-specialized FPGA bitstreams.
- Its resource table breaks down `LUT (K)`, `FF (K)`, `DSP`, and `BRAM` for full parameter sets and submodules such as CMUX, MAC, FFT, and IFFT.

Conclusion for HDEC:

- Even when the design is parameter-flexible rather than multi-algorithm in one bitstream, the paper treats LUT and FF as paired area metrics.

### 10. Poseidon: Practical Homomorphic Encryption Accelerator

Source:
https://mingzhe-zhang.github.io/paper/Poseidon-HPCA2023.pdf

Relevant behavior:

- Poseidon explicitly motivates efficient resource reuse instead of blindly increasing parallelism.
- It breaks FHE into operators and time-multiplexes/reuses them.
- Its resource table reports `LUT(k)`, `FF(k)`, `DSP`, `BRAM`, and latency for MA, MM, NTT, automorphism, and SBT.
- Its comparison table uses `LUT`, `REG`, and `DSP` for selected computations.

Conclusion for HDEC:

- For a reuse-heavy accelerator, authors show operator/module resource breakdowns, but still include registers.
- `REG` is the same conceptual bucket as FF/register cost and should not be ignored.

## Pattern Across Papers

| Pattern | Evidence | Implication for HDEC |
|---|---|---|
| Full resource vector is standard | Cryptensor, HE Sparse CNN, Bandwidth-Efficient HE MxV, SAFE, HE-CNN quantization, FPT, Poseidon | Compare HDC-only vs HDC+ECC using full top-level resources. |
| FF/registers are not optional | Cryptensor emphasizes operand-register reduction; most FPGA tables include FF/kFF/REG | Do not publish only Logic LUT unless it is clearly a secondary diagnostic. |
| Logic-only LUT is uncommon in papers | Most papers write `LUT`, not Vivado's `LUT as Logic` split | Use `Slice LUT` for headline, and add `Logic LUT`/`LUTRAM` for transparency. |
| Composite area metrics sometimes include FF | NTT/HE papers use formulas involving LUT, FF, DSP, BRAM, or equivalent slice | If one-number area is needed, include FF in the formula. |
| Module breakdown is accepted | SAFE, FPT, Poseidon, NTTGen | HDEC can include both full-top and module/hierarchy breakdowns. |
| Cross-domain reuse is usually compared against full alternatives | Cryptensor and FFT/NTT report the unified accelerator and compare against prior accelerators | Add a naive separate-design comparison if ECC-only data is available. |

## Recommended HDEC Paper Table

Minimum table:

| Design | Vivado | Part | Clock target | WNS | Fmax est. | Slice LUT | Logic LUT | LUTRAM | FF | BRAM | DSP | CARRY4 | HDC pass | ECC cycles |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---:|
| HDC-only top | 2024.2 | xc7z020clg400-2 | 200 MHz | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | PASS | N/A |
| HDC+ECC shared top | 2024.2 | xc7z020clg400-2 | 200 MHz | 0.159 ns | 206.569 MHz | 6258 | 5786 | 472 | 2113 | 0 | 0 | 20 | PASS | 6005 |
| Delta | - | - | - | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | TBD | - | - |

Extended table, if ECC-only synthesis is available:

| Design | Slice LUT | Logic LUT | LUTRAM | FF | BRAM | DSP | Notes |
|---|---:|---:|---:|---:|---:|---:|---|
| HDC-only | TBD | TBD | TBD | TBD | TBD | TBD | Baseline user-visible HDC function |
| ECC-only | TBD | TBD | TBD | TBD | TBD | TBD | Standalone point-multiply block/top |
| Naive sum | TBD | TBD | TBD | TBD | TBD | TBD | HDC-only + ECC-only |
| HDC+ECC shared | 6258 | 5786 | 472 | 2113 | 0 | 0 | Current V23/V22 2024.2 shared top |
| Savings vs naive sum | TBD | TBD | TBD | TBD | TBD | TBD | Reuse benefit |
| Overhead vs HDC-only | TBD | TBD | TBD | TBD | TBD | TBD | Integration cost |

## Recommended Wording

Use language like:

> We report post-synthesis/OOC full-top FPGA resource utilization under the same Vivado version, part, and clock constraint. LUT usage is reported as both total Slice LUT and its Logic-LUT/LUTRAM split; FF, BRAM, DSP, and CARRY4 are reported separately. The HDC+ECC overhead is measured against the HDC-only top, while reuse savings are measured against the naive sum of independent HDC-only and ECC-only accelerators.

Avoid language like:

> The design only adds X logic LUTs.

unless it is immediately followed by FF, LUTRAM, BRAM/DSP, timing, and cycle-count deltas.

## Final Recommendation

For this project, the paper should **not** compare only `Logic LUT` while ignoring FF. The strongest and most literature-consistent presentation is:

1. Main claim: HDC+ECC full-top resource overhead versus HDC-only.
2. Reuse claim: HDC+ECC shared-top resource versus naive HDC-only + ECC-only sum.
3. Transparency: split total LUT into `Logic LUT` and `LUTRAM`, because HDEC's VRF uses distributed LUTRAM and the recent reports already track this.
4. Acceptance guardrail: show that HDC correctness, ECC PMUL cycles, and 200 MHz timing still pass.

This aligns with the resource-accounting behavior in the surveyed papers and with the local HDEC optimization rules.
