# Revision and Reviewer-Risk Checklists

## Whole-Paper Argument Audit

- Can the paper be stated as `problem -> gap -> insight -> mechanism -> evidence -> boundary`?
- Does the title name the actual architecture/mechanism?
- Do Abstract, Introduction, figures, contributions, experiments, and Conclusion tell the same story?
- Is every contribution distinct and mapped to a section plus evidence?
- Does the evidence validate the complete workload, not only a local operator?
- Are limitations or scope boundaries visible?

## Claim-Evidence Matrix

For every major claim, record:

| Claim | Mechanism | Evidence | Comparator/scope | Status |
|---|---|---|---|---|

Use `supported`, `partially supported`, or `missing`. Downgrade verbs or add evidence for incomplete rows.

## Abstract Audit

- Is the exact bottleneck visible within the first two sentences?
- Does the central insight appear before module details?
- Are mechanisms causally connected rather than listed?
- Are the platform, implementation scope, and strongest numbers current?
- Does every comparison name its baseline and metric?
- Is the final sentence a bounded implication?
- Are first-use abbreviations handled correctly?

## Introduction Audit

- Does the opening establish relevance without becoming a tutorial?
- Is the prior-work boundary synthesized rather than listed chronologically?
- Is the exact unresolved gap explicit?
- Does the key observation make the architecture plausible?
- Are detailed equations, RTL names, and result tables deferred?
- Are contributions ordered by scientific importance?
- Does each contribution map to later evidence?
- Is the same motivation repeated in Section II?

## Method and Architecture Audit

- Is the data representation or algorithmic transformation explained before the hardware that implements it?
- Are correctness, approximation, and security conditions stated?
- Does each block implement a previously motivated requirement?
- Are state, memory, datapath, reduction/accumulation, controller, and writeback boundaries clear?
- Are pipeline hazards and scheduling assumptions explicit?
- Are shared and private resources distinguishable?
- Are raw signal names and engineering-history language removed?

## Figure and Table Audit

- Does each figure answer one reader question?
- Is Fig. 1 the central insight/system boundary rather than a decorative workflow?
- Are figures introduced before interpretation?
- Are panel labels, widths, units, and abbreviations defined?
- Do table captions state device/technology and comparison scope?
- Are exact values in tables and mechanism interpretation in prose?
- Are FPGA and ASIC metrics kept separate?

## Experiment Audit

- Are tools, platform, implementation stage, target/achieved frequency, datasets/workloads, and parameters stated?
- Is functional correctness demonstrated before performance claims?
- Are raw area, cycles, latency, throughput, power, and energy definitions clear?
- Is there an ablation, breakdown, hierarchy, or design-space result for each architectural claim?
- Are prior-work comparisons fair in functionality and implementation scope?
- Are negative or tradeoff results reported rather than hidden?
- Does end-to-end evidence support local-operator claims?

## Language Audit

- Is one canonical term used for each concept?
- Is each paragraph limited to one job?
- Does each result paragraph lead with its conclusion?
- Are promotional adjectives replaced with mechanisms or numbers?
- Are `first`, `best`, `optimal`, `general`, and `significant` scoped and supported?
- Are Chinese-to-English sentences rebuilt by logic rather than translated clause by clause?

## HDEC-Specific Audit

- Is the unified GF(2) bit-matrix data representation the lead insight?
- Is the HDC subsystem described as complete for the target model without claiming universal HDC coverage?
- Does the paper show shared packet/state, bit-product/reduction, GF(2) accumulation, and writeback paths?
- Is diagonal-level on-the-fly modular reduction connected to that shared path?
- Are shared resources excluded from strict ECC-private area?
- Are standalone HDC and ECC baselines complete and interface-matched?
- Are PMUL cycles, field-operation counts, and representative scalar traces constant when claimed?
- Does the paper avoid semantic-versus-real reuse terminology and demonstrate sharing directly?

## Rejection-Risk Signals

Treat these as major risks:

- the main contribution is an implementation detail with no generalizable insight;
- area savings come from reducing functionality or mismatched baselines;
- a shared-accelerator claim lacks hierarchy/private-area evidence;
- an algorithm claim lacks correctness, accuracy, or security validation;
- cycle gains come from special-case shortcuts or changing operation counts without disclosure;
- comparison tables mix devices, technologies, memories, or interfaces without qualification;
- Abstract and Introduction lead with different innovations;
- evaluation omits the workload where the claimed benefit should matter.

## Revision Output

When revising prose, report:

1. current structural issue;
2. revised wording or paragraph map;
3. why the change improves TCAS-I/SCI logic;
4. required evidence or figure/table update.

When no material issue remains, say so and identify residual evidence or comparison risk.
