# Language and Argument Playbook

## Chinese-First Workflow

For Chinese author notes, do not translate sentence by sentence immediately.

1. Split each note into claim, evidence, condition, comparison, implication, and limitation.
2. Reorder those units according to the target section.
3. Write rigorous Chinese academic prose with stable terminology.
4. Verify every number and claim against the manuscript evidence.
5. Translate intent and logic into English.
6. Polish English for IEEE hardware style without changing scope.

## Terminology Ledger

Record for every recurring concept:

| Canonical concept | Chinese term | First-use English form | Short form/symbol | Forbidden variants |
|---|---|---|---|---|

Use one term for one concept. Do not vary technical nouns for stylistic variety. Expand uncommon abbreviations at first use. Do not routinely expand FPGA, LUT, FF, BRAM, or DSP for a circuit readership.

## Paragraph Logic

Give each paragraph one job. A strong hardware paragraph usually follows one of these patterns.

### Gap Paragraph

`known approach -> achieved benefit -> scope boundary -> unresolved consequence`

### Mechanism Paragraph

`design objective -> proposed mechanism -> why it works -> architectural consequence`

### Results Paragraph

`conclusion -> exact evidence -> fair comparator -> causal interpretation -> boundary`

### Comparison Paragraph

`comparison scope -> decisive metrics -> source of difference -> remaining tradeoff`

The first sentence should state the paragraph's message. Connect later sentences by cause, contrast, evidence, or restriction.

## Sentence Construction

- Prefer one principal claim per sentence.
- Put the subject and technical verb early.
- Keep conditions next to the claim they limit.
- Replace long noun chains with a short subject plus an active technical verb.
- Use parallel grammar for contribution lists and comparison items.
- Avoid comma strings that mix motivation, method, results, and implication.
- Avoid sentences whose grammatical subject is an empty phrase such as `It is worth noting that`.

## Evidence-Calibrated Verbs

Use direct verbs only with direct evidence:

- derivation or architecture: `defines`, `maps`, `organizes`, `restructures`, `shares`, `schedules`;
- measured result: `achieves`, `reduces`, `requires`, `occupies`, `operates at`;
- supported conclusion: `demonstrates`, `shows`;
- limited inference: `indicates`, `suggests`, `can support`.

Avoid using `proves` for implementation results. Avoid `significantly` unless a statistical test or clearly defined engineering magnitude supports it.

## Tense and Voice

- Present tense for equations, architecture behavior, figures, and established facts.
- Past tense for completed experimental procedures when the distinction matters.
- Present or present perfect for the paper's contribution and reported results, used consistently.
- Active voice is acceptable and often clearer: `This article presents...`, `We map...`, `The scheduler removes...`.
- Passive voice is useful when the action or artifact matters more than the actor, but do not use it to hide an unclear subject.

## IEEE Hardware Tone

Prefer concrete mechanism language over promotional language.

Prefer:

- `The proposed schedule overlaps...`
- `The shared datapath supports...`
- `The implementation occupies...`
- `Compared under the same device and interface scope...`

Avoid:

- `groundbreaking`, `revolutionary`, `remarkable`, `perfect`, `extremely efficient`;
- `obviously`, `clearly`, or `naturally` when a derivation is needed;
- `best` or `state of the art` without a table-defined comparison set;
- repeated `novel` labels instead of explaining the novelty.

## Common Chinese-Draft Repairs

| Draft symptom | Repair |
|---|---|
| Broad importance before naming the object | Name the workload/system in the first sentence |
| Method list before the gap | Move the exact gap before method names |
| `显著提高` without baseline | Add comparator and metric or soften the claim |
| Several `为了...本文...` sentences | Consolidate into one objective and one mechanism chain |
| Results mixed into method derivation | Keep derivation in Method and measured gain in Results |
| Engineering history narrated chronologically | Present the final insight and mechanism |
| One Chinese sentence becomes one long English sentence | Split by claim and evidence relation |
| Several translations for one term | Lock the terminology ledger |

## First-Use and Symbol Rules

- Define HDC and ECC at first use in both Chinese working text and final English text.
- Define GF(2^m) notation when the field is first introduced.
- Keep multiplication signs, dimensions, superscripts, and units consistent.
- Use exact resource names from tools and tables, such as `Logic LUT`, rather than silently changing them to generic `LUT`.
