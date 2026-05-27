# VRF LUTRAM/BRAM Patch Plan for WSL Codex CLI

Date: 2026-05-27

Repository: `H:\CVA6-HDEC\cva6-vhdc-core`

Baseline target:

- Branch: `hdec-phase1`
- Commit: `1707a6d6`
- Tag: `hdec-phase1-hdc-baseline-pre-ecc`

This note is for continuing the VRF memory inference work from WSL Codex CLI.
It is a patch plan only. It does not require changing BMCA, Lane, ECC, CVA6, or
the full CVA6 integration.

## 1. Current Vivado Resource Problem Summary

The frozen HDC-only OOC Vivado run used:

- Vivado: 2022.2
- Part: `xc7z020clg400-2`
- Top: `hdec_top`
- Clock: 10 ns
- Flow: `synth_design -mode out_of_context`

Resource summary from the baseline OOC reports:

| Block | LUTs | FFs | BRAM | LUTRAM |
|---|---:|---:|---:|---:|
| `hdec_top` total | 32,837 | 19,861 | 0 | 0 |
| `i_vrf` / `hdec_vrf_64x256` | 30,240 | 16,649 | 0 | 0 |

Contribution:

- `i_vrf` is 92.1% of total LUTs.
- `i_vrf` is 83.8% of total FFs.
- `report_ram_utilization` reports 0 BlockRAM and 0 LUTRAM.

Vivado warning observed in the baseline run:

- `vrf_b0_reg`, `vrf_b1_reg`, `vrf_b2_reg`, and `vrf_b3_reg` were dissolved into
  registers.

Conclusion: the high utilization is dominated by VRF storage being implemented as
flip-flop/register logic instead of SRAM-like LUTRAM or BRAM. Lane/BMCA logic is
visible but secondary.

## 2. Current `hdec_vrf_64x256.sv` Interface and Semantics

Use the frozen baseline file at:

- `core/hdec/rtl/hdec_vrf_64x256.sv`

The module imports:

- `hdec_pkg::*`
- `hdec_resource_pkg::*`

Interface summary:

- Bank count: 4 banks, controlled by `LANE_NUM`.
- Depth per bank: 64 entries, controlled by `VRF_ENTRIES`.
- Width per bank entry: 64 bits, controlled by `LANE_WIDTH`.
- Read ports: one read address/data path per bank:
  - `bank_ra_addr_i[LANE_NUM]`
  - `bank_ra_data_o[LANE_NUM]`
- Write ports: one write enable/address/data path per bank:
  - `bank_we_i[LANE_NUM]`
  - `bank_wa_addr_i[LANE_NUM]`
  - `bank_wdata_i[LANE_NUM]`
- Read behavior: 1-cycle synchronous registered read, not same-cycle
  combinational read.
- Write behavior: synchronous write.
- Reset behavior: reset does not directly clear every memory entry in the reset
  branch. It resets the init FSM and read output registers.
- Init clear: yes. `INIT_CLEAR` walks `init_cnt_q` from 0 to 255 and writes zero
  into one bank entry per cycle.
- Read-after-write forwarding: yes. Same-cycle write/read to the same bank
  address forwards `bank_wdata_i` to `bank_ra_data_o`.
- `vrf_ready_o`: high only when init clear reaches `INIT_DONE`.

`hdec_top` access timing:

- `hdec_top` instantiates the VRF as `i_vrf` near the top of
  `core/hdec/rtl/hdec_top.sv`.
- `hdec_top` sets `vrf_ra` in one FSM state and consumes `vrf_rd` in a following
  FSM state. Examples:
  - `HDEC_VRD64` sets `vrf_ra`, then `S_RD_WAIT` returns `vrf_rd`.
  - `S_HBIND_RD0` sets source 0 address, then `S_HBIND_RD1` captures `vrf_rd`
    into `src0_n` and issues source 1 address.
  - `S_HSIM_RD0` / `S_HSIM_RD1`, `S_HPERM_RD_A` / `S_HPERM_RD_B`,
    `S_BADD_RD_HV` / `S_BADD_RD_ACC`, and `S_HCLIP_RD_ACC` follow the same
    one-state-delayed pattern.

Important conclusion: `hdec_top` does not appear to require same-cycle
combinational VRF data. It already behaves like it expects a 1-cycle registered
read.

