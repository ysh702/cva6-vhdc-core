module tb_hdec_cvxif_smoke_vv24;
    import hdec_pkg::*;

    typedef struct packed {
        logic [31:0] instr;
        logic [31:0] id;
    } issue_req_t;

    typedef struct packed {
        logic [1:0][63:0] rs;
        logic [1:0]       rs_valid;
    } register_req_t;

    typedef struct packed {
        logic          issue_valid;
        issue_req_t    issue_req;
        logic          register_valid;
        register_req_t register;
        logic          result_ready;
    } cvxif_req_t;

    typedef struct packed {
        logic       accept;
        logic       writeback;
        logic [1:0] register_read;
    } issue_resp_t;

    typedef struct packed {
        logic accept;
    } compressed_resp_t;

    typedef struct packed {
        logic [63:0] data;
        logic [31:0] id;
        logic [4:0]  rd;
        logic        we;
    } result_resp_t;

    typedef struct packed {
        logic             issue_ready;
        issue_resp_t      issue_resp;
        logic             register_ready;
        logic             compressed_ready;
        compressed_resp_t compressed_resp;
        logic             result_valid;
        result_resp_t     result;
    } cvxif_resp_t;

    logic clk_i;
    logic rst_ni;
    cvxif_req_t req;
    cvxif_resp_t resp;

    hdec_cvxif_wrapper #(
        .NrRgprPorts (2),
        .XLEN        (32),
        .cvxif_req_t (cvxif_req_t),
        .cvxif_resp_t(cvxif_resp_t)
    ) dut (
        .clk_i,
        .rst_ni,
        .cvxif_req_i(req),
        .cvxif_resp_o(resp)
    );

    initial clk_i = 1'b0;
    always #2.5 clk_i = ~clk_i;

    function automatic logic [31:0] encode_hdec(
        input logic [6:0] funct7,
        input logic [2:0] funct3,
        input logic [4:0] rd
    );
        encode_hdec = {funct7, 5'd0, 5'd1, funct3, rd, OPCODE_HDEC};
    endfunction

    initial begin
        req = '0;
        rst_ni = 1'b0;
        repeat (4) @(posedge clk_i);
        rst_ni = 1'b1;
        @(negedge clk_i);

        // An unmatched opcode must be rejected without consuming the slot.
        req.issue_valid = 1'b1;
        req.issue_req.instr = 32'h0000_0013;
        #1;
        if (!resp.issue_ready || resp.issue_resp.accept)
            $fatal(1, "CVXIF unmatched instruction was not cleanly rejected");
        @(posedge clk_i);
        @(negedge clk_i);
        req.issue_valid = 1'b0;

        // HCLR exercises issue, register handoff, hdec_top/VRF and result return.
        req.issue_req.instr = encode_hdec(F7_PHASE1_BASE, 3'b010, 5'd7);
        req.issue_req.id = 32'h24A0_0001;
        req.register_valid = 1'b1;
        req.register.rs_valid = 2'b01;
        req.register.rs[0] = '0;
        req.result_ready = 1'b1;
        req.issue_valid = 1'b1;
        #1;
        if (!resp.issue_ready || !resp.issue_resp.accept)
            $fatal(1, "CVXIF HCLR issue was not accepted");
        if (resp.issue_resp.register_read !== 2'b01)
            $fatal(1, "CVXIF register-read contract changed");
        @(posedge clk_i);
        @(negedge clk_i);
        req.issue_valid = 1'b0;
        req.register_valid = 1'b0;

        for (int cycle = 0; cycle < 2000; cycle++) begin
            @(posedge clk_i);
            #1;
            if (resp.result_valid) begin
                if (!resp.result.we || resp.result.rd !== 5'd7
                    || resp.result.id !== 32'h24A0_0001
                    || resp.result.data[1:0] !== STATUS_OK)
                    $fatal(1, "CVXIF result payload mismatch data=%h rd=%0d id=%h we=%0b",
                           resp.result.data, resp.result.rd, resp.result.id, resp.result.we);
                $display("[HDEC_CVXIF_SMOKE_VV24] PASS");
                $finish;
            end
        end
        $fatal(1, "CVXIF result timeout");
    end
endmodule
