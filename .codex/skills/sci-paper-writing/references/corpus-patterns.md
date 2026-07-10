# Local SCI/IEEE Hardware Corpus Patterns

## Corpus Scope and Weighting

The local corpus contains 30 full papers:

- 14 ECC or multiscalar-multiplication papers.
- 9 HDC papers.
- 7 AI-cryptography, privacy-computing, or fusion papers.

Use source weighting rather than treating all PDFs as stylistically equivalent:

- **Primary style evidence:** 16 IEEE Transactions papers from TCAS-I, TCAD, TVLSI, and TC.
- **Secondary journal evidence:** 7 papers from other journal venues.
- **Supporting mechanism evidence:** 7 conference or unresolved-venue papers.

Use every paper for technical organization insights, but use the primary group to decide TCAS-I/TCAD tone, section movement, comparison discipline, and contribution framing. See `corpus-evidence-map.md` for paper-level provenance.

The section-aware refresh on 2026-07-10 extracted all 30 PDFs and reviewed abstracts, full heading chains, contribution passages, method/architecture/evaluation organization, and conclusions. Twenty-nine abstracts were reliably isolated; their median length was 196 words. The 16 primary IEEE Transactions papers had introductions ranging from about 600 to 1450 extracted words, with a median near 1000 words. These are observations, not mandatory word limits.

## Stable Corpus-Level Findings

### Abstracts

Strong hardware abstracts normally perform six moves:

1. Name the workload or system pressure.
2. State the exact computational, memory, area, bandwidth, or flexibility gap.
3. Present the architecture and central insight.
4. Name two or three linked mechanisms, ordered from algorithm/dataflow to hardware.
5. Report implementation scope and decisive quantitative results.
6. End with a bounded implication for the target use case.

The typical journal abstract is about 170-240 words. Short briefs and conferences can be shorter. Do not fill space to reach a target; preserve the six moves and remove textbook background first.

### Introductions

The strongest introductions are move-driven rather than paragraph-count-driven:

`application pressure -> workload bottleneck -> prior design boundary -> exact unresolved gap -> key observation -> proposed response -> contributions/evidence preview`

Common traits in the primary corpus:

- The gap is explicit before the detailed architecture.
- The final introduction passage connects each contribution to a later section or measured result.
- Background is selective; formulas and implementation details move to preliminaries or method sections.
- Architecture papers often point to Fig. 1 near the transition from gap to proposed system.
- Contribution lists usually contain mechanism-level items plus an evaluation item.

Do not infer that every introduction needs the same number of paragraphs. For a full TCAS-I article, 5-9 functional paragraphs plus a compact contribution list is common; the exact count follows the argument.

### Full-Paper Architecture

Across HDC, ECC, and fusion papers, the durable causal chain is:

`bottleneck -> mathematical/algorithmic transformation -> data representation or schedule -> datapath and state organization -> implementation -> workload-level evidence`

Four recurring paper archetypes appear in the corpus:

- arithmetic operator or ECC microarchitecture;
- algorithm-hardware co-design;
- shared/fusion accelerator;
- programmable processor or host-integrated system.

Select the structure from `article-architecture-playbook.md`. HDEC is primarily a shared/fusion architecture paper with an algorithm-hardware co-design layer.

### Evaluation

Strong evaluations build an evidence ladder:

1. functional or mathematical correctness;
2. implementation setup and scope;
3. resource and timing results;
4. cycle, latency, throughput, power, or energy results;
5. breakdown, ablation, data-dependency, or design-space evidence;
6. fair comparison with prior work;
7. end-to-end or application-level effect when relevant.

The best papers do not rely on a single aggregate table. They explain why the measured gain follows from the proposed dataflow, schedule, sharing mechanism, or arithmetic transformation.

## Domain-Specific Patterns

### HDC Papers

HDC papers usually establish one of three bottlenecks: model accuracy, high-dimensional state movement/storage, or limited programmability. Strong algorithm-hardware papers validate both model behavior and hardware efficiency. General-purpose HDC claims require evidence across supported operations, learning stages, datasets, dimensions, and software programmability.

### ECC and MSM Papers

ECC papers commonly move from field/point arithmetic to data dependencies, multiplier organization, scheduling, controller/datapath design, and implementation comparison. A field multiplier result alone does not establish scalar-point-multiplication efficiency. Report point-level cycles or latency and explain whether the schedule, number of arithmetic units, and constant-time behavior differ.

### Fusion and Privacy-Computing Papers

Fusion papers first prove a common computational anchor such as GEMM, polynomial convolution, NTT, packed ciphertext primitives, or shared data. The architecture then follows from that anchor. A fusion claim is weak if it only places two accelerators behind one interface; it is strong when the data representation, core operators, state/memory flow, and evaluation all demonstrate shared execution.

## Patterns Not to Copy

The corpus also contains weak habits that are not journal rules:

- historical openings that delay the exact gap;
- abstracts that enumerate every module;
- six or more contribution bullets with overlapping claims;
- `novel`, `first`, or `best` without a fair comparison scope;
- tool-flow details presented as research contributions;
- results that compare different FPGA families or ASIC nodes without qualification;
- conclusions that repeat the abstract but omit limitations;
- related-work lists organized only by year or citation order.

Treat these as anti-patterns even when they appear in published papers.

## Tone and Diction

Prefer restrained mechanism verbs:

- `presents`, `organizes`, `maps`, `restructures`, `shares`, `schedules`, `reduces`, `supports`, `demonstrates`.

Use evidence-sensitive verbs:

- direct measured evidence: `shows`, `demonstrates`, `achieves`;
- indirect or limited evidence: `indicates`, `suggests`, `can support`.

For IEEE Transactions prose, `This article presents...` is often natural. `This paper` and `we` are also acceptable when used consistently. Do not imitate Nature-specific `Here we show...` phrasing unless the target venue uses it.
