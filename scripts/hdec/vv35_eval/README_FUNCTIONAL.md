# VV35 functional and cycle runner

Run from the VV35 worktree:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  scripts/hdec/vv35_eval/run_vv35_functional.ps1 -Suite quick
```

Suites are `smoke`, `quick`, `ecc_direct`, `hdc_direct`, and `full`. Supplying `-Seed <64-hex>` replays the exact random input bundle. The `ecc_direct` suite is a short add, reduction, and inversion contract subset. The `hdc_direct` suite reruns the legacy full-flow HDC contract with Vivado 2024.2 relaxed language checking, needed only because that testbench declares a timescale while synthesizable modules rely on the simulator default. All four direct contracts are also part of `full`.

PASS is determined only from the simulator result log. A test passes when Vivado returns zero, the generic `xvlog`, `xelab`, and `xsim` exit codes are all zero, the test's exact PASS marker appears exactly once in `xsim.log`, no failure marker appears there, and every reported coverage count matches its expected value. The Vivado batch transcript is never searched for PASS because it can echo simulator output and duplicate the marker.

The vector bundle has two traceable sources under one master seed. VV31 supplies K-233 PMUL and HDC vectors. VV30 supplies the mutually dependent primitive GF, GFMAC, inversion, and square group required by older contracts. The runner regenerates `gf_mul_expected.mem` with the existing VV30 reference model and records final per-file hashes.

The first quick probe performed while building this runner correctly failed only `gfmac_tail_fusion`: the VV31-only directory did not contain `gf_acc_inputs.mem` and `gf_mac_expected.mem`, so XSim read unknown values. That result is classified as `TEST_INFRASTRUCTURE_VECTOR_BUNDLE_INCOMPLETE`, not as an RTL failure. The original failed manifest and log remain in `tmp/hdec_logs/vv35_eval/functional_20260803_102545_193`.

The corrected replay using the same master seed passed all seven quick tests. Its evidence is in `tmp/hdec_logs/vv35_eval/functional_20260803_103040_988`.
