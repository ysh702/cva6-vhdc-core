// =============================================================================
// hdec_lane_shift_align.sv — Lane-local bit-granular Shift-Align
// =============================================================================
// Pure combinational static function block. No valid/ready/busy FSM.
// Aligns a 64-bit window from {src_b_i, src_a_i} with 1-bit granularity.
// HDC HPERM keeps its existing nibble-granular ISA by driving bit_shift_i
// as {nibble_shift, 2'b00}. ECC micro-ops can reuse this primitive with
// arbitrary 0..63 bit offsets for reduction/square layout work.
// =============================================================================

module hdec_lane_shift_align (
    input  logic [63:0] src_a_i,
    input  logic [63:0] src_b_i,
    input  logic [5:0]  bit_shift_i,
    output logic [63:0] result_o
);

    logic [63:0] lo_shift;
    logic [63:0] hi_shift;
    logic [5:0]  hi_shift_amt;

    assign lo_shift = src_a_i >> bit_shift_i;
    assign hi_shift_amt = 6'd0 - bit_shift_i;
    assign hi_shift = (bit_shift_i == 6'd0) ? 64'b0
                                            : (src_b_i << hi_shift_amt);
    assign result_o = lo_shift | hi_shift;

endmodule
