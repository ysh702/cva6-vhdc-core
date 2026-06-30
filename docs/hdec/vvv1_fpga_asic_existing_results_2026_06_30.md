# HDEC Existing FPGA Board and ASIC DC Results for VVV1

Date: 2026-06-30

Branch for this record: `VVV1`

This note consolidates the already available FPGA board-validation data and
ASIC Design Compiler data for the HDEC prototype.  It is intended as the
paper-data source before the spreadsheet is updated.

## 1. Source Artifacts

### FPGA Evidence

Primary local evidence root:

```text
reports/hdec/vv5_fpga_final_validation_2026_06_24
```

Relevant report already summarized on the `VV6` documentation branch:

```text
docs/hdec/vv6_fpga_final_validation_report_2026_06_24.md
```

Configuration:

| Item | Value |
|---|---|
| FPGA board | ALINX/Atom ZYNQ7020 |
| FPGA part | `xc7z020clg400-2` |
| Vivado | 2024.2 |
| HDEC source branch before report split | `hdec-vv5-vector-fabric` |
| HDEC source commit | `93341f77` |
| Report branch | `VV6` |
| Final board run | `zynq7020_hdec_full200_r3d` |

Important limitation: this FPGA result is an HDEC PL-only monitor/board
validation.  It does not include a full CVA6/APU boot, and it should not be
reported as a complete CVA6+HDEC SoC board result.

### ASIC Evidence

Primary local package root:

```text
H:\CVA6-HDEC\build\hdec_asic_vvv1_sram_macro_r1
```

Report extraction root:

```text
H:\CVA6-HDEC\build\hdec_asic_vvv1_sram_macro_r1_reports
```

Final remote run package name:

```text
hdec_asic_vvv1_sram_macro_r1
```

Final remote archive:

```text
hdec_asic_vvv1_1to5_outputs_final.tar.gz
```

The ASIC run uses a VVV1-oriented RTL package with `HDEC_ASIC_SRAM_MACRO` so
that the VRF is represented as four SRAM macro boundaries instead of being
expanded into flip-flops.  The current DC run links the 65 nm standard-cell
library but does not link a real SRAM macro library, so reported DC macro area
is zero.  SRAM area is therefore reported separately as an estimate.

## 2. FPGA Simulation Results

Vivado xsim validation:

| Testbench | Result | Key evidence |
|---|---:|---|
| `tb_hdec_hdc_full_flow_v20` | PASS | HDC full flow passed |
| `tb_hdec_hmatch_compare_split` | PASS | HMATCH compare/split cases passed |
| `tb_hdec_hperm_bit_align` | PASS | HPERM bit alignment passed |
| `tb_hdec_ecc_reduce_v1` | PASS | ECC reduction passed |
| `tb_hdec_ecc_pmul_profile_v27` | PASS | ECC PMUL profile passed |

ECC PMUL cycle profile in xsim:

| Metric | Cycles |
|---|---:|
| `PMUL_PROFILE_WALL_CYCLES` | 135952 |
| `PMUL_PROFILE_SAMPLED_CYCLES` | 135952 |
| `PMUL_PROFILE_PHASE_INV_SQR_CYCLES` | 939 |
| `PMUL_PROFILE_PHASE_INV_MUL_CYCLES` | 980 |
| `PMUL_PROFILE_PHASE_PMUL_FIELD_CYCLES` | 119870 |
| `PMUL_PROFILE_PHASE_PMUL_ADD_CYCLES` | 5656 |
| `PMUL_PROFILE_PHASE_PMUL_COPY_CYCLES` | 705 |
| `PMUL_PROFILE_SUB_ADD_CYCLES` | 122558 |
| `PMUL_PROFILE_SUB_DBL_CYCLES` | 10016 |
| `PMUL_PROFILE_SUB_AFFINE_CYCLES` | 3360 |
| `PMUL_PROFILE_SQR_STARTS` | 1633 |
| `PMUL_PROFILE_ST_ECC_LOAD_CYCLES` | 3564 |
| `PMUL_PROFILE_ST_ECC_DIAG_CYCLES` | 33264 |
| `PMUL_PROFILE_ST_ECC_LEAF_FOLD_CYCLES` | 32076 |
| `PMUL_PROFILE_ST_ECC_WRITE_PAIR_CYCLES` | 42768 |
| `PMUL_PROFILE_ST_ECC_REDUCE_CYCLES` | 2821 |
| `PMUL_PROFILE_ST_ECC_UOP_CYCLES` | 4242 |

