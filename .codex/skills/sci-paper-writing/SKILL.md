---
name: sci-paper-writing
description: Draft, restructure, revise, compare, and audit SCI/IEEE hardware-architecture manuscripts in TCAS-I, TCAD, TVLSI, and Transactions-style prose. Use for abstracts, introductions, related work, preliminaries, algorithm and architecture sections, scheduling and software-hardware co-design, experiments, discussions, conclusions, contribution framing, figures, tables, captions, reviewer-risk checks, and Chinese-to-English academic writing, especially for HDEC, HDC, ECC, FPGA/ASIC, privacy computing, and accelerator papers.
---

# SCI/IEEE Hardware Paper Writing

## Purpose

Use this skill as the circuit-and-architecture writing layer. Derive section logic and style from the weighted local corpus under `C:\Users\Administrator\Desktop\论文文献`: 30 HDC, ECC/MSM, and AI-cryptography accelerator papers, with IEEE Transactions papers treated as the primary style evidence and other journals/conferences used as supporting evidence.

Use `nature-writing` for broad argument architecture and `nature-polishing` for final English polish when those skills are requested. This skill decides the hardware-paper structure, technical granularity, evidence burden, and fair-comparison language.

## Required Workflow

1. Read the target text, figures, tables, and available results before rewriting.
2. Identify the target venue, requested section, and paper archetype from `references/article-architecture-playbook.md`.
3. State one bounded paper argument: `problem -> exact gap -> insight -> mechanism -> evidence -> boundary`.
4. Build a terminology ledger. Define uncommon abbreviations at first use; keep hardware-standard abbreviations such as FPGA, LUT, FF, BRAM, and DSP short unless the journal requires expansion.
5. Build a claim-evidence map. Every contribution must point to a mechanism section and to a figure, table, equation, experiment, or measured result.
6. Select the section moves from `references/section-playbook.md`; do not impose a fixed paragraph count when the argument requires a different length.
7. For Chinese source material, stabilize rigorous Chinese claims before translation and apply `references/language-and-argument-playbook.md`.
8. Draft in mechanism-first IEEE hardware style, then run `references/revision-checklists.md`.
9. Preserve the user's claims, numbers, algorithms, and boundaries. Mark missing evidence instead of inventing it.

## Task Modes

- **Analyze or plan:** diagnose structure and provide a paragraph/section map; do not modify files.
- **Compare wording:** show current wording, revised wording, and a short reason for each material change.
- **Draft or rewrite:** return the one-sentence argument, revised prose, and unresolved evidence needs.
- **Apply to DOCX:** edit only after explicit authorization and use the document render-and-verify workflow.
- **Audit:** lead with claim, evidence, comparison, terminology, and reviewer-risk findings rather than line-level polish.

## Reference Routing

- Corpus composition, measured patterns, and source weighting: `references/corpus-patterns.md`
- Whole-paper archetypes and section ordering: `references/article-architecture-playbook.md`
- Section-by-section drafting rules: `references/section-playbook.md`
- Chinese drafting, English conversion, paragraph logic, and verbs: `references/language-and-argument-playbook.md`
- Figure, table, caption, and text choreography: `references/figures-tables-playbook.md`
- Evaluation, comparison scope, metrics, and result paragraphs: `references/experiments-comparison-playbook.md`
- HDEC-specific framing, terminology, and contribution order: `references/hdec-tcasi-framing.md`
- Final audit and reviewer-risk checks: `references/revision-checklists.md`
- Per-paper provenance for the 30-paper corpus: `references/corpus-evidence-map.md`

Run `scripts/summarize_local_corpus.py` when the local PDF folder changes or fresh section-level corpus statistics are required. Treat extraction statistics as navigation aids; verify important prose patterns against the source PDFs.

## Hard Rules

- Present the final research logic, not branch history, failed trials, RTL version names, or laboratory chronology.
- Lead contributions with the insight and mechanism, not a list of modules or implementation actions.
- Do not claim `first`, `novel`, `optimal`, `general`, `state of the art`, or `complete` without a defined scope and direct evidence.
- Do not invent citations, baselines, datasets, accuracy, resource, frequency, cycle, power, or energy results.
- Do not compare raw numbers without stating platform, technology, frequency, arithmetic scope, memory/interface inclusion, and implementation stage.
- Do not mix FPGA and ASIC metrics as though LUT, gate area, memory macros, and power estimates were directly interchangeable.
- Do not force a standalone Discussion or Related Work section when the target journal and argument do not need one.
- Do not copy weak corpus habits such as excessive acronym expansion, long historical openings, contribution lists made of tools/modules, or repeated claims without evidence.

## HDEC Default Stance

For HDEC, lead with the research insight that binary HDC and binary-field ECC can be organized as a unified GF(2) bit-matrix data representation. Present the HDC subsystem as a complete binary HDC training/inference substrate for the target model, while keeping the main contribution on the shared data representation and execution structure. Show how HDC primitives, ECC polynomial modular multiplication, and diagonal-level on-the-fly modular reduction use the common packet, bit-product/reduction, GF(2) accumulation, state, and writeback substrate. Do not frame engineering-history distinctions such as semantic versus real reuse; demonstrate resource sharing through the architecture and measurements.

## Output Contract

For a substantial section task, return:

1. One-sentence argument.
2. Section or paragraph job map.
3. Revised prose or precise revision plan.
4. Claim-evidence gaps and comparison-scope cautions.
5. Short explanation of the most important structural changes.

Keep the response shorter for a narrow sentence or paragraph edit.
