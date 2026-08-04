# VV35 ASIC mapped-gate validation and activity-based power (R16)

## Outcome

The available VV35 ASIC flow is complete and accepted for mapped-gate,
pre-layout evaluation. Remote LSF job `10912` completed both matched scenarios
with `workflow_status=PASS` and exit code 0. The returned archive and all 34
files listed by its internal manifest passed independent local SHA-256 checks.

The power numbers below are driven by activity captured from the R13
max-SDF-requested mapped-gate testbench runs. They are not based on an assumed
average toggle rate. R16 reuses the R13 DDC and SAIF files read-only and does
not rerun VCS or modify the R13 result tree.

## Run identity

| Field | Value |
|---|---|
| Branch | `VV35` |
| RTL checkpoint | `498e957761d562030b67c68cb13e60bcdfd4da0c` |
| Remote job / host | `10912` / `js05` |
| Runtime | 2026-08-04 18:59:21Z to 19:00:09Z (48 s) |
| Tool | Synopsys Design Compiler `T-2022.03-SP5-2` |
| Corner / library | `wc_1.00V_125C` / `CORE65LPSVT` |
| Top / clock | `hdec_top` / 5.000 ns (200 MHz) |
| VRF implementation | `REG_VRF`, 16,384 bits in standard-cell registers |
| Qualification | `MAPPED_GATE_SYNTHESIS_LEVEL_DC_POWER_WITH_R13_SDF_GATE_TB_SAIF_NO_PLACEMENT_ROUTE_PARASITICS` |

## Matched workload

SERIAL and INTERLEAVED use the same mapped DDC, netlist/SDF provenance,
testbench, vectors, operation counts, clock and activity-window boundary. Only
HMATCH release timing changes.

| Scenario | PMUL | HMATCH | Cycles | Time at 200 MHz |
|---|---:|---:|---:|---:|
| SERIAL | 1 | 1,632 | 337,853 | 1.689265 ms |
| INTERLEAVED | 1 | 1,632 | 200,144 | 1.000720 ms |

Interleaving removes 137,709 cycles (`40.760034690%`) and gives a
`1.688049604x` speedup.

## Power and energy

Power is taken from the explicit DC summary components. Total power is dynamic
power plus leakage, and energy is independently computed from the unrounded
power and the exact frozen execution time.

| Metric | SERIAL | INTERLEAVED | Change |
|---|---:|---:|---:|
| Cell internal power | 26.2045 mW | 26.6568 mW | — |
| Net switching power | 2.2056 mW | 2.4552 mW | — |
| Dynamic power | 28.4100 mW | 29.1120 mW | +2.470961% |
| Leakage power | 0.1774186 mW | 0.1774459 mW | +0.015387% |
| Total power | 28.5874186 mW | 29.2894459 mW | +2.455721% |
| Dynamic energy | 0.04799201865 mJ | 0.02913296064 mJ | -39.296238292% |
| Total energy | 0.0482917256813 mJ | 0.029310534301 mJ | -39.305266301% |

Thus the same scheduling effect seen on FPGA is reproduced on the ASIC mapped
gate model: interleaving raises average power slightly, but the shorter runtime
reduces energy to solution substantially.

## Activity integrity

Both SAIF files are nonzero-activity outputs of the R13 gate testbench and are
bound at `tb_vv35_schedule_gate/dut`. R16 consumed the SAIFs directly; it did
not use the compressed VCD files as live inputs.

| Audit | SERIAL | INTERLEAVED |
|---|---:|---:|
| SAIF duration | 1,689,265 ns | 1,000,720 ns |
| SAIF transaction count | 21,760,658,744,836 | 14,267,579,704,836 |
| Nets user annotated | 56,212 / 56,212 (100%) | 56,212 / 56,212 (100%) |
| Ports user annotated | 201 / 201 (100%) | 201 / 201 (100%) |
| Pins user annotated | 222,686 / 222,686 (100%) | 222,686 / 222,686 (100%) |
| Default / propagated activity | 0% / 0% | 0% / 0% |
| DC power execution | PASS | PASS |

The DC annotation percentages and Vivado's FPGA direct-net annotation
percentage use different object sets, denominators and tool semantics. They are
quality checks within each flow and must not be compared numerically.

## Area and timing context

Both scenarios load the same DDC, so area and timing are identical. The area
report uses library area units. Net/interconnect area and therefore total area
are undefined in this wire-load pre-layout report; the valid figure is total
cell area.

| Metric | Result |
|---|---:|
| Cells | 55,922 |
| Combinational cells | 37,825 |
| Sequential cells | 18,082 |
| Macros / black boxes | 0 |
| Combinational area | 154,476.917618 library area units |
| Noncombinational area | 144,123.722771 library area units |
| Total cell area | 298,600.640388 library area units |

DC reported 50 worst maximum-delay paths at the 5 ns constraint; all 50 are
`MET`, with the worst displayed slack `0.00 ns` at the report's two-decimal
precision. This is synthesis-level timing at `wc_1.00V_125C`, using ideal clock
network delay and the reported enclosed wire-load model. It is not a routed-RC
timing result.

The ASIC VRF is standard-cell `REG_VRF`, while the FPGA implementation uses
four BRAMs. Absolute FPGA and ASIC area or power are therefore not a
like-for-like technology comparison, and the register-based ASIC result is
generally pessimistic relative to a characterized SRAM-macro implementation.

## Integrity and evidence

- Downloaded archive SHA-256:
  `8943ae6caf52f55ab0bab45f1f33193222cbc1b68d1120c5bcce489ce5c34a2f`.
- The independently downloaded `.sha256` and `archive_status_r16.txt` agree
  with the locally calculated archive hash; `archive_status=PASS` and
  `final_exit_code=0`.
- The internal `vv35_asic_power_only_r16_files.sha256` manifest lists 34 files;
  local rehash result: 34 checked, 0 mismatches.
- The bounded local acceptance rerun completed 373 checks with
  `overall_status=PASS` and zero required failures. Its script and JSON result
  are preserved in `local_acceptance/`.
- `raw_remote/` preserves the returned reports, job status and submission
  trace. `download_verification/` preserves the exact source archive and its
  two external integrity records.
- `VV35_ASIC_R16_METRICS.csv` is the compact publication table; values retain
  the precision of the accepted DC reports and independently recomputed energy.

The repository-wide FPGA/ASIC comparison and the R13 functional/gate
verification provenance are consolidated in
`../VV35_FINAL_FPGA_ASIC_EVIDENCE_MAP_20260805.md`.
