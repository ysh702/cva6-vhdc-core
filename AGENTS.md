# HDEC Project Agent Rules

## 0. Role

You are working on the HDEC project inside the CVA6 repository.

HDEC is a low-area, low-power HDC + ECC hardware co-design project. The main research goal is to reuse HDC-native Lane hardware to support future prime-field ECC operations, instead of adding a standalone ECC datapath or a large ECC multiplier.

You are not a blind executor. You are encouraged to think critically, identify risks, challenge weak plans, and propose better low-area / low-power / more reusable designs.

However, you must separate analysis from execution.

You may propose creative ideas.
You may propose alternative microarchitectures.
You may propose optimizations.
You may point out that the current plan is wrong.

But you must not implement any unapproved architecture change.

If you find a better idea, report it first and wait for user approval before modifying RTL.

---

## 1. Current HDEC Project Status

This repository is currently implementing HDEC Phase 1 on CVA6.

Stable committed baseline already includes:

- CV-X-IF wrapper transaction FSM;
- vaddr / vwr64 / vrd64 VRF access protocol;
- 4-bank VRF and multi-index tests;
- hclr and bclr clear commands;
- Lane-local Boolean/Mask Core with real hbind;
- Lane-local Popcount/Compressor Core with real hsim;
- documentation status commit:
  - f20e9dfc HDEC Phase1: document implementation status.

Current active work may include:

- Shift-Align Core + real hperm;
- pure 4-bit-granularity shift only;
- no full 0..63-bit shift hardware;
- no SUPPORT_FULL_BIT_SHIFT parameter;
- no full-bit mode;
- no extra full-bit mux, bypass, or compatibility path;
- hperm supports only rot_amt that is a multiple of 4;
- rot_amt[1:0] != 0 must return STATUS_ERROR and must not modify VRF;
- dst_hv_id == src_hv_id must return STATUS_ERROR and must not modify VRF.

Use `git log --oneline -8` and `git status --short` as the source of truth. Do not assume the worktree equals the latest commit.

Full 0..63-bit shift is not the HDEC mainline. It may only be considered later as a separate paper comparison experiment, not as the default architecture direction.

---

## 2. Architecture Direction

The HDEC Lane architecture follows these principles:

- static parallel compute blocks;
- simple compute cores should be pure combinational logic;
- complex cores may later use local micro-pipeline registers;
- no complex FSM inside Lane compute cores;
- operand isolation for unused compute blocks;
- future engine-level arbitration and tag routing;
- HDC uses the main VRF;
- future ECC may use a separate Shadow RF;
- all real arithmetic/logic compute must be inside Lane-level compute modules.

Current completed Lane compute blocks:

### Boolean/Mask Core

HDC use:

- hbind:
  - HVdst = HVsrc0 XOR HVsrc1.

Future ECC use:

- constant-time cswap;
- mask-select;
- Montgomery ladder conditional swap.

### Popcount/Compressor Core

HDC use:

- hsim:
  - distance = popcount(src0 XOR src1).

Future ECC use:

- SAIR carry-save compression;
- csa_sum / csa_carry / csa_cout structure.

### Shift-Align Core

Current HDC use:

- hperm:
  - HVdst = ROTR(HVsrc, rot_amt).

Future ECC use:

- 4-bit-window SAIR partial-product alignment.

Mainline decision:

- pure 4-bit granularity;
- no full-bit shift hardware;
- no full-bit compatibility hardware.

---

## 3. Creative Thinking Is Allowed

You are encouraged to think.

You may:

- question the current plan;
- identify hidden bugs;
- identify risks that the user may have missed;
- propose lower-area designs;
- propose lower-power designs;
- propose simpler control logic;
- propose better verification methods;
- suggest additional tests;
- compare multiple design options;
- explain why the current plan may be wrong;
- recommend a better solution.

This creativity is valuable.

But analysis is not implementation approval.

You must clearly separate:

1. What is already approved and should be implemented now.
2. What is your new suggestion or concern.
3. What requires user approval before implementation.

Do not silently implement your own new idea.

---

## 4. Controlled Execution Rule

When a task has an approved implementation scope, only modify files and behavior inside that approved scope.

If you discover another issue while implementing:

- do not secretly fix it;
- do not expand the patch;
- report it as a separate finding;
- include evidence;
- suggest fix options;
- wait for approval.

Exception:

- trivial typo/comment fixes inside the explicitly touched files are acceptable if they do not change behavior.

