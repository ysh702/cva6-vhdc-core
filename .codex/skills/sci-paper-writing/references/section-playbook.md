# Section Playbook for SCI/IEEE Hardware Papers

## Title

Name the system class and the differentiating mechanism. Prefer one technical noun phrase over a claim sentence.

Useful forms:

- `[System]: A [mechanism] Accelerator for [workload/constraint]`
- `[Mechanism]-Based [processor/architecture] for [operation/domain]`

Avoid vague adjectives, result numbers, version names, and unsupported `first` or `optimal` claims.

## Abstract

Use one compact paragraph with six moves:

1. workload/system need;
2. exact gap in current implementations;
3. proposed system and central insight;
4. two or three linked mechanisms;
5. implementation platform and strongest fair results;
6. bounded implication.

For a full Transactions paper, 170-240 English words is a useful corpus range, not a hard limit. Write the abstract after the argument and results stabilize.

Do not include:

- extended textbook background;
- every module or acronym;
- results without baseline and scope;
- future-work promises;
- multiple sentences saying the same architecture is efficient.

## Introduction

Write functional moves rather than targeting a fixed paragraph count:

1. **Relevance:** establish the application and resource pressure.
2. **Domain bottleneck:** identify the computation, memory, bandwidth, latency, flexibility, or integration problem.
3. **Prior boundary:** synthesize what existing approaches solve and what remains unresolved.
4. **Insight:** state the observation that makes a new design possible.
5. **Response:** present the proposed method/architecture at mechanism level.
6. **Contributions and evidence preview:** list distinct contributions and indicate validation scope.

For cross-domain papers, introduce both domains only to the depth needed to establish the common anchor. Move formulas, detailed schedules, state names, and implementation mechanics to later sections.

Contribution bullets should follow:

`insight/transformation -> architectural consequence -> validated benefit`

Use 3-5 nonoverlapping items. Do not lead with a minor supporting algorithm when the paper's central contribution is an architecture or shared representation.

## Background and Preliminaries

Include only concepts used later in equations, figures, or design decisions. End each subsection with the specific implication for the proposed design.

Good sequence:

`baseline definition -> cost/dependency -> design implication`

Do not repeat the Introduction's motivation or reproduce a field tutorial.

## Related Work

Group papers by mechanism, design objective, or implementation model. For each group:

1. state what the group achieves;
2. identify the boundary relevant to this paper;
3. explain why that boundary matters for the present problem.

Use neutral language. Distinguish differences in scope, platform, and functionality before comparing metrics.

## Algorithm, Model, or Data Representation

Use this section to establish correctness and hardware relevance before introducing blocks.

Recommended order:

1. define inputs, outputs, notation, and baseline;
2. identify the expensive or irregular operation;
3. derive the transformation or representation;
4. show equivalence, approximation condition, or security/correctness boundary;
5. expose regularity, locality, shared subexpressions, or schedulable dependencies;
6. summarize the hardware consequence.

For algorithm-hardware co-design, separate algorithmic benefit from hardware benefit and validate both.

## Architecture

Move from system boundary to datapath detail:

1. top-level interface and execution context;
2. data/state representation and memory organization;
3. core operator or processing element;
4. reduction, accumulation, or writeback path;
5. controller, schedule, pipeline, and hazards;
6. workload mapping and private/shared resources;
7. configurability and limitations.

Introduce every figure before interpreting it. Explain why each block exists and which earlier algorithmic property it implements. Avoid raw RTL names and MUX-by-MUX narration unless the selector itself is the contribution.

## Scheduling and Software-Hardware Co-Design

State:

- operation dependency graph;
- issue/capture/commit or pipeline stages;
- where bubbles or data movement occur in the baseline;
- how the schedule hides, removes, or overlaps them;
- resource conflicts and correctness constraints;
- software-visible invocation and state boundaries.

Cycle claims must identify the operation class or state transition that changed. Constant-time claims require scalar-independent operation counts or traces.

## Experiments and Results

Use the evidence ladder in `experiments-comparison-playbook.md`. Open each results subsection with the question or conclusion it answers, then present numbers, comparison, mechanism-based interpretation, and boundary.

Do not use a table as a substitute for prose. Do not repeat every cell in the text; interpret the decisive comparisons.

## Discussion

Use only when interpretation cannot fit naturally in Results. Cover:

- why the mechanism produced the measured trend;
- where the design is most useful;
- tradeoffs across area, time, energy, accuracy, security, or programmability;
- limits of platform, model, field size, workload, or comparison scope.

Do not introduce a new unvalidated contribution.

## Conclusion

Use one short paragraph or two compact paragraphs:

1. restate the problem and central insight;
2. summarize the mechanism and decisive evidence;
3. state the practical meaning and boundary;
4. name future work only when concrete and justified.

Do not copy the abstract sentence by sentence and do not add new numbers or claims.

## Keywords and Index Terms

Select 4-8 searchable domain and mechanism terms. Prefer recognized field vocabulary over internal method names. Include the target workload, architecture class, mathematical domain, and implementation platform when useful.
