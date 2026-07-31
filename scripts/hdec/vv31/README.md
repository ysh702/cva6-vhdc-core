# VV31 regression runner

The runner uses Vivado Simulator 2024.2 and one replayable vector bundle for
every test in a run.  A normal invocation obtains a new 256-bit master seed
from the operating-system CSPRNG.  `K=3` is excluded from the primary random
PMUL set and appears only in the supplemental directed-scalar file.

## Entry points

```powershell
# Show registered suites and tests without requiring Vivado.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  scripts/hdec/vv31/run_vv31_regression.ps1 -ListSuites

# Generator-only smoke test. Missing testbenches do not block this mode.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  scripts/hdec/vv31/run_vv31_regression.ps1 `
  -Suite baseline_gap -VectorsOnly

# Per-candidate regression with one fresh legal random K.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  scripts/hdec/vv31/run_vv31_regression.ps1 -Suite stage

# Final/freeze multi-K regression.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  scripts/hdec/vv31/run_vv31_regression.ps1 -Suite full

# Exact replay from a previous VV31 run or vector manifest.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  scripts/hdec/vv31/run_vv31_regression.ps1 `
  -ReplayManifest <path-to-run_manifest.json> -VectorsOnly
```

Use `-PythonExe` when automatic discovery is undesirable.  The default Vivado
path is `E:\Vivado\Vivado\2024.2\bin`.

## Suites

- `baseline_gap`: current-resource-gap trace with one random legal K.
- `quick`: one random K and two HDC training/inference episodes.
- `stage`: per-candidate gate with one fresh legal random K and eight episodes.
- `full`: final/freeze gate with sixteen random K values and thirty-two
  episodes.
- `stress`: sixty-four random K values and 128 episodes.
- `replay`: explicit-seed mode; `-ReplayProfile` restores the cardinality.

Normal `stage` runs always obtain a new seed from the operating-system CSPRNG.
Use an explicit replay option only to reproduce a failure.  Do not use
`stage` as final ECC evidence; after the ECC schedule is frozen, run `full`
for the combined multi-K regression.

Every simulation must print exactly one `[VV31:<test>] PASS`.  Coverage records
use `[VV31:COVERAGE] test=<name> observed=<n> expected=<n>`.  Cycle, resource,
atomicity, and scheduling evidence should use uppercase metric tags such as
`[VV31:PMUL_CYCLE]`, `[VV31:RESOURCE_EVENT]`, and
`[VV31:SCHED_METRICS]`; all are copied into `run_manifest.json`.
