# Win11 Codex Vivado Check

Date: 2026-05-26
Workspace: `H:\CVA6-HDEC\cva6-vhdc-core`

## 1. Git Baseline Status

- Branch checked: `hdec-phase1`
- HEAD short commit: `1707a6d6`
- Tag at HEAD: `hdec-phase1-hdc-baseline-pre-ecc`
- Initial `git status --short`: clean before creating this report and the minimal Vivado check Tcl.
- Submodules: `git submodule status --recursive` succeeded when run through `H:\Git\bin\bash.exe`; listed submodules were initialized at recorded commits, with no leading `-` missing markers observed.

Notes:

- Native PowerShell `git submodule status --recursive` failed because the current Git invocation could not find Git-for-Windows Unix helper tools (`basename`, `sed`, `git-sh-setup`). Running via Git Bash worked.
- Requested `corev_apu/src/hdec_cvxif_wrapper.sv` was not present. The actual wrapper is `core/hdec/rtl/hdec_cvxif_wrapper.sv`, and `core/Flist.cva6` includes it.
- Requested `core/hdec/rtl/hdec_vrf.sv` was not present. The actual VRF file is `core/hdec/rtl/hdec_vrf_64x256.sv`.

## 2. CVA6/HDEC Structure Understanding

### CVA6/HDEC Integration Path

- `corev_apu/src/ariane.sv` includes `cvxif_types.svh`, defines CV-X-IF request/response types, instantiates `cva6`, and wires `cvxif_req_o` / `cvxif_resp_i`.
- When `CVA6Cfg.CvxifEn` is true, `ariane.sv` instantiates `hdec_cvxif_wrapper` as `i_hdec_coprocessor`.
- When CV-X-IF is disabled, `ariane.sv` drives a benign ready/default CV-X-IF response instead.
- `core/Flist.cva6` adds `+incdir+${CVA6_REPO_DIR}/core/hdec/rtl/` and includes the HDEC RTL files after the main CVA6 files.

### `hdec_cvxif_wrapper` and `hdec_top`

- `hdec_cvxif_wrapper` is the CV-X-IF adapter. It decodes custom HDEC instructions, accepts matched issue requests, waits for register operands when needed, and serializes one outstanding HDEC transaction through states `W_IDLE`, `W_WAIT_REG`, `W_SEND_TOP`, `W_WAIT_TOP`, and `W_RESULT`.
- It instantiates `hdec_top` and drives `valid_i`, `operator_i`, and operand fields from latched CV-X-IF payload registers.
- `hdec_top` is the current Phase 1 HDEC execution block. It owns the VRF, sequences HDC operations, drives lane compute paths, and returns a 64-bit result to the wrapper.

### HDEC HDC Datapath Modules

Main HDC-related RTL observed under `core/hdec/rtl`:

- `hdec_pkg.sv`: Phase 1 constants, opcode enum, custom instruction encoding table. Architecture is 4 lanes x 64-bit, 1024-bit HDC vectors.
- `hdec_resource_pkg.sv`: resource-side constants/types.
- `hdec_top.sv`: top-level HDEC execution FSM, VRF management, HDC operation sequencing.
- `hdec_vrf_64x256.sv`: 4-bank x 64-entry x 64-bit VRF, one bank per lane, with synchronous read/write and init clear.
- `hdec_lane_4x64.sv`: 64-bit lane shell containing lane-local boolean, BMCA, bundle, shift-align, add/sub counter, and clip compute blocks.
- `hdec_lane_boolean_mask.sv`: lane-local XOR/boolean mask path.
- `hdec_lane_bmca.sv`: lane-local bit matrix compression array for Hamming distance / bundle batching.
- `hdec_bmca_cell.sv`: one-bit 3:2 compressor cell.
- `hdec_lane_shift_align.sv`: lane-local shift/align logic for permutation.
- `hdec_lane_addsub_counter.sv`: packed counter add/sub support for bundle accumulation.
- `hdec_lane_clip.sv`: packed counter threshold-to-bit clipping.
- `hdec_hdc_*_ctrl.sv`, `hdec_hdc_engine.sv`, `hdec_cmd_decode.sv`: present as HDC control/engine decomposition files, but current `hdec_top.sv` still contains substantial transitional sequencing.

### Lane / VRF / BMCA Responsibilities

