// Independently synthesized IP shells for the VV35 HDC+ECC accelerator
// evaluation.  Each shell owns a complete private hdec_top specialization.

module vv35_hdc_ip_top import hdec_pkg::*; (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        valid_i,
    output logic        ready_o,
    input  hdec_op_t    operator_i,
    input  logic [63:0] operand_a_i,
    input  logic [63:0] operand_b_i,
    output logic        valid_o,
    output logic [63:0] result_o
);
    hdec_top #(
        .ECC_STATUS_CYCLE_COUNT(1'b0),
        .ECC_DEBUG_FIELD_OPS(1'b0),
        .VV31_SCHED_ENABLE(1'b0),
        .VV33_FINE_INTERLEAVE(1'b0),
        .VV33_PAIRED_HMATCH(1'b0),
        .ENABLE_HDC_OPS(1'b1),
        .ENABLE_ECC_OPS(1'b0)
    ) u_core (
        .clk_i,
        .rst_ni,
        .valid_i,
        .ready_o,
        .operator_i,
        .operand_a_i,
        .operand_b_i,
        .valid_o,
        .result_o
    );
endmodule

module vv35_ecc_ip_top import hdec_pkg::*; (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        valid_i,
    output logic        ready_o,
    input  hdec_op_t    operator_i,
    input  logic [63:0] operand_a_i,
    input  logic [63:0] operand_b_i,
    output logic        valid_o,
    output logic [63:0] result_o
);
    hdec_top #(
        .ECC_STATUS_CYCLE_COUNT(1'b0),
        .ECC_DEBUG_FIELD_OPS(1'b0),
        .ECC_PMUL_RESIDUE_SEEDING(1'b1),
        .ECC_PMUL_AFFINE_FACTORING(1'b1),
        .ECC_INV_SQUARE_REDIRECT(1'b1),
        .ECC_PMUL_DBL_FROBENIUS(1'b1),
        .ECC_PMUL_ADD_Z_FORWARD(1'b1),
        .VV31_SCHED_ENABLE(1'b1),
        .VV33_FINE_INTERLEAVE(1'b0),
        .VV33_PAIRED_HMATCH(1'b0),
        .ENABLE_HDC_OPS(1'b0),
        .ENABLE_ECC_OPS(1'b1)
    ) u_core (
        .clk_i,
        .rst_ni,
        .valid_i,
        .ready_o,
        .operator_i,
        .operand_a_i,
        .operand_b_i,
        .valid_o,
        .result_o
    );
endmodule