## 3. FPGA Core OOC Result

Output root:

```text
reports/hdec/vv5_fpga_final_validation_2026_06_24/ooc_try11_repro
```

Top module: `hdec_top`

| Metric | Result |
|---|---:|
| Part | `xc7z020clg400-2` |
| Constraint | 5.000 ns |
| WNS | 0.186 ns |
| Worst data delay | 4.812 ns |
| Estimated Fmax | 207.727 MHz |
| Worst endpoint | `i_vec/payload_q_reg[0][10]/D` |
| Slice LUTs | 4675 |
| LUT as Logic | 4675 |
| LUT as Memory | 0 |
| Slice Registers | 1382 |
| Block RAM Tile | 4 |
| DSP | 0 |
| CARRY4 | 12 |

Paper-facing interpretation: these are the cleanest FPGA core area/timing
numbers because they exclude the board monitor, VIO/debug hub, and MMCM.

## 4. FPGA Board Bring-Up Results

### 4.1 LED Probe

Observed result:

```text
LED probe: visible frequent blink
```

This confirmed that the connected board, JTAG download path, PL clock, and
visible LED path were usable.

### 4.2 HDEC Smoke v2 at 50 MHz

Output root:

```text
reports/hdec/vv5_fpga_final_validation_2026_06_24/zynq7020_smoke_t20_v2
```

Board-observed result:

```text
HDEC smoke v2: PASS
Observed LED behavior: slow blink
Validated operation: VADDR -> VWR64 -> VADDR -> VRD64 readback compare
```

Routed implementation:

| Metric | Result |
|---|---:|
| Clock | 50 MHz, 20.000 ns |
| Routed WNS | 9.915 ns |
| Routed TNS | 0.000 ns |
| Slice LUTs | 5418 |
| Slice Registers | 1626 |
| Block RAM Tile | 4 |
| DSP | 0 |
| CARRY4 | 38 |

### 4.3 VIO Monitor v1 at 50 MHz

Output root:

```text
reports/hdec/vv5_fpga_final_validation_2026_06_24/zynq7020_monitor_v1
```

Validated checks:

| Pass bit | Check |
|---:|---|
| 0 | VRF write/read |
| 1 | HPERM shift-1 alignment |
| 2 | HMATCH single-class compare |
| 3 | ECC direct reduce |
| 4 | ECC MUL -> REDUCE |

Board VIO result:

| VIO item | Value |
|---|---:|
| `terminal_pass_q` | 1 |
| `terminal_fail_q` | 0 |
| `pass_bits_q` | `0x0000001f` |
| `fail_bits_q` | `0x00000000` |
| `error_code_q` | `0x00000000` |
| `cmd_count_q` | `0x000000a1` |
| `total_cycles_q` | `0x00000507` |
| Total cycles | 1287 |
| Total time at 50 MHz | 25.74 us |
| `max_cmd_cycles_q` | `0x0067` |
| Max command cycles | 103 |
| `last_result_q` | `0x0000018688850b04` |

Routed implementation including monitor/VIO/debug:

| Metric | Result |
|---|---:|
| Clock | 50 MHz, 20.000 ns |
| Routed WNS | 10.493 ns |
| Routed TNS | 0.000 ns |
| Slice LUTs | 7542 |
| Slice Registers | 5022 |
| Block RAM Tile | 4 |
| DSP | 0 |
| CARRY4 | 84 |

These utilization numbers include the debug monitor and should not be used as
pure core area.

## 5. Final FPGA Board Result: 200 MHz r3d

Output root:

```text
reports/hdec/vv5_fpga_final_validation_2026_06_24/zynq7020_hdec_full200_r3d
```

Execution story:

```text
HDC is the foreground workload.
ECC PMUL is launched as a background service.
Foreground HDC work continues through the ready/valid contract.
The monitor stops when the background ECC operation reports done.
```

Validated checks:

| Pass bit | Check | Validated path |
|---:|---|---|
| 0 | VRF write/read | vector register file access |
| 1 | HPERM | HDC permutation and bit alignment |
| 2 | HMATCH | HDC class comparison |
| 3 | ECC_REDUCE | GF(2^233) reduction |
| 4 | ECC_MUL_REDUCE | GF(2) multiply plus reduction |
| 5 | HDC_FULL_FLOW | `HSIM/HCLR/HBIND/HPERM/HCNTCLR/HCNTADD/HCNTCLIP/HSIM/HMATCH` |
| 6 | ECC_PMUL_BG_DONE_AFTER_HDC_FOREGROUND | ECC background PMUL plus foreground HDC work before ECC done |