- Lane: processes one 64-bit slice of the 256-bit VRF word and contributes to 1024-bit HDC operations across four chunks. Current lane modules expose static compute blocks and reserved future control/writeback ports.
- VRF: stores HDC hypervectors and accumulator state as four banks of 64-bit words. The top-level FSM maps HDC slots/chunks/subgroups into bank/index operations.
- BMCA: loads up to four 64-bit rows per lane, compresses per-bit population information into low/high bit planes, and produces a lane-local count. `hdec_top` sums the four lane counts for Hamming distance/search and also reuses BMCA outputs for bundle accumulation.

### Frozen HDC Baseline Tests

Documented in `docs/hdec/phase1_hdc_baseline_results.md`:

- Stage 3 single-query HDC inference benchmark passed on Verilator.
  - Test: `verif/hdec/hdc_inference_test.S`
  - Parser: `verif/hdec/parse_inference_perf.py`
  - Result: PASS, `tohost = 0`, `ILLEGAL = 0`, predicted class 2 as expected, `min_dist = 0`.
  - Steady-state compute: 165 cycles = HBUNDLE4 63 + HCLIP 39 + HMATCH 63.
- Stage 4 E2E train+infer ladder benchmark passed on Verilator.
  - Test: `verif/hdec/hdc_e2e_train_infer_test.S`
  - Parser: `verif/hdec/parse_e2e_train_infer_perf.py`
  - Result: PASS, `tohost = 0`, `ILLEGAL = 0`.
  - Ladder A/B/C passed: sample encoding self-check, prototype build self-check, full 4-class train plus 8-sample inference.
  - Inference accuracy: 8/8, all `min_dist = 0`.

### Suggested HDC-only Vivado Baseline Entry

For the next Vivado HDC-only baseline, prioritize HDEC-local RTL rather than full CVA6:

1. Start with `hdec_top` plus its direct dependencies from `core/hdec/rtl`.
2. Include `hdec_pkg.sv`, `hdec_resource_pkg.sv`, `hdec_vrf_64x256.sv`, `hdec_lane_4x64.sv`, and the lane subblocks used by `hdec_lane_4x64`.
3. Consider a small synthetic HDC-only wrapper/test top later if Vivado requires concrete stimulus-facing ports, but do not choose an FPGA part or constraints until those requirements are defined.
4. Avoid full `ariane` / full CVA6 synthesis for the first HDC-only resource/timing baseline because it would mix CVA6/cache/APU/submodule effects with the HDEC datapath.

## 3. Vivado 2022.2 Check Result

- `where vivado`: not found in PATH.
- User-provided Vivado path found:
  - `H:\SWTOOLS\Vivado\2022.2\bin\vivado.bat`
  - `H:\SWTOOLS\Vivado\2022.2\bin\unwrapped\win64.o\vvgl.exe`
- Version command:
  - `& "H:\SWTOOLS\Vivado\2022.2\bin\vivado.bat" -version`
  - Output: `Vivado v2022.2 (64-bit)`, SW Build `3671981`, IP Build `3669848`, Tool Version Limit `2022.10`.
- Minimal batch test:
  - Tcl: `build/vivado/check_vivado_version.tcl`
  - Command: `& "H:\SWTOOLS\Vivado\2022.2\bin\vivado.bat" -mode batch -source "H:/CVA6-HDEC/cva6-vhdc-core/build/vivado/check_vivado_version.tcl"`
  - Result: success, exit code 0.
  - Output included:
    - `Vivado batch mode is working`
    - `Vivado v2022.2 (64-bit)`

Warnings seen during Vivado launch:

- `CRITICAL WARNING: [Common 17-741] No write access right to the local Tcl store at 'C'. XilinxTclStore is reverted to the installation area.`
- `WARNING: [Common 17-1509] Migration of commands.paini file failed ... C:\Users\Lenovo\AppData\Roaming/Xilinx/Vivado/2022.2/commands`

These warnings did not prevent the minimal batch script from running.

## 4. Uncertain Points / Not Done

- No full Vivado project was created.
- No FPGA part was selected.
- No constraints file was selected.
- No RTL was read into Vivado.
- No synthesis, implementation, Verilator, or Vivado project generation was run.
- The exact HDC-only Vivado top wrapper and part/constraint target remain undefined.
- `hdec_hdc_engine.sv` and `hdec_hdc_*_ctrl.sv` exist, but current observed integration path still centers on `hdec_top.sv`.