Stage 3/4 initialization behavior:

- `verif/hdec/hdc_inference_test.S` explicitly runs `HCLR` for slots 0 to 7 and
  `BCLR` before compute.
- The Stage 3 comment says HV0 stays all-zero from `HCLR`.
- `verif/hdec/hdc_e2e_train_infer_test.S` heavily uses `BCLR` and its `fill_hv`
  macro explicitly writes all 16 `VADDR` + `VWR64` pairs.

This means Stage 3/4 should not rely only on reset-time VRF memory contents if
the software initialization remains intact. Still, keep the current `vrf_ready_o`
and init behavior unless there is a deliberate review decision to remove it.

## 3. Why Current VRF Does Not Infer LUTRAM/BRAM

The likely blockers are local to `hdec_vrf_64x256.sv`.

Specific baseline code structures to inspect:

1. Storage is plain unpacked arrays with a local parameter still naming the
   implementation as register-like:

   ```systemverilog
   localparam string VRF_IMPL = "REG";

   logic [LANE_WIDTH-1:0] vrf_b0 [0:VRF_ENTRIES-1];
   logic [LANE_WIDTH-1:0] vrf_b1 [0:VRF_ENTRIES-1];
   logic [LANE_WIDTH-1:0] vrf_b2 [0:VRF_ENTRIES-1];
   logic [LANE_WIDTH-1:0] vrf_b3 [0:VRF_ENTRIES-1];
   ```

2. One large `always_ff @(posedge clk_i)` handles read output registration,
   normal writes, and init-clear writes for all four banks.

3. Each bank has two possible write sources in the same process:

   ```systemverilog
   if (bank_we_i[0])
       vrf_b0[bank_wa_addr_i[0]] <= bank_wdata_i[0];

   if (init_state_q == INIT_CLEAR && init_cnt_q[7:6] == 2'd0)
       vrf_b0[init_cnt_q[5:0]] <= '0;
   ```

   This creates a more complex write-port pattern than a simple single-port RAM
   template. If both conditions were true, the later init-clear assignment wins.

4. Read-after-write forwarding is interleaved with the memory read in the same
   large process:

   ```systemverilog
   if (bank_we_i[0] && (bank_wa_addr_i[0] == ra0))
       bank_ra_data_o[0] <= bank_wdata_i[0];
   else
       bank_ra_data_o[0] <= vrf_b0[ra0];
   ```

   Forwarding is functionally useful, but combined with multi-bank writes and
   init-clear muxing it may prevent Vivado from matching a clean RAM template.

5. Read addresses are declared as automatic local variables inside the clocked
   block:

   ```systemverilog
   automatic logic [VRF_IDX_W-1:0] ra0 = bank_ra_addr_i[0];
   ```

   This is legal SystemVerilog, but it is not the simplest Vivado inference
   template. Prefer direct indexed reads or separately declared wires if needed.

6. The reset branch does not reset memory entries, but it resets all read outputs
   through a loop:

   ```systemverilog
   for (int b = 0; b < LANE_NUM; b++)
       bank_ra_data_o[b] <= '0;
   ```

   This is not the main memory-inference blocker because it does not clear the
   memory arrays. The bigger issue is the combined read/write/init-clear process.

7. The init-clear FSM writes every entry after reset. Sequential clear can be
   compatible with RAM inference if written as a simple RAM write port, but the
   current code overlays init writes and normal writes inside the same process
   after forwarding/read logic.

Bottom line: Vivado sees the VRF as complex register behavior rather than four
simple RAMs. The first patch should simplify the RAM template while preserving
the module interface and the observed 1-cycle read semantics.

## 4. Recommended First Patch: LUTRAM-Friendly VRF

Goal: make Vivado infer distributed RAM / LUTRAM first. Do not jump directly to
BRAM.

Rationale:

- Each bank is only 64 x 64 bits.
- LUTRAM is a good match for shallow 64-entry arrays.
- LUTRAM can preserve low-latency registered-read behavior with much less FSM
  disruption than BRAM.
- BRAM would likely require stricter synchronous read timing and may force
  `hdec_top` FSM changes.

Patch constraints:

- Keep the `hdec_vrf_64x256.sv` module interface unchanged.
- Do not change `hdec_top` ports.
- Avoid changing the `hdec_top` FSM unless a regression proves the read latency
  was misunderstood.
