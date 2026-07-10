# Article Architecture Playbook

## Select the Paper Archetype

Choose the architecture from the center of novelty, not from the list of implemented modules.

### A. Arithmetic Operator or ECC Microarchitecture

Use when the main contribution is a multiplier, modular arithmetic unit, finite-field processor, or scalar-multiplication schedule.

Recommended spine:

1. Introduction: target operation, area/time bottleneck, exact limitation.
2. Preliminaries: only the mathematics needed to understand the transformation.
3. Proposed arithmetic method: decomposition, recurrence, reduction, or scheduling model.
4. Complexity and dependency analysis: operation counts, critical path, hazards, cycle model.
5. Architecture: datapath, state, controller, pipeline, memory, and reuse.
6. Implementation and evaluation: correctness, resource, timing, cycles, comparison.
7. Conclusion and scope.

The paper must show that operator-level improvements survive at the complete processor or PMUL/ECPM level.

### B. Algorithm-Hardware Co-Design

Use when the algorithm or representation is changed specifically to make hardware more efficient.

Recommended spine:

1. Introduction: application requirement and algorithm-hardware mismatch.
2. Background and motivation: baseline algorithm and measured/derived bottleneck.
3. Proposed algorithm or data representation.
4. Mapping and dataflow: how the transformation exposes regularity, locality, or parallelism.
5. Hardware architecture and scheduling.
6. Algorithm evaluation: accuracy, correctness, complexity, or security.
7. Hardware evaluation: implementation, performance, energy, ablation, comparison.
8. Conclusion and boundary.

Keep the algorithm claim and hardware claim separately testable.

### C. Shared or Fusion Accelerator

Use when two workloads are unified around a common representation or operator substrate.

Recommended spine:

1. Introduction: why both workloads coexist and why separate accelerators duplicate resources.
2. Background/related work: establish the two workload domains and the missing integration point.
3. Common computational anchor: unified data representation, algebra, dataflow, or primitive set.
4. Shared architecture: state/memory, operators, accumulation/reduction, control, and writeback.
5. Workload-specific mappings: show what is shared and what remains private.
6. Scheduling and software/host integration.
7. Evaluation: both workloads, shared-area evidence, private-area evidence, performance, and separate-accelerator baseline.
8. Conclusion and integration boundary.

Do not call a design shared merely because two blocks use one interface. Show the common data path and quantify the avoided duplication.

### D. Programmable Processor or Host-Integrated System

Use when configurability, ISA, compiler/runtime, or host decoupling is central.

Recommended spine:

1. Introduction: portability or programmability gap.
2. Background and workload primitives.
3. Architecture and instruction/operation set.
4. Programming model, compiler, driver, or runtime.
5. Hardware implementation and configuration space.
6. Primitive-level and end-to-end evaluation.
7. Comparison of function coverage, portability, and cost.
8. Conclusion.

Claims of generality require operation coverage and multiple end-to-end workloads, not only synthesis-time parameters.

## Build the Argument Before the Outline

Write these six records before drafting:

| Record | Required content |
|---|---|
| Problem | The system or workload constraint that matters |
| Gap | What current approaches cannot do under that constraint |
| Insight | The mathematical, algorithmic, or architectural observation |
| Mechanism | The transformation, dataflow, architecture, and schedule |
| Evidence | Figures, equations, correctness tests, implementation results, comparisons |
| Boundary | What is not claimed or not supported |

If a section does not advance one record, merge it, move it, or remove it.

## Contribution-to-Evidence Matrix

Before final prose, map every contribution:

| Contribution | Mechanism section | Primary figure/equation | Validation table/experiment | Scope qualifier |
|---|---|---|---|---|
| C1 | Section ... | Fig./Eq. ... | Table/Exp. ... | Under ... |

Reject a contribution bullet that has no mechanism location or no evidence location.

## Related Work Placement

- Put Related Work in Section II when the comparison requires substantial technical grouping.
- Keep a compact related-work passage in the Introduction for short briefs or when the gap is simple.
- Place a later Related Work section only when the paper first needs to teach an unfamiliar system; ensure the Introduction still states the unresolved gap.

Group prior work by mechanism or design objective, not publication year.

## Discussion Placement

A standalone Discussion is optional in TCAS-I/TCAD hardware papers. Use it when the paper must interpret cross-platform trends, generality, security/accuracy tradeoffs, or limitations. Otherwise, put bounded interpretation in the evaluation subsections and limitations in the conclusion.

## HDEC Selection

Treat HDEC as archetype C with elements of archetype B:

`unified GF(2) bit-matrix representation -> HDC/ECC mapping -> shared execution structure -> diagonal-level on-the-fly modular reduction -> scheduling/integration -> reuse and performance evidence`

The fixed sparse HDC method supports the mapping but does not replace the shared-representation contribution as the paper's lead.
