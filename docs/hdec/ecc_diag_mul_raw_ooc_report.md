# GF2 Diagonal Raw Multiplier Vivado OOC Report

## Context

- Branch: `ecc-diag-mul-raw-v1`
- Commit: `b382f8a0 hdec: add diagonal GF2 raw multiplier prototype`
- Target module: `core/hdec/rtl/gf2_256_diag_mul_raw.sv`
- Vivado OOC synthesis: successful, batch exit code 0
- RTL: not modified
- Clock: `clk_i` constrained at 10 ns

## Timing Summary

- WNS: `+1.975 ns`
- TNS: `0.000 ns`
- Estimated Fmax: approximately `124.61 MHz`
- Clock sweep: 10 ns passes; 7.5 ns WNS is `-0.525 ns`

## Utilization Summary

- Slice LUTs: `3640`
- FF / Slice Registers: `1082`
- CARRY: `0`
- MUXF7: `19`
- MUXF8: `4`
- LUT6: `3105`
- LUT5: `215`
- LUT4: `111`
- LUT3: `432`
- LUT2: `74`
- LUT1: `1`

## Critical Path Summary

- Source: `b_reg_reg[224]/C`
- Destination: `prod_q_reg[0]/D` and neighboring `prod_q_reg[100..103]/D`
- Requirement: `10.000 ns`
- Data path delay: `8.022 ns`
- Logic levels: `10`
- Route delay share: approximately `79.93%`

## Conclusion

The module passes 100 MHz in Vivado out-of-context synthesis. Resource use is dominated by LUTs and FFs, with no carry-chain usage, matching expectations for GF(2) bitwise raw multiplication. The current Fmax is mainly limited by a route-dominated critical path, not by DSP or carry-chain resources.

This result represents single-module OOC synthesis only. It does not represent final timing after full HDEC or CVA6 system integration.
