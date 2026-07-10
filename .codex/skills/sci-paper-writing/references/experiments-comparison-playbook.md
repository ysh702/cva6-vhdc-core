# Experiments and Comparison Playbook

## Start From Evaluation Questions

State 3-6 questions that correspond directly to the contributions. Typical hardware questions are:

- Is the algorithm/architecture functionally correct?
- Does the proposed mechanism reduce the claimed bottleneck?
- What area, timing, memory, power, and energy does the implementation require?
- What is the end-to-end cycle, latency, or throughput effect?
- Which mechanism produces each gain?
- How does the design compare under a fair scope?

Organize subsections around these questions, not around the order in which experiments were run.

## Evidence Ladder

Use the following order when applicable:

1. **Setup:** platform, tools, implementation stage, target/achieved frequency, datasets/workloads, security parameters, baselines, and metric definitions.
2. **Correctness:** golden model, test vectors, algorithm accuracy, field-operation checks, protocol output, or board-level validation.
3. **Implementation:** LUT/FF/BRAM/DSP or cell area/memory macros, timing, and hierarchy.
4. **Performance:** operation counts, cycles, latency, throughput, utilization, power, and energy.
5. **Mechanism evidence:** ablation, breakdown, dependency/schedule analysis, design-space exploration, or resource hierarchy.
6. **Prior-work comparison:** fair device/technology and functionality scope.
7. **End-to-end evidence:** complete learning, inference, PMUL, protocol, or joint workload.

## Result Paragraph Structure

Write each result paragraph as:

`conclusion -> exact value -> comparator and scope -> mechanism-based explanation -> boundary`

Example shape:

`The proposed schedule reduces PMUL latency under the same row-tile configuration. It requires X cycles, compared with Y cycles for the baseline. The reduction comes from [...], while the number of field multiplications remains fixed. This comparison does not include [...].`

Do not repeat every table entry. Interpret the result that supports the subsection's question.

## Metric Discipline

### FPGA

Use exact tool terms:

- `Logic LUT`, `Slice LUT`, `FF`, `LUTRAM`, `BRAM`, `DSP`, `WNS`, and `Fmax`.
- State synthesis, OOC, post-place-and-route, or full-system scope.
- State the FPGA family/device and tool version.

Do not silently treat `Slices`, `Logic LUT`, and `Slice LUT` as the same metric.

### ASIC

State:

- technology/library and PVT corner;
- voltage, temperature, and clock constraint;
- combinational, sequential, memory/macro, and total area as available;
- achieved timing and power-estimation method;
- whether memories are inferred registers or compiled macros.

Do not divide FPGA LUT counts by ASIC area to claim a cross-platform ratio.

### Performance

Define cycles, latency, throughput, utilization, power, and energy. Report raw metrics before composite metrics such as area-time product, ADP, ATP, EDP, or throughput/area.

## Fair Comparison Checklist

Before writing `Compared with`, verify:

- same operation or end-to-end task;
- same field/curve, model, dimension, accuracy/security level, or parameter set;
- same or explicitly different FPGA family/technology node;
- same inclusion of memory, host interface, wrapper, preprocessing, and software;
- frequency and implementation stage reported;
- resource metric definitions compatible;
- baseline is measured, reproduced, or clearly cited.

If conditions differ, state the difference before interpreting the result.

## Ablation and Breakdown

Use an ablation or breakdown to prove architectural causality:

- algorithm transformation on/off;
- shared versus separate state/operator/writeback;
- scheduling/folding mechanism on/off;
- pipeline depth or digit width;
- memory/cache/data-sharing configuration;
- private and shared resource hierarchy;
- cycles by operation/state class;
- accuracy or security effect.

Reject an ablation that changes several mechanisms at once without explaining attribution.

## HDC Evaluation

Report, when relevant:

- datasets, encoding, dimension, classes, train/retrain/infer flow;
- model accuracy and comparison conditions;
- supported primitive and workflow coverage;
- primitive cycles and end-to-end train/infer performance;
- memory/state requirements;
- resource, frequency, power, and energy;
- configurability or software programmability evidence for general-purpose claims.

## ECC Evaluation

Report, when relevant:

- field, curve, coordinate system, scalar width, and irreducible polynomial;
- field-operation correctness and complete PMUL correctness;
- field-operation counts and PMUL wall cycles;
- cycles by state/operation class;
- constant-time evidence across representative scalars;
- area, timing, latency, throughput, power, and energy;
- number/type of multipliers or arithmetic units;
- fair prior-work comparison.

Do not attribute cycle reduction to scheduling without showing unchanged operation counts when that is the claim.

## HDEC Resource-Sharing Evidence

The HDEC reuse claim requires a complete evidence package:

- full HDEC area and timing;
- standalone HDC accelerator with equivalent host-interface scope;
- standalone ECC accelerator with equivalent host-interface scope;
- separate HDC+ECC sum;
- strict ECC-private area inside HDEC;
- hierarchy or bucket evidence for shared state/VRF, packet, row tile, accumulation, and writeback;
- both HDC and ECC functional validation;
- PMUL cycle and constant-time checks.

Do not count a shared resource as ECC-private merely because ECC uses it. Do not claim area savings from a standalone baseline whose functionality or interface is smaller than HDEC.

## HDEC Suggested Tables

1. HDC model/function coverage and accuracy.
2. ECC field-operation and PMUL correctness.
3. Full FPGA resources, timing, and implementation scope.
4. HDEC versus separate HDC+ECC accelerators.
5. Shared versus private area/FF hierarchy.
6. ECC PMUL operation and cycle breakdown with scalar-independence checks.
7. HDC and ECC prior-work comparisons, kept in separate fair-scope tables.
8. ASIC implementation and power/energy, separated from FPGA metrics.
