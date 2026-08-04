# VV35 final FPGA/ASIC evidence map (2026-08-05)

## 1. Current outcome

VV35 FPGA validation is complete for post-route implementation, repeated ZYNQ-7020
functional/cycle execution, and routed-netlist gate-SAIF power estimation. The
physical board rail power is **not measured**. ASIC mapped-gate synthesis and both
zero-delay and max-SDF-requested gate simulations are complete in R13; the gate
runs passed with no SDF error marker, but the retained evidence does not quantify
SDF annotation coverage. The final matched SERIAL/INTERLEAVED DC power
publication completed with **R16 PASS** from the same R13 DDC and real
testbench-derived SAIF activity. R16 reports a 2.455721% increase in average
total power for INTERLEAVED, but its shorter frozen execution window reduces
total energy by 39.305266301%.

The ASIC evidence available on the remote host is synthesis-level pre-layout
evidence. Within R6's defined `/data/synopsys` search and safe-probe scope, no
usable native physical-implementation shell was identified, so this document
makes no ASIC placement, routing, extracted-RC, or post-layout power claim.

## 2. Frozen comparison contract

- Branch: `VV35`.
- FPGA post-route and routed gate-SAIF manifests pin `ba053f51...`; the board
  core baseline and ASIC R13/R16 source checkpoint pin
  `498e957761d562030b67c68cb13e60bcdfd4da0c`; the board evidence/harness was
  finalized at `d3030f52be932e5eda80d805cde0f67ad781eddf`. The HDEC core RTL is
  unchanged across these endpoints; the endpoint commits are nevertheless
  recorded separately rather than treated as one run identity.
- Top and clock: standalone `hdec_top`, 5.000 ns, 200 MHz.
- Current normalized workload contract canonical-LF SHA-256:
  `8797b88f22244a52cbc530dff977ed5c8f79f141c3e5f883b9337330d8f4464a`.
- Frozen vector-manifest SHA-256:
  `1a79121c84b9147bdd366d88165cc48df8d9037a283552a3acbfcdc1e4afaa73`.
- Workload: one legal random K-233 PMUL and 1,632 identical four-class HMATCH
  requests. Expected HMATCH class/score/result are class 0, 505, and `0x1f9`.
- The earlier FPGA gate manifests directly pin the frozen vector hash and exact
  cycle windows; their equivalence to the current normalized JSON contract is
  established by those vectors and windows, not by claiming that the older runs
  consumed the current JSON bytes.
- Within each technology, SERIAL and INTERLEAVED use the same RTL/netlist,
  vectors, operation counts, clock, voltage/corner or FPGA image, and
  measurement-boundary definition. Only HMATCH request release timing changes;
  the two activity windows intentionally have different durations.
- Reset, vector preload, warm-up, final status query, and result readback are
  outside the activity window. All 1,632 HMATCH responses must finish within
  the frozen window, and PMUL result/status are checked immediately afterward.

| Scenario | PMUL | HMATCH | Frozen cycles | Time at 200 MHz |
|---|---:|---:|---:|---:|
| SERIAL | 1 | 1,632 | 337,853 | 1.689265 ms |
| INTERLEAVED | 1 | 1,632 | 200,144 | 1.000720 ms |

The interleaved schedule saves 137,709 cycles, a 40.760034690% reduction, and
provides a 1.688049604x speedup. These exact windows are shared by the RTL
public-interface test, FPGA post-route gate test, board controller, and ASIC
mapped-gate testbench.

## 3. FPGA evidence

### 3.1 Vivado 2024.2 post-route board implementation

The board image was built with Vivado 2024.2 (build 5239630) for
`xc7z020clg400-2`. This is genuine FPGA placement-and-routing evidence, not an
ASIC layout result.

| Metric | Final result |
|---|---:|
| Setup WNS / TNS | +0.064 ns / 0.000 ns |
| Hold WHS / THS | +0.031 ns / 0.000 ns |
| Setup / hold failing endpoints | 0 / 0 |
| Unconstrained internal endpoints | 0 |
| Fully routed nets | 10,691 / 10,691 |
| Routing errors | 0 |
| Full board Slice LUT / FF | 7,302 / 5,435 |
| HDEC hierarchy Slice LUT / FF | 4,738 / 1,513 |
| HDEC hierarchy BRAM / DSP | 4 / 0 |

