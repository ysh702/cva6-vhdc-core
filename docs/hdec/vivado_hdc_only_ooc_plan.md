# Vivado HDC-only OOC Plan

Date: 2026-05-26
Repository: `H:\CVA6-HDEC\cva6-vhdc-core`
Vivado: `H:\SWTOOLS\Vivado\2022.2\bin\vivado.bat`

## 1. Current Git Baseline

Checked before this analysis:

- Branch: `hdec-phase1`
- HEAD short commit: `1707a6d6`
- Tag at HEAD: `hdec-phase1-hdc-baseline-pre-ecc`
- `git status --short` before writing this file:
  - `?? docs/hdec/win11_codex_vivado_check.md`

The previous Win11/Vivado check report is untracked and intentionally left uncommitted.

## 2. OOC Top Options

### Option A: `hdec_top` Directly as OOC Top

`hdec_top` is a plausible first OOC top.

Observed port shape:

```systemverilog
module hdec_top import hdec_pkg::*; import hdec_resource_pkg::*; (
    input logic clk_i, rst_ni, valid_i,
    output logic ready_o,
    input hdec_op_t operator_i,
    input logic [63:0] operand_a_i, operand_b_i,
    output logic valid_o,
    output logic [63:0] result_o
);
```

Pros:

- Exercises the current real Phase 1 HDC execution block.
- Avoids CVA6, CV-X-IF, cache, APU, and full SoC dependencies.
- Direct dependencies are HDEC-local: `hdec_pkg`, `hdec_resource_pkg`, VRF, lane, and lane subblocks.
- No dependency on `cvxif_types.svh`, CVA6 packages, or `core/include` packages was observed inside `hdec_top`.

Cons:

- The top-level opcode port uses package enum type `hdec_op_t`, not a plain `logic [3:0]` port. Vivado usually handles SystemVerilog package types when files are read in order, but a plain wrapper may be more robust for OOC handoff and scripted parameter sweeps.
- `hdec_top` includes transitional sequencing and VRF management, not only pure combinational lane datapath. This is good for a realistic HDC block baseline, but less isolated than lane-only micro-baselines.

### Option B: Future `hdec_ooc_top_wrapper`

A minimal wrapper could expose only plain logic ports and cast the opcode into `hdec_pkg::hdec_op_t`. Do not create this wrapper until the FPGA part, clock, and intended measurement boundary are agreed.

Sketch only:

```systemverilog
module hdec_ooc_top_wrapper (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        valid_i,
    output logic        ready_o,
    input  logic [3:0]  operator_i,
    input  logic [63:0] operand_a_i,
    input  logic [63:0] operand_b_i,
    output logic        valid_o,
    output logic [63:0] result_o
);
    hdec_top i_hdec_top (
        .clk_i,
        .rst_ni,
        .valid_i,
        .ready_o,
        .operator_i (hdec_pkg::hdec_op_t'(operator_i)),
        .operand_a_i,
        .operand_b_i,
        .valid_o,
        .result_o
    );
endmodule
```

Pros:

- Top ports are plain scalar/vector `logic`, which is friendlier to OOC scripts and downstream constraints.
- Allows future insertion of optional synthesis keep/dont-touch/debug attributes outside the RTL proper, if desired.

Cons:

- Requires adding a new RTL file later, which is outside this current no-RTL-change step.
- Adds one more artifact whose measurement boundary must be documented.

### Recommendation

Use `hdec_top` directly for the first HDC-only OOC dependency/elaboration attempt. It is the real current HDC execution boundary, is already included in `core/Flist.cva6`, and avoids the CV-X-IF wrapper's external CVA6 type parameters.

If Vivado elaboration or reporting around the enum top port becomes awkward, add a tiny `hdec_ooc_top_wrapper` in a later, explicit RTL-change step.

## 3. Required RTL Files for First HDC-only OOC Baseline

Recommended read order:

1. Package files:
   - `core/hdec/rtl/hdec_pkg.sv`
   - `core/hdec/rtl/hdec_resource_pkg.sv`

2. Leaf lane blocks:
   - `core/hdec/rtl/hdec_lane_boolean_mask.sv`
   - `core/hdec/rtl/hdec_bmca_cell.sv`
   - `core/hdec/rtl/hdec_lane_shift_align.sv`
   - `core/hdec/rtl/hdec_lane_addsub_counter.sv`
   - `core/hdec/rtl/hdec_lane_clip.sv`

3. Composite lane blocks:
   - `core/hdec/rtl/hdec_lane_bmca.sv`
   - `core/hdec/rtl/hdec_lane_4x64.sv`

4. Storage:
   - `core/hdec/rtl/hdec_vrf_64x256.sv`