- Keep four independent memory arrays, one per bank.
- Add Vivado memory style attributes:

  ```systemverilog
  (* ram_style = "distributed" *) logic [LANE_WIDTH-1:0] vrf_b0 [0:VRF_ENTRIES-1];
  (* ram_style = "distributed" *) logic [LANE_WIDTH-1:0] vrf_b1 [0:VRF_ENTRIES-1];
  (* ram_style = "distributed" *) logic [LANE_WIDTH-1:0] vrf_b2 [0:VRF_ENTRIES-1];
  (* ram_style = "distributed" *) logic [LANE_WIDTH-1:0] vrf_b3 [0:VRF_ENTRIES-1];
  ```

- Split bank writes into simple per-bank clocked write processes.
- Keep registered read outputs and normal same-cycle read-after-write forwarding
  if possible.
- Avoid any reset branch that clears all memory entries.
- If keeping reset initialization, keep it as a simple sequential init-clear write
  through the same single write port per bank.
- During init clear, prefer that init owns the bank write port. Normal HDEC
  traffic is expected only after reset/init, especially if `vrf_ready_o` is used
  later.

Suggested shape:

```systemverilog
logic init_b0_we, init_b1_we, init_b2_we, init_b3_we;
logic [VRF_IDX_W-1:0] init_addr;

assign init_addr  = init_cnt_q[5:0];
assign init_b0_we = (init_state_q == INIT_CLEAR) && (init_cnt_q[7:6] == 2'd0);

always_ff @(posedge clk_i) begin
    if (init_b0_we)
        vrf_b0[init_addr] <= '0;
    else if (bank_we_i[0])
        vrf_b0[bank_wa_addr_i[0]] <= bank_wdata_i[0];
end

always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni)
        bank_ra_data_o <= '0;
    else begin
        if (bank_we_i[0] && (bank_wa_addr_i[0] == bank_ra_addr_i[0]))
            bank_ra_data_o[0] <= bank_wdata_i[0];
        else
            bank_ra_data_o[0] <= vrf_b0[bank_ra_addr_i[0]];
    end
end
```

Repeat the same simple write template for banks 1 to 3. Keep the init FSM small.

If Stage 3/4 or lower-level tests require reset-cleared VRF contents:

- Preferred software-visible rule: HDEC code must explicitly initialize VRF with
  `HCLR`, `BCLR`, or explicit `VADDR` + `VWR64` writes before use.
- Low-risk hardware fallback: keep the existing sequential init-clear FSM, but
  rewrite it as simple per-bank write enables so Vivado can still infer LUTRAM.
- Do not introduce a wide reset clear loop over the memory arrays.
- Do not add a complex multi-cycle controller unless there is a failing test that
  proves it is needed.

## 5. Second-Stage Alternative: BRAM-Friendly VRF

BRAM should be treated as a second-stage optimization, not the first patch.

Potential benefits:

- Lower LUT usage than LUTRAM for larger future VRFs.
- Better scalability if VRF depth/width grows.

Risks:

- BRAM read is synchronous and may impose stricter one-cycle or extra-cycle
  latency depending on mode and output register settings.
- `hdec_top` may need additional read wait states in places that currently assume
  one registered read latency.
- Write-forwarding and same-cycle read/write behavior must be reviewed carefully.
- BRAM resource mapping for four shallow 64 x 64 banks may be inefficient.

Recommendation: first make the existing VRF infer LUTRAM and pass Stage 3/4.
Only then evaluate a BRAM version behind a separate branch and explicit latency
contract.

## 6. WSL Codex CLI Execution Steps

Run these in the WSL clone of the repository, not through `\\wsl.localhost` from
Windows.

1. Confirm baseline:

   ```sh
   cd /path/to/cva6-vhdc-core
   git fetch --all --tags --prune
   git switch hdec-phase1
   git pull --ff-only origin hdec-phase1
   git rev-parse --short HEAD
   git tag --points-at HEAD
   git status --short
   ```

   Expected:

   ```text
   1707a6d6
   hdec-phase1-hdc-baseline-pre-ecc
   ```

2. Create the work branch:

   ```sh
   git switch -c vrf-lutram-inference-v1
   ```

3. Modify only:

   ```text
   core/hdec/rtl/hdec_vrf_64x256.sv
   ```

   Optional new report/script files may be added later, but do not touch BMCA,
   Lane, ECC, CVA6, submodules, or unrelated RTL.