Bitstream DRC completed with 0 errors and 27 warnings. The retained warnings
include 20 HDEC BRAM asynchronous-reset `REQP-1839` warnings plus standalone
PL/debug-hub warnings; they did not prevent timing closure, complete routing,
or bitstream generation, but must not be reported as zero warnings.

### 3.2 ZYNQ-7020 silicon function and cycles

Five repetitions of each INTERLEAVED, SERIAL, and CLOCKED_IDLE scenario passed
strict field-by-field VIO validation: **15/15 scenarios PASS**. Both active
scenarios completed 1,632 HMATCH operations with zero errors and returned final
HMATCH `0x1f9` and status `0x48`.

| Scenario | Window cycles | Natural final HMATCH cycle | Repeats | Result |
|---|---:|---:|---:|---|
| INTERLEAVED | 200,144 | 200,114 | 5 | PASS |
| SERIAL | 337,853 | 337,853 | 5 | PASS |
| CLOCKED_IDLE | 2,000,000 | 0 | 5 | PASS |

This qualifies real-board function, result, and cycle behavior. SysMon recorded
temperature and voltages but not current, so it cannot be converted into rail
power or energy:

- `physical_rail_power=NOT_MEASURED`
- `physical_rail_energy=NOT_MEASURED`

### 3.3 Routed FPGA gate-SAIF power

The power comparison uses the same VV35 HDEC core and frozen workload on one
routed standalone HDEC DCP, with delay-only max-SDF gate simulation
(cell/path/interconnect delays retained and `TIMINGCHECK` removed) and
workload-derived SAIF. It is an activity-based post-route FPGA estimate,
independent of the later board-wrapper bitstream and not a physical rail
measurement. Static timing analysis remains the setup/hold authority. The
routed DCP closed the 5 ns internal timing target with WNS +0.042 ns.

| Metric | SERIAL | INTERLEAVED | Change |
|---|---:|---:|---:|
| Cycles | 337,853 | 200,144 | -40.760% |
| Average total power | 0.235 W | 0.285 W | +21.277% |
| Average dynamic power | 0.130 W | 0.180 W | +38.462% |
| Device static power | 0.105 W | 0.105 W | 0% |
| Estimated total energy | 0.396977 mJ | 0.285205 mJ | -28.156% |
| Estimated dynamic energy | 0.219604 mJ | 0.180130 mJ | -17.975% |

The gate SAIF directly annotated 4,139/7,284 design nets (56.82%, reported as
57%) and Vivado rated both runs `High` confidence. Remaining nets use propagated
activity, so this is stronger than an average-toggle/vectorless estimate but is
still a tool estimate. The supported interpretation is: interleaving raises
instantaneous average power while reducing execution time enough to lower
energy to solution.

## 4. ASIC evidence

### 4.1 R13 mapped-gate synthesis and gate verification

R13 generated the mapped `hdec_top` DDC/netlist/SDF at the
`wc_1p00v_125c` corner and ran both scenarios with the frozen public-interface
testbench. The overall R13 wrapper did not publish a terminal PASS because its
final parser misinterpreted the DC `report_saif` activity-annotation table; this
is not a gate-test failure. Direct audit of that raw SAIF table showed Nets,
Ports, and Pins as 100% User Annotated activity, with Default and Propagated
activity at 0%.

| R13 check | SERIAL | INTERLEAVED |
|---|---:|---:|
| Zero-delay mapped-gate simulation | PASS | PASS |
| Max-SDF requested gate simulation, no SDF error marker | PASS | PASS |
| Frozen activity cycles | 337,853 | 200,144 |
| HMATCH completed / expected | 1,632 / 1,632 | 1,632 / 1,632 |
| Testbench errors | 0 | 0 |
| Unknown public-interface samples | 0 | 0 |
| Gate-testbench activity SAIF produced | YES | YES |

The two SAIFs are derived from the actual max-SDF-requested gate-testbench
activity (with no SDF error marker), not an assumed average toggle rate. This
qualifies the activity source but does not claim quantified SDF annotation
coverage. The final R16 DC reports below publish the mapped area and pre-layout
timing for this same R13 design context.

