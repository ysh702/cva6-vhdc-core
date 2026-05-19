// =============================================================================
// hdec_bmca_cell.sv - BMCA 3:2 Bit Compressor Cell
// =============================================================================
// Standard one-bit compressor used by the BMCA hvsim batch path.
// lo + 2*hi equals the number of asserted inputs.
// =============================================================================

module hdec_bmca_cell (
    input  logic a_i,
    input  logic b_i,
    input  logic c_i,
    output logic lo_o,
    output logic hi_o
);

    assign lo_o = a_i ^ b_i ^ c_i;
    assign hi_o = (a_i & b_i) | (a_i & c_i) | (b_i & c_i);

endmodule
