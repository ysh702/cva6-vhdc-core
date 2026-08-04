# VV35 ASIC synthesis and activity-power handoff

This flow targets standalone `hdec_top`, not CVA6. It uses the same frozen
random K-233 point, resident query, four prototypes and 1,632 HMATCH operations
as the FPGA gate experiment.

`tb_vv35_schedule_asic.sv` preserves the FPGA gate workload and adds only a
portable VCD recorder around `metric_active`. The FPGA report keeps its exact
original testbench hash, while ASIC activity is regenerated against the mapped
ASIC netlist.

## Evidence levels

- `REG_VRF`: complete synthesized design with the 16,384-bit VRF implemented
  as standard-cell storage. This is a complete register-based pre-layout
  reference and is usually pessimistic relative to a suitable SRAM macro.
- `BLACKBOX_VRF`: logic core plus the second VRF return stage. Four 64x64 1R1W
  memory banks are excluded. Missing memory area, power and access timing are
  unknown, not zero. This mode is synthesis-only and cannot run the functional
  gate/power workload without real memory models.
- `SRAM_MACRO_VRF`: complete result only after a compatible adapter and real
  macro timing, area and power views are supplied.

The selected SRAM must provide four independent 64x64, 64-bit, 1R1W banks and
the documented n+1/n+2 read latency. Its same-address read/write policy must
return old data like the RTL, or the workload trace must prove that such a
collision never occurs.

The DC result is a synthesis-level pre-layout estimate. A post-layout result
requires the same workload on a placed-and-routed netlist with extracted
parasitics, followed by PrimeTime PX or an equivalent signoff-capable flow.

## Minimal command sequence

```bash
cd scripts/hdec/vv35_eval/asic
cp env.example.sh env.local.sh
# edit env.local.sh, then:
source env.local.sh
./run_vv35_asic.sh synth REG_VRF
./run_vv35_asic.sh gate SERIAL ZERO REG_VRF
./run_vv35_asic.sh gate INTERLEAVED ZERO REG_VRF
./run_vv35_asic.sh gate SERIAL SDF REG_VRF
./run_vv35_asic.sh gate INTERLEAVED SDF REG_VRF
./run_vv35_asic.sh power SERIAL REG_VRF
./run_vv35_asic.sh power INTERLEAVED REG_VRF
```

After both power runs pass the coverage review, summarize only a matched pair:

```bash
python3 summarize_vv35_asic.py \
  --serial "$HDEC_ASIC_OUT/reg_vrf/power_serial/power.rpt" \
  --interleaved "$HDEC_ASIC_OUT/reg_vrf/power_interleaved/power.rpt" \
  --serial-manifest "$HDEC_ASIC_OUT/reg_vrf/power_serial/run_manifest.txt" \
  --interleaved-manifest "$HDEC_ASIC_OUT/reg_vrf/power_interleaved/run_manifest.txt" \
  --output "$HDEC_ASIC_OUT/reg_vrf/paired_power_summary.json"
```

The two scenarios must read the same DDC. Do not recompile between them.
Gate-level PASS is required before power analysis. Save the `read_saif` log,
the mapped/unmapped activity audit and the full hierarchical power report.
The runner stops when the installed Synopsys release cannot produce the SAIF
coverage audit. Review that report before accepting a power value; a successful
`read_saif` command alone is not sufficient. VV35 uses a project acceptance
threshold of at least 90% overall annotation and requires the clock and all
material sequential-output groups to be covered. A lower or structurally
incomplete result is preliminary even if Power Compiler emits a number.

The Xilinx post-route SAIF cannot annotate the ASIC netlist. Only the vector
bundle and scenario contract are shared across technologies.

The supplied SDC excludes asynchronous reset paths from ordinary setup/hold
WNS. Report recovery/removal separately if the laboratory signoff flow checks
reset release. The output load is expressed in the capacitance unit shown by
`reports/units.rpt`, not assumed to be pF.
