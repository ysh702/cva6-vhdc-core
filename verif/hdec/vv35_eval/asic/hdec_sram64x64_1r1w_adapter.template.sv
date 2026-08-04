// Copy this file outside the repository and adapt it to the laboratory SRAM.
// The replacement file must define module hdec_vrf_64x256 with the exact VV35
// interface. It must instantiate FOUR independent 64-entry x 64-bit 1R1W
// macros. A 1RW macro is not equivalent.
//
// Required timing contract:
//   request at cycle n
//   macro registered output / bank_ra_early_o at cycle n+1
//   bank_ra_data_o at cycle n+2
//   same-address read/write returns the OLD stored value, matching the RTL;
//   otherwise prove by trace/assertion that the tested workload never creates
//   such a collision and record the macro's actual read-during-write policy
//
// Required deliverables:
//   Liberty .db with timing, area, internal power and leakage
//   functional Verilog model for gate simulation
//   LEF/NDM when place and route is performed
//
// Port mapping sketch for each bank:
//   macro.CLK   <- clk_i
//   macro.RADDR <- bank_ra_addr_i[bank]
//   macro.Q     -> macro_rdata[bank]
//   macro.WE    <- bank_we_i[bank]
//   macro.WADDR <- row_wa_addr_i
//   macro.D     <- bank_wdata_i[bank]
//
// Keep one additional always_ff stage from macro_rdata to bank_ra_data_o and
// connect bank_ra_early_o directly to macro_rdata.
