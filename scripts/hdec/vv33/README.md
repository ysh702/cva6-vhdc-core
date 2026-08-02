# VV33 fixed-workload verification

The original `phase_lifetime` probe is retired.  Its testbench referenced the
removed `vv33_fg_*` experimental sidecar signals and its single-HBIND/single-
HSIM workload could not measure end-to-end scheduling benefit.  The old runner
now delegates to the fixed-workload smoke comparison so existing commands fail
forward to a maintained test rather than compiling stale hierarchy names.

## Fixed-workload comparison

`run_vv33_fixed_workload.ps1` runs a matched serial/interleaved experiment.
The `full` suite preserves the originally requested one legal random K-233 PMUL
with 46 HDC training/inference episodes.  It is retained for traceability, not
as an equal-work normalization.  Measured standalone HDC cost is 874 cycles per
episode, so 46 episodes represent 40204 cycles rather than 146908 PMUL cycles.

The `equalized` suite uses 168 episodes.  This is the nearest integer to
`146908 / 874 = 168.087`.  The runner does not assume those historical values
when reporting a result.  It recomputes cycles per episode and the nearest
equalized count from the standalone HDC and PMUL cycles measured in that same
run.

The serial top sets `VV33_FINE_INTERLEAVE=0` by
`defparam` and deliberately presents no HDC request until PMUL completes.  This
is important because the older background-job protocol can still yield at
coarse boundaries even when the VV33 window is disabled.  The interleaved top
uses the candidate RTL default and presents HDC work immediately.  Both runs
use the same vector bundle and the same HDC operation order.

The 4-BRAM layout cannot hold 46 complete external HDC vector sets while PMUL
owns rows 32--63 and the HDC counter occupies rows 16--31.  Therefore the test
preloads one random base hypervector before timing.  Each episode derives four
different encoded training samples with legal four-bit-aligned HPERM rotations,
then executes HPERM, HBIND, HCNTADD, HCNTCLIP, HSIM, and HMATCH.  No host VRF
load or result read is present inside the timed interval.  Preload cycles are
reported separately.

Quick two-episode compile and smoke comparison:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\hdec\vv33\run_vv33_fixed_workload.ps1 `
  -Suite smoke -Mode compare
```

Formal 46-episode comparison:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\hdec\vv33\run_vv33_fixed_workload.ps1 `
  -Suite full -Mode compare
```

Equal-work comparison:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\hdec\vv33\run_vv33_fixed_workload.ps1 `
  -Suite equalized -Mode compare
```

Seed replay:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\hdec\vv33\run_vv33_fixed_workload.ps1 `
  -Suite full -Mode compare -Seed <64-hex-digit-seed>
```

For every compare run, the manifest derives and records:

```text
C_serial,components = C_PMUL + C_HDC
C_serial,measured   = measured strict-serial wall time
C_ideal             = max(C_PMUL, C_HDC)
C_gap               = C_serial,measured - C_ideal
C_saved             = C_serial,measured - C_interleaved
```

It also records the small control overhead between the component sum and the
measured serial wall time.  The manifest keeps functional PASS separate from
the method evidence gate.  A run remains `method_evidence_gate=NOT_MET` if it
lacks data-bearing overlap, changes standalone HDC timing, increases PMUL wall
time, or saves less than 5% of the fixed-workload serial wall time.

## Complete-inference contract

The paired-return search benchmark remains available in
`run_vv33_bank_episode_interleave.ps1`.  Add `-FullInference` to run the primary
accelerator-resident inference contract instead:

```powershell
powershell -ExecutionPolicy Bypass -File `
  scripts\hdec\vv33\run_vv33_bank_episode_interleave.ps1 -FullInference
```

Each complete inference executes `HPERM`, `HBIND`, then a three-class
highest-overlap `HMATCH`.  Model and binary-input loads are outside all timing
windows.  The runner generates one fresh legal K-233 scalar, performs a
capacity probe, freezes the completed inference count, then measures the exact
same workload as standalone HDC, actual serial HDEC and fixed-work mixed HDEC.
Its primary metrics are the three raw cycle values plus the serial cycle
reduction:

```text
C_dual_reference = max(C_PMUL, C_HDC_batch)
C_saved          = C_serial_measured - C_interleaved
R_cycle          = C_saved / C_serial_measured
```

`C_dual_reference` is a compute-only theoretical reference derived from two
standalone measurements.  It is not a measured two-accelerator system.