4. Run Verilator build in WSL:

   ```sh
   rm -rf work-ver
   make verilate NUM_JOBS=16
   ```

   If the repository requires environment variables, set the same ones used by
   the local CVA6 environment, especially `RISCV`, `VERILATOR_INSTALL_DIR`, and
   `SPIKE_INSTALL_DIR`.

5. Build and run Stage 3:

   ```sh
   mkdir -p tmp/hdec_logs

   riscv64-unknown-elf-gcc -march=rv64gc_zifencei -mabi=lp64d \
     -nostartfiles -nostdlib -mcmodel=medany \
     -I verif/tests/custom/env -I verif/tests/custom/common \
     -T verif/hdec/hdec_link.ld verif/tests/custom/common/crt.S \
     verif/hdec/hdc_inference_test.S \
     -o tmp/hdec_logs/hdc_inference_test.elf

   work-ver/Variane_testharness tmp/hdec_logs/hdc_inference_test.elf \
     > tmp/hdec_logs/hdc_inference_test.log

   python3 verif/hdec/parse_inference_perf.py tmp/hdec_logs/hdc_inference_test.log
   ```

6. Build and run Stage 4:

   ```sh
   riscv64-unknown-elf-gcc -march=rv64gc_zifencei -mabi=lp64d \
     -nostartfiles -nostdlib -mcmodel=medany \
     -I verif/tests/custom/env -I verif/tests/custom/common \
     -T verif/hdec/hdec_link.ld verif/tests/custom/common/crt.S \
     verif/hdec/hdc_e2e_train_infer_test.S \
     -o tmp/hdec_logs/hdc_e2e_train_infer_test.elf

   work-ver/Variane_testharness tmp/hdec_logs/hdc_e2e_train_infer_test.elf \
     > tmp/hdec_logs/hdc_e2e_train_infer_test.log

   python3 verif/hdec/parse_e2e_train_infer_perf.py tmp/hdec_logs/hdc_e2e_train_infer_test.log
   ```

