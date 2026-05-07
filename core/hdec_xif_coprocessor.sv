// =============================================================================
// hdec_xif_coprocessor.sv — HDEC Co-Processor with CV-X-IF interface
// =============================================================================
// CV-X-IF Protocol:
//   Phase 1 (Issue):   CPU sends instruction + id → we decode, save id/hartid/rd
//   Phase 2 (Register): CPU sends rs1/rs2 values → we start hdec_top
//   Phase 3 (Result):   CPU accepts result with saved id → scoreboard unblocks
//
// Key insight: issue_ready_o is gated on register values being available AND
// hdec_top being ready. This merges the Issue+Register handshake into one
// "ready" signal, matching CV-X-IF's split-transaction protocol.
// =============================================================================

module hdec_xif_coprocessor
    import hdec_xif_pkg::*;
#(
    parameter int unsigned NrRgprPorts    = 2,
    parameter int unsigned XLEN           = 64,
    parameter type readregflags_t         = logic,
    parameter type writeregflags_t        = logic,
    parameter type id_t                   = logic,
    parameter type hartid_t               = logic,
    parameter type x_compressed_req_t     = logic,
    parameter type x_compressed_resp_t    = logic,
    parameter type x_issue_req_t          = logic,
    parameter type x_issue_resp_t         = logic,
    parameter type x_register_t           = logic,
    parameter type x_commit_t             = logic,
    parameter type x_result_t             = logic,
    parameter type cvxif_req_t            = logic,
    parameter type cvxif_resp_t           = logic,
    localparam type registers_t           = logic [NrRgprPorts-1:0][XLEN-1:0]
) (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  cvxif_req_t  cvxif_req_i,
    output cvxif_resp_t cvxif_resp_o
);

    // =========================================================================
    // CV-X-IF Channel Signal Aliases
    // =========================================================================
    // --- Issue Channel ---
    logic           issue_valid;
    x_issue_req_t   issue_req;
    logic           issue_ready;
    x_issue_resp_t  issue_resp;

    // --- Register Channel ---
    logic           register_valid;
    x_register_t    register_req;

    // --- Compressed Channel (unused, always ready) ---
    logic               compressed_valid;
    x_compressed_req_t  compressed_req;
    logic               compressed_ready;
    x_compressed_resp_t compressed_resp;

    // --- Result Channel ---
    logic       result_valid;
    x_result_t  result;

    assign issue_req        = cvxif_req_i.issue_req;
    assign issue_valid      = cvxif_req_i.issue_valid;
    assign register_req     = cvxif_req_i.register;
    assign register_valid   = cvxif_req_i.register_valid;
    assign compressed_req   = cvxif_req_i.compressed_req;
    assign compressed_valid = cvxif_req_i.compressed_valid;

    assign cvxif_resp_o.issue_ready      = issue_ready;
    assign cvxif_resp_o.issue_resp       = issue_resp;
    assign cvxif_resp_o.register_ready   = issue_ready;  // tied: we accept registers when issue completes
    assign cvxif_resp_o.compressed_ready = compressed_ready;
    assign cvxif_resp_o.compressed_resp  = compressed_resp;
    assign cvxif_resp_o.result_valid     = result_valid;
    assign cvxif_resp_o.result           = result;

    // =========================================================================
    // Instruction Table (from package)
    // =========================================================================
    hdec_instr_entry_t [HDEC_NB_INSTR-1:0] instr_table;
    assign instr_table = get_hdec_instr_table();

    // =========================================================================
    // Instruction Decoder — Issue Phase
    // =========================================================================
    logic [HDEC_NB_INSTR-1:0] sel;          // one-hot match
    logic                     hdec_matched;  // instruction is ours
    hdec_issue_resp_t         hdec_resp;
    hdec_op                   decoded_op;
    logic [4:0]               decoded_rd;

    // Register read readiness
    logic rs1_ready, rs2_ready;
    logic hdec_core_ready;

    for (genvar i = 0; i < HDEC_NB_INSTR; i++) begin : gen_match
        assign sel[i] = ((instr_table[i].mask & issue_req.instr) == instr_table[i].instr);
    end

    assign hdec_matched = issue_valid & (|sel);

    always_comb begin
        hdec_resp   = '{accept: 1'b0, writeback: 1'b0, register_read: 2'b00};
        decoded_op  = HDEC_BIND;
        decoded_rd  = issue_req.instr[11:7];
        for (int unsigned i = 0; i < HDEC_NB_INSTR; i++) begin
            if (sel[i]) begin
                hdec_resp  = instr_table[i].resp;
                decoded_op = instr_table[i].opcode;
            end
        end
    end

    // Gate on register data availability
    assign rs1_ready = (~hdec_resp.register_read[0] || register_req.rs_valid[0]);
    assign rs2_ready = (~hdec_resp.register_read[1] || register_req.rs_valid[1]);

    // =========================================================================
    // Transaction State — lock id/hartid/rd/op during Issue→Result lifecycle
    // =========================================================================
    id_t       saved_id, saved_id_n;
    hartid_t   saved_hartid, saved_hartid_n;
    logic [4:0] saved_rd, saved_rd_n;
    hdec_op    saved_op, saved_op_n;
    logic      transaction_active, transaction_active_n;

    // =========================================================================
    // hdec_top instantiation
    // =========================================================================
    logic        hdec_start;
    logic        hdec_ecc_valid;
    logic        hdec_ready;
    logic        hdec_valid_out;
    logic [63:0] hdec_result;
    hdec_op      hdec_operator;

    assign hdec_operator    = (hdec_matched && issue_ready) ? decoded_op : saved_op;
    assign hdec_core_ready  = hdec_ready;
    assign hdec_ecc_valid   = (hdec_operator == HDEC_ECC_START);
    // -------------------------------------------------------------------------
    // CV-X-IF: issue_valid is a LEVEL signal that stays high until the core
    // advances. hdec_top expects a single-cycle PULSE on valid_i to start
    // its state machine. We edge-detect the issue acceptance to generate a
    // one-shot pulse, preventing re-triggering of the same instruction.
    // -------------------------------------------------------------------------
    logic issue_accepted, issue_accepted_q;
    assign issue_accepted = issue_ready & issue_valid;
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) issue_accepted_q <= 1'b0;
        else issue_accepted_q <= issue_accepted;
    end
    assign hdec_start = issue_accepted && !issue_accepted_q;

    hdec_top i_hdec (
        .clk_i       (clk_i),
        .rst_ni      (rst_ni),
        .valid_i     (hdec_start),
        .ecc_valid_i (hdec_ecc_valid),
        .operator_i  (hdec_operator),
        .operand_a_i (register_req.rs[0]),
        .operand_b_i (register_req.rs[1]),
        .ready_o     (hdec_ready),
        .valid_o     (hdec_valid_out),
        .result_o    (hdec_result)
    );

    // =========================================================================
    // Issue Ready — gated on register data + hdec ready
    // =========================================================================
    assign issue_ready = hdec_matched
                       & hdec_resp.accept
                       & rs1_ready
                       & rs2_ready
                       & hdec_core_ready;

    assign issue_resp.accept        = hdec_matched & hdec_core_ready;
    assign issue_resp.writeback     = hdec_resp.writeback;
    assign issue_resp.register_read = hdec_resp.register_read;

    // =========================================================================
    // Compressed Channel — always reject (no compressed HDEC)
    // =========================================================================
    assign compressed_ready  = 1'b1;
    assign compressed_resp   = '{instr: 32'b0, accept: 1'b0};

    // =========================================================================
    // Transaction Lifecycle — save id/hartid/rd/op on start, clear on finish
    // =========================================================================
    always_comb begin
        saved_id_n        = saved_id;
        saved_hartid_n    = saved_hartid;
        saved_rd_n        = saved_rd;
        saved_op_n        = saved_op;
        transaction_active_n = transaction_active;

        if (hdec_start) begin
            saved_id_n          = issue_req.id;
            saved_hartid_n      = issue_req.hartid;
            saved_rd_n          = decoded_rd;
            saved_op_n          = decoded_op;
            transaction_active_n = 1'b1;
        end

        if (hdec_valid_out) begin
            transaction_active_n = 1'b0;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            saved_id            <= '0;
            saved_hartid        <= '0;
            saved_rd            <= '0;
            saved_op            <= HDEC_BIND;
            transaction_active  <= 1'b0;
        end else begin
            saved_id            <= saved_id_n;
            saved_hartid        <= saved_hartid_n;
            saved_rd            <= saved_rd_n;
            saved_op            <= saved_op_n;
            transaction_active  <= transaction_active_n;
        end
    end

    // =========================================================================
    // Result Channel — level-signal matching CV-X-IF example pattern
    // =========================================================================
    // result_valid is a LEVEL (not a pulse). It stays high after hdec_top
    // finishes until the core moves on (issue_valid drops) or a new
    // instruction starts (hdec_start pulses). This prevents the writeback
    // stage from missing a 1-cycle result pulse if it's busy.
    // =========================================================================
    logic        result_valid_d, result_valid_q;
    logic [63:0] result_data_d, result_data_q;

    always_comb begin
        result_valid_d = result_valid_q;
        result_data_d  = result_data_q;
        if (!issue_valid || hdec_start) result_valid_d = 1'b0;
        if (hdec_valid_out && transaction_active) begin
            result_valid_d = 1'b1;
            result_data_d  = hdec_result;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            result_valid_q <= 1'b0;
            result_data_q  <= '0;
        end else begin
            result_valid_q <= result_valid_d;
            result_data_q  <= result_data_d;
        end
    end

    always_comb begin
        result.hartid = saved_hartid;
        result.id     = saved_id;
        result.data   = result_data_q;
        result.rd     = saved_rd;
        result.we     = writeregflags_t'(1'b1);
    end

    assign result_valid = result_valid_q;

endmodule
