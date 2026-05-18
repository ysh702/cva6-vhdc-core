// =============================================================================
// hdec_lane_boolean_mask.sv — XOR-only Bitwise Front-End, Pure Combinational
// =============================================================================
// Phase 1 HDC use: hbind and hsim XOR diff generation.
// No flops, no FSM, no valid/ready/busy — always_comb only.
// =============================================================================

module hdec_lane_boolean_mask (
    input  logic [63:0] src_a_i,
    input  logic [63:0] src_b_i,
    output logic [63:0] result_o
);

    assign result_o = src_a_i ^ src_b_i;

endmodule
