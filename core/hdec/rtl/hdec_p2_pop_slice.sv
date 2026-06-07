// =============================================================================
// hdec_p2_pop_slice.sv - Local P2 XOR/popcount control and popcount capture
// =============================================================================

module hdec_p2_pop_slice (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        pop_d_i,
    input  logic        xor_d_i,
    input  logic [63:0] src_a_i,
    input  logic [63:0] src_b_i,
    output logic        xor_only_valid_o,
    output logic [63:0] xor_result_o,
    output logic [6:0]  popcount_q_o
);

    logic        pop_q;
    logic        xor_q;
    logic [63:0] bool_src_a;
    logic [63:0] bool_src_b;
    logic [63:0] bool_result;
    logic [6:0]  popcount_count;

    assign bool_src_a = (pop_q || xor_q) ? src_a_i : '0;
    assign bool_src_b = (pop_q || xor_q) ? src_b_i : '0;

    hdec_lane_boolean_mask i_boolean_mask (
        .src_a_i (bool_src_a),
        .src_b_i (bool_src_b),
        .result_o(bool_result)
    );

    hdec_lane_popcount_compressor i_popcount (
        .mode_i      (1'b0),
        .diff_i      (pop_q ? bool_result : '0),
        .a_i         ('0),
        .b_i         ('0),
        .c_i         ('0),
        .count_o     (popcount_count),
        .csa_sum_o   (),
        .csa_carry_o (),
        .csa_cout_o  ()
    );

    assign xor_only_valid_o = xor_q && !pop_q;
    assign xor_result_o     = bool_result;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            pop_q        <= 1'b0;
            xor_q        <= 1'b0;
            popcount_q_o <= '0;
        end else begin
            pop_q <= pop_d_i;
            xor_q <= xor_d_i;
            if (pop_q)
                popcount_q_o <= popcount_count;
        end
    end

endmodule
