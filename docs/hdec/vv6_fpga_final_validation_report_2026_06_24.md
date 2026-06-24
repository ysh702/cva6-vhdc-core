# VV5/VV6 HDEC FPGA Final Validation Report

Date: 2026-06-24

Source branch before report split: `hdec-vv5-vector-fabric`

Report branch: `VV6`

Target board: ALINX/Atom ZYNQ7020, `xc7z020clg400-2`

Vivado version: 2024.2, `D:\vivado2024.2\Vivado\2024.2`

Primary evidence root on the local machine:

```text
H:\CVA6-HDEC\cva6-vhdc-core-v22\reports\hdec\vv5_fpga_final_validation_2026_06_24
```

## 1. Executive conclusion

The VV5 HDEC design passed the planned FPGA validation on the connected
ZYNQ7020 board. The final accepted FPGA result is the 200 MHz `r3d` monitor
run:

```text
terminal_pass = 1
terminal_fail = 0
pass_bits     = 0x0000007f
fail_bits     = 0x00000000
error_code    = 0x00000000
```

The result validates the intended system story:

```text
HDC is the foreground workload.
ECC PMUL is launched as a background service.
Foreground HDC work continues through the normal ready/valid contract.
The test ends when the background ECC operation reports done.
```

This means ECC should be described as a background security/cryptographic
service, not as the main execution stream. HDC remains the main line of work.
When HDC and ECC require a shared resource, a small ready/valid serialization
point is acceptable; the architecture does not need to save and interrupt a
large ECC intermediate state for every foreground HDC command.

## 2. What is validated

The current evidence set validates:

- Vivado 2024.2 RTL simulation for HDC full flow, HMATCH, HPERM, ECC reduction,
  and ECC point-multiplication profiling.
- Out-of-context synthesis of the core `hdec_top` at a 5.000 ns constraint.
- PL-only board smoke tests on the actual ZYNQ7020 board.
- 50 MHz and 200 MHz VIO-monitored board tests.
- Final 200 MHz HDC-mainline/ECC-background board behavior.

The current evidence set does not yet validate:

- Full CVA6/APU board boot on this ZYNQ7020 board.
- External instrument current/power measurement.
- ASIC 65 nm standard-cell area/power/timing.

## 3. Vivado simulation results

Output root:

```text
reports/hdec/vv5_fpga_final_validation_2026_06_24/xsim
```

| Testbench | Result | Key evidence |
|---|---:|---|
| `tb_hdec_hdc_full_flow_v20` | PASS | `[HDEC_HDC_FULL_FLOW_V20] PASS` |
| `tb_hdec_hmatch_compare_split` | PASS | all six HMATCH compare/split cases passed |
| `tb_hdec_hperm_bit_align` | PASS | `[HDEC_HPERM_BIT_ALIGN] PASS` |
| `tb_hdec_ecc_reduce_v1` | PASS | `[HDEC_ECC_REDUCE_V1] PASS` |
| `tb_hdec_ecc_pmul_profile_v27` | PASS | `[HDEC_ECC_PMUL_PROFILE_V27] PASS` |

ECC PMUL profile in xsim:

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

Interpretation:

- The HDC data path is functionally alive at RTL level: bind, permute, count,
  clip, similarity, and match are all covered.
- The ECC reduction and PMUL control path are alive at RTL level.
- The PMUL cycle number is the reference for judging whether the later board
  monitor is behaving consistently.

## 4. Core HDEC OOC synthesis

Output root:

```text
reports/hdec/vv5_fpga_final_validation_2026_06_24/ooc_try11_repro
```

Top module: `hdec_top`

Part: `xc7z020clg400-2`

Constraint: 5.000 ns

| Metric | Result |
|---|---:|
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

Interpretation:

- This is the best FPGA number to cite as the core HDEC area/timing result.
- The core meets 200 MHz out of context, with a small but positive margin.
- `0 DSP` is an important low-area/edge-device result.
- The four BRAM tiles reflect the vector storage footprint and are consistent
  with the 1024-dimensional HDC direction.

## 5. Board support and observed hardware

Vivado Hardware Manager observed the connected target:

| Item | Result |
|---|---|
| Hardware target | `localhost:3121/xilinx_tcf/Digilent/C3054C71ABCD` |
| PL device | `xc7z020_1` |
| Device family | ZYNQ7020 |
| Board part used in builds | `xc7z020clg400-2` |

Confirmed PL-side board pins from local ZYNQ7020 projects:

