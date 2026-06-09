// hdec_cvxif_wrapper.sv — Phase1: single-outstanding-transaction FSM
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

    // ── FSM State ─────────────────────────────────────────────────────────
    typedef enum logic [2:0] { W_IDLE, W_WAIT_REG, W_SEND_TOP, W_WAIT_TOP, W_RESULT } wstate_t;
    wstate_t wstate_q, wstate_n;

    // ── Instruction Decode ─────────────────────────────────────────────────
    logic [31:0] instr; assign instr = cvxif_req_i.issue_req.instr;
    logic        matched;
    hdec_op_t    decoded_op;

    always_comb begin
        decoded_op = HDEC_VWR64;
        if      (instr[31:25]==7'b0000010 && instr[14:12]==3'b000) decoded_op = HDEC_VWR64;
        else if (instr[31:25]==7'b0000010 && instr[14:12]==3'b001) decoded_op = HDEC_VRD64;
        else if (instr[31:25]==7'b0000010 && instr[14:12]==3'b010) decoded_op = HDEC_HCLR;
        else if (instr[31:25]==7'b0000010 && instr[14:12]==3'b011) decoded_op = HDEC_HCNTCLR;
        else if (instr[31:25]==7'b0000010 && instr[14:12]==3'b100) decoded_op = HDEC_HCNTADD;
        else if (instr[31:25]==7'b0000010 && instr[14:12]==3'b101) decoded_op = HDEC_HBIND;
        else if (instr[31:25]==7'b0000010 && instr[14:12]==3'b110) decoded_op = HDEC_HPERM;
        else if (instr[31:25]==7'b0000010 && instr[14:12]==3'b111) decoded_op = HDEC_HSIM;
        else if (instr[31:25]==7'b0000011 && instr[14:12]==3'b000) decoded_op = HDEC_HCNTCLIP;
        else if (instr[31:25]==7'b0000011 && instr[14:12]==3'b001) decoded_op = HDEC_HMATCH;
        else if (instr[31:25]==7'b0000011 && instr[14:12]==3'b010) decoded_op = HDEC_VADDR;
    end
    assign matched = (instr[6:0]==OPCODE_HDEC)
                  && ((instr[31:25]==F7_PHASE1_BASE)
                   || ((instr[31:25]==F7_PHASE1_EXT) && (instr[14:12] <= F3_VADDR)));

    // ── Rule 1: issue_ready does NOT gate on matched — unmatched instrs get clean reject via accept=0 ──
    assign cvxif_resp_o.issue_ready = (wstate_q == W_IDLE);

    // ── Rule 3: accept = matched && issue_ready ────────────────────────────
    assign cvxif_resp_o.issue_resp.accept    = matched && cvxif_resp_o.issue_ready;
    assign cvxif_resp_o.issue_resp.writeback = 1'b1;
    assign cvxif_resp_o.issue_resp.register_read = 2'b01;
    assign cvxif_resp_o.register_ready  = 1'b1;
    assign cvxif_resp_o.compressed_ready = 1'b1;
    assign cvxif_resp_o.compressed_resp.accept = 1'b0;

    // ── Rule 2: issue_fire = issue_valid && issue_ready && matched ────────
    logic issue_fire;
    assign issue_fire = cvxif_req_i.issue_valid && cvxif_resp_o.issue_ready && matched;

    logic register_operands_valid;
    assign register_operands_valid =
        cvxif_req_i.register_valid &&
        (!cvxif_resp_o.issue_resp.register_read[0] || cvxif_req_i.register.rs_valid[0]) &&
        (!cvxif_resp_o.issue_resp.register_read[1] || cvxif_req_i.register.rs_valid[1]);

    // ── Latched payload registers (Rule 9: all top_* come from registers) ─
    hdec_op_t      top_op_q,   top_op_n;
    logic [63:0]   top_rs1_q,  top_rs1_n;
    logic [4:0]    top_rd_q,   top_rd_n;
    logic [XLEN-1:0] top_id_q, top_id_n;

    logic [63:0]   result_data_q, result_data_n;
    logic [4:0]    result_rd_q,   result_rd_n;
    logic [XLEN-1:0] result_id_q, result_id_n;
    logic          result_we_q,   result_we_n;

