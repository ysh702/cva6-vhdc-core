# VV31-0 Compatibility and OOC Gate Appendix

## Scope and snapshot

This appendix closes the VV31-0 compatibility and physical-baseline gate.  No
scheduling RTL was implemented as part of this check.  The synthesized
`hdec_top.sv` snapshot had SHA-256
`64bccfab5b6a04992dab267a3d4087a257c51cf1c3653bff205c16fd8209a881`.
The full-regression manifest records aggregate RTL SHA-256
`f35984a60be229ec0b0a2433777363a045a85dd1cbbae5e60965cd8d2c59db21`.

## Commands

The compatibility run used Vivado 2024.2 and a fresh OS-CSPRNG seed:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File E:\HDEC\cva6-vhdc-core\tmp\hdec_vv31_schedule_worktree\scripts\hdec\vv30\run_vv30_regression.ps1 `
  -Suite full `
  -VivadoBin E:\Vivado\Vivado\2024.2\bin `
  -OutRoot E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_0_gate_vv30_full_20260731
```

The matched OOC synthesis used the same device and 5 ns constraint as the
entry measurement:

```powershell
E:\Vivado\Vivado\2024.2\bin\vivado.bat `
  -mode batch -nolog -nojournal -notrace `
  -source E:\HDEC\cva6-vhdc-core\tmp\hdec_vv31_schedule_worktree\scripts\hdec\vv30\vv30_ooc_final.tcl `
  -tclargs `
    E:\HDEC\cva6-vhdc-core\tmp\hdec_vv31_schedule_worktree `
    E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_0_gate_ooc_after_probes_20260731 `
    5.0 vv31_0_after_probes
```

## Functional compatibility result

All nine functional tests passed:

| Test | Evidence |
|---|---|
| Shift-align basis | 2048/2048 cases, PASS |
| Fused contribution map | 4464/4464 cases, PASS |
| Native diagonal map | 4464/4464 cases, PASS |
| Square-reduction basis and random set | 4339/4339 cases, PASS |
| GFMAC tail fusion | 4096/4096 cases, 179 cycles for GFMUL and GFMAC, zero temporary writes, PASS |
| Inversion redirect contract | 16/16 cases, PASS |
| Random-K PMUL | 16/16 legal unique random K, every case correct and exactly 159221 cycles, PASS |
| HDC full flow | `[HDEC_HDC_FULL_FLOW_V20] PASS` |
| HPERM contract | all 1024 rotation encodings and all 256 source/destination slot pairs, PASS |

The random bundle used master seed
`cd9c29eb5a40be6b480cb4e6f09889be799024e47c7c3f81519c6d811526a334`.
The 16 PMUL scalars had Hamming weights from 100 through 129.  Their identical
159221-cycle measurements show no scalar-content-dependent cycle variation in
this run.

The top-level runner reports `FAIL` only because the dedicated HPERM Tcl flow
emits the same PASS marker once into the wrapper log and once into its
`result_log`.  The runner concatenates both logs, observes
`pass_marker_count=2`, and requires exactly one marker.  The HPERM XSim result
itself has no failure-level message and terminates with
`[VV30:hperm_contract] PASS`.  This is a runner bookkeeping defect, not an RTL
functional failure.  HPERM is not used to block the ECC-scheduling stage.

## Matched OOC result

Vivado 2024.2 completed OOC synthesis successfully for
`xc7z020clg400-2`:

| Metric | VV31-0 after simulation probes | Entry baseline | Delta |
|---|---:|---:|---:|
| Logic LUT | 4651 | 4651 | 0 |
| FF | 1274 | 1274 | 0 |
| BRAM | 4 | 4 | 0 |
| DSP | 0 | 0 | 0 |
| WNS at 5 ns | 0.328 ns | 0.328 ns | 0 |
| Estimated Fmax | 214.041 MHz | 214.041 MHz | 0 |

The worst endpoint remains `group_dist_q_reg[8]/D`.  Thus the
simulation-only resource probes do not alter the synthesized hardware.

## Artifacts

- Full compatibility regression:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_0_gate_vv30_full_20260731`
- Regression manifest:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_0_gate_vv30_full_20260731\run_manifest.json`
- Matched OOC synthesis:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_0_gate_ooc_after_probes_20260731`
- OOC summary:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_0_gate_ooc_after_probes_20260731\reports\run_summary.txt`

## Gate conclusion

`ACCEPTED`

VV31-0 has a reproduced functional and physical baseline.  ECC-only
scheduling changes may now be measured cumulatively from 4651 Logic LUT,
1274 FF, 4 BRAM, 0 DSP, 0.328 ns WNS, and 159221 PMUL cycles.
