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

    (* keep = "true", equivalent_register_removal = "no" *)
    logic        pop_q;
    (* keep = "true", equivalent_register_removal = "no" *)
    logic        xor_q;
    logic [63:0] src_a_q;
    logic [63:0] bool_result;
    logic [6:0]  popcount_count;

    assign bool_result    = src_a_q ^ src_b_i;
    assign popcount_count = 7'($countones(bool_result));

    assign xor_only_valid_o = xor_q && !pop_q;
    assign xor_result_o     = bool_result;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            pop_q        <= 1'b0;
            xor_q        <= 1'b0;
            src_a_q      <= '0;
            popcount_q_o <= '0;
        end else begin
            pop_q <= pop_d_i;
            xor_q <= xor_d_i;
            if (xor_d_i)
                src_a_q <= src_a_i;
            if (pop_q)
                popcount_q_o <= popcount_count;
        end
    end

endmodule
