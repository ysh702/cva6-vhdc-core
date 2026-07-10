# Figures, Tables, and Captions Playbook

## Plan Figures Around Claims

Every figure should answer one reader question and support one manuscript claim. Create a figure-evidence map before drawing:

| Figure | Reader question | Main conclusion | Required panels | Supporting section |
|---|---|---|---|---|

Remove a figure that only decorates background or duplicates a table.

## Common Hardware-Paper Figure Sequence

1. **Fig. 1, motivation or system insight:** show the bottleneck, common computational anchor, or proposed system boundary.
2. **Algorithm/data representation:** show the transformation, dependencies, or mapping that makes the architecture possible.
3. **Top-level architecture:** show interface, state/memory, datapath, control, and writeback boundaries.
4. **Core operator:** show the processing element, multiplier, row tile, reduction path, or pipeline.
5. **Schedule/dataflow:** show timing, hazards, overlap, and resource ownership.
6. **Evaluation figures:** show trends, breakdowns, ablations, design-space tradeoffs, and end-to-end gains.

Not every paper needs all six. Merge panels when they answer one question; separate figures when the reader must learn a new concept.

## Introduction Figure

For architecture papers, the first figure should reveal the central idea rather than present every RTL block. A good multi-panel Fig. 1 can show:

- baseline or separate-system limitation;
- mathematical/dataflow commonality or key observation;
- proposed architecture boundary and shared path.

Detailed FSMs, mux controls, and micro-operation timelines belong later.

## Architecture Figures

- Use consistent data widths, arrow conventions, colors, and block names.
- Distinguish state storage, compute, reduction/accumulation, control, and external interface visually.
- Label shared and workload-private resources when resource sharing is a claim.
- Show data direction and writeback ownership; avoid ambiguous bidirectional arrows.
- Keep software/runtime elements outside the datapath boundary unless they are physically part of the hardware.
- Match figure nouns to manuscript terminology exactly.

## Scheduling Figures

Show:

- cycle or stage axis;
- operation dependencies;
- resource occupancy;
- baseline bubbles or conflicts;
- proposed overlap or packing;
- terminal writeback/commit boundary.

State whether the timeline is exact, representative, or simplified. Do not imply higher parallelism than the implemented hardware provides.

## Evaluation Figures

- Put the conclusion in the surrounding prose, not only in the legend.
- Use the same baseline order, color, and metric definition across figures.
- Include units and whether larger or smaller is better.
- Use breakdowns or ablations to connect measured gains to mechanisms.
- Show raw area, cycles, frequency, accuracy, or energy alongside normalized metrics when practical.
- Do not use a bar chart when a compact table communicates exact values better.

## Tables

Use tables for exact comparisons, configurations, operation counts, resource reports, and coverage matrices.

Every comparison table must state:

- platform/device or technology node;
- implementation stage;
- frequency;
- arithmetic/workload scope;
- whether memory, host interface, wrapper, and preprocessing are included;
- metric definitions and normalization.

Use footnotes for unavoidable scope differences. Do not hide unfavorable metrics with `N/A` when the value can be measured.

## Captions

Write captions that are understandable without rereading the entire section:

1. name the figure/table object;
2. define panels, symbols, and abbreviations not obvious from the graphic;
3. state the operating condition or comparison scope;
4. avoid making a new unsupported claim.

IEEE captions are usually concise and descriptive. Do not import Nature-style mini-discussions into every caption.

## Text-Figure Choreography

Use this order:

1. introduce the question or object;
2. cite the figure/table;
3. describe the relevant structure or trend;
4. interpret why it matters;
5. state the boundary or transition.

Do not cite a figure after several paragraphs of interpretation. Do not narrate every wire, panel, or table cell.

## HDEC Figure Set

For HDEC, a coherent figure sequence is:

1. separate HDC/ECC implementation versus unified GF(2) bit-matrix insight and HDEC boundary;
2. unified HDC/ECC data representation;
3. shared state, packet, bit-product/reduction, GF(2) accumulation, and writeback architecture;
4. HDC workload mapping;
5. ECC Karatsuba-diagonal multiplication and diagonal-level on-the-fly modular reduction;
6. cycle schedule and constant-time PMUL flow;
7. resource-sharing, private-area, cycle, and performance evidence.
