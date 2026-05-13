// hdec_cvxif_wrapper.sv — Phase1 baseline: vaddr+vwr64+vrd64, funct7+funct3 decode
module hdec_cvxif_wrapper import hdec_pkg::*; #(
    parameter int unsigned NrRgprPorts=2, parameter int unsigned XLEN=32,
    parameter type readregflags_t=logic, parameter type writeregflags_t=logic,
    parameter type id_t=logic, parameter type hartid_t=logic,
    parameter type x_compressed_req_t=logic, parameter type x_compressed_resp_t=logic,
    parameter type x_issue_req_t=logic, parameter type x_issue_resp_t=logic,
    parameter type x_register_t=logic, parameter type x_commit_t=logic,
    parameter type x_result_t=logic, parameter type cvxif_req_t=logic, parameter type cvxif_resp_t=logic,
    localparam type registers_t=logic[NrRgprPorts-1:0][XLEN-1:0]
) ( input logic clk_i, rst_ni, input cvxif_req_t cvxif_req_i, output cvxif_resp_t cvxif_resp_o );
    logic [31:0] instr; hdec_op_t hdec_opcode; logic matched;
    assign instr=cvxif_req_i.issue_req.instr;
    always_comb begin
        hdec_opcode=HDEC_VWR64;
        if      (instr[31:25]==7'b0000010 && instr[14:12]==3'b000) hdec_opcode=HDEC_VWR64;
        else if (instr[31:25]==7'b0000010 && instr[14:12]==3'b001) hdec_opcode=HDEC_VRD64;
        else if (instr[31:25]==7'b0000010 && instr[14:12]==3'b010) hdec_opcode=HDEC_HCLR;
        else if (instr[31:25]==7'b0000010 && instr[14:12]==3'b011) hdec_opcode=HDEC_BCLR;
        else if (instr[31:25]==7'b0000010 && instr[14:12]==3'b100) hdec_opcode=HDEC_BADD;
        else if (instr[31:25]==7'b0000010 && instr[14:12]==3'b101) hdec_opcode=HDEC_HBIND;
        else if (instr[31:25]==7'b0000010 && instr[14:12]==3'b110) hdec_opcode=HDEC_HPERM;
        else if (instr[31:25]==7'b0000010 && instr[14:12]==3'b111) hdec_opcode=HDEC_HSIM;
        else if (instr[31:25]==7'b0000011 && instr[14:12]==3'b000) hdec_opcode=HDEC_CLIP;
        else if (instr[31:25]==7'b0000011 && instr[14:12]==3'b001) hdec_opcode=HDEC_HSEARCH;
        else if (instr[31:25]==7'b0000011 && instr[14:12]==3'b010) hdec_opcode=HDEC_VADDR;
    end
    assign matched=(instr[6:0]==7'b0001011)&&((instr[31:25]==7'b0000010)||(instr[31:25]==7'b0000011));
    logic busy; assign cvxif_resp_o.issue_ready=matched&&!busy; assign cvxif_resp_o.register_ready=1'b1;
    assign cvxif_resp_o.compressed_ready=1'b1; assign cvxif_resp_o.issue_resp.accept=matched;
    assign cvxif_resp_o.issue_resp.writeback=1'b1; assign cvxif_resp_o.issue_resp.register_read=2'b01;
    assign cvxif_resp_o.compressed_resp.accept=1'b0;
    logic cmd_valid_q,cmd_valid_n; hdec_op_t cmd_op_q,cmd_op_n; logic [63:0] cmd_rs1_q,cmd_rs1_n,cmd_rs2_q,cmd_rs2_n;
    logic [4:0] cmd_rd_q,cmd_rd_n; logic [XLEN-1:0] cmd_id_q,cmd_id_n;
    logic issue_accepted; assign issue_accepted=cvxif_req_i.issue_valid&&matched;
    always_comb begin
        cmd_valid_n=cmd_valid_q; cmd_op_n=cmd_op_q; cmd_rs1_n=cmd_rs1_q; cmd_rs2_n=cmd_rs2_q; cmd_rd_n=cmd_rd_q; cmd_id_n=cmd_id_q;
        if(issue_accepted&&cvxif_req_i.register_valid&&!cmd_valid_q)begin cmd_valid_n=1'b1; cmd_op_n=hdec_opcode; cmd_rs1_n=cvxif_req_i.register.rs[0]; cmd_rs2_n=cvxif_req_i.register.rs[1]; cmd_rd_n=instr[11:7]; cmd_id_n=cvxif_req_i.issue_req.id; end
        if(cmd_valid_q&&top_ready)cmd_valid_n=1'b0;
    end
    assign busy=cmd_valid_q||cvxif_resp_o.result_valid;
    logic top_valid,top_ready,top_result_valid; logic [63:0] top_result; assign top_valid=cmd_valid_q;
    hdec_top i_hdec_top(.clk_i,.rst_ni,.valid_i(top_valid),.ready_o(top_ready),.operator_i(cmd_op_q),.operand_a_i(cmd_rs1_q),.operand_b_i(cmd_rs2_q),.valid_o(top_result_valid),.result_o(top_result));
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni)begin cvxif_resp_o.result_valid<=1'b0; cvxif_resp_o.result.data<='0; cvxif_resp_o.result.rd<='0; cvxif_resp_o.result.we<=1'b0; cvxif_resp_o.result.id<='0;
            cmd_valid_q<=1'b0; cmd_op_q<=HDEC_VWR64; cmd_rs1_q<='0; cmd_rs2_q<='0; cmd_rd_q<='0; cmd_id_q<='0; end
        else begin cmd_valid_q<=cmd_valid_n; cmd_op_q<=cmd_op_n; cmd_rs1_q<=cmd_rs1_n; cmd_rs2_q<=cmd_rs2_n; cmd_rd_q<=cmd_rd_n; cmd_id_q<=cmd_id_n;
            if(top_result_valid)begin cvxif_resp_o.result_valid<=1'b1; cvxif_resp_o.result.data<=top_result; cvxif_resp_o.result.rd<=cmd_rd_q; cvxif_resp_o.result.we<=1'b1; cvxif_resp_o.result.id<=cmd_id_q; end
            else if(!cvxif_req_i.issue_valid)cvxif_resp_o.result_valid<=1'b0;
        end
    end
endmodule