### 4.2 R16 matched DC power publication

R16 completed **PASS** as remote LSF job `10912` on host `js05`
(`18:59:21Z`--`19:00:09Z`). It uses commit
`498e957761d562030b67c68cb13e60bcdfd4da0c`, Synopsys DC
`T-2022.03-SP5-2`, the R13 `REG_VRF` DDC, and the two R13 gate-activity SAIFs.
In this ASIC configuration, the 16,384-bit VRF is implemented by standard-cell
registers, whereas the FPGA implementation uses four BRAMs. R16 uses native
`report_power`; all results remain mapped-gate, synthesis-level, and pre-layout.

The final evidence label is:

`MAPPED_GATE_SYNTHESIS_LEVEL_DC_POWER_WITH_R13_SDF_GATE_TB_SAIF_NO_PLACEMENT_ROUTE_PARASITICS`

Here `R13_SDF_GATE_TB_SAIF` identifies the gate-testbench activity source; it
does not add a claim of quantified SDF annotation coverage.

| Metric | SERIAL | INTERLEAVED | Derived change |
|---|---:|---:|---:|
| Total power | 28.5874186 mW | 29.2894459 mW | +2.455721% |
| Dynamic power | 28.4100 mW | 29.1120 mW | +2.470961% |
| Leakage power | 0.1774186 mW | 0.1774459 mW | +0.0000273 mW |
| Total energy | 0.0482917256813 mJ | 0.029310534301 mJ | 39.305266301% reduction |
| Dynamic energy | 0.04799201865 mJ | 0.02913296064 mJ | 39.296238292% reduction |

The energy values were recomputed from the unrounded reported power and frozen
time:

```text
time_s = cycles / 200000000
energy_mJ = power_mW * time_s
energy_reduction = (serial_energy - interleaved_energy) / serial_energy
```

For both scenarios, the DC activity table reports every counted object as User
Annotated and none as Default or Propagated:

| DC activity object | Object count | User Annotated | Default | Propagated |
|---|---:|---:|---:|---:|
| Nets | 56,212 | 100% | 0% | 0% |
| Ports | 201 | 100% | 0% | 0% |
| Pins | 222,686 | 100% | 0% | 0% |

SERIAL and INTERLEAVED have identical mapped-design area:

| Area metric | R16 value for both scenarios (library area units where applicable) |
|---|---:|
| Total cells | 55,922 |
| Combinational cells | 37,825 |
| Sequential cells | 18,082 |
| Combinational area | 154,476.917618 |
| Noncombinational area | 144,123.722771 |
| Total cell area | 298,600.640388 |
| Macros | 0 |
| Total area including nets | Undefined: wire-load flow provides no net area |

Timing uses `CORE65LPSVT` at `wc_1.00V_125C` with a 5.000 ns constraint.
`report_timing` examined 50 maximum-delay paths and all were `MET`; the worst
displayed slack is 0.00 ns at two-decimal report precision. This is ideal-clock,
wire-load-model, pre-layout timing, not extracted-RC or post-route STA, and the
printed 0.00 ns must not be presented as a higher-precision margin.

Do not transplant the FPGA power numbers into this table. Only the workload,
cycle windows, and comparison rules are shared across technologies; absolute
power depends on the target library, implementation, voltage/corner, and
measurement boundary.

The Vivado 56.82% direct design-net annotation and the DC 100% User Annotated
Nets/Ports/Pins values have different denominators, object classes, and tool
semantics. They are activity-quality checks within their respective tools, not
evidence that ASIC activity coverage is higher than FPGA activity coverage.
Likewise, FPGA BRAM and ASIC standard-cell `REG_VRF` area/power are not a
like-for-like technology comparison; the register implementation is generally
more pessimistic than a characterized SRAM macro.

## 5. R6 ASIC physical-flow boundary

R6 was a read-only Synopsys physical-environment preflight, not a
placement-and-routing run. Its diagnostic job passed with exit code 0 and left
server roots unchanged, but its conclusive fields within the defined search and
safe-probe scope are:

```text
physical_flow_status=BLOCKED_NO_NATIVE_PHYSICAL_IMPLEMENTATION_SHELL
physical_implementation_shell_pass_count=0
matched_rc_technology_count=0
place_and_route_executed=0
gpdk045_used=0
```