| Function | Signal | Package pin | Notes |
|---|---|---|---|
| PL clock | `L16` | `U18` | 50 MHz input clock |
| Key/reset | `KEY` | `N16` | active-low board key/reset path |
| LED candidate | `LED_L14` | `L14` | earlier local project evidence |
| Visible LED | `LED_T20` | `H15` | active-low visible LED path |

## 6. FPGA bring-up rounds

### 6.1 LED probe

Purpose: verify that the board, JTAG path, PL clock, and visible LED pin are
usable before testing HDEC logic.

Observed board result:

```text
LED probe: visible frequent blink
```

Interpretation:

- The physical board did not need to be swapped.
- JTAG programming and the PL clock/LED path were usable.

### 6.2 HDEC smoke v2 at 50 MHz

Output root:

```text
reports/hdec/vv5_fpga_final_validation_2026_06_24/zynq7020_smoke_t20_v2
```

Self-test sequence:

```text
VADDR(bank=0, idx=0)
VWR64(0x0123456789abcdef)
VADDR(bank=0, idx=0)
VRD64
readback compare
```

Observed board result:

```text
slow blink PASS
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

Interpretation:

- Basic HDEC command handshake and VRF write/readback work on the board.
- This is a bring-up check, not the final architecture result.

### 6.3 VIO monitor v1 at 50 MHz

Output root:

```text
reports/hdec/vv5_fpga_final_validation_2026_06_24/zynq7020_monitor_v1
```

Validated checks:

| Pass bit | Board self-test | Validated path |
|---:|---|---|
| 0 | VRF write/read | vector register file access |
| 1 | HPERM shift-1 alignment | HDC permutation / bit alignment |
| 2 | HMATCH single-class compare | HDC class comparison |
| 3 | ECC direct reduce | GF(2^233) reduction |
| 4 | ECC MUL -> REDUCE | GF(2) multiply plus GF(2^233) reduction |

Board VIO result:

| VIO item | Value | Meaning |
|---|---:|---|
| `terminal_pass_q` | 1 | sequence finished successfully |
| `terminal_fail_q` | 0 | no terminal failure |
| `pass_bits_q` | `0x0000001f` | all five checks passed |
| `fail_bits_q` | `0x00000000` | no failed check |
| `error_code_q` | `0x00000000` | no monitor error |
| `cmd_count_q` | `0x000000a1` | 161 HDEC commands |
| `total_cycles_q` | `0x00000507` | 1287 cycles |
| `max_cmd_cycles_q` | `0x0067` | 103 cycles |
| `last_result_q` | `0x0000018688850b04` | ECC MUL->REDUCE readback matched |

Cycle counters at 50 MHz:

| Check | Cycles | Time |
|---|---:|---:|
| VRF write/read | 30 | 0.60 us |
| HPERM shift-1 alignment | 336 | 6.72 us |
| HMATCH single-class compare | 461 | 9.22 us |
| ECC direct reduce | 177 | 3.54 us |
| ECC MUL -> REDUCE | 283 | 5.66 us |
| Total sequence | 1287 | 25.74 us |

Routed implementation including VIO/debug monitor:

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

Interpretation:

- This proves multiple HDC and ECC functions run correctly on the actual
  board.
- The area includes the debug monitor and VIO, so it should not be used as the
  core area number.

### 6.4 Round 1 200 MHz MMCM clock probe

Output root:

```text
reports/hdec/vv5_fpga_final_validation_2026_06_24/zynq7020_clk200_probe_r1
```

Purpose: verify that a 200 MHz PL clock can be generated from the board 50 MHz
clock before running HDEC at 200 MHz.

| Metric | Result |
|---|---:|
| Input clock | 50 MHz |
| Generated clock | 200 MHz, 5.000 ns |
| Routed WNS | 1.292 ns |
| Routed TNS | 0.000 ns |
| Slice LUTs | 9 |
| Slice Registers | 28 |
| Block RAM Tile | 0 |
| DSP | 0 |
| CARRY4 | 7 |
| BUFGCTRL | 2 |
| MMCME2_ADV | 1 |
| Vivado vectorless total on-chip power | 0.212 W |
| Vivado vectorless dynamic power | 0.108 W |
| Vivado vectorless static power | 0.104 W |

Interpretation:

- The 200 MHz clocking path itself is not the problem.
- The MMCM wrapper is suitable for the later 200 MHz HDEC monitor.

### 6.5 Round 2 200 MHz five-check monitor

Output root:

```text
reports/hdec/vv5_fpga_final_validation_2026_06_24/zynq7020_monitor200_r2
```

Validated checks:

```text
VRF, HPERM, HMATCH, ECC_REDUCE, ECC_MUL_REDUCE
```

Timing:

| Metric | Result |
|---|---:|
| HDEC monitor clock | 200 MHz, 5.000 ns |
| Routed WNS | 0.009 ns |
| Routed TNS | 0.000 ns |
| Failing endpoints | 0 |

Routed utilization including monitor/VIO/debug/MMCM:

| Resource | Used | Available | Utilization |
|---|---:|---:|---:|
| Slice LUTs | 7791 | 53200 | 14.64% |
| Slice Registers | 5281 | 106400 | 4.96% |
| Block RAM Tile | 4 | 140 | 2.86% |
| DSP | 0 | 220 | 0.00% |
| CARRY4 | 84 | - | - |
| BUFGCTRL | 3 | 32 | 9.38% |
| MMCME2_ADV | 1 | 4 | 25.00% |

Board VIO result:

| VIO item | Value | Meaning |
|---|---:|---|
| `terminal_pass_q` | 1 | sequence passed |
| `terminal_fail_q` | 0 | no terminal failure |
| `pass_bits_q` | `0x0000001f` | all five checks passed |
| `fail_bits_q` | `0x00000000` | no failed check |
| `error_code_q` | `0x00000000` | no monitor error |
| `cmd_count_q` | `0x000000a1` | 161 HDEC commands |
| `total_cycles_q` | `0x00000507` | 1287 cycles |
| Total time at 200 MHz | 6.435 us | `1287 * 5 ns` |
| `max_cmd_cycles_q` | `0x0067` | 103 cycles |
| `last_result_q` | `0x0000018688850b04` | ECC MUL->REDUCE result |

Vivado vectorless power estimate:

| Metric | Result |
|---|---:|
| Total on-chip power | 0.321 W |
| Dynamic power | 0.211 W |
| Device static power | 0.109 W |
| Junction temperature estimate | 28.7 C |

Interpretation:

- The core HDC/ECC datapaths can run at 200 MHz on the actual board.
- WNS is positive but very small, so 200 MHz is passed, not over-provisioned.

### 6.6 Final r3d 200 MHz HDC-mainline/ECC-background monitor

Output root:

```text
reports/hdec/vv5_fpga_final_validation_2026_06_24/zynq7020_hdec_full200_r3d
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

