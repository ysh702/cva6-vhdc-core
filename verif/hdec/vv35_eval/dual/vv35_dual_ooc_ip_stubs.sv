// Black-box declarations used only while linking the independent accelerator top.

(* black_box *)
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
endmodule

(* black_box *)
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
endmodule
