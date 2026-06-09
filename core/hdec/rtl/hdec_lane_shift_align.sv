// =============================================================================
// hdec_lane_shift_align.sv — Lane-local 4-bit Granular Shift-Align
// =============================================================================
// Pure combinational static function block. No valid/ready/busy FSM.
// Supports only nibble shifts: 0, 4, 8, ..., 60 bits.
// =============================================================================

module hdec_lane_shift_align (
    input  logic [63:0] src_a_i,
    input  logic [63:0] src_b_i,
    input  logic [3:0]  nibble_shift_i,
    output logic [63:0] result_o
);

    logic [127:0] cat_word;
    logic [127:0] sh1, sh2, sh4, sh8;

    assign cat_word = {src_b_i, src_a_i};
    assign sh1 = nibble_shift_i[0] ? {4'b0,  cat_word[127:4]}  : cat_word;
    assign sh2 = nibble_shift_i[1] ? {8'b0,  sh1[127:8]}       : sh1;
    assign sh4 = nibble_shift_i[2] ? {16'b0, sh2[127:16]}      : sh2;
    assign sh8 = nibble_shift_i[3] ? {32'b0, sh4[127:32]}      : sh4;

    assign result_o = sh8[63:0];

endmodule