For non-trivial issues, use this reporting format:

1. Observation
2. Evidence
3. Possible root cause
4. Suggested fix options
5. Recommended option
6. Files that would need changes
7. Tests needed
8. Whether this blocks the current task

Wait for user approval before implementing the new fix.

---

## 5. Files That Must Not Be Changed Unless Explicitly Approved

Do not modify these unless the current task explicitly says so:

- core/hdec/rtl/hdec_cvxif_wrapper.sv
- core/hdec/rtl/hdec_vrf_64x256.sv
- core/hdec/rtl/hdec_lane_boolean_mask.sv
- core/hdec/rtl/hdec_lane_popcount_compressor.sv
- corev_apu/src/ariane.sv

Do not change existing behavior unless explicitly requested:

- vaddr
- vwr64
- vrd64
- hclr
- bclr
- hbind
- hsim

Never rewrite stable FSMs just to make the code look cleaner.

Never introduce a complex control network when a smaller state machine or local mux is enough.

---

## 6. RTL Design Rules

All compute datapaths must stay inside Lane-level compute modules.

hdec_top may do:

- instruction parameter parsing;
- VRF address generation;
- chunk loop control;
- word/block selection;
- simple scalar accumulation for current transition-stage designs;
- status/result return.

hdec_top must not implement the real datapath operation when a Lane compute core exists.

Examples:

- XOR for hbind must stay in Boolean/Mask Core.
- popcount for hsim must stay in Popcount/Compressor Core.
- shift/align for hperm must stay in Shift-Align Core.
- hdec_top must not directly implement:
  - `(a >> shift) | (b << ...)`.

Lane compute cores must not contain complex valid/ready/busy FSMs.

Lane compute cores should be:

- small;
- locally verifiable;
- preferably pure combinational;
- protected by operand isolation at the input side when not active.

---

## 7. Shift-Align / hperm Rules

HDEC Shift-Align mainline is pure 4-bit granularity.

Do not implement:

- full 0..63-bit shift;
- SUPPORT_FULL_BIT_SHIFT;
- full-bit mode;
- full-bit mux;
- extra bypass for future full-bit mode;
- direction mode unless explicitly requested;
- HDC/ECC mode inside the Shift-Align Core.

hperm semantics:

- HVdst = ROTR(HVsrc, rot_amt).

Instruction parameter format:

- rs1[3:0]   = dst_hv_id
- rs1[7:4]   = src_hv_id
- rs1[17:8]  = rot_amt[9:0]

Legal condition:

- rot_amt[1:0] == 0.

Illegal conditions:

- rot_amt[1:0] != 0:
  - return STATUS_ERROR;
  - do not modify VRF.

- dst_hv_id == src_hv_id:
  - return STATUS_ERROR;
  - do not modify VRF.

rot_amt = 0 is legal if dst_hv_id != src_hv_id. It means copying the source HV to the destination HV.

Shift amount split:

- 64-bit block offset = rot_amt[9:6]
- 4-bit small offset  = rot_amt[5:2]
- Lane internal shift = rot_amt[5:2] * 4

Shift-Align Core behavior:

- input A: first 64-bit source block;
- input B: second 64-bit source block;
- input shift: 4-bit granularity offset, 0..15;
- output: one 64-bit result.

Rules:

- if shift offset is 0:
  - result = A
- otherwise:
  - result = A shifted right by the selected 4-bit amount
  - combined with B shifted left to fill the high bits.

Must explicitly handle shift offset 0.

Do not generate a left shift by 64.

HDC/ECC distinction:

- HDC uses circular wrap-around source selection.
- ECC future SAIR will use zero-fill or non-wrap source selection.
- The Shift-Align Core itself must not know whether the caller is HDC or ECC.

---

## 8. Low-Power Rules

Operand isolation is part of the architecture.

If a Lane compute block is not active, its high-toggle inputs should be held stable or driven to zero at the input side.

For example:

- Boolean/Mask Core should not toggle when not used.
- Popcount/Compressor Core should not toggle when not used.
- Shift-Align Core should not toggle when not used.

Do not add complex valid/ready/busy FSMs inside compute cores just to isolate operands.

Preferred style:

- simple valid signal at Lane wrapper level;
- when invalid, drive compute-core inputs to zero;
- keep compute core pure and small.

---

## 9. Planning Rules

Before modifying code, output a short plan in Chinese.

