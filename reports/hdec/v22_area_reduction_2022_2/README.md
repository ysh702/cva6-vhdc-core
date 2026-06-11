# HDEC ECC V22 area reduction log

Date: 2026-06-11
Branch: `hdec-ecc-pointmul-v22`
Base: `origin/hdec-ecc-pointmul-v21` / `08425ba5`
Vivado used for V22: 2022.2
Part: `xc7z020clg400-2`
Top: `hdec_top`
Constraint: 5.000 ns, OOC synthesis

## V20/V21 understanding

V20 is the architectural checkpoint that changed PMUL from the earlier Montgomery/Lopez-Dahab style with full projective point state into a true x-only ladder. The PMUL loop now keeps only X/Z for the two ladder points, and Y is recovered only during the final affine reconstruction. This is why the reported PMUL cycle count dropped from the V18 18414-cycle point multiply to 6005 cycles, while area also improved.

V21 is a cleanup checkpoint on top of V20. It removed source-level dead state such as unused ECC copy-source bookkeeping, the unused VRF reset port, the unused top-level operand-B mirror, and the unused HCNTADD chunk mirror. The V21 report shows no post-synthesis resource change versus V20 because Vivado was already pruning those elements.

## V21 reference from remote report

The remote V21 report was generated with Vivado 2024.2:

| Version | WNS (ns) | Est. Fmax (MHz) | Slice LUT | Logic LUT | LUTRAM | FF | PMUL cycles | HDC full-flow |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| V21 remote report | 0.293 | 212.450 | 6459 | 5987 | 472 | 2150 | 6005 | PASS |

## V22 local baseline

Because this work uses Vivado 2022.2, V22 uses the following local baseline for round-to-round comparisons:

| Version | Vivado | WNS (ns) | Est. Fmax (MHz) | Slice LUT | Logic LUT | LUTRAM | FF | CARRY4 | PMUL cycles | HDC full-flow |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| V22 baseline, V21 RTL | 2022.2 | 0.147 | 206.058 | 6756 | 6284 | 472 | 2153 | 22 | 6005 | PASS |

Baseline artifacts:

- `baseline_xsim/ecc_pmul_xsim.log`
- `baseline_xsim/hdc_full_flow_xsim.log`
- `baseline_ooc_200/run_summary.txt`
- `baseline_ooc_200/utilization.rpt`
- `baseline_ooc_200/utilization_hier.rpt`
- `baseline_ooc_200/timing_top200.csv`
- `baseline_ooc_200/timing_summary_top50.rpt`

## V22 verification note

The original V20 HDC full-flow testbench passed in the remote V21 Vivado 2024.2 report but failed under Vivado 2022.2 because loop-local expressions inside the pattern writer were evaluated incompatibly. V22 keeps RTL unchanged for the baseline and rewrites the HDC full-flow testbench to compute bank, row offset, and pattern data in explicit local steps. After this testbench-only compatibility fix, Vivado 2022.2 full-flow XSIM passes.

## Optimization rule

The V22 loop is:

1. Two small area-oriented optimizations.
2. One larger structural refactor.
3. Run ECC PMUL XSIM and HDC full-flow XSIM after every three RTL modification rounds.
4. For a retained round, commit the RTL/report state and compare against both the local V22 baseline and the remote V21 report.

The acceptance target is at least 200 MHz. Frequency above 200 MHz is useful margin but not the primary objective. PMUL cycles should stay at 6005 or decrease; small cycle increases are not desired for this version. The primary goal is lower LUT/FF.