`ifdef HDEC_SIM_PERF
    logic        perf_active_q;
    logic [31:0] perf_cycles_q;
    hdec_op_t    perf_op_q;
    logic [31:0] evid_cycle_q;
    logic [9:0]  evid_count_q;
    wstate_t     evid_prev_wstate_q;

    function automatic string perf_op_name(input hdec_op_t op);
        case (op)
            HDEC_VWR64:    perf_op_name = "VWR64";
            HDEC_VRD64:    perf_op_name = "VRD64";
            HDEC_HCLR:     perf_op_name = "HCLR";
            HDEC_HCNTCLR:  perf_op_name = "HCNTCLR";
            HDEC_HCNTADD:  perf_op_name = "HCNTADD";
            HDEC_HBIND:    perf_op_name = "HBIND";
            HDEC_HPERM:    perf_op_name = "HPERM";
            HDEC_HSIM:     perf_op_name = "HSIM";
            HDEC_HCNTCLIP: perf_op_name = "HCNTCLIP";
            HDEC_HMATCH:   perf_op_name = "HMATCH";
            HDEC_VADDR:    perf_op_name = "VADDR";
            default:       perf_op_name = "UNKNOWN";
        endcase
    endfunction

    initial begin
        $display("[HDEC_INIT] wrapper perf tracing enabled at time 0");
    end

    function automatic void print_evid(input string event_name);
        if (evid_count_q < 10'd1023) begin
            $display("[HDEC_EVID] cycle=%0d event=%s instr=0x%08h opcode=0x%02h rd=%0d funct3=0x%0h rs1=%0d rs2=%0d funct7=0x%02h wstate=%0d wstate_n=%0d matched=%0b issue_valid=%0b issue_ready=%0b issue_fire=%0b issue_accept=%0b issue_wb=0x%0h issue_reg_read=0x%0h register_valid=%0b register_ready=%0b register_rs_valid=0x%0h register_rs0=0x%016h register_rs1=0x%016h top_valid=%0b top_ready=%0b top_done=%0b result_valid=%0b result_ready=%0b result_we=0x%0h result_rd=%0d",
                     evid_cycle_q, event_name,
                     instr, instr[6:0], instr[11:7], instr[14:12],
                     instr[19:15], instr[24:20], instr[31:25],
                     wstate_q, wstate_n, matched,
                     cvxif_req_i.issue_valid, cvxif_resp_o.issue_ready, issue_fire,
                     cvxif_resp_o.issue_resp.accept,
                     cvxif_resp_o.issue_resp.writeback,
                     cvxif_resp_o.issue_resp.register_read,
                     cvxif_req_i.register_valid, cvxif_resp_o.register_ready,
                     cvxif_req_i.register.rs_valid,
                     cvxif_req_i.register.rs[0], cvxif_req_i.register.rs[1],
                     top_valid, top_ready, top_result_valid,
                     cvxif_resp_o.result_valid, cvxif_req_i.result_ready,
                     cvxif_resp_o.result.we, cvxif_resp_o.result.rd);
        end
    endfunction
`endif

    // ── hdec_top interface ─────────────────────────────────────────────────
    logic          top_valid, top_ready, top_result_valid;
    logic [63:0]   top_result;

    // Rule 9: top_valid from state register, not CV-X-IF combinational
    assign top_valid = (wstate_q == W_SEND_TOP);

    hdec_top i_hdec_top (
        .clk_i, .rst_ni,
        .valid_i    (top_valid),
        .ready_o    (top_ready),
        .operator_i (top_op_q),
        .operand_a_i(top_rs1_q),
        .operand_b_i('0),
        .valid_o    (top_result_valid),
        .result_o   (top_result)
    );

    // ── CV-X-IF result outputs (from latched registers) ────────────────────
    assign cvxif_resp_o.result_valid = (wstate_q == W_RESULT);
    assign cvxif_resp_o.result.data  = result_data_q;
    assign cvxif_resp_o.result.rd    = result_rd_q;
    assign cvxif_resp_o.result.we    = result_we_q;
    assign cvxif_resp_o.result.id    = result_id_q;

    // ── always_comb: FSM transitions + register next values ────────────────
    always_comb begin
        wstate_n      = wstate_q;
        top_op_n      = top_op_q;
        top_rs1_n     = top_rs1_q;
        top_rd_n      = top_rd_q;
        top_id_n      = top_id_q;
        result_data_n = result_data_q;
        result_rd_n   = result_rd_q;
        result_id_n   = result_id_q;
        result_we_n   = result_we_q;

        unique case (wstate_q)
            W_IDLE: begin
                // Rule 4: only issue_fire latches instr/rd/id/opcode
                if (issue_fire) begin
                    top_op_n  = decoded_op;
                    top_rd_n  = instr[11:7];
                    top_id_n  = cvxif_req_i.issue_req.id;
                    if (register_operands_valid) begin
                        top_rs1_n = cvxif_resp_o.issue_resp.register_read[0] ? cvxif_req_i.register.rs[0] : '0;
                        wstate_n  = W_SEND_TOP;
                    end else begin
                        wstate_n  = W_WAIT_REG;
                    end
                end
            end

            W_WAIT_REG: begin
                // Rule 5: wait for register_valid, then latch rs1
                if (register_operands_valid) begin
                    top_rs1_n = cvxif_resp_o.issue_resp.register_read[0] ? cvxif_req_i.register.rs[0] : '0;
                    wstate_n  = W_SEND_TOP;
                end
            end

            W_SEND_TOP: begin
                // Rule 6: hold top_valid until top_ready
                if (top_ready)
                    wstate_n = W_WAIT_TOP;
            end

            W_WAIT_TOP: begin
                // Rule 7: wait for top_result_valid
                if (top_result_valid) begin
                    result_data_n = top_result;
                    result_rd_n   = top_rd_q;
                    result_id_n   = top_id_q;
                    result_we_n   = 1'b1;
                    wstate_n      = W_RESULT;
                end
            end

            W_RESULT: begin
                // Rule 8: CVA6 has no result_ready.  Waiting for !issue_valid
                // deadlocks when the CPU pipelines the next issue while result
                // is still pending.  Instead assert result_valid for one cycle
                // then return to W_IDLE unconditionally.
                wstate_n = W_IDLE;
            end

            default: wstate_n = W_IDLE;
        endcase
    end

    // ── always_ff: state + payload registers ───────────────────────────────
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            wstate_q      <= W_IDLE;
            top_op_q      <= HDEC_VWR64;
            top_rs1_q     <= '0;
            top_rd_q      <= '0;
            top_id_q      <= '0;
            result_data_q <= '0;
            result_rd_q   <= '0;
            result_id_q   <= '0;
            result_we_q   <= 1'b0;
`ifdef HDEC_SIM_PERF
            perf_active_q <= 1'b0;
            perf_cycles_q <= '0;
            perf_op_q     <= HDEC_VWR64;
            evid_cycle_q  <= '0;
            evid_count_q  <= '0;
            evid_prev_wstate_q <= W_IDLE;
`endif
        end else begin
            wstate_q      <= wstate_n;
            top_op_q      <= top_op_n;
            top_rs1_q     <= top_rs1_n;
            top_rd_q      <= top_rd_n;
            top_id_q      <= top_id_n;
            result_data_q <= result_data_n;
            result_rd_q   <= result_rd_n;
            result_id_q   <= result_id_n;
            result_we_q   <= result_we_n;
`ifdef HDEC_SIM_PERF
            evid_cycle_q <= evid_cycle_q + 32'd1;
            evid_prev_wstate_q <= wstate_q;

            if ((evid_count_q < 10'd1023) && (wstate_q != evid_prev_wstate_q)) begin
                print_evid("STATE_CHANGE");
                evid_count_q <= evid_count_q + 8'd1;
            end
            if ((evid_count_q < 10'd1023) && cvxif_req_i.issue_valid && cvxif_resp_o.issue_ready) begin
                print_evid("ISSUE_READY_VALID");
                evid_count_q <= evid_count_q + 8'd1;
            end
            if ((evid_count_q < 10'd1023) && cvxif_req_i.issue_valid && matched) begin
                print_evid("ISSUE_MATCHED");
                evid_count_q <= evid_count_q + 8'd1;
            end
            if ((evid_count_q < 10'd1023) && issue_fire) begin
                print_evid("ISSUE_FIRE");
                evid_count_q <= evid_count_q + 8'd1;
            end
            if ((evid_count_q < 10'd1023) && (wstate_q == W_WAIT_REG)) begin
                print_evid("WAIT_REG");
                evid_count_q <= evid_count_q + 8'd1;
            end
            if ((evid_count_q < 10'd1023) && cvxif_req_i.register_valid) begin
                print_evid("REGISTER_VALID");
                evid_count_q <= evid_count_q + 8'd1;
            end
            if ((evid_count_q < 10'd1023) && cvxif_req_i.register_valid && cvxif_resp_o.register_ready) begin
                print_evid("REGISTER_READY_VALID");
                evid_count_q <= evid_count_q + 8'd1;
            end
            if ((evid_count_q < 10'd1023) && top_valid && top_ready) begin
                print_evid("TOP_START");
                evid_count_q <= evid_count_q + 8'd1;
            end
            if ((evid_count_q < 10'd1023) && top_result_valid) begin
                print_evid("TOP_DONE");
                evid_count_q <= evid_count_q + 8'd1;
            end
            if ((evid_count_q < 10'd1023) && cvxif_resp_o.result_valid) begin
                print_evid("RESULT_VALID");
                evid_count_q <= evid_count_q + 8'd1;
            end

            if (issue_fire) begin
                perf_active_q <= 1'b1;
                perf_cycles_q <= '0;
                perf_op_q     <= decoded_op;
            end else if (perf_active_q) begin
                perf_cycles_q <= perf_cycles_q + 32'd1;
            end

            if (perf_active_q && (wstate_q != W_RESULT) && (wstate_n == W_RESULT)) begin
                $display("[HDEC_PERF] op=%s cycles=%0d",
                         perf_op_name(perf_op_q), perf_cycles_q + 32'd1);
                perf_active_q <= 1'b0;
                perf_cycles_q <= '0;
            end
`endif
        end
    end

endmodule