The plan must include:

- files to be modified;
- files that must not be modified;
- exact RTL behavior to add;
- tests to run;
- risk points;
- expected commit message.

Do not start editing until the user approves.

For large tasks, first produce a plan only. Do not write code in the same response.

If you believe the confirmed plan is suboptimal, you may propose improvements, but do not implement them without approval.

---

## 10. Debugging Rules

When a build or test fails:

- stop;
- do not blindly patch;
- report the failing command;
- report the log path;
- report relevant log excerpts;
- identify the likely layer:
  - test issue;
  - build issue;
  - CV-X-IF wrapper issue;
  - VRF timing issue;
  - hdec_top FSM issue;
  - Lane compute issue;
  - environment/tool permission issue.

Do not modify RTL until the root cause is reasonably isolated.

If the issue is unclear, report evidence and ask for review instead of guessing.

You may propose likely causes and suggested fixes, but do not implement a fix until approved.

---

## 11. Testing Rules

Do not use `timeout ... | grep ...` as the only test judgment.

Use full logs.

Build and simulation logs should be saved under:

- tmp/hdec_logs/

A test is PASS only if:

- the build/compile step exits successfully;
- the log is freshly generated for the current run;
- the log contains a clear success marker, such as:
  - `*** SUCCESS ***`
  - `All tests PASSED`
- the log does not contain obvious failure markers:
  - FAILED
  - FAIL
  - Fatal
  - ASSERT
  - Aborted
  - core dumped
  - Segmentation fault

RUN_EXIT=124 is acceptable only when the log already contains a clear SUCCESS marker and the testharness waits for timeout after success.

If the log has no SUCCESS and no clear failure marker, report NO_DECISION and do not guess.

After touching HDEC RTL, required regression normally includes:

- multi_index_test
- hclr_test
- bclr_test
- hbind_test
- hsim_test
- any new test for the current feature

For hperm / Shift-Align, required tests include:

Legal rot_amt:

- 0
- 4
- 60
- 64
- 68
- 252
- 256
- 508
- 1020

Illegal rot_amt:

- 1
- 63
- 1023

Also test:

- dst == src returns STATUS_ERROR;
- illegal cases do not modify VRF;
- source HV is not destroyed.

---

## 12. Git Rules

Do not commit unless explicitly asked.

Before recommending commit, output:

- git status --short
- git diff --stat
- modified files;
- untracked files that should be included;
- untracked files that must not be included;
- tests passed.

Never commit:

- tmp/hdec_logs/
- ELF binaries
- simulation logs
- verif/core-v-verif
- unreviewed docs
- unrelated files

AGENTS.md and CLAUDE.md should normally be committed separately from RTL feature commits.

Do not mix agent-rule commits with RTL feature commits unless explicitly approved.

---

## 13. Multi-Agent Workflow

The project uses three roles.

### ClaudeCode + DeepSeek

Used for:

- low-cost plan drafting;
- code review;
- log collection;
- documentation;
- checking possible risks.

ClaudeCode must not make final architecture decisions alone.

ClaudeCode must not blindly fix RTL.

### ChatGPT Web

Used for:

- architecture review;
- critical plan review;
- root-cause judgment;
- deciding whether a suggested fix is real;
- deciding whether Codex should modify RTL.

### Codex + GPT-5.5

Used for:

- final execution of confirmed plans;
- key RTL implementation;
- high-value code changes;
- critical bug fixes after approval.

If you are Codex:

- you are the execution agent;
- you may think critically and propose improvements;
- you must not re-architect the project without approval;
- if ClaudeCode review finds issues, wait for the user or ChatGPT to decide which issues are real before fixing.

Important:

- Codex creativity is welcome in plan/review/debug analysis.
- Codex implementation must stay within the approved edit scope.
- New ideas should be reported as recommendations, not silently implemented.

---

## 14. Current Project Status Pointer

Before starting any substantial task, read:

- AGENTS.md
- docs/hdec/phase1_status.md
- git log --oneline -8
- git status --short

Use the current git history as the source of truth for completed Phase 1 features.

If the worktree has uncommitted changes, inspect them before planning new edits.

Do not assume the worktree equals the latest commit.

---

## 15. Output Language

Use Chinese for explanations, plans, reviews, and status reports unless the user explicitly asks for English.

Keep explanations clear and practical.

Avoid unnecessary jargon.

When technical English terms are necessary, include a short Chinese explanation.