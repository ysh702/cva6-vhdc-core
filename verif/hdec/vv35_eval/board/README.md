# VV35 CVA6+HDEC board workload

This directory provides the board endpoint of the same workload used by the
RTL and post-route gate tests: one sect233k1 PMUL and 1,632 four-class HMATCH
operations. SERIAL and INTERLEAVED use the same vectors, operation counts and
bitstream. Only the HMATCH release time changes.

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

This source is an endpoint for the repository's existing CVA6 bare-metal flow,
not a standalone board project. The laboratory must supply its normal linker
script, startup, bitstream build, GPIO address and JTAG load procedure.

Raw CSV input accepted by the energy script is either

```text
timestamp_s,marker,rail,power_w
```

or

```text
timestamp_s,marker,rail,voltage_v,current_a
```

Rows sharing a timestamp are summed, which supports multiple measured rails.

Example integration command:

```bash
python scripts/hdec/vv35_eval/board/compute_vv35_board_energy.py serial.csv \
  --scenario SERIAL --rail-scope VCCINT+VCCBRAM \
  --idle-trace idle_spin.csv --repeat-count 100 \
  --rdcycle-delta <result_block_delta> --rdcycle-frequency-hz <cpu_hz> \
  --bitstream-sha256 <sha256> --firmware-sha256 <sha256> \
  --vector-bundle-sha256 <sha256> --output serial.json
```

Use the same arguments and hashes for INTERLEAVED. The comparison utility
refuses pairs whose image hashes, vectors, rail scope, clock relation or PMUL
wait contract differ.
