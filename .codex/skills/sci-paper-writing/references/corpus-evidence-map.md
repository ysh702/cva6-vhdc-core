# Corpus Evidence Map

This file records the paper-level provenance behind the skill. It contains derived structural lessons, not reproduced paper text. `Primary` denotes IEEE Transactions papers used to set journal style; `Secondary` denotes other journals; `Supporting` denotes conference or unresolved-venue material used mainly for mechanism and organization examples.

## ECC and MSM Papers

| Paper file | Weight | Structural lesson used by the skill |
|---|---|---|
| `2024-1246.pdf` | Supporting | Connect an ISA, processing engine, runtime scheduling, performance model, and multi-FPGA evaluation into one system argument. |
| `A_Low_Area-Time_ECPM_Hardware_Accelerator_Over_Curve25519_on_FPGA.pdf` | Primary | Derive the architecture from data-hazard, pipeline-depth, and multiplier-iteration analysis; validate both FPGA and ASIC scope and state limitations. |
| `ECC-1.pdf` | Secondary | Area-first ECC narrative based on bit-serial multiplication and arithmetic-unit reuse; useful for evidence requirements but not for contribution-list style. |
| `ECC-2.pdf` | Secondary | Tie digit-parallel multiplication, inversion reuse, controller design, power, cycles, and throughput/area comparison together. |
| `ECC-3.pdf` | Primary | Move from multiplier recurrence and complexity to complete ECC processor implementation and a separate performance discussion. |
| `ECC-4.pdf` | Secondary | Explain the area/time consequence of a bit-parallel multiplier and consolidated arithmetic unit; use cautiously for novelty wording. |
| `ECC-5.pdf` | Secondary | Combine digit-serial multiplication, PMUL scheduling, resource reuse, and low-power techniques; demonstrates why long module-style contribution lists should be compressed. |
| `Fama_An_FPGA-Oriented_Multiscalar_Multiplication_Accelerator_Optimized_via_AlgorithmHardware_Co-Design.pdf` | Primary | A concise brief structure: constrained algorithm selection, compact point-add unit, and area-time evidence. |
| `FPGA Implementation of the ECC Over GF(2^m) for Small Embedded Applications.pdf` | Secondary | Show complete compact ECC through state-machine scheduling, field operations, PMUL, side-channel discussion, and implementation results. |
| `High-Performance_Pipelined_Architecture_of_Elliptic_Curve_Scalar_Multiplication_Over_GF_2m_.pdf` | Primary | Use dependency analysis and pipeline-stage exploration to connect scheduling, critical path, cycles, and complete scalar multiplication. |
| `High-speed hardware architecture of scalar multiplication for binary elliptic curve cryptosystems.pdf` | Secondary | Coordinate parallel point operations, digit-serial multipliers, inversion, and clock-domain behavior; requires careful scope discussion. |
| `High-Speed_and_Low-Latency_ECC_Processor_Implementation_Over_GF_2m_on_FPGA.pdf` | Primary | Compare one- and three-multiplier architectures through segmented pipelining, modified scheduling, latency, and area-time evidence. |
| `Myosotis_An_Efficiently_Pipelined_and_Parameterized_Multiscalar_Multiplication_Architecture_via_Data_Sharing.pdf` | Primary | Present data sharing, cache allocation, and integrated multi-PADD as a parameterized bandwidth-area-latency tradeoff. |
| `Speed_Area-Efficient_ECC_Processor_Implementation_Over_GF2m_on_FPGA_via_Novel_Algorithm-Architecture_Co-Design.pdf` | Primary | Use a bottom-up chain from multiplier design and complexity to dependency graph, scheduling, processor implementation, and ADP comparison. |

## HDC Papers

| Paper file | Weight | Structural lesson used by the skill |
|---|---|---|
| `3649329.3656532.pdf` | Supporting | Start from the high-dimensional processing cost, change the classifier semantics to enable principled early termination, and validate online learning. |
| `A_ReRAM-Based_Processing-In-Memory_Architecture_for_Hyperdimensional_Computing.pdf` | Primary | Abstract encoding and comparison into common primitives before presenting a unified processing engine and train/infer evaluation. |
| `HDC-1.pdf` | Primary | Support a general-purpose HDC claim with primitive coverage, configurable architecture, ISA/software integration, and complete workload results. |
| `HDC-2.pdf` | Secondary | Treat portability as a full-system problem involving host-agnostic interfaces, DMA/memory, software stack, and end-to-end benchmarks. |
| `HDC-3.pdf` | Primary | Separate model quantization/accuracy, processor extensions, hardware-software co-design, and area/energy evaluation. |
| `HDC-4.pdf` | Primary | Present learnable HDC transformations before the matching accelerator and validate algorithm and hardware separately. |
| `HDC-5.pdf` | Primary | Lead with the exact class-hypervector storage bottleneck, then derive a logic-based query, tiny accelerator, search tool, and ASIC/FPGA evidence. |
| `HyperMetric_Efficient_Hyperdimensional_Computing_With_Metric_Learning_for_Robust_Edge_Intelligence.pdf` | Primary | Build from a mechanism insight about Hamming-margin robustness to training, approximate encoding hardware, and error-aware evaluation. |
| `Tri-HD_Energy-Efficient_On-Chip_Learning_With_In-Memory_Hyperdimensional_Computing.pdf` | Primary | Establish complete HDC-pipeline coverage, introduce a hardware-compatible metric, then show PIM implementation and end-to-end evidence. |

## Fusion and Privacy-Computing Papers

| Paper file | Weight | Structural lesson used by the skill |
|---|---|---|
| `3706628.3708868.pdf` | Supporting | Unify HE operations through common primitives and co-design ISA, asynchronous dataflow, compiler scheduling, and resource evaluation. |
| `FUSION-1.pdf` | Primary | Prove a shared GEMM computational anchor before presenting the common architecture, workload-specific mappings, and dual-domain evaluation. |
| `FUSION-2.pdf` | Supporting | Use an explicit motivation section, resource/performance models, inter-layer reuse, and design-space exploration for a configurable framework. |
| `FUSION-3.pdf` | Supporting | Organize a secure-inference system around representation switching, optimized kernels, microbenchmarks, and end-to-end protocol results. |
| `PPGNN_Fast_and_Accurate_Privacy-Preserving_Graph_Neural_Network_Inference_via_Parallel_and_Pipelined_Arithmetic-and-Logic_FHE_Accelerator.pdf` | Supporting | Link a parameter-reducing algorithm to specialized pipelined engines and end-to-end accuracy/performance/energy results. |
| `Primer_Fast_Private_Transformer_Inference_on_Encrypted_Data.pdf` | Supporting | Structure a short paper around hybrid protocol design, offline/online movement, packing, and end-to-end latency. |
| `SAFE_A_Scalable_Homomorphic_Encryption_Accelerator_for_Vertical_Federated_Learning.pdf` | Primary | Identify HMVP as the application bottleneck, then connect encoding variants, dataflow/roofline analysis, hardware, system integration, and end-to-end training. |

## Corpus Use Rules

- Use the primary group to infer TCAS-I/TCAD/TVLSI/TC style.
- Use secondary/supporting papers to broaden mechanism and architecture patterns.
- Verify any citation or technical claim against the original PDF; this map is not a citation source.
- Do not copy sentences or novelty claims from the corpus.
- Re-run the corpus script and refresh this map when files are added, removed, or replaced.
