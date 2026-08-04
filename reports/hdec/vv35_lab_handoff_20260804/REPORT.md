# VV35 board and ASIC laboratory handoff validation

## Outcome

VV35 now has one frozen cross-platform workload and separate runners for the
existing routed-FPGA estimate, CVA6+HDEC board measurement and ASIC
DC/Power-Compiler estimate. No HDEC RTL file was changed for this handoff.

The shared workload is one random legal sect233k1 PMUL plus 1,632 four-class
HMATCH operations. SERIAL and INTERLEAVED use the same vectors, operation
counts, hardware image/netlist and measurement boundary. Only foreground
request release timing changes.

## Validation performed on the development machine

- Frozen vector hashes, K, operation counts, cycle references, board include,
  ASIC file list and CSV column alignment under Vivado 2024.2 Python 3.8.3:
  PASS.
- Python syntax for all VV35 evaluation utilities: PASS.
- Bash syntax for the ASIC runner: PASS.
- PowerShell syntax for the laboratory bundle builder: PASS.
- Vivado/XSim 2024.2 compile and elaboration of the portable gate testbench:
  PASS.
- Public-interface RTL smoke using the gate workload, one random K-233 PMUL
  and one interleaved HMATCH: PASS. The PMUL result, HMATCH result and guard
  rows were checked by the testbench.
- Board power integration parser synthetic-unit test: PASS.
- ASIC power report unit-conversion parser synthetic-unit test: PASS.

Synopsys DC, VCS, Power Compiler and the RISC-V board cross-toolchain are not
installed on this machine. Their scripts were statically validated but must be
executed in the laboratory. A result is not accepted until gate simulation
passes and the SAIF coverage audit is readable.

## Evidence labels

- Routed Xilinx netlist plus gate SAIF: activity-based routed FPGA power
  estimate, not a board measurement.
- Board instrument trace: board-level measured power for explicitly named
  rails, including the stated CPU/wrapper/system boundary.
- DC plus gate SAIF plus Power Compiler: synthesis-level pre-layout ASIC power
  estimate.
- Placed/routed netlist plus parasitics plus PrimeTime PX: post-layout ASIC
  power estimate.

The BLACKBOX_VRF result excludes four SRAM banks, including their area, power
and access timing. It is a logic-core result only. A complete SRAM-based ASIC
result requires exactly four compatible 64x64, 64-bit, 1R1W macro instances
with timing, area, internal-power and leakage views.

## Reproducibility anchors

- Workload contract SHA-256:
  `63d57a1a5e472df8db6adc97bcda08c503cd8b478a4d3f07033c6f76f32161a9`
- Vector manifest SHA-256:
  `1a79121c84b9147bdd366d88165cc48df8d9037a283552a3acbfcdc1e4afaa73`
- Board generated include SHA-256:
  `d7e6895f220f475344867a32517bd5b6fbb9cc0da0657aa967cab27d6099b0de`
- Random K:
  `0000002fa9f8d054ea7fd4613721adbba762ed34fd11b768a6bff1725e8ce89a`
- K Hamming weight: 128.
- Expected HMATCH result: class 0, score 505, packed result `0x1f9`.

The post-commit portable laboratory ZIP is generated outside the repository by
`scripts/hdec/vv35_eval/prepare_vv35_lab_bundle.ps1` and carries its own file
manifest and ZIP hash.