No matching `icc_shell`, `icc2_shell`, `fc_shell`, `astro_shell`, `psyn_shell`,
or `mw_shell` physical-implementation shell passed the R6 search/probe. Neither
did a `pt_shell` analysis runtime or StarRC extraction runtime. The identified
`dc_shell` marker probe returned `rc=124`, and the safety gate set
`safe_native_parse=0`, so native database/Milkyway/NDM parsing was not executed;
this scoped marker probe does not negate the independently completed R13 DC
synthesis or R16 DC power workflow.
Accordingly, this workflow produced no floorplanning, placement, CTS, routing,
extracted parasitics, post-route STA, physical DRC/LVS, GDS, or post-layout
power. The R6 PASS qualifies the audit procedure and this scoped capability
finding; it does not upgrade R13/R16 to post-layout evidence.

## 6. Completed ASIC acceptance status

R13 zero-delay and max-SDF-requested gate verification passed with no SDF error
marker, and R16 completed the final matched DC publication with PASS. The
accepted evidence now establishes:

1. The same R13 `REG_VRF` DDC, frozen vectors, 5.000 ns clock, and exact activity
   windows were used for SERIAL and INTERLEAVED.
2. Both gate scenarios completed 1,632 HMATCH operations with zero testbench
   errors or unknown public-interface samples.
3. Both DC activity audits report 100% User Annotated Nets, Ports, and Pins with
   0% Default and Propagated activity.
4. Mapped cell counts and cell areas are identical between scenarios; total area
   including nets remains undefined because this is a wire-load pre-layout flow.
5. All 50 reported maximum-delay paths are `MET` at the printed precision under
   the same `CORE65LPSVT` `wc_1.00V_125C` context.
6. Unrounded DC power values and frozen durations reproduce the reported total
   and dynamic energies and their reductions.
7. The downloaded archive SHA-256
   `8943ae6caf52f55ab0bab45f1f33193222cbc1b68d1120c5bcce489ce5c34a2f`
   matches both external integrity records; all 34 internal manifest entries
   rehash correctly, and the bounded local acceptance completed 373 checks with
   zero required failures.

The available ASIC task is therefore complete at mapped-gate, real-activity,
pre-layout level. It is not an ASIC placement-and-routing or post-layout result.
Post-layout completion would require a working physical implementation and
parasitic-extraction toolchain; R6 did not identify one within its defined
Synopsys search and safe-probe scope.

## 7. Evidence index

- Frozen contract:
  `verif/hdec/vv35_eval/common/workload_contract.json`
- FPGA board/silicon report:
  `reports/hdec/vv35_board_silicon_20260804/VV35_BOARD_SILICON_REPORT.md`
- FPGA board repeated results:
  `reports/hdec/vv35_board_silicon_20260804/board_results_5trials_validated.csv`
- FPGA routed implementation report:
  `reports/hdec/vv35_eval_postroute_repair_20260803/VV35_POSTROUTE_REPORT.md`
- FPGA routed gate-SAIF comparison:
  `reports/hdec/vv35_eval_gate_saif_full_sdf_20260803/VV35_GATE_SAIF_POWER_COMPARISON.csv`
- FPGA routed gate-SAIF narrative:
  `reports/hdec/vv35_eval_gate_saif_full_sdf_20260803/VV35_GATE_SAIF_POWER_REPORT.md`
- FPGA same-net scheduling evidence:
  `reports/hdec/vv35_eval_same_net_20260803/VV35_SAME_NET_SCHEDULING_REPORT.md`
- FPGA/public-interface functional consolidation:
  `reports/hdec/vv35_eval_functional_20260803/VV35_FUNCTIONAL_CONSOLIDATED.md`
- FPGA/global PPA summary:
  `reports/hdec/vv35_global_ppa_20260803/VV35_FINAL_REPORT.md`
- ASIC R13/R16 synthesis, gate-verification, power, area, timing, and activity
  evidence:
  `reports/hdec/vv35_asic_dc_power_r16_20260805/`
- ASIC R6 physical preflight:
  `reports/hdec/vv35_asic_synopsys_physical_preflight_r6_20260805/README.md`
  and `synopsys_physical_conclusion_r6.txt` in the same directory.