5. OOC top:
   - `core/hdec/rtl/hdec_top.sv`

6. Optional future wrapper, if created later:
   - `core/hdec/rtl/hdec_ooc_top_wrapper.sv`

Notes:

- `hdec_lane_bmca.sv` instantiates `hdec_bmca_cell`, so the cell should be read first.
- `hdec_lane_4x64.sv` instantiates boolean, BMCA, shift-align, add/sub counter, and clip modules, so all leaf lane blocks should be available first.
- `hdec_top.sv` instantiates `hdec_vrf_64x256` and four `hdec_lane_4x64` instances.

## 4. Files to Exclude from First HDC-only Baseline

Do not include these in the first HDC-only OOC baseline unless the measurement scope changes:

- `core/hdec/rtl/hdec_cvxif_wrapper.sv`
  - It is the CV-X-IF adapter and has many CVA6/CV-X-IF parameterized type ports. It instantiates `hdec_top`, but is not needed to measure HDC-only datapath/control.
- `core/hdec/rtl/hdec_cmd_decode.sv`
  - Present as a command decode block, but not instantiated by current `hdec_top`.
- `core/hdec/rtl/hdec_hdc_engine.sv`
  - Present as a future/decomposed HDC engine top with controller placeholders, but current observed integration path is still through `hdec_top`.
- `core/hdec/rtl/hdec_hdc_bind_ctrl.sv`
- `core/hdec/rtl/hdec_hdc_bundle_ctrl.sv`
- `core/hdec/rtl/hdec_hdc_clear_ctrl.sv`
- `core/hdec/rtl/hdec_hdc_clip_ctrl.sv`
- `core/hdec/rtl/hdec_hdc_perm_ctrl.sv`
- `core/hdec/rtl/hdec_hdc_search_ctrl.sv`
- `core/hdec/rtl/hdec_hdc_sim_ctrl.sv`
  - Several are placeholders or part of the future engine split and are not in the active `hdec_top` instance tree.
- `core/hdec/rtl/hdec_lane_popcount_compressor.sv`
  - Present, but not instantiated by `hdec_lane_4x64` in the current active path.
- Full CVA6 / APU / cache / submodule filelists from `core/Flist.cva6`
  - Excluded to avoid synthesizing full CVA6 or mixing non-HDEC resources into this HDC-only baseline.

## 5. Vivado Tcl Flow Draft

This is a draft only. Do not run until FPGA part, clock assumptions, and report paths are confirmed.

```tcl
# HDC-only OOC baseline draft. Do not use for full CVA6.

set_part <USER_TO_PROVIDE>

# Optional, only after user provides a target period:
# create_clock -name clk_i -period <USER_TO_PROVIDE_NS> [get_ports clk_i]

set repo_dir {H:/CVA6-HDEC/cva6-vhdc-core}
set hdec_rtl $repo_dir/core/hdec/rtl

read_verilog -sv $hdec_rtl/hdec_pkg.sv
read_verilog -sv $hdec_rtl/hdec_resource_pkg.sv

read_verilog -sv $hdec_rtl/hdec_lane_boolean_mask.sv
read_verilog -sv $hdec_rtl/hdec_bmca_cell.sv
read_verilog -sv $hdec_rtl/hdec_lane_shift_align.sv
read_verilog -sv $hdec_rtl/hdec_lane_addsub_counter.sv
read_verilog -sv $hdec_rtl/hdec_lane_clip.sv

read_verilog -sv $hdec_rtl/hdec_lane_bmca.sv
read_verilog -sv $hdec_rtl/hdec_lane_4x64.sv
read_verilog -sv $hdec_rtl/hdec_vrf_64x256.sv
read_verilog -sv $hdec_rtl/hdec_top.sv

# Option A: direct top
synth_design -top hdec_top -mode out_of_context

# Option B, only if a wrapper is created later:
# read_verilog -sv $hdec_rtl/hdec_ooc_top_wrapper.sv
# synth_design -top hdec_ooc_top_wrapper -mode out_of_context

report_utilization -file $repo_dir/reports/hdec_ooc_utilization.rpt
report_timing_summary -file $repo_dir/reports/hdec_ooc_timing_summary.rpt
report_power -file $repo_dir/reports/hdec_ooc_power.rpt
```

## 6. Current Uncertain Points

- FPGA part is not specified.
- Constraint file is not specified.
- Clock period is not specified.
- Whether to use direct `hdec_top` or a future plain-port wrapper is not finally confirmed.
- No decision has been made on whether to measure full `hdec_top`, lane-only, VRF-only, or BMCA-only micro-baselines in addition to the HDC-only top baseline.
- No synthesis, implementation, full Vivado project creation, or full CVA6 synthesis has been run in this step.
