// =============================================================================
// hdec_lane_boolean_mask.sv — Boolean/Mask Core, Pure Combinational
// =============================================================================
// Phase 1: XOR_ONLY / MASK_XOR_DELTA / MASK_SELECT.
// No flops, no FSM, no valid/ready/busy — always_comb only.
// =============================================================================

module hdec_lane_boolean_mask (
    input  logic [63:0] src_a_i,
    input  logic [63:0] src_b_i,
    input  logic [63:0] mask_i,
    input  logic [1:0]  mode_i,
    output logic [63:0] result_o
);

    always_comb begin
        unique case (mode_i)
            2'b00:   result_o = src_a_i ^ src_b_i;                     // XOR_ONLY
            2'b01:   result_o = (src_a_i ^ src_b_i) & mask_i;          // MASK_XOR_DELTA
            2'b10:   result_o = (src_a_i & ~mask_i) | (src_b_i & mask_i); // MASK_SELECT
            default: result_o = 64'b0;
        endcase
    end

endmodule
