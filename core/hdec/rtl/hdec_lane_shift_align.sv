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

    always_comb begin
        unique case (nibble_shift_i)
            4'd0:    result_o = src_a_i;
            4'd1:    result_o = (src_a_i >> 4)  | (src_b_i << 60);
            4'd2:    result_o = (src_a_i >> 8)  | (src_b_i << 56);
            4'd3:    result_o = (src_a_i >> 12) | (src_b_i << 52);
            4'd4:    result_o = (src_a_i >> 16) | (src_b_i << 48);
            4'd5:    result_o = (src_a_i >> 20) | (src_b_i << 44);
            4'd6:    result_o = (src_a_i >> 24) | (src_b_i << 40);
            4'd7:    result_o = (src_a_i >> 28) | (src_b_i << 36);
            4'd8:    result_o = (src_a_i >> 32) | (src_b_i << 32);
            4'd9:    result_o = (src_a_i >> 36) | (src_b_i << 28);
            4'd10:   result_o = (src_a_i >> 40) | (src_b_i << 24);
            4'd11:   result_o = (src_a_i >> 44) | (src_b_i << 20);
            4'd12:   result_o = (src_a_i >> 48) | (src_b_i << 16);
            4'd13:   result_o = (src_a_i >> 52) | (src_b_i << 12);
            4'd14:   result_o = (src_a_i >> 56) | (src_b_i << 8);
            4'd15:   result_o = (src_a_i >> 60) | (src_b_i << 4);
            default: result_o = src_a_i;
        endcase
    end

endmodule
