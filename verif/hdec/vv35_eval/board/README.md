# VV35 board workload

This directory provides the board endpoint of the same workload used by the
RTL and post-route gate tests: one sect233k1 PMUL and 1,632 four-class HMATCH
operations. SERIAL and INTERLEAVED use the same vectors, operation counts and
bitstream. Only the HMATCH release time changes.

## Attached Zynq-7020: standalone PL endpoint

The directly runnable endpoint for the currently attached `xc7z020clg400-2`
uses the unmodified default `hdec_top` RTL, a synthesizable request controller,
and VIO. It does not require a CPU, linker script, OpenOCD, or firmware:

```powershell
D:\vivado2024.2\Vivado\2024.2\bin\vivado.bat -mode batch `
  -source scripts/hdec/vv35_eval/board/build_vv35_zynq7020_board.tcl `
  -tclargs <repo-root> <out-root>

D:\vivado2024.2\Vivado\2024.2\bin\vivado.bat -mode batch `
  -source scripts/hdec/vv35_eval/board/run_vv35_zynq7020_board.tcl `
  -tclargs <out-root>/vv35_zynq7020_board.bit `
           <out-root>/vv35_zynq7020_board.ltx `
           <out-root>/board_results.csv 5
```

The runner programs one image and changes only VIO `run_mode`: `0` SERIAL,
`1` INTERLEAVED, and `2` CLOCKED_IDLE. JTAG is silent between arm and the one
completion refresh. The optional final argument is the number of repeated
three-scenario trials (default 1). Before writing each CSV row, the runner
fails closed on sequence, requested/actual mode, PASS/FAIL, controller state,
preload count, errors, cycles, completion counts and result/status words.
`window_cycles` is the frozen comparison window
(337853/200144); `hmatch_completion_cycles` is the natural time of the final
HMATCH response and is not, by itself, proof that PMUL has also completed.
Final ECC status and X/Y/guard readback are required for PASS.

The completed 2026-08-04 silicon run used five trials and produced 15/15 PASS
rows. See `reports/hdec/vv35_board_silicon_20260804/` for the qualified result
and raw-artifact hashes.

H15 is used only as a terminal PASS LED. No physical power marker is bound in
the supplied XDC because driving a board LED during the active interval adds
duration-dependent LED energy. Bind `metric_active` to a schematic-verified,
unloaded header/test point before a physical power campaign. Zynq SysMon
voltage and temperature readings do not measure rail current and therefore do
not yield board power or energy.

## Prepared CVA6 software endpoint

## Build and runtime controls

Add `vv35_board_schedule_test.S` and `vv35_board_vectors.inc` to the existing
CVA6 bare-metal test flow. The source uses the current custom-0 instruction
encodings in `hdec_pkg.sv`.

The following writable symbols can be patched through JTAG before `main`:

- `vv35_run_mode`: `0` for SERIAL, `1` for INTERLEAVED, `2` for the
  `CLOCKED_IDLE_SPIN` baseline.
- `vv35_batch_count`: `1` for precise cycle measurement. Use a larger equal
  count for both scenarios if the power instrument needs a longer window.
- `vv35_marker_mmio`: `0` disables the marker. Otherwise it is a 32-bit MMIO
  register or GPIO address written with `1` at measurement start and `0` at
  measurement end.
- `vv35_pmul_wait_cycles`: PMUL service interval expressed in CPU `rdcycle`
  ticks. Its default is `146908` and is valid only for a same-frequency,
  ungated CPU/HDEC clock.
- `vv35_idle_window_cycles`: duration of mode `2`, `CLOCKED_IDLE_SPIN`, used
  only to obtain a reproducible same-image baseline trace.

The `vv35_result_block` symbol contains eleven 64-bit words:

| Offset | Meaning |
|---:|---|
| 0 | magic `VV35LAB1` |
| 8 | error count, zero is PASS |
| 16 | run mode |
| 24 | batch count |
| 32 | measurement start `rdcycle` |
| 40 | end `rdcycle` |
| 48 | complete marked-window `rdcycle` delta |
| 56 | total HMATCH completions |
| 64 | last HMATCH result, expected `0x1f9` |
| 72 | final ECC status, expected low nibble `0x8` |
| 80 | configured `vv35_pmul_wait_cycles` |

The program also checks PMUL X/Y and VRF guard rows outside the power marker.
It returns zero through `_exit` only when all checks pass.

## Measurement procedure

