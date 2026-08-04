# VV35 post-route gate-level SAIF flow

`run_vv35_gate_saif.ps1` exports the frozen routed checkpoint as a timesim
netlist plus max-corner SDF, removes only SDF `TIMINGCHECK` groups, runs the
public-interface serial and interleaved workloads, records the physical DUT
network into SAIF, and applies each SAIF to that same routed checkpoint for
Vivado power analysis.

The flow never recompiles or edits RTL.  It uses the same gate netlist,
checkpoint, vectors, clock period, task count, and result checks for both
scenarios.  Runtime request timing is the only serial/interleaved variable.

## Mapping pilot

Use a short no-SDF run to validate hierarchy mapping before paying the runtime
cost of a complete timing simulation.  A non-default task count requires an
explicit measurement window.

```powershell
& .\scripts\hdec\vv35_eval\run_vv35_gate_saif.ps1 `
  -Scenario BOTH `
  -TaskCount 64 `
  -WindowCycles 155000 `
  -UseSdf $false
```

This is a mapping and flow pilot only.  It is not the final glitch-aware power
comparison.

## Frozen full comparison

```powershell
& .\scripts\hdec\vv35_eval\run_vv35_gate_saif.ps1 `
  -Scenario BOTH `
  -TaskCount 1632 `
  -UseSdf $true
```

For the frozen workload the runner selects 337853 serial cycles and 200144
interleaved cycles.  It writes one manifest, a CSV table, XSim logs, SAIF files,
Vivado power logs, and full power reports.  The manifest records hashes for the
checkpoint, exported netlist, raw and delay-only SDF, vector manifest,
testbench, runner, SAIF script, and power script.

The resulting values remain activity-based estimates from a routed FPGA model.
They are stronger than RTL-SAIF estimates because physical net names and routed
delays are represented, but they are not board measurements.