7. After WSL regression passes, return to Win11 Vivado and rerun HDC-only OOC
   only:

   ```powershell
   Set-Location H:\CVA6-HDEC\cva6-vhdc-core
   & "H:\SWTOOLS\Vivado\2022.2\bin\vivado.bat" -mode batch `
     -source "H:/CVA6-HDEC/cva6-vhdc-core/scripts/vivado/hdec_hdc_ooc_synth.tcl"
   ```

   Expected direction:

   - `i_vrf` LUT/FF should drop sharply.
   - LUTRAM should become nonzero.
   - BRAM may remain zero for the LUTRAM-friendly first patch.
   - The old dissolved-into-registers warning should disappear.

8. Suggested optional VRF-only OOC check:

   Create a small Vivado Tcl that reads only:

   ```text
   core/hdec/rtl/hdec_pkg.sv
   core/hdec/rtl/hdec_resource_pkg.sv
   core/hdec/rtl/hdec_vrf_64x256.sv
   ```

   Then synthesize:

   ```tcl
   synth_design -top hdec_vrf_64x256 -part xc7z020clg400-2 -mode out_of_context
   report_utilization -hierarchical
   report_ram_utilization
   report_timing_summary
   ```

## 7. Things Not To Do

Do not:

- Modify BMCA.
- Modify Lane datapath modules.
- Modify ECC logic.
- Modify CVA6 core or CV-X-IF integration.
- Broadly rewrite `hdec_top` FSM.
- Change HDC instruction semantics just to satisfy synthesis.
- Break Stage 3 or Stage 4 Verilator behavior for a better Vivado report.
- Commit `reports/*.dcp`.
- Commit `build/`.
- Commit full Vivado projects.
- Commit submodule changes.
- Blindly optimize unrelated logic.
- Add complex control networks before proving they are necessary.

## 8. Final Prompt for WSL Codex CLI

Copy this prompt into WSL Codex CLI:

```text
We are optimizing HDEC VRF memory inference in the CVA6 + HDEC repository.

Repository: /path/to/cva6-vhdc-core
Baseline branch: hdec-phase1
Baseline commit: 1707a6d6
Baseline tag: hdec-phase1-hdc-baseline-pre-ecc

Goal:
Make core/hdec/rtl/hdec_vrf_64x256.sv infer LUTRAM/distributed RAM in Vivado
instead of being dissolved into registers. Keep this as a minimal, reviewable RTL
patch.

Known Vivado baseline:
- hdec_top OOC on xc7z020clg400-2, 10 ns, Vivado 2022.2
- hdec_top total: 32,837 LUT / 19,861 FF / BRAM 0 / LUTRAM 0
- i_vrf: 30,240 LUT / 16,649 FF
- i_vrf is 92.1% LUT and 83.8% FF
- report_ram_utilization shows 0 BlockRAM and 0 LUTRAM
- Vivado warned that vrf_b0_reg through vrf_b3_reg were dissolved into registers

Important design facts:
- hdec_vrf_64x256 has 4 banks, each 64 x 64 bits.
- It has one read path and one write path per bank.
- Existing read semantics are 1-cycle synchronous registered read.
- Existing writes are synchronous.
- Existing code has same-cycle read-after-write forwarding.
- Existing code has a sequential init-clear FSM after reset.
- hdec_top appears to set vrf_ra in one FSM state and consume vrf_rd in a later
  FSM state. Do not assume combinational VRF read is required.

Please do:
1. Confirm git branch/commit/tag and create branch vrf-lutram-inference-v1.
2. Modify only core/hdec/rtl/hdec_vrf_64x256.sv.
3. Keep the module interface unchanged.
4. Keep hdec_top unchanged unless a failing regression proves a latency issue.
5. Use four independent memory arrays with Vivado distributed RAM attributes:
   (* ram_style = "distributed" *).
6. Split per-bank writes into simple synchronous write processes.
7. Preserve the 1-cycle registered read behavior.
8. Preserve normal read-after-write forwarding if possible.
9. Avoid reset-time full memory array clearing.
10. If reset-cleared VRF is required, keep only a small sequential init-clear FSM
    with simple per-bank write enables.

Please do not:
- Modify BMCA, Lane, ECC, CVA6, CV-X-IF, or unrelated RTL.
- Run full CVA6 synthesis.
- Change instruction semantics.
- Add a complex controller just to make synthesis pass.
- Commit reports/*.dcp, build/, full Vivado projects, or submodule changes.

Verification order:
1. Rebuild Verilator model:
   rm -rf work-ver
   make verilate NUM_JOBS=16

2. Run Stage 3:
   mkdir -p tmp/hdec_logs
   riscv64-unknown-elf-gcc -march=rv64gc_zifencei -mabi=lp64d \
     -nostartfiles -nostdlib -mcmodel=medany \
     -I verif/tests/custom/env -I verif/tests/custom/common \
     -T verif/hdec/hdec_link.ld verif/tests/custom/common/crt.S \
     verif/hdec/hdc_inference_test.S \
     -o tmp/hdec_logs/hdc_inference_test.elf
   work-ver/Variane_testharness tmp/hdec_logs/hdc_inference_test.elf \
     > tmp/hdec_logs/hdc_inference_test.log
   python3 verif/hdec/parse_inference_perf.py tmp/hdec_logs/hdc_inference_test.log

3. Run Stage 4:
   riscv64-unknown-elf-gcc -march=rv64gc_zifencei -mabi=lp64d \
     -nostartfiles -nostdlib -mcmodel=medany \
     -I verif/tests/custom/env -I verif/tests/custom/common \
     -T verif/hdec/hdec_link.ld verif/tests/custom/common/crt.S \
     verif/hdec/hdc_e2e_train_infer_test.S \
     -o tmp/hdec_logs/hdc_e2e_train_infer_test.elf
   work-ver/Variane_testharness tmp/hdec_logs/hdc_e2e_train_infer_test.elf \
     > tmp/hdec_logs/hdc_e2e_train_infer_test.log
   python3 verif/hdec/parse_e2e_train_infer_perf.py tmp/hdec_logs/hdc_e2e_train_infer_test.log

4. After WSL regression passes, ask Win11 Vivado to rerun HDC-only OOC and check
   that LUTRAM is nonzero and the VRF dissolved-into-registers warning is gone.

Stop and report if:
- The patch requires changing hdec_top read latency semantics.
- Verilator Stage 3 or Stage 4 fails.
- Vivado still dissolves the VRF into registers after the minimal LUTRAM patch.
```