1. Build one bitstream and one firmware image. Record their SHA-256 hashes.
2. Disable DVFS and keep clock, voltage, cooling and software environment
   fixed. Run SERIAL and INTERLEAVED by changing only `vv35_run_mode`.
   Verify that CPU `rdcycle` and HDEC are clocked at the same frequency. If not,
   calibrate `vv35_pmul_wait_cycles` from a PMUL-only run before comparison.
3. For cycles, set `vv35_batch_count=1` and record result-block cycles.
4. For power, capture timestamp, marker and all named rails. If one batch is
   too short for the instrument, use the same larger batch count for both
   modes and obtain at least 1,000 marked samples.
5. If incremental energy is needed, set `vv35_run_mode=2` and capture the
   supplied `CLOCKED_IDLE_SPIN` trace using the same image, clocks and rail
   scope. Record this label; it is not a WFI or board-off baseline.
6. Integrate traces with `compute_vv35_board_energy.py` and report both gross
   energy and idle-subtracted incremental energy.
7. Repeat each scenario at least five times. Report mean and standard
   deviation only from runs whose result block passes.

After producing one JSON summary for each scenario, use
`compare_vv35_board_runs.py serial.json interleaved.json` to calculate cycle
reduction, speedup, gross-energy reduction and idle-subtracted energy reduction.
Its qualification is deliberately `QUALIFIED_PER_PAIR_BOARD_COMPARISON_V2`:
one pair is not a five-trial aggregate. Retain at least five paired comparisons
and report their paired mean, standard deviation/confidence interval, and all
failed or excluded trials separately.

Board cycles include the CPU, CV-X-IF wrapper and software issue overhead.
They must be reported as measured and need not equal the standalone-core gate
references of 337,853 and 200,144 cycles. If CPU `rdcycle` and HDEC use
different clocks, report both frequencies and use the marker duration as the
wall-clock measurement.

The marker transition and `rdcycle` instruction cannot occur in the same CPU
cycle. Consequently, marker time is the authoritative board-energy window and
`rdcycle` is the authoritative system-cycle window. Do not combine the average
power from one with the duration from the other. For `batch_count>1`, the first
PMUL start response is outside the marker while the remaining starts are
inside; this is a fixed amortized boundary overhead and must be reported.

The assembly source is an endpoint for an existing CVA6 bare-metal flow, not
for the standalone PL bitstream above. A CVA6 board port must supply its linker
script, startup, CVA6+HDEC bitstream, GPIO address and JTAG load procedure.

Raw CSV input accepted by the energy script is either

```text
timestamp_s,marker,rail,power_w
```

or

```text
timestamp_s,marker,rail,voltage_v,current_a
```

Rows sharing a timestamp are summed, which supports multiple measured rails.
Every timestamp must contain each named rail exactly once; timestamps must be
strictly increasing, and the marker must contain one bounded, contiguous high
window with at least 1,000 samples per rail. The script reads and hashes the
VIO/result evidence itself and rejects a trace whose scenario, cycles or PASS
fields do not match.

Example integration command for a future physically instrumented standalone-PL
run (only after `metric_active` is bound to an unloaded test point):

```bash
python scripts/hdec/vv35_eval/board/compute_vv35_board_energy.py serial.csv \
  --idle-trace idle_spin.csv --endpoint standalone_pl_vio \
  --scenario SERIAL --batch-count 1 --trial-id pair01-serial --pair-id pair01 \
  --result-evidence board_results.csv --evidence-trial 1 \
  --cycle-delta 337853 --cycle-frequency-hz 200000000 \
  --hdec-frequency-hz 200000000 --rail-scope VCCINT+VCCBRAM \
  --instrument-model <model> --sample-rate-hz <rate> --board-id <serial> \
  --clock-config 200MHz --voltage-config nominal --temperature-c <degC> \
  --active-power-uncertainty-w <watts> --idle-power-uncertainty-w <watts> \
  --bitstream-sha256 <sha256> --vector-bundle-sha256 <sha256> \
  --output serial.json
```

Use the same physical conditions, provenance and raw idle trace for
INTERLEAVED, changing only scenario, trial ID, active trace and the expected
standalone cycle delta. For a CVA6 result-block endpoint, select
`--endpoint cva6_result_block` and additionally supply the bound result
evidence JSON, firmware SHA-256, PMUL wait cycles and CPU/HDEC clock relation.
The comparison utility refuses pairs whose images, vectors, rail grid, idle
trace, integrator, fixed conditions or workload evidence disagree; temperature
is allowed only within the encoded 1 °C pair tolerance. Signed idle-subtracted
values are retained, but percentage reduction is emitted only when both
incremental measurements exceed their supplied uncertainty.