Timing:

| Metric | Result |
|---|---:|
| Input clock | 50 MHz on `L16/U18` |
| HDEC monitor clock | 200 MHz, 5.000 ns |
| Routed WNS | 0.049 ns |
| Routed TNS | 0.000 ns |
| Failing endpoints | 0 |
| `clk200_raw` endpoints | 9408 |
| Routing errors | 0 |

Routed utilization including monitor/VIO/debug/MMCM:

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 7899 | 53200 | 14.85% |
| Slice Registers | 5405 | 106400 | 5.08% |
| Block RAM Tile | 4 | 140 | 2.86% |
| DSP | 0 | 220 | 0.00% |
| CARRY4 | 92 | - | - |
| BUFGCTRL | 3 | 32 | 9.38% |
| MMCME2_ADV | 1 | 4 | 25.00% |

Board VIO result:

| VIO item | Value |
|---|---:|
| `terminal_pass_q` | 1 |
| `terminal_fail_q` | 0 |
| `pass_bits_q` | `0x0000007f` |
| `fail_bits_q` | `0x00000000` |
| `error_code_q` | `0x00000000` |
| `cmd_count_q` | `0x000000ca` |
| HDEC commands | 202 |
| `total_cycles_q` | `0x00021bec` |
| Total cycles | 138220 |
| Total time at 200 MHz | 691.10 us |
| `max_cmd_cycles_q` | `0x1337` |
| Max command cycles | 4919 |
| `last_result_q` | `0x0000000013100048` |

Board SysMon readback:

| Sensor | Value |
|---|---:|
| Temperature | 42.9 C |
| VCCINT | 0.993 V |
| VCCAUX | 1.779 V |
| VCCBRAM | 0.993 V |

Vivado vectorless power estimate:

| Metric | Result |
|---|---:|
| Total on-chip power | 0.310 W |
| Dynamic power | 0.201 W |
| Device static power | 0.109 W |
| Junction temperature estimate | 28.6 C |
| Clock dynamic power | 0.045 W |
| Slice logic dynamic power | 0.009 W |
| Signal dynamic power | 0.016 W |
| Block RAM dynamic power | 0.025 W |
| MMCM dynamic power | 0.106 W |
| VCCINT current estimate | 0.103 A |
| VCCAUX current estimate | 0.069 A |
| VCCBRAM current estimate | 0.001 A |

Paper-facing interpretation: the final board test validates the intended
HDC-mainline/ECC-background behavior at 200 MHz.  The final board utilization
and power include the monitor/VIO/debug/MMCM wrapper.  For pure HDEC core
area, use the OOC result in Section 3.

## 6. ASIC RTL/Flow Change for VVV1

The VVV1 ASIC package keeps the HDEC operator/scheduler behavior unchanged, but
changes the ASIC synthesis view of the VRF storage:

| Item | Value |
|---|---|
| Macro-mode define | `HDEC_ASIC_SRAM_MACRO` |
| Behavioral simulation define | `HDEC_ASIC_SRAM_BEHAV` |
| SRAM wrapper | `hdec_vrf_bank_1r1w_sram` |
| SRAM organization | 4 banks, each 64 x 64 1R1W |
| Total VRF SRAM bits | 16384 bit |

This avoids judging the architecture from an unrealistic flip-flop-expanded
vector register file.  The current run does not link real SRAM macro timing,
area, LEF, or GDS files, so the SRAM macro area remains an estimate.

## 7. ASIC DC Results

Tool level: Design Compiler logic synthesis with a 65 nm standard-cell library.

Power activity: VCS workload SAIF was generated and fed back into DC for
activity-aware power reporting.  This is not PrimeTime signoff and not
post-layout power.

Timing:

| Metric | Result |
|---|---:|
| Setup TNS | 0.00 ns |
| Setup violating paths | 0 |
| Hold WNS | 0.00 ns |

Standard-cell area:

| Metric | Result |
|---|---:|
| Leaf cell count | 14517 |
| Combinational cell count | 12940 |
| Sequential cell count | 1577 |
| Logic cell area | 59776.599166 um^2 |
| Logic cell area | 0.059777 mm^2 |
| Combinational area | 44040.879621 um^2 |
| Non-combinational area | 15735.719545 um^2 |
| DC macro area | 0.000000 um^2 |

SRAM accounting:

