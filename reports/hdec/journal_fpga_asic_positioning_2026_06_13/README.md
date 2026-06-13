# Journal positioning: FPGA-only vs ASIC data for HDC/ECC papers

Date: 2026-06-13
Branch: hdec-ecc-pointmul-v27

## Question

For SCI Q1/Q2-style targets such as IEEE TC, TCAD, TCAS-I, and IEEE IoT-J, do HDC/ECC hardware papers usually need ASIC data, or is pure FPGA data acceptable?

## Short answer

Pure FPGA data is acceptable in these venues when the paper is explicitly an FPGA accelerator, FPGA prototype, RISC-V/FPGA SoC, or reconfigurable architecture paper.

ASIC data becomes more expected when the paper claims:

- ultra-low-power circuit design,
- standard-cell / CMOS implementation,
- post-layout energy/area,
- in-memory / emerging-memory hardware,
- chip-level circuit novelty,
- ASIC-oriented IoT node deployment.

For HDEC, a Vivado-only FPGA paper is defensible if we position the contribution as an FPGA/HDC/ECC accelerator and compare against FPGA HDC/ECC papers using LUT/FF/BRAM/DSP/cycles. An ASIC synthesis line would strengthen TCAD/TCAS-I positioning, but it is not mandatory for TC or IoT-J if the story is clearly FPGA-based.

## Evidence table

| Venue | Paper | Topic | Implementation evidence | Data type | Takeaway |
| --- | --- | --- | --- | --- | --- |
| IEEE TC 2020 | Salamat et al., "Accelerating Hyperdimensional Computing on FPGAs by Exploiting Computational Reuse" | HDC accelerator | Verilog RTL, Xilinx Vivado, Kintex-7 KC705, Vivado power estimation | FPGA-only: LUT/FF/BRAM/DSP utilization, throughput, energy | TC accepts pure FPGA HDC accelerator papers |
| IEEE TCAD 2020 | Imani et al., "QuantHD: A Quantization Framework for Hyperdimensional Computing" | HDC quantization + accelerator | Verilog, Xilinx Vivado, Kintex-7 KC705 | FPGA-only: LUT/FF/DSP/BRAM utilization, FPGA inference/training | TCAD can accept HDC work with FPGA-only implementation when contribution includes algorithm-hardware co-design |
| IEEE TCAS-I 2021 | Eggimann et al., "A 5 uW Standard Cell Memory-Based Configurable HDC Accelerator" | HDC always-on accelerator | all-digital CMOS, standard-cell memory, post-layout simulation | ASIC/post-layout: power, energy, area reduction | TCAS-I circuit-style HDC work tends to use ASIC/post-layout data |
| IEEE TCAD 2025 | Yu et al., "LAHDC: Logic-Aggregation-Based Query..." | embedded HDC accelerator | abstract positions against ASIC/FPGA HDC accelerators and reports area/energy reduction vs ASIC HDC | ASIC-oriented comparison; likely generated hardware | TCAD HDC papers often emphasize area/energy, and ASIC data helps |
| IEEE IoT-J 2022 | Taheri et al., "RISC-HD: Lightweight RISC-V Processor for Efficient HDC Inference" | RISC-V extension for HDC inference | RISC-V/HDC IoT processor paper | implementation-oriented; IoT edge hardware | IoT-J accepts processor/FPGA-style HDC hardware papers |
| IEEE TCAS-I 2014 | Azarderakhsh et al., "Efficient Algorithm and Architecture for ECC..." | binary ECC for constrained nodes | VHDL + Synopsys Design Compiler, STM 65 nm standard-cell library | ASIC: GE, cycles, delay, power, energy | TCAS-I ECC constrained-hardware papers often use ASIC synthesis |
| IEEE TCAS-I 2017 | Koziel et al., "Post-Quantum Cryptography on FPGA Based on Isogenies..." | isogeny/ECC-like PQC | explicitly FPGA-based | FPGA: LUT/FF/cycles/frequency style | TCAS-I also accepts pure FPGA when the paper is explicitly FPGA-based |
| IEEE IoT-J 2024 | Mao et al., "REALISE-IoT: RISC-V-Based Efficient and Lightweight Public-Key System..." | IoT public-key/ECC-style system | RISC-V lightweight public-key system for IoT | system/implementation data | IoT-J values deployment/system relevance; FPGA/prototype data can be sufficient |