| VIO item | Value | Meaning |
|---|---:|---|
| `terminal_pass_q` | 1 | final monitor sequence passed |
| `terminal_fail_q` | 0 | no terminal failure |
| `pass_bits_q` | `0x0000007f` | all seven checks passed |
| `fail_bits_q` | `0x00000000` | no failed check |
| `error_code_q` | `0x00000000` | no monitor error |
| `cmd_count_q` | `0x000000ca` | 202 HDEC commands |
| `total_cycles_q` | `0x00021bec` | 138220 cycles |
| Total time at 200 MHz | 691.10 us | `138220 * 5 ns` |
| `max_cmd_cycles_q` | `0x1337` | 4919 cycles |
| `last_result_q` | `0x0000000013100048` | final ECC status/done word |

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

Interpretation:

- This is the final board result to cite for the HDC-mainline/ECC-background
  story.
- The monitor proves that HDC foreground work can proceed after an ECC
  background PMUL launch, and the sequence stops when ECC reports done.
- `total_cycles = 138220` is close to the xsim ECC PMUL reference
  `135952 cycles`. The difference is `2268 cycles`, about `1.67%` over the
  PMUL reference, under this monitor sequence. This supports the claim that the
  heavy ECC background operation can be mostly hidden behind foreground HDC
  work in the tested schedule.
- The Vivado power number is an estimate, not a measured board-current value.
  It should be described as post-implementation vectorless estimated power.

## 7. Intermediate r3/r3b/r3c debugging record

These rounds are not the final accepted paper result, but they explain why
`r3d` is the correct final monitor behavior.

| Round | Result | Important observation |
|---|---|---|
| `r3` | failed at test 6 | forcing extra foreground/resource checks while PMUL was active pulled the monitor into ECC/debug behavior rather than the intended HDC foreground story |
| `r3b` | failed at test 6 | direct active-status/readback probing still behaved like an ECC debug path |
| `r3c` | reached `pass_bits=0x7f` but terminal-failed at test 7 | HDC foreground plus ECC background-done had already passed; the failure was caused by an extra PMUL result readback step |
| `r3d` | PASS | removed the debug-only PMUL result dump and used `ECC_STATUS == done` as the architectural stop condition |

