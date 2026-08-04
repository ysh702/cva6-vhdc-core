# VV35 FPGA board and ASIC laboratory handoff

This handoff freezes one measurement question across three endpoints:

> From the same VV35 RTL configuration and frozen vectors, one K-233 PMUL and
> 1,632 four-class HMATCH operations are executed either serially or with the
> committed interleaving schedule. Within each endpoint, SERIAL and
> INTERLEAVED share one unchanged image or mapped netlist. Only request timing
> changes.

The source of truth is
`verif/hdec/vv35_eval/common/workload_contract.json`. The frozen vector bundle
is stored beside it. Do not regenerate vectors independently on the board or
ASIC host.

## What is already available

- RTL and direct functional regression for `hdec_top`.
- Post-route FPGA timing and utilization flow for `xc7z020clg400-2` at 5 ns.
- Public-interface serial and interleaved gate testbench.
- Post-route gate simulation and SAIF-based Vivado power flow.

The existing FPGA SAIF is not reusable for ASIC power annotation. It contains
Xilinx physical names. ASIC activity must be regenerated from the exact DC
netlist used for power analysis.

## Afternoon checklist

### FPGA board

1. Build one bitstream and keep it unchanged for both scenarios.
2. Use the frozen vectors and identical clock/voltage settings.
3. Build one firmware binary from
   `verif/hdec/vv35_eval/board/vv35_board_schedule_test.S`. Select SERIAL or
   INTERLEAVED only through `vv35_run_mode`.
4. Set the optional marker GPIO address for the board. Connect that marker to
   the power logger or logic analyzer.
5. Record rail name, voltage, sample rate, instrument model, ambient
   temperature, bitstream hash and binary hash.
6. Capture the supplied `CLOCKED_IDLE_SPIN` mode with the same image, clock and
   rail scope if idle-subtracted energy will be reported. Always retain gross
   rail energy as the primary measured quantity.
7. Integrate gross and idle-subtracted energy with
   `scripts/hdec/vv35_eval/board/compute_vv35_board_energy.py`.
8. Read the program result block and require PASS before using the power trace.

Use `vv35_batch_count=1` for exact `rdcycle` measurements. If the power logger
cannot resolve the roughly millisecond-scale single batch, use the same larger
batch count in both scenarios and collect at least 1,000 marked samples. Keep
the one-batch cycle experiment and repeated-batch energy experiment as two
separate rows in the result table.

Board measurements include the named board rails. They are not interchangeable
with standalone-core Vivado power. CPU-integrated runs also include CV-X-IF and
software overhead; report those cycles as measured rather than forcing the
standalone-core cycle count.

The default `vv35_pmul_wait_cycles=146908` is valid only when the CPU cycle
counter and HDEC use the same ungated clock. Otherwise first calibrate this
runtime value from a PMUL-only board run or replace it with a reliable done
event. Do not run the frozen SERIAL comparison with an unverified clock ratio.
The physical marker and the two `rdcycle` reads are necessarily separated by a
few software instructions. Integrate board energy strictly from marker
timestamps and compute board cycles strictly from `rdcycle`; never multiply a
marker-derived average power by the `rdcycle` interval as if both windows were
identical.

### ASIC Design Compiler and Power Compiler

1. Fill the environment variables in
   `scripts/hdec/vv35_eval/asic/env.example.sh`.
2. Run `run_vv35_asic.sh synth REG_VRF` first. Accept its complete-register-VRF
   label only after the reference report confirms that no storage is unresolved.
3. Run zero-delay gate simulation for SERIAL and INTERLEAVED and require both
   PASS markers.
4. Run the same simulations with the DC SDF. Generate a VCD only while
   `metric_active` is asserted, then convert each VCD to SAIF.
5. Apply both SAIF files to the same DDC with `run_vv35_asic.sh power`.
6. Save mapped and unmapped SAIF reports. Check clock, input ports and
   sequential outputs separately from the overall percentage. The VV35
   acceptance threshold is at least 90% overall annotation with no unexplained
   missing clock or sequential-output cluster. Below that threshold, label the
   value preliminary and do not use it as the paper's ASIC power result.
7. Run `BLACKBOX_VRF` only as a synthesis area and local-logic timing result for
   the logic core and public return stage. It has no functional memory activity
   or SRAM access timing. Never fill missing SRAM area, access timing or power
   with zero.
8. Use `SRAM_MACRO_VRF` only after adapting four 64x64, 64-bit, 1R1W macros
   with timing, internal-power, leakage and area views.

The runner requires a gate-level PASS and a readable SAIF coverage audit. DC
and Power Compiler results are synthesis-level pre-layout estimates. If the
laboratory has place-and-route plus extracted parasitics and PrimeTime PX,
repeat the same gate workload and SAIF contract on the post-layout netlist.

## Data to bring back

For every run, keep:

- branch, commit, dirty state and RTL/netlist hashes;
- vector manifest and vector-bundle hash;
- scenario, operation counts, measured cycles and PASS log;
- tool version, device or process, library, PVT and clock constraints;
- area/resource, WNS/TNS and critical-path report;
- activity duration, annotation coverage, unmatched objects and trace hash;
- average total/dynamic/static or leakage power;
- total and dynamic or idle-subtracted energy;
- memory implementation and SRAM macro identity;
- raw reports and the completed common result CSV.

The primary equations are

\[
T=C/f, \qquad E=P_{\mathrm{avg}}T,
\]

\[
R_C=\frac{C_s-C_i}{C_s}, \qquad
S=\frac{C_s}{C_i}, \qquad
R_E=\frac{E_s-E_i}{E_s}.
\]

FPGA LUTs and ASIC cell area remain separate native metrics. Do not convert
LUTs to gates.