## What this means for HDEC

HDEC should not apologize for being FPGA-first. The FPGA literature is a valid comparison space because many HDC/ECC accelerator papers report:

- LUT,
- FF,
- BRAM/LUTRAM,
- DSP,
- Fmax,
- cycles,
- latency,
- energy from FPGA power tools.

However, submission positioning matters:

### Strong FPGA-first positioning

Best for:

- IEEE TC,
- IEEE IoT-J,
- FPGA-friendly TCAD special cases,
- reconfigurable/embedded accelerator journals.

Required story:

- HDEC is an FPGA HDC/ECC accelerator.
- Compare against FPGA HDC and FPGA binary-field ECC papers.
- Use full FPGA resource vector, not only Logic LUT.
- Report cycles, Fmax, wall-clock latency, energy estimate if available.

### Strong ASIC-enhanced positioning

Best for:

- TCAS-I,
- TCAD if claiming circuit-level area/energy,
- low-power / always-on / chip-level framing.

Required story:

- Add ASIC synthesis with Genus/DC or equivalent.
- Report cell area, GE/NAND2-equivalent gates, timing, power, energy.
- If possible, add post-layout or at least clear "pre-layout synthesis" wording.
- Keep FPGA results separate; do not mix LUT and um2 in one direct comparison.

## Recommendation for HDEC paper strategy

Use FPGA as the main, fully verified story now:

1. FPGA HDC+ECC Pareto result:
   - `6005` PMUL cycles.
   - `6258 LUT / 2113 FF` full HDC+ECC top.
   - compare against FPGA ECC papers using cycles vs LUT.
2. HDC/ECC operator-reuse story:
   - binary-field ECC maps to HDC-native XOR, popcount/parity, shift, and linear fold.
3. V27 temporal reuse:
   - foreground HDC, background ECC interleaving.
   - compare sequential `T_HDC + 6005` vs interleaved execution.

Then add ASIC as an optional strengthening line if the tools are available:

1. run ASIC synthesis only after V27 architecture settles.
2. report ASIC area/timing/power/energy as a separate table.
3. use ASIC data to target TCAD/TCAS-I more confidently.

Do not spend effort on "Virtuoso-specific optimization" now. Optimize RTL at the algorithm and architecture level so that both Vivado FPGA and ASIC synthesis can benefit:

- reduce VRF muxing,
- unify HDC/ECC uop broker,
- make boolean-popcount a shared primitive,
- expose square/reduce as linear fold,
- reduce ECC-only product/control state.

## Bottom line

Pure Vivado FPGA data can support a serious TC/IoT-J-style paper, and there are direct HDC examples in IEEE TC and TCAD that use FPGA-only data. For TCAS-I/TCAD circuit-style framing, ASIC data is a strong plus and sometimes expected, but it is not universally required. The safest route is:

> FPGA results as the primary contribution; ASIC synthesis as optional secondary validation if tools/time allow.

## Sources

- Salamat et al., IEEE TC 2020, HD-Core FPGA HDC: https://par.nsf.gov/servlets/purl/10301134
- Imani et al., IEEE TCAD 2020, QuantHD FPGA HDC: https://par.nsf.gov/servlets/purl/10169532
- Eggimann et al., IEEE TCAS-I 2021, 5 uW SCM HDC accelerator: https://arxiv.org/abs/2102.02758
- Azarderakhsh et al., IEEE TCAS-I 2014, ECC for constrained applications: https://cse.usf.edu/~mehran2/Papers/J8.pdf
- Yu et al., IEEE TCAD 2025, LAHDC: https://dl.acm.org/doi/abs/10.1109/TCAD.2024.3420905
- Taheri et al., IEEE IoT-J 2022, RISC-HD: https://doi.org/10.1109/JIOT.2022.3191717
- Koziel et al., IEEE TCAS-I 2017, isogenies on FPGA: https://doi.org/10.1109/TCSI.2016.2611561
- Mao et al., IEEE IoT-J 2024, REALISE-IoT: https://doi.org/10.1109/JIOT.2023.3296135