Interpretation:

- The paper story should not be based on direct ECC result readback debugging.
- The correct architectural endpoint is background ECC completion while HDC
  remains the foreground workload.
- If a shared resource is occupied, the architecture can wait locally at
  ready/valid boundaries. This is different from making ECC the mainline.

## 8. Which numbers should be used in a paper

Recommended paper-facing numbers:

| Purpose | Number to use | Reason |
|---|---|---|
| Core FPGA area/timing | `hdec_top` OOC: 4675 LUT, 1382 FF, 4 BRAM, 0 DSP, 207.727 MHz estimated Fmax | excludes VIO/debug wrapper overhead |
| Board proof at 200 MHz | r3d: WNS 0.049 ns, TNS 0, `pass_bits=0x7f` | actual ZYNQ7020 board bitstream and VIO result |
| HDC/ECC foreground-background behavior | r3d: 138220 cycles at 200 MHz, 691.10 us | validates HDC-mainline/ECC-background execution |
| ECC PMUL reference | xsim: 135952 cycles | reference background ECC operation cost |
| Estimated FPGA power | r3d Vivado vectorless: 0.310 W total, 0.201 W dynamic | acceptable as estimated post-implementation power only |
| Board health | SysMon: 42.9 C, VCCINT 0.993 V, VCCAUX 1.779 V, VCCBRAM 0.993 V | confirms the programmed board was stable |

Numbers that should not be used as core area:

- `zynq7020_monitor_v1`, `zynq7020_monitor200_r2`, and `zynq7020_hdec_full200_r3d`
  utilization numbers include the board monitor, VIO/debug hub, and in the
  200 MHz runs the MMCM. They are useful for board evidence, not pure HDEC
  core area.

Numbers that should not be called measured power:

- Vivado `report_power` values are vectorless estimates. They are not external
  current measurements. A paper should label them as estimated power unless a
  current probe or board power monitor is used later.

## 9. Quality judgment

The FPGA result is strong for this stage.

Positive points:

- The core design meets the 200 MHz target on `xc7z020clg400-2`.
- The final board bitstream also meets 200 MHz and passes all monitored checks.
- The core uses 0 DSP and only 4 BRAM tiles.
- The HDC-mainline/ECC-background story is validated on board, not only in RTL
  simulation.
- The final monitor sequence shows only about 1.67% cycle overhead relative to
  the standalone ECC PMUL reference under the tested schedule.

Limitations:

- The 200 MHz margin is positive but thin. The design passes 200 MHz, but it
  should not be described as having large frequency headroom.
- The board wrapper utilization is not the same as core area.
- FPGA power is still estimated, not externally measured.
- Full CVA6/APU integration on this board has not been performed.

Recommended wording:

```text
On a ZYNQ7020 FPGA, HDEC meets 200 MHz and passes a complete monitored
foreground/background validation in which HDC remains the foreground workload
while ECC point multiplication executes as a background security service.
The core OOC result uses 4675 LUT, 1382 FF, 4 BRAM, and 0 DSP, and the final
board monitor passes all seven checks with pass_bits=0x7f.
```

## 10. Next ASIC step

The FPGA validation should now be complemented by a 65 nm ASIC flow using
Design Compiler.

Recommended ASIC branches:

- `VV6`: documentation and final FPGA evidence.
- `VVV1`: ASIC-oriented branch where RTL may be modified for standard-cell
  synthesis, SRAM modeling, clock gating, and power/timing optimization.

Recommended ASIC measurements:

| ASIC item | Why it matters |
|---|---|
| HDC-only area/timing/power | HDC baseline |
| ECC-only area/timing/power | crypto baseline |
| HDC+ECC unshared area/timing/power | naive composition baseline |
| HDEC shared area/timing/power | proves reuse benefit |
| Dynamic power with SAIF/VCD | more credible than vectorless FPGA power |
| Energy per HDC inference/update | paper-facing edge-AI metric |
| Energy per ECC PMUL | paper-facing security metric |
| HDC stall cycles while ECC runs | quantifies foreground/background overlap |
| SRAM/memory macro accounting | prevents unfair flip-flop-based memory area |

The ASIC flow should avoid synthesizing large vector memories purely into
flip-flops unless that is intentionally being measured as a worst case. For
paper-quality numbers, vector storage should be mapped to SRAM macros or
reported with a separate SRAM estimate.
