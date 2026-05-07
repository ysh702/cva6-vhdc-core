// =========================================================================
// HDEC: HDC + ECC Co-Processor — adapted for CV-X-IF interface
// =========================================================================
// VRF: 16 registers x 16 chunks x 64-bit = 16 x 1024-bit = 2KB
// 4 BRAM banks (TDP, 2 ports each), interleaved across Lanes
// =========================================================================
// Changes from legacy version:
//   - Removed fifo_full_i (CV-X-IF has its own flow control)
//   - Removed trans_id_i/o (CV-X-IF wrapper handles transaction IDs)
//   - Uses hdec_xif_pkg instead of ariane_pkg
// =========================================================================

module hdec_top
    import hdec_xif_pkg::*;
(
    input  logic                    clk_i,
    input  logic                    rst_ni,
    input  logic                    valid_i,
    input  logic                    ecc_valid_i,
    input  hdec_op                  operator_i,
    input  logic [63:0]             operand_a_i,
    input  logic [63:0]             operand_b_i,
    output logic                    ready_o,
    output logic                    valid_o,
    output logic [63:0]             result_o
);

    // =========================================================================
    // BRAM VRF — 4 banks x 64 entries x 64-bit, True Dual Port
    // =========================================================================
    localparam int BRAM_DEPTH = 64;
    (* ram_style = "block" *) logic [63:0] vrf_b0 [0:BRAM_DEPTH-1];
    (* ram_style = "block" *) logic [63:0] vrf_b1 [0:BRAM_DEPTH-1];
    (* ram_style = "block" *) logic [63:0] vrf_b2 [0:BRAM_DEPTH-1];
    (* ram_style = "block" *) logic [63:0] vrf_b3 [0:BRAM_DEPTH-1];

    // TDP read addresses (Port A: main data, Port B: second operand / boundary)
    logic [5:0]  vrf_ra_addr [0:3];
    logic [5:0]  vrf_rb_addr [0:3];
    logic [63:0] vrf_ra_pipe [0:3];
    logic [63:0] vrf_rb_pipe [0:3];
    logic        vrf_read_launched;

    // Write forwarding
    logic        wr_pending;
    logic [1:0]  wr_bank;
    logic [5:0]  wr_addr;
    logic [63:0] wr_data;

    function automatic logic [5:0] vaddr(logic [3:0] r, logic [1:0] s);
        return {r, s};  // reg * 4 + send_cnt
    endfunction

    // BRAM synchronous reads (TDP, 2 ports per bank)
    always_ff @(posedge clk_i) begin
        if (rst_ni) begin
            for (int i = 0; i < 4; i++) begin
                automatic logic [5:0] aa = vrf_ra_addr[i];
                automatic logic [5:0] ba = vrf_rb_addr[i];
                if (wr_pending && wr_bank == i) begin
                    if (wr_addr == aa) vrf_ra_pipe[i] <= wr_data;
                    else case (i) 0: vrf_ra_pipe[i] <= vrf_b0[aa]; 1: vrf_ra_pipe[i] <= vrf_b1[aa];
                                   2: vrf_ra_pipe[i] <= vrf_b2[aa]; 3: vrf_ra_pipe[i] <= vrf_b3[aa]; endcase
                    if (wr_addr == ba) vrf_rb_pipe[i] <= wr_data;
                    else case (i) 0: vrf_rb_pipe[i] <= vrf_b0[ba]; 1: vrf_rb_pipe[i] <= vrf_b1[ba];
                                   2: vrf_rb_pipe[i] <= vrf_b2[ba]; 3: vrf_rb_pipe[i] <= vrf_b3[ba]; endcase
                end else begin
                    case (i)
                        0: begin vrf_ra_pipe[i] <= vrf_b0[aa]; vrf_rb_pipe[i] <= vrf_b0[ba]; end
                        1: begin vrf_ra_pipe[i] <= vrf_b1[aa]; vrf_rb_pipe[i] <= vrf_b1[ba]; end
                        2: begin vrf_ra_pipe[i] <= vrf_b2[aa]; vrf_rb_pipe[i] <= vrf_b2[ba]; end
                        3: begin vrf_ra_pipe[i] <= vrf_b3[aa]; vrf_rb_pipe[i] <= vrf_b3[ba]; end
                    endcase
                end
            end
        end else begin
            for (int i = 0; i < 4; i++) begin vrf_ra_pipe[i] <= 64'b0; vrf_rb_pipe[i] <= 64'b0; end
        end
    end

    // =========================================================================
    // VRF Initialization State Machine (BRAM power-on clear)
    // =========================================================================
    typedef enum logic [1:0] { INIT_CLEAR, INIT_DONE } init_state_e;
    init_state_e init_state_q, init_state_n;
    logic [7:0]  init_cnt_q, init_cnt_n;
    logic        vrf_ready;

    always_comb begin
        init_state_n = init_state_q; init_cnt_n = init_cnt_q;
        vrf_ready = (init_state_q == INIT_DONE);
        if (init_state_q == INIT_CLEAR) begin
            if (init_cnt_q == 8'd255) init_state_n = INIT_DONE;
            else init_cnt_n = init_cnt_q + 1;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin init_state_q <= INIT_CLEAR; init_cnt_q <= '0; end
        else begin
            init_state_q <= init_state_n; init_cnt_q <= init_cnt_n;
            if (init_state_q == INIT_CLEAR) begin
                case (init_cnt_q[7:6])
                    2'd0: vrf_b0[init_cnt_q[5:0]] <= 64'b0;
                    2'd1: vrf_b1[init_cnt_q[5:0]] <= 64'b0;
                    2'd2: vrf_b2[init_cnt_q[5:0]] <= 64'b0;
                    2'd3: vrf_b3[init_cnt_q[5:0]] <= 64'b0;
                endcase
            end
        end
    end

    // =========================================================================
    // ECC State Machine
    // =========================================================================
    typedef enum logic [2:0] { ECC_IDLE, ECC_ACTIVE, ECC_WAIT1, ECC_WAIT2, ECC_SHIFT, ECC_DONE } ecc_state_e;
    ecc_state_e ecc_state_q, ecc_state_n;
    logic [8:0]  ecc_loop_cnt_q, ecc_loop_cnt_n;
    logic [255:0] ecc_k_q, ecc_A_q, ecc_Acc_q;
    localparam logic [255:0] POLY_MASK = 256'h0000000000000000000000000000000000000000000000000000000000000425;

    // =========================================================================
    // Main State Machine
    // =========================================================================
    typedef enum logic [1:0] { ST_IDLE, ST_EXECUTE, ST_FINISH } state_e;
    state_e state_q, state_n;
    logic [3:0] saved_vd_q, saved_vd_n, saved_vs1_q, saved_vs1_n, saved_vs2_q, saved_vs2_n;
    hdec_op     saved_op_q, saved_op_n;
    logic [2:0] send_cnt_q, send_cnt_n, recv_cnt_q, recv_cnt_n;
    logic [11:0] total_popcnt_q, total_popcnt_n;

    hdec_op latched_operator;
    logic [6:0] latched_threshold;

    logic      hdc_active, lane_valid_in, lane_cnt_clear;
    logic [3:0] lanes_out_valid;
    logic [3:0][63:0] lanes_in_1, lanes_in_2, lanes_out_data, lanes_out_ecc;
    logic [3:0][6:0]  lanes_out_popcnt;

    assign hdc_active = (state_q == ST_EXECUTE);

    // Local interlock: track active instruction's VRF write target (RAW protection)
    logic       pipe_wr_pending;
    logic [3:0] pipe_vd_q;

    function automatic logic raw_hazard(logic [3:0] vs1, logic [3:0] vs2, logic [3:0] vd);
        return pipe_wr_pending && ((vs1 == pipe_vd_q) || (vs2 == pipe_vd_q) || (vd == pipe_vd_q));
    endfunction

    // Lane pipeline tags
    // OWNER_NONE/OWNER_HDC/OWNER_ECC imported from hdec_xif_pkg
    logic [1:0] lane_owner_in;
    logic [3:0][1:0] lane_o_owner;

    // Result register for 1-cycle instruction output register
    logic        result_valid_q, result_valid_n;
    logic [63:0] result_data_q, result_data_n;

    assign valid_o  = result_valid_q;
    assign result_o = result_data_q;

    // =========================================================================
    // ECC fetch tracking: ECC_FETCH blocks until ECC DONE
    // =========================================================================
    logic ecc_fetch_pending_q, ecc_fetch_pending_n;
    // =========================================================================
    // Latch operator / threshold on instruction arrival
    // =========================================================================
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            latched_operator  <= HDEC_BIND; latched_threshold <= 7'd0;
        end else if (state_q == ST_IDLE && valid_i) begin
            if (operator_i == HDEC_BINARIZE) begin
                latched_operator  <= HDEC_BUNDLE; latched_threshold <= operand_a_i[21:15];
            end else if (operator_i == HDEC_BUNDLE_ACCUM) begin
                latched_operator  <= HDEC_BUNDLE;
            end else latched_operator <= operator_i;
        end else if (ecc_state_q == ECC_ACTIVE && !hdc_active) latched_operator <= HDEC_BIND;
    end

    hdec_op current_lane_op;
    assign current_lane_op = (!hdc_active && ecc_state_q != ECC_IDLE) ? HDEC_BIND : latched_operator;

    generate
        for (genvar i = 0; i < 4; i++) begin : gl
            hdec_lane il (
                .clk(clk_i), .rst_n(rst_ni), .i_valid(lane_valid_in), .o_valid(lanes_out_valid[i]),
                .i_op_mode(current_lane_op),
                .i_ecc_mode(lane_owner_in == OWNER_ECC || (!hdc_active && ecc_state_q != ECC_IDLE)),
                .i_cnt_clear(lane_cnt_clear), .i_threshold(latched_threshold),
                .i_owner(lane_owner_in), .o_owner(lane_o_owner[i]),
                .i_rs1_data(lanes_in_1[i]), .i_rs2_data(lanes_in_2[i]),
                .o_lane_data(lanes_out_data[i]), .o_popcnt_val(lanes_out_popcnt[i]),
                .o_ecc_data(lanes_out_ecc[i])
            );
        end
    endgenerate

    // =========================================================================
    // Main Combinatorial Logic
    // =========================================================================
    always_comb begin
        state_n = state_q; send_cnt_n = send_cnt_q; recv_cnt_n = recv_cnt_q;
        total_popcnt_n = total_popcnt_q;
        saved_vd_n = saved_vd_q; saved_vs1_n = saved_vs1_q; saved_vs2_n = saved_vs2_q;
        saved_op_n = saved_op_q;
        ecc_state_n = ecc_state_q; ecc_loop_cnt_n = ecc_loop_cnt_q;
        lane_cnt_clear = 1'b0; lanes_in_1 = '0; lanes_in_2 = '0;
        result_valid_n = 1'b0; result_data_n = result_data_q;
        ecc_fetch_pending_n = ecc_fetch_pending_q;

        lane_valid_in = 1'b0; lane_owner_in = OWNER_NONE;

        // ── HDC send phase: S1 always granted (highest priority) ──
        if (state_q == ST_EXECUTE && vrf_read_launched) begin
            lane_valid_in = 1'b1; lane_owner_in = OWNER_HDC;
        end

        // ── ECC: seizes S1 whenever HDC doesn't need it (fine-grained interleave) ──
        if (!lane_valid_in && ecc_state_q == ECC_ACTIVE && ecc_k_q[0] == 1'b1) begin
            lane_valid_in = 1'b1; lane_owner_in = OWNER_ECC;
            // ECC data routing moved here from state machine
            lanes_in_1[0] = ecc_A_q[63:0];      lanes_in_2[0] = ecc_Acc_q[63:0];
            lanes_in_1[1] = ecc_A_q[127:64];    lanes_in_2[1] = ecc_Acc_q[127:64];
            lanes_in_1[2] = ecc_A_q[191:128];   lanes_in_2[2] = ecc_Acc_q[191:128];
            lanes_in_1[3] = ecc_A_q[255:192];   lanes_in_2[3] = ecc_Acc_q[255:192];
        end

        ready_o = 1'b0;

        case (state_q)
            ST_IDLE: begin
                ready_o = vrf_ready;
                // Gate ready when ECC fetch pending but ladder not done
                if (ecc_fetch_pending_q && ecc_state_q != ECC_DONE)
                    ready_o = 1'b0;

                // Handle pending ECC fetch that just completed
                if (ecc_fetch_pending_q && ecc_state_q == ECC_DONE) begin
                    result_valid_n = 1'b1; result_data_n = ecc_Acc_q[63:0];
                    ecc_fetch_pending_n = 1'b0;
                    ecc_state_n = ECC_IDLE;
                end

                if (valid_i && ready_o) begin
                    if (operator_i == HDEC_INGEST) begin
                        result_valid_n = 1'b1; result_data_n = 64'b0;
                    end else if (operator_i == HDEC_ECC_START) begin
                        // Fast path: complete in 1 cycle, ECC runs in background
                        result_valid_n = 1'b1; result_data_n = 64'b0;
                    end else if (operator_i == HDEC_CLEAR_CNT) begin
                        lane_cnt_clear = 1'b1;
                        result_valid_n = 1'b1; result_data_n = 64'b0;
                    end else if (operator_i == HDEC_ECC_FETCH) begin
                        if (ecc_state_q == ECC_DONE) begin
                            result_valid_n = 1'b1; result_data_n = ecc_Acc_q[63:0];
                            ecc_state_n = ECC_IDLE;
                        end else begin
                            ecc_fetch_pending_n = 1'b1;
                        end
                    end else begin
                        // Multi-cycle operations: stall if RAW hazard
                        if (raw_hazard(operand_a_i[8:5], operand_a_i[3:0], operand_a_i[13:10]))
                            ready_o = 1'b0;
                        saved_vd_n  = operand_a_i[13:10];
                        saved_vs1_n = operand_a_i[8:5];
                        saved_vs2_n = operand_a_i[3:0];
                        saved_op_n  = operator_i;
                        state_n = ST_EXECUTE; send_cnt_n = '0; recv_cnt_n = '0;
                        total_popcnt_n = '0;
                        if (operator_i == HDEC_BUNDLE) lane_cnt_clear = 1'b1;
                    end
                end

            end

            ST_EXECUTE: begin
                // Phase 2: BRAM data launched last cycle → route to lanes this cycle
                if (vrf_read_launched) begin
                    if (saved_op_q == HDEC_PERMUTE) begin
                        for (int i = 0; i < 3; i++)
                            lanes_in_1[i] = {vrf_ra_pipe[i][62:0], vrf_ra_pipe[i+1][63]};
                        lanes_in_1[3] = {vrf_ra_pipe[3][62:0], vrf_rb_pipe[0][63]};
                    end else begin
                        for (int i = 0; i < 4; i++) begin
                            lanes_in_1[i] = vrf_ra_pipe[i];
                            lanes_in_2[i] = (saved_op_q == HDEC_BUNDLE_ACCUM)
                                            ? 64'b0 : vrf_rb_pipe[i];
                        end
                    end
                    send_cnt_n = send_cnt_q + 1;
                end

                if (lanes_out_valid[0] && lane_o_owner[0] == OWNER_HDC) begin
                    recv_cnt_n = recv_cnt_q + 1;
                    if (saved_op_q == HDEC_MATCH)
                        total_popcnt_n = total_popcnt_q + lanes_out_popcnt[0] + lanes_out_popcnt[1]
                                       + lanes_out_popcnt[2] + lanes_out_popcnt[3];
                    if (recv_cnt_q == 3) state_n = ST_FINISH;
                end
            end

            ST_FINISH: begin
                // Write back valid_o and result
                if (saved_op_q == HDEC_ECC_FETCH && ecc_state_q != ECC_IDLE) begin
                    // Still computing, stay in FINISH
                end else begin
                    result_valid_n = 1'b1;
                    if (saved_op_q == HDEC_MATCH)
                        result_data_n = {52'b0, total_popcnt_q};
                    else if (saved_op_q == HDEC_ECC_FETCH)
                        result_data_n = ecc_Acc_q[63:0];
                    else
                        result_data_n = 64'b0;
                    state_n = ST_IDLE;
                end
            end
        endcase

        // ECC state machine — un-gated, runs freely.
        // ECC_ACTIVE injects data via the top-level lane arbitration (above).
        // The state machine only tracks: did we win S1? → WAIT1 → WAIT2 → SHIFT
        case (ecc_state_q)
            ECC_IDLE: if (valid_i && state_q == ST_IDLE && operator_i == HDEC_ECC_START && ready_o) begin
                ecc_state_n = ECC_ACTIVE; ecc_loop_cnt_n = '0;
            end
            ECC_ACTIVE: begin
                if (ecc_k_q[0] == 1'b1) begin
                    if (lane_valid_in && lane_owner_in == OWNER_ECC)
                        ecc_state_n = ECC_WAIT1;
                end else begin
                    ecc_state_n = ECC_SHIFT;
                end
            end
            ECC_WAIT1: ecc_state_n = ECC_WAIT2;
            ECC_WAIT2: begin
                if (lane_o_owner[0] == OWNER_ECC && lanes_out_valid[0])
                    ecc_state_n = ECC_SHIFT;
            end
            ECC_SHIFT: begin
                ecc_loop_cnt_n = ecc_loop_cnt_q + 1;
                if (ecc_loop_cnt_q == 255) ecc_state_n = ECC_DONE;
                else ecc_state_n = ECC_ACTIVE;
            end
            ECC_DONE: ;  // hold
            default: ecc_state_n = ECC_IDLE;
        endcase
    end

    // =========================================================================
    // Sequential Logic
    // =========================================================================
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= ST_IDLE; ecc_state_q <= ECC_IDLE; ecc_k_q <= '0;
            ecc_A_q <= '0; ecc_Acc_q <= '0; ecc_loop_cnt_q <= '0;
            send_cnt_q <= '0; recv_cnt_q <= '0; total_popcnt_q <= '0;
            saved_vd_q <= '0; saved_vs1_q <= '0; saved_vs2_q <= '0;
            result_valid_q <= 1'b0; result_data_q <= '0;
            vrf_read_launched <= 1'b0; pipe_wr_pending <= 1'b0; pipe_vd_q <= '0;
            // ECC ladder registers
            ecc_state_q <= ECC_IDLE; ecc_k_q <= '0;
            ecc_A_q <= '0; ecc_Acc_q <= '0; ecc_loop_cnt_q <= '0;
            wr_pending <= 1'b0;
            ecc_fetch_pending_q <= 1'b0;
            for (int i = 0; i < 4; i++) begin vrf_ra_addr[i] <= '0; vrf_rb_addr[i] <= '0; end
        end else begin
            state_q <= state_n; send_cnt_q <= send_cnt_n; recv_cnt_q <= recv_cnt_n;
            total_popcnt_q <= total_popcnt_n;
            saved_vd_q <= saved_vd_n; saved_vs1_q <= saved_vs1_n; saved_vs2_q <= saved_vs2_n;
            saved_op_q <= saved_op_n;
            result_valid_q <= result_valid_n; result_data_q <= result_data_n;
            ecc_fetch_pending_q <= ecc_fetch_pending_n;

            ecc_state_q <= ecc_state_n; ecc_loop_cnt_q <= ecc_loop_cnt_n;

            if (ecc_state_q == ECC_SHIFT) begin
                ecc_k_q <= ecc_k_q >> 1;
                ecc_A_q <= (ecc_A_q[255]) ? ((ecc_A_q << 1) ^ POLY_MASK) : (ecc_A_q << 1);
            end
            if (lane_o_owner[0] == OWNER_ECC && lanes_out_valid[0])
                ecc_Acc_q <= {lanes_out_ecc[3], lanes_out_ecc[2], lanes_out_ecc[1], lanes_out_ecc[0]};
            if (ecc_state_q == ECC_SHIFT) begin
                ecc_k_q <= ecc_k_q >> 1;
                ecc_A_q <= (ecc_A_q[255]) ? ((ecc_A_q << 1) ^ POLY_MASK) : (ecc_A_q << 1);
            end

            // INGEST write
            wr_pending <= 1'b0;
            if (state_q == ST_IDLE && valid_i && vrf_ready && operator_i == HDEC_INGEST) begin
                automatic logic [1:0] ing_cnt = recv_cnt_q[1:0];  // reused as ingest counter
                case (ing_cnt)
                    2'd0: vrf_b0[{operand_b_i[3:0], recv_cnt_q[3:2]}] <= operand_a_i;
                    2'd1: vrf_b1[{operand_b_i[3:0], recv_cnt_q[3:2]}] <= operand_a_i;
                    2'd2: vrf_b2[{operand_b_i[3:0], recv_cnt_q[3:2]}] <= operand_a_i;
                    2'd3: vrf_b3[{operand_b_i[3:0], recv_cnt_q[3:2]}] <= operand_a_i;
                endcase
                wr_pending <= 1'b1; wr_bank <= ing_cnt;
                wr_addr <= {operand_b_i[3:0], recv_cnt_q[3:2]}; wr_data <= operand_a_i;
                recv_cnt_n = recv_cnt_q + 1;
            end

            // VRF writeback (HDC lane outputs)
            if (state_q == ST_EXECUTE && lanes_out_valid[0] && lane_o_owner[0] == OWNER_HDC) begin
                if (saved_op_q == HDEC_BIND || saved_op_q == HDEC_BINARIZE
                    || saved_op_q == HDEC_PERMUTE) begin
                    for (int i = 0; i < 4; i++) begin
                        automatic logic [5:0] wa = {saved_vd_q[3:0], recv_cnt_q[1:0]};
                        case (i)
                            0: vrf_b0[wa] <= lanes_out_data[i]; 1: vrf_b1[wa] <= lanes_out_data[i];
                            2: vrf_b2[wa] <= lanes_out_data[i]; 3: vrf_b3[wa] <= lanes_out_data[i];
                        endcase
                    end
                end
            end

            // Local interlock tracking
            if (state_q == ST_IDLE && state_n == ST_EXECUTE) begin
                pipe_wr_pending <= 1'b1; pipe_vd_q <= saved_vd_n;
            end
            if ((state_q == ST_EXECUTE && lanes_out_valid[0] && lane_o_owner[0] == OWNER_HDC
                 && (saved_op_q == HDEC_BIND || saved_op_q == HDEC_BINARIZE
                     || saved_op_q == HDEC_PERMUTE))
                || (state_q == ST_FINISH && state_n == ST_IDLE))
                pipe_wr_pending <= 1'b0;

            // VRF read address launch
            vrf_read_launched <= 1'b0;
            if (state_q == ST_EXECUTE && send_cnt_q < 4) begin
                for (int i = 0; i < 4; i++)
                    vrf_ra_addr[i] <= vaddr(saved_vs1_q[3:0], send_cnt_q[1:0]);
                if (saved_op_q == HDEC_PERMUTE) begin
                    logic [1:0] next_send = (send_cnt_q == 3) ? 2'd0 : send_cnt_q[1:0] + 2'd1;
                    for (int i = 0; i < 4; i++)
                        vrf_rb_addr[i] <= vaddr(saved_vs1_q[3:0], next_send);
                end else if (saved_op_q != HDEC_BUNDLE_ACCUM) begin
                    for (int i = 0; i < 4; i++)
                        vrf_rb_addr[i] <= vaddr(saved_vs2_q[3:0], send_cnt_q[1:0]);
                end else begin
                    for (int i = 0; i < 4; i++) vrf_rb_addr[i] <= '0;
                end
                vrf_read_launched <= 1'b1;
            end
        end
    end

endmodule
