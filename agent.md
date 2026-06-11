# HDEC Optimization Agent Rules

This file records the standing optimization workflow for future HDEC ECC/HDC work.

## Core metrics

Track these metrics for every meaningful RTL optimization:

- ECC full computation status.
- ECC cycle count, especially PMUL/scalar point-multiply cycles.
- HDC full-flow test status.
- 200 MHz OOC timing status.
- Slice LUT, Logic LUT, LUTRAM, FF, BRAM, DSP, and CARRY4.

## Acceptance policy

- Keep timing at or above 200 MHz.
- Do not increase ECC cycles unless there is a clearly justified area/timing tradeoff.
- Prefer lower LUT and FF.
- LUTRAM changes must be separated from Logic LUT changes.
- BRAM and DSP should stay at 0 unless explicitly approved.
- ECC and HDC regressions must pass before a version is treated as retainable.

## Optimization loop

Use 4-round cycles.

Each 4-round cycle must contain:

- Two small optimizations: low-risk edits intended to reduce LUT/FF modestly.
- Two large optimizations: structural, architectural, algorithmic, or operator-level refactors intended to reduce LUT/FF more substantially without changing visible behavior.

For each round:

- Run Vivado OOC synthesis.
- Record Fmax/WNS, LUT, Logic LUT, LUTRAM, FF, CARRY4, and the worst path.
- Keep the edit only if it stays above 200 MHz and improves the design goal, or if it is a necessary cleanup with no PPA regression.
- Revert rejected edits before starting the next round.

After every 4 rounds:

- Run ECC regression and record cycle count.
- Run HDC full-flow regression.
- Only continue from a checkpoint where both regressions pass.

## Reporting

Every optimization version should include a project-local report under `reports/hdec/`.

The report should include:

- Branch and commit.
- Vivado version and FPGA part.
- Per-round table with action, OOC result, and keep/reject decision.
- Final comparison against the previous accepted version.
- ECC cycle count and regression status.
- HDC full-flow regression status.
- Worst path summary and next recommended target.

## Storage rule

Do not place generated Tcl, logs, reports, or Vivado temporary files on `C:`. Keep generated artifacts inside the project directory, normally under `tmp/` for transient runs and `reports/hdec/` for retained evidence.