| Metric | Result |
|---|---:|
| VRF SRAM macro instances | 4 |
| VRF SRAM bits | 16384 bit |
| SRAM area estimate, low | 0.012000 mm^2 |
| SRAM area estimate, mid | 0.020000 mm^2 |
| SRAM area estimate, high | 0.035000 mm^2 |
| Logic + SRAM estimate, low | 0.071777 mm^2 |
| Logic + SRAM estimate, mid | 0.079777 mm^2 |
| Logic + SRAM estimate, high | 0.094777 mm^2 |

Power:

| Metric | Result |
|---|---:|
| Power activity mode | SAIF workload |
| Total dynamic power | 2.4563 mW |
| Cell leakage power | 1.7208 uW |
| Total power including leakage | 2.4580 mW |
| SAIF available | yes |
| Vectorless power report available | yes |

VCS workload counters:

| Metric | Result |
|---|---:|
| `HDC_FULL_FLOW_STANDALONE_CYCLES` | 1095 |
| `PMUL_BG_HDC_LOOP_WALL_CYCLES` | 137050 |
| `PMUL_BG_HDC_LOOP_HDC_ITERS` | 1 |
| `PMUL_BG_HDC_LOOP_EQUIV_HDC_CYCLES` | 1095 |
| `PMUL_BG_HDC_LOOP_STATUS_LOW16` | 0 |
| Workload status | PASS |

Important interpretation:

- `macro_area = 0` means no real SRAM macro library was linked into DC.  It
  does not mean the architecture has no vector memory.
- The logic-only area is the directly reported DC standard-cell result.
- The logic-plus-SRAM range is the current paper-facing ASIC area estimate
  until a real SRAM compiler macro library and P&R flow are available.

## 8. Recommended Paper-Facing Numbers

| Purpose | Number to cite | Notes |
|---|---|---|
| FPGA core area/timing | 4675 LUT, 1382 FF, 4 BRAM, 0 DSP, 207.727 MHz estimated Fmax | Use OOC core result, excludes debug wrapper |
| FPGA board proof | 200 MHz r3d, WNS 0.049 ns, TNS 0, `pass_bits=0x7f` | HDEC PL-only board monitor, not full CVA6 |
| FPGA foreground/background latency | 138220 cycles, 691.10 us at 200 MHz | Final HDC-mainline/ECC-background board sequence |
| FPGA estimated power | 0.310 W total, 0.201 W dynamic | Vivado vectorless estimate, not external current measurement |
| ASIC logic area | 0.059777 mm^2 | 65 nm DC standard-cell logic only |
| ASIC logic + SRAM estimated area | 0.071777 to 0.094777 mm^2 | Includes 16-Kbit VRF SRAM estimate |
| ASIC SAIF dynamic power | 2.4563 mW | Workload-SAIF DC power, not post-layout |
| ASIC leakage power | 1.7208 uW | DC cell leakage |
| HDC standalone full-flow cycles in ASIC workload | 1095 cycles | VCS workload |
| ECC background workload wall cycles | 137050 cycles | VCS workload |

## 9. Remaining Data Not Yet Claimed

The following data are not yet available and should not be claimed as measured
results:

| Missing item | Reason |
|---|---|
| Full CVA6+HDEC board boot and software-driven custom-instruction test | Current board result is HDEC PL-only monitor |
| External FPGA board-current measurement | Current FPGA power is Vivado vectorless estimate |
| Real SRAM macro area/timing/power | No foundry SRAM macro `.db/.lef/.gds` was linked |
| ASIC P&R/post-layout area, timing, and power | Current flow stops at DC synthesis |
| PrimeTime signoff power | Current activity-aware power is generated in DC from SAIF |

## 10. Safe Wording for Manuscript

Recommended wording:

```text
The HDEC prototype was validated on a ZYNQ7020 FPGA using a PL-only monitored
test harness.  The core HDEC OOC implementation achieves 207.727 MHz with
4675 LUTs, 1382 FFs, four BRAM tiles, and no DSPs.  A final 200 MHz board
monitor passes all seven HDC/ECC checks with pass_bits=0x7f, validating the
HDC-foreground/ECC-background execution model.

For ASIC-oriented evaluation, the VVV1 RTL maps the 16-Kbit VRF to SRAM macro
boundaries and was synthesized in a 65 nm standard-cell flow.  The logic-only
area is 0.059777 mm^2, while the logic-plus-estimated-SRAM area is
0.071777--0.094777 mm^2.  Workload-SAIF power analysis reports 2.4563 mW
dynamic power and 1.7208 uW leakage power.  These ASIC results are DC
synthesis-level estimates rather than post-layout signoff data.
```
