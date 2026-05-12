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
    // ECC — GF(2^256) ALU + Montgomery Ladder + ITA (L1/L2 architecture)
    // =========================================================================
    localparam logic [255:0] POLY_MASK = 256'h0000000000000000000000000000000000000000000000000000000000000425;
    localparam logic [255:0] ECC_B     = 256'h0000000000000000000000000000000000000000000000000000000000000001;
    localparam logic [3:0]  ECC_SLOT0 = 4'd14;  // X1/Z1/X2/Z2
    localparam logic [3:0]  ECC_SLOT1 = 4'd15;  // xG/b/T1/T2

    // ── Single-cycle GF(2^256) Square ─────────────────────────────────────
    function automatic logic [255:0] gf_sqr_256(input logic [255:0] a);
        logic [511:0] e;
        e = '0;
        for (int i = 0; i < 256; i++) e[2*i] = a[i];
        for (int j = 511; j >= 256; j--) if (e[j]) begin
            e[j] = 1'b0;
            e[j-256+10] ^= 1'b1; e[j-256+5] ^= 1'b1;
            e[j-256+2] ^= 1'b1; e[j-256]   ^= 1'b1;
        end
        return e[255:0];
    endfunction

    // ── GF(2^256) Multiply state machine ──────────────────────────────────
    typedef enum logic [2:0] { GF_IDLE, GF_LOAD, GF_ACTIVE, GF_W1, GF_W2, GF_SHIFT, GF_DONE } gf_state_e;
    gf_state_e gf_state_q, gf_state_n;
    logic [8:0]  gf_loop_q, gf_loop_n;
    logic [255:0] gf_k_q, gf_k_d, gf_A_q, gf_A_d, gf_Acc_q, gf_Acc_d;

    // ── L1: ONLY new D-FF (256-bit private-key register) ──────────────────
    logic [255:0] ladder_k_q, ladder_k_d;
    logic [63:0]  saved_ecc_k_q, saved_ecc_k_d;  // K snapshot at ECC_START
    logic [7:0]   ladder_step, ladder_step_d;
    logic [5:0]   ecc_uPC_q, ecc_uPC_n;
    logic [3:0]   ladder_sub_q, ladder_sub_n;
    logic [255:0] T1_buf, T1_buf_d, T2_buf, T2_buf_d, T4_buf, T4_buf_d;

    // ── ITA: Itoh-Tsujii inversion microcode ──────────────────────────────
    // BRAM read has 2-cycle latency: READ (addr) → WAIT → LATCH (data in ra_pipe)
    localparam logic [5:0]
        ITA_READ_Z1   = 6'd0,  ITA_WAIT_Z1   = 6'd1,  ITA_LATCH_Z1  = 6'd2,
        ITA_A2_SQR    = 6'd3,  ITA_A2_MUL    = 6'd4,
        ITA_A3_SQR    = 6'd5,  ITA_A3_MUL    = 6'd6,  ITA_SAVE_A3   = 6'd7,
        ITA_A6_SQR    = 6'd8,  ITA_A6_MUL    = 6'd9,
        ITA_A12_SQR   = 6'd10, ITA_A12_MUL   = 6'd11,
        ITA_A15_SQR   = 6'd12, ITA_A15_MUL   = 6'd13, ITA_SAVE_A15  = 6'd14,
        ITA_A30_SQR   = 6'd15, ITA_A30_MUL   = 6'd16,
        ITA_A60_SQR   = 6'd17, ITA_A60_MUL   = 6'd18,
        ITA_A120_SQR  = 6'd19, ITA_A120_MUL  = 6'd20,
        ITA_A240_SQR  = 6'd21, ITA_A240_MUL  = 6'd22,
        ITA_A255_SQR  = 6'd23, ITA_A255_MUL  = 6'd24,
        ITA_ZINV_SQR  = 6'd25,                           // ZINV = A255^2
        ITA_SAVE_ZINV = 6'd26, ITA_SELF_RD_Z1  = 6'd27,  // self-check: Z1 × ZINV = 1
        ITA_SELF_WAIT  = 6'd28, ITA_SELF_LATCH  = 6'd29,
        ITA_SELF_MUL   = 6'd30, ITA_SELF_PASS   = 6'd31,
        ITA_READ_X1   = 6'd32, ITA_WAIT_X1   = 6'd33, ITA_LATCH_X1  = 6'd34,
        ITA_XAFF_MUL  = 6'd35,
        ITA_DONE      = 6'd36;
    logic [5:0]   ita_uPC_q, ita_uPC_n;
    logic [7:0]   ita_cnt_q, ita_cnt_n;
    logic [255:0] ita_acc_q, ita_acc_d;
    logic         ita_sqr_active_q, ita_sqr_active_n;
    logic         ita_mul_pending_q, ita_mul_pending_n;

    // ── GF_MUL result handshake ──
    logic        gfmul_trigger;
    logic        gf_wait_result_q, gf_wait_result_n;  // ECC op issued, awaiting result

    // ── ECC Debug Dump: ladder sub-step trace ───────────────────────────
    localparam ECC_DBG = 0;  // set to 1 to enable debug dump
    always_ff @(posedge clk_i) begin
        if (ECC_DBG && ecc_top_q == ECC_INIT) begin
            $display("[DBG-INIT] uPC=%0d | gf_A=%h",
                     ecc_uPC_q, gf_A_q);
            if (ecc_vrf_wr)
                $display("[DBG-INIT-VRF] uPC=%0d -> slot=%0d.%0d data=%h",
                         ecc_uPC_q, ecc_wr_reg, ecc_wr_sub, ecc_wr_data);
        end
        if (ECC_DBG && ecc_top_q == ECC_LADDER) begin
            if (ladder_sub_q == 4'd0 || ladder_sub_q == 4'd1 ||
                (ladder_sub_q == 4'd2 && gf_state_q == GF_IDLE) ||
                (ladder_sub_q == 4'd2 && gf_state_q == GF_DONE) ||
                ladder_sub_q == 4'd3 || ladder_sub_q == 4'd4 ||
                (ladder_sub_q == 4'd5 && gf_state_q == GF_DONE) ||
                (ladder_sub_q == 4'd6 && gf_state_q == GF_IDLE) ||
                (ladder_sub_q == 4'd8 && gf_state_q == GF_DONE) ||
                ladder_sub_q == 4'd10 ||
                (ladder_sub_q == 4'd11 && gf_state_q == GF_IDLE) ||
                (ladder_sub_q == 4'd11 && gf_state_q == GF_DONE) ||
                (ladder_sub_q == 4'd12 && gf_state_q == GF_IDLE) ||
                (ladder_sub_q == 4'd12 && gf_state_q == GF_DONE) ||
                ladder_sub_q == 4'd13)
                $display("[DBG] step=%0d sub=%0d kbit=%b gf=%0d | gf_A=%h gf_Acc=%h",
                         ladder_step, ladder_sub_q, ladder_k_q[255], gf_state_q,
                         gf_A_q, gf_Acc_q);
            if (ecc_vrf_wr)
                $display("[DBG-VRF-WR] step=%0d sub=%0d -> slot=%0d.%0d data=%h",
                         ladder_step, ladder_sub_q, ecc_wr_reg, ecc_wr_sub, ecc_wr_data);
        end
    end
    always_ff @(posedge clk_i) begin
        if (ecc_top_q == ECC_LADDER && ladder_step == 8'd254) begin
            $display("[TRACE] Step 254 | sub=%0d | gf_state=%0d", ladder_sub_q, gf_state_q);

            if (ecc_vrf_wr) begin
                $display("  -> [STORE] VRF slot=%0d sub=%0d | Data=%h", ecc_wr_reg, ecc_wr_sub, ecc_wr_data);
            end

            if (gf_state_q == GF_DONE && ecc_top_q == ECC_LADDER && ladder_step >= 8'd252)
                $display("[GF-DONE] t=%0t step=%0d sub=%0d Acc=%h gf_A=%h", $time, ladder_step, ladder_sub_q, gf_Acc_q, gf_A_q);
            if (gf_state_q == GF_DONE && ecc_top_q == ECC_ITA)
                $display("[GF-DONE-ITA] t=%0t uPC=%0d Acc=%h", $time, ita_uPC_q, gf_Acc_q);

        // ECC result capture trace
        if (lane_o_owner[0] == OWNER_ECC && lanes_out_valid[0] && ladder_step >= 8'd252)
            $display("[ECC-RES] t=%0t step=%0d sub=%0d loop=%0d Acc_new=%h wait=%b",
                     $time, ladder_step, ladder_sub_q, gf_loop_q,
                     {lanes_out_ecc[3], lanes_out_ecc[2], lanes_out_ecc[1], lanes_out_ecc[0]},
                     gf_wait_result_q);
        end

        if (ecc_top_q == ECC_ITA) begin
            if (ita_uPC_q == ITA_LATCH_Z1)
                $display("[ITA] Z1 = %h", {vrf_ra_pipe[3], vrf_ra_pipe[2], vrf_ra_pipe[1], vrf_ra_pipe[0]});
            if (ita_uPC_q == ITA_LATCH_X1)
                $display("[ITA] X1 = %h", {vrf_ra_pipe[3], vrf_ra_pipe[2], vrf_ra_pipe[1], vrf_ra_pipe[0]});
            if (ita_uPC_q == ITA_DONE)
                $display("[ITA] DONE | XAFF = %h  (low64: %h)", ita_acc_q, ita_acc_q[63:0]);
        end

        // ECC_FETCH reads gf_Acc_q[63:0] (set to XAFF at ITA_DONE)

        // ── K probe: capture ECC_START K value ──
        if (state_q == ST_IDLE && valid_i && operator_i == HDEC_ECC_START)
            $display("[K-PROBE] t=%0t operand_a_i=%h", $time, operand_a_i);

        // ── ECC_DONE probe ──
        if (ecc_top_q != ECC_DONE && ecc_top_n == ECC_DONE)
            $display("[ECC-DONE] t=%0t  gf_Acc=%h", $time, gf_Acc_d);

        // ── ECC_FETCH probe ──
        if (state_q == ST_IDLE && valid_i && operator_i == HDEC_ECC_FETCH)
            $display("[FETCH] t=%0t ecc_top=%0d word=%0d  gf_Acc[63:0]=%h",
                     $time, ecc_top_q, operand_a_i[1:0], gf_Acc_q[63:0]);
    end

    // ── ECC VRF Store/Load flags ──────────────────────────────────────────
    logic        ecc_vrf_wr;       // trigger ECC VRF write
    logic [3:0]  ecc_wr_reg;       // target register
    logic [1:0]  ecc_wr_sub;       // target sub_chunk
    logic [255:0] ecc_wr_data;     // 256-bit data to write
    logic        ecc_vrf_grant;    // ECC VRF read allowed (HDC idle)
    logic        ecc_vrf_rd;       // trigger ECC VRF read
    logic [3:0]  ecc_rd_reg;       // ECC VRF read target register
    logic [1:0]  ecc_rd_sub;       // ECC VRF read target sub_chunk
    logic [255:0] ecc_vrf_read_data_q;  // latched 256-bit VRF read data
    logic        ecc_vrf_read_launched_q;

    // ── Top-level ECC FSM ────────────────────────────────────────────────
    typedef enum logic [2:0] { ECC_IDLE, ECC_INIT, ECC_LADDER, ECC_ITA, ECC_DONE } ecc_top_e;
    ecc_top_e ecc_top_q, ecc_top_n;

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
    logic gf_fetch_pending_q, gf_fetch_pending_n;
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
        end else if (gf_state_q == GF_ACTIVE && !hdc_active) latched_operator <= HDEC_BIND;
    end

    hdec_op current_lane_op;
    // ECC always uses BIND op (XOR); HDC uses latched_operator
    assign current_lane_op = (lane_owner_in == OWNER_ECC) ? HDEC_BIND : latched_operator;

    generate
        for (genvar i = 0; i < 4; i++) begin : gl
            hdec_lane il (
                .clk(clk_i), .rst_n(rst_ni), .i_valid(lane_valid_in), .o_valid(lanes_out_valid[i]),
                .i_op_mode(current_lane_op),
                .i_ecc_mode(lane_owner_in == OWNER_ECC || (!hdc_active && gf_state_q != GF_IDLE)),
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
        gf_state_n = gf_state_q; gf_loop_n = gf_loop_q;
        lane_cnt_clear = 1'b0; lanes_in_1 = '0; lanes_in_2 = '0;
        result_valid_n = 1'b0; result_data_n = result_data_q;
        gf_fetch_pending_n = gf_fetch_pending_q;
        gf_A_d = gf_A_q; gf_k_d = gf_k_q; gf_Acc_d = gf_Acc_q;
        saved_ecc_k_d = saved_ecc_k_q;
        ladder_k_d = ladder_k_q; ladder_step_d = ladder_step;
        T1_buf_d = T1_buf; T2_buf_d = T2_buf; T4_buf_d = T4_buf;
        ladder_sub_n = ladder_sub_q;
        gfmul_trigger = 1'b0;
        gf_wait_result_n = gf_wait_result_q;
        ecc_top_n   = ecc_top_q;   ecc_uPC_n   = ecc_uPC_q;
        ecc_wr_reg  = '0;          ecc_wr_sub  = '0;
        ecc_vrf_wr  = 1'b0;        ecc_wr_data = '0;
        ecc_vrf_rd  = 1'b0;
        ecc_rd_reg  = '0;          ecc_rd_sub  = '0;
        ita_uPC_n   = ita_uPC_q;   ita_cnt_n   = ita_cnt_q;
        ita_acc_d   = ita_acc_q;
        ita_sqr_active_n = ita_sqr_active_q;
        ita_mul_pending_n = ita_mul_pending_q;

        lane_valid_in = 1'b0; lane_owner_in = OWNER_NONE;

        // ── ECC VRF grant: available only when HDC idle (VRF ports free) ──
        ecc_vrf_grant = (state_q == ST_IDLE);

        // ── HDC send phase: S1 always granted (highest priority) ──
        if (state_q == ST_EXECUTE && vrf_read_launched) begin
            lane_valid_in = 1'b1; lane_owner_in = OWNER_HDC;
        end

        // ── ECC: seizes S1 when HDC is idle AND no outstanding result ──
        if (!lane_valid_in && gf_state_q == GF_ACTIVE && gf_k_q[0] == 1'b1
            && !gf_wait_result_q) begin
            lane_valid_in = 1'b1; lane_owner_in = OWNER_ECC;
            gf_wait_result_n = 1'b1;  // outstanding ECC op in Lane pipeline
            // ECC data routing moved here from state machine
            lanes_in_1[0] = gf_A_q[63:0];      lanes_in_2[0] = gf_Acc_q[63:0];
            lanes_in_1[1] = gf_A_q[127:64];    lanes_in_2[1] = gf_Acc_q[127:64];
            lanes_in_1[2] = gf_A_q[191:128];   lanes_in_2[2] = gf_Acc_q[191:128];
            lanes_in_1[3] = gf_A_q[255:192];   lanes_in_2[3] = gf_Acc_q[255:192];
        end

        ready_o = 1'b0;

        case (state_q)
            ST_IDLE: begin
                ready_o = vrf_ready;

                // ECC_FETCH pending: serve when ECC reaches DONE (returns word0)
                if (gf_fetch_pending_q && ecc_top_q == ECC_DONE) begin
                    result_valid_n = 1'b1; result_data_n = gf_Acc_q[63:0];
                    gf_fetch_pending_n = 1'b0;
                end

                if (valid_i && ready_o) begin
                    if (operator_i == HDEC_INGEST) begin
                        result_valid_n = 1'b1; result_data_n = 64'b0;
                    end else if (operator_i == HDEC_ECC_START) begin
                        if (ecc_top_q != ECC_IDLE && ecc_top_q != ECC_DONE) begin
                            ready_o = 1'b0;
                            $display("[ERROR_ECC_START_BUSY] t=%0t ecc_top=%0d", $time, ecc_top_q);
                        end else begin
                            result_valid_n = 1'b1; result_data_n = 64'b0;
                            saved_ecc_k_d = operand_a_i;
                            ladder_k_d = {192'b0, operand_a_i};
                            ecc_top_n = ECC_INIT;
                            ecc_uPC_n = '0;
                            ita_uPC_n = ITA_READ_Z1;
                            ladder_step_d = 8'd254;
                        end
                    end else if (operator_i == HDEC_CLEAR_CNT) begin
                        lane_cnt_clear = 1'b1;
                        result_valid_n = 1'b1; result_data_n = 64'b0;
                    end else if (operator_i == HDEC_ECC_FETCH) begin
                        if (ecc_top_q == ECC_DONE) begin
                            unique case (operand_a_i[1:0])
                                2'd0: result_data_n = gf_Acc_q[63:0];
                                2'd1: result_data_n = gf_Acc_q[127:64];
                                2'd2: result_data_n = gf_Acc_q[191:128];
                                2'd3: result_data_n = gf_Acc_q[255:192];
                            endcase
                            result_valid_n = 1'b1;
                        end else begin
                            $display("[FETCH-DEFER] t=%0t ecc_top=%0d word=%0d", $time, ecc_top_q, operand_a_i[1:0]);
                            gf_fetch_pending_n = 1'b1;
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
                if (saved_op_q == HDEC_ECC_FETCH && gf_state_q != GF_IDLE) begin
                    // Still computing, stay in FINISH
                end else begin
                    result_valid_n = 1'b1;
                    if (saved_op_q == HDEC_MATCH)
                        result_data_n = {52'b0, total_popcnt_q};
                    else if (saved_op_q == HDEC_ECC_FETCH)
                        result_data_n = gf_Acc_q[63:0];
                    else
                        result_data_n = 64'b0;
                    state_n = ST_IDLE;
                end
            end
        endcase

        // ── Ladder / ITA Controller (MUST run before GF machine) ──────────
        case (ecc_top_q)
            ECC_IDLE: ;
            ECC_INIT: begin
                if (ecc_uPC_q == 6'd0) begin
                    ecc_vrf_wr = 1'b1; ecc_wr_reg = ECC_SLOT1; ecc_wr_sub = 2'd0;
                    ecc_wr_data = {192'b0, operand_a_i};
                    ecc_uPC_n = 6'd1;
                end else if (ecc_uPC_q == 6'd1) begin
                    gf_A_d = gf_sqr_256({192'b0, saved_ecc_k_q});
                    ecc_uPC_n = 6'd2;
                end else if (ecc_uPC_q == 6'd2) begin
                    ecc_vrf_wr = 1'b1; ecc_wr_reg = ECC_SLOT0; ecc_wr_sub = 2'd0;
                    ecc_wr_data = {192'b0, saved_ecc_k_q};
                    ecc_uPC_n = 6'd3;
                end else if (ecc_uPC_q == 6'd3) begin
                    ecc_vrf_wr = 1'b1; ecc_wr_reg = ECC_SLOT0; ecc_wr_sub = 2'd1;
                    ecc_wr_data = 256'h1;
                    ecc_uPC_n = 6'd4;
                end else if (ecc_uPC_q == 6'd4) begin
                    ecc_vrf_wr = 1'b1; ecc_wr_reg = ECC_SLOT0; ecc_wr_sub = 2'd3;
                    ecc_wr_data = gf_A_q;
                    ecc_uPC_n = 6'd5;
                end else if (ecc_uPC_q == 6'd5) begin
                    ecc_vrf_wr = 1'b1; ecc_wr_reg = ECC_SLOT0; ecc_wr_sub = 2'd2;
                    ecc_wr_data = gf_sqr_256(gf_A_q) ^ ECC_B;
                    ecc_uPC_n = 6'd6;
                end else begin
                    ecc_top_n = ECC_LADDER; ecc_uPC_n = 6'd0;
                end
            end
            ECC_LADDER: begin
                if (ladder_step == 8'd0) begin
                    ecc_top_n = ECC_ITA; ecc_uPC_n = 6'd0;
                end else if (gf_state_q == GF_DONE) begin
                    gf_state_n = GF_IDLE;
                    case (ladder_sub_q)
                        4'd2: begin ecc_vrf_wr=1; ecc_wr_reg=ECC_SLOT0; ecc_wr_sub=2'd1; ecc_wr_data=gf_Acc_q; ladder_sub_n=3; end
                        4'd5: begin ecc_vrf_wr=1; ecc_wr_reg=ECC_SLOT0; ecc_wr_sub=2'd0; ecc_wr_data=T1_buf ^ gf_Acc_q; ladder_sub_n=6; end
                        4'd8: begin T1_buf_d = gf_Acc_q; ladder_sub_n=9; end
                        4'd9: begin T2_buf_d = gf_Acc_q; ladder_sub_n=10; end
                        4'd11: begin T4_buf_d = gf_Acc_q; ladder_sub_n=12; end
                        4'd12: begin
                            if (ladder_k_q[255]) begin
                                ecc_vrf_wr=1; ecc_wr_reg=ECC_SLOT0; ecc_wr_sub=2'd0; ecc_wr_data=gf_Acc_q ^ T4_buf;
                            end else begin
                                ecc_vrf_wr=1; ecc_wr_reg=ECC_SLOT0; ecc_wr_sub=2'd2; ecc_wr_data=gf_Acc_q ^ T4_buf;
                            end
                            ladder_sub_n=13;
                        end
                        default: ladder_sub_n = ladder_sub_q + 1;
                    endcase
                end else if (gf_state_q == GF_IDLE) begin
                    case (ladder_sub_q)
                        4'd0: begin gf_A_d=gf_sqr_256(gf_A_q); ladder_sub_n=1; end
                        4'd1: begin ecc_vrf_wr=1; ecc_wr_reg=ECC_SLOT1; ecc_wr_sub=2'd2; ecc_wr_data=gf_A_q; ladder_sub_n=2; end
                        4'd2: begin gf_k_d = gf_sqr_256(gf_A_q); gfmul_trigger=1; gf_loop_n='0; gf_Acc_d='0; ladder_sub_n=2; end
                        4'd3: begin gf_A_d=gf_sqr_256(gf_A_q); T1_buf_d=gf_A_q; ladder_sub_n=4; end
                        4'd4: begin gf_k_d=ECC_B; gfmul_trigger=1; gf_loop_n='0; gf_Acc_d=gf_sqr_256(gf_A_q); ladder_sub_n=5; end
                        4'd5: ;
                        4'd6: begin gf_k_d=gf_A_q; gfmul_trigger=1; gf_loop_n='0; gf_Acc_d='0; ladder_sub_n=8; end
                        4'd7: begin gf_k_d=gf_A_q; gfmul_trigger=1; gf_loop_n='0; gf_Acc_d='0; ladder_sub_n=9; end
                        4'd10: begin gf_A_d=gf_sqr_256(T1_buf ^ T2_buf); ladder_sub_n=11; end
                        4'd11: begin gf_k_d=gf_A_q; gfmul_trigger=1; gf_loop_n='0; gf_Acc_d='0; ladder_sub_n=11; end
                        4'd12: begin gf_k_d=gf_A_q; gfmul_trigger=1; gf_loop_n='0; gf_Acc_d='0; ladder_sub_n=12; end
                        4'd13: begin
                            ladder_k_d = ladder_k_q >> 1;
                            if (ladder_step > 1) begin
                                ladder_step_d = ladder_step - 1; ladder_sub_n = 4'd0;
                            end else begin
                                ladder_step_d = 8'd0; ladder_sub_n = 4'd0;
                            end
                        end
                        default: ladder_sub_n = ladder_sub_q + 1;
                    endcase
                end
            end
            ECC_ITA: begin
                // GF_DONE handler — latch result from last MUL, advance uPC
                if (ita_mul_pending_q && gf_state_q == GF_DONE) begin
                    gf_state_n   = GF_IDLE;
                    ita_acc_d    = gf_Acc_q;
                    ita_mul_pending_n = 1'b0;
                    ita_uPC_n    = ita_uPC_q + 6'd1;  // advance past MUL state
                end

                // ── SQR_REPEAT helper ─────────────────────────────────────
                // uPCs 2,4,7,9,11,14,16,18,20,22,24 run SQR chain of ita_cnt cycles
                if (ita_sqr_active_q) begin
                    ita_acc_d = gf_sqr_256(ita_acc_q);
                    if (ita_cnt_q == 8'd1) begin
                        ita_cnt_n = 8'd0;
                        ita_sqr_active_n = 1'b0;
                        ita_uPC_n = ita_uPC_q + 6'd1;
                    end else begin
                        ita_cnt_n = ita_cnt_q - 8'd1;
                    end
                end

                // ── Per-uPC dispatch ─────────────────────────────────────
                case (ita_uPC_q)
                    // 0: ITA_READ_Z1 — launch VRF read for Z1 (respect HDC priority)
                    ITA_READ_Z1: begin
                        if (ecc_vrf_grant) begin
                            ecc_vrf_rd = 1'b1;
                            ecc_rd_reg = ECC_SLOT0;
                            ecc_rd_sub = 2'd1;
                            ita_uPC_n  = ITA_WAIT_Z1;
                        end
                    end

                    // 1: ITA_WAIT_Z1 — BRAM pipeline delay
                    ITA_WAIT_Z1: begin
                        ita_uPC_n = ITA_LATCH_Z1;
                    end

                    // 2: ITA_LATCH_Z1 — latch Z1 from VRF (vrf_ra_pipe valid now)
                    ITA_LATCH_Z1: begin
                        ita_acc_d  = {vrf_ra_pipe[3], vrf_ra_pipe[2], vrf_ra_pipe[1], vrf_ra_pipe[0]};
                        T1_buf_d   = {vrf_ra_pipe[3], vrf_ra_pipe[2], vrf_ra_pipe[1], vrf_ra_pipe[0]};
                        ita_uPC_n  = ITA_A2_SQR;
                    end

                    // 2: ITA_A2_SQR — A1^(2^1)
                    ITA_A2_SQR: begin
                        if (!ita_sqr_active_q) begin
                            ita_cnt_n = 8'd1;
                            ita_sqr_active_n = 1'b1;
                        end
                    end

                    // 3: ITA_A2_MUL — A2 = A1^2 × A1
                    ITA_A2_MUL: begin
                        if (!ita_mul_pending_q && gf_state_q == GF_IDLE) begin
                            gf_A_d    = ita_acc_q;
                            gf_k_d    = T1_buf;      // Z1 = A1
                            gf_Acc_d  = '0;
                            gfmul_trigger = 1'b1;
                            ita_mul_pending_n = 1'b1;
                        end
                    end

                    // 4: ITA_A3_SQR — A2^(2^1)
                    ITA_A3_SQR: begin
                        if (!ita_sqr_active_q) begin
                            ita_cnt_n = 8'd1;
                            ita_sqr_active_n = 1'b1;
                        end
                    end

                    // 5: ITA_A3_MUL — A3 = A2^2 × A1
                    ITA_A3_MUL: begin
                        if (!ita_mul_pending_q && gf_state_q == GF_IDLE) begin
                            gf_A_d    = ita_acc_q;
                            gf_k_d    = T1_buf;      // still Z1 = A1
                            gf_Acc_d  = '0;
                            gfmul_trigger = 1'b1;
                            ita_mul_pending_n = 1'b1;
                        end
                    end

                    // 6: ITA_SAVE_A3
                    ITA_SAVE_A3: begin
                        T2_buf_d  = ita_acc_q;       // save A3 (NOT gf_Acc_q)
                        ita_uPC_n = ITA_A6_SQR;
                    end

                    // 7: ITA_A6_SQR — A3^(2^3)
                    ITA_A6_SQR: begin
                        if (!ita_sqr_active_q) begin
                            T1_buf_d  = ita_acc_q;   // snapshot A3
                            ita_cnt_n = 8'd3;
                            ita_sqr_active_n = 1'b1;
                        end
                    end

                    // 8: ITA_A6_MUL — A6 = A3^8 × A3
                    ITA_A6_MUL: begin
                        if (!ita_mul_pending_q && gf_state_q == GF_IDLE) begin
                            gf_A_d    = ita_acc_q;
                            gf_k_d    = T1_buf;     // A3 snapshot
                            gf_Acc_d  = '0;
                            gfmul_trigger = 1'b1;
                            ita_mul_pending_n = 1'b1;
                        end
                    end

                    // 9: ITA_A12_SQR — A6^(2^6)
                    ITA_A12_SQR: begin
                        if (!ita_sqr_active_q) begin
                            T1_buf_d  = ita_acc_q;   // snapshot A6
                            ita_cnt_n = 8'd6;
                            ita_sqr_active_n = 1'b1;
                        end
                    end

                    // 10: ITA_A12_MUL — A12 = A6^64 × A6
                    ITA_A12_MUL: begin
                        if (!ita_mul_pending_q && gf_state_q == GF_IDLE) begin
                            gf_A_d    = ita_acc_q;
                            gf_k_d    = T1_buf;
                            gf_Acc_d  = '0;
                            gfmul_trigger = 1'b1;
                            ita_mul_pending_n = 1'b1;
                        end
                    end

                    // 11: ITA_A15_SQR — A12^(2^3)
                    ITA_A15_SQR: begin
                        if (!ita_sqr_active_q) begin
                            ita_cnt_n = 8'd3;
                            ita_sqr_active_n = 1'b1;
                        end
                    end

                    // 12: ITA_A15_MUL — A15 = A12^8 × A3
                    ITA_A15_MUL: begin
                        if (!ita_mul_pending_q && gf_state_q == GF_IDLE) begin
                            gf_A_d    = ita_acc_q;
                            gf_k_d    = T2_buf;     // A3
                            gf_Acc_d  = '0;
                            gfmul_trigger = 1'b1;
                            ita_mul_pending_n = 1'b1;
                        end
                    end

                    // 13: ITA_SAVE_A15
                    ITA_SAVE_A15: begin
                        T4_buf_d  = ita_acc_q;       // save A15 (NOT gf_Acc_q)
                        ita_uPC_n = ITA_A30_SQR;
                    end

                    // 14: ITA_A30_SQR — A15^(2^15)
                    ITA_A30_SQR: begin
                        if (!ita_sqr_active_q) begin
                            T1_buf_d  = ita_acc_q;   // snapshot A15
                            ita_cnt_n = 8'd15;
                            ita_sqr_active_n = 1'b1;
                        end
                    end

                    // 15: ITA_A30_MUL — A30 = A15^32768 × A15
                    ITA_A30_MUL: begin
                        if (!ita_mul_pending_q && gf_state_q == GF_IDLE) begin
                            gf_A_d    = ita_acc_q;
                            gf_k_d    = T1_buf;
                            gf_Acc_d  = '0;
                            gfmul_trigger = 1'b1;
                            ita_mul_pending_n = 1'b1;
                        end
                    end

                    // 16: ITA_A60_SQR — A30^(2^30)
                    ITA_A60_SQR: begin
                        if (!ita_sqr_active_q) begin
                            T1_buf_d  = ita_acc_q;
                            ita_cnt_n = 8'd30;
                            ita_sqr_active_n = 1'b1;
                        end
                    end

                    // 17: ITA_A60_MUL
                    ITA_A60_MUL: begin
                        if (!ita_mul_pending_q && gf_state_q == GF_IDLE) begin
                            gf_A_d    = ita_acc_q;
                            gf_k_d    = T1_buf;
                            gf_Acc_d  = '0;
                            gfmul_trigger = 1'b1;
                            ita_mul_pending_n = 1'b1;
                        end
                    end

                    // 18: ITA_A120_SQR — A60^(2^60)
                    ITA_A120_SQR: begin
                        if (!ita_sqr_active_q) begin
                            T1_buf_d  = ita_acc_q;
                            ita_cnt_n = 8'd60;
                            ita_sqr_active_n = 1'b1;
                        end
                    end

                    // 19: ITA_A120_MUL
                    ITA_A120_MUL: begin
                        if (!ita_mul_pending_q && gf_state_q == GF_IDLE) begin
                            gf_A_d    = ita_acc_q;
                            gf_k_d    = T1_buf;
                            gf_Acc_d  = '0;
                            gfmul_trigger = 1'b1;
                            ita_mul_pending_n = 1'b1;
                        end
                    end

                    // 20: ITA_A240_SQR — A120^(2^120)
                    ITA_A240_SQR: begin
                        if (!ita_sqr_active_q) begin
                            T1_buf_d  = ita_acc_q;
                            ita_cnt_n = 8'd120;
                            ita_sqr_active_n = 1'b1;
                        end
                    end

                    // 21: ITA_A240_MUL — A240 = A120^(2^120) × A120
                    ITA_A240_MUL: begin
                        if (!ita_mul_pending_q && gf_state_q == GF_IDLE) begin
                            gf_A_d    = ita_acc_q;
                            gf_k_d    = T1_buf;
                            gf_Acc_d  = '0;
                            gfmul_trigger = 1'b1;
                            ita_mul_pending_n = 1'b1;
                        end
                    end

                    // 22: ITA_A255_SQR — A240^(2^15)
                    ITA_A255_SQR: begin
                        if (!ita_sqr_active_q) begin
                            ita_cnt_n = 8'd15;
                            ita_sqr_active_n = 1'b1;
                        end
                    end

                    // 23: ITA_A255_MUL — A255 = A240^(2^15) × A15
                    ITA_A255_MUL: begin
                        if (!ita_mul_pending_q && gf_state_q == GF_IDLE) begin
                            gf_A_d    = ita_acc_q;
                            gf_k_d    = T4_buf;     // A15
                            gf_Acc_d  = '0;
                            gfmul_trigger = 1'b1;
                            ita_mul_pending_n = 1'b1;
                        end
                    end

                    // 24: ITA_ZINV_SQR — ZINV = A255^2
                    ITA_ZINV_SQR: begin
                        if (!ita_sqr_active_q) begin
                            ita_cnt_n = 8'd1;
                            ita_sqr_active_n = 1'b1;
                        end
                        // advance to ITA_SAVE_ZINV handled by SQR_REPEAT helper when cnt→0
                    end

                    // 26: ITA_SAVE_ZINV — stash ZINV in T2_buf for self-check & XAFF
                    ITA_SAVE_ZINV: begin
                        T2_buf_d  = ita_acc_q;       // ZINV saved (A3 no longer needed)
                        ita_uPC_n = ITA_SELF_RD_Z1;
                    end

                    // 27: ITA_SELF_RD_Z1 — re-read Z1 from VRF for self-check
                    ITA_SELF_RD_Z1: begin
                        if (ecc_vrf_grant) begin
                            ecc_vrf_rd = 1'b1;
                            ecc_rd_reg = ECC_SLOT0;
                            ecc_rd_sub = 2'd1;
                            ita_uPC_n  = ITA_SELF_WAIT;
                        end
                    end

                    // 28: ITA_SELF_WAIT — BRAM pipeline delay
                    ITA_SELF_WAIT: begin
                        ita_uPC_n = ITA_SELF_LATCH;
                    end

                    // 29: ITA_SELF_LATCH — latch Z1 into T1_buf
                    ITA_SELF_LATCH: begin
                        T1_buf_d  = {vrf_ra_pipe[3], vrf_ra_pipe[2], vrf_ra_pipe[1], vrf_ra_pipe[0]};
                        ita_uPC_n = ITA_SELF_MUL;
                    end

                    // 30: ITA_SELF_MUL — CHECK = Z1 × ZINV
                    ITA_SELF_MUL: begin
                        if (!ita_mul_pending_q && gf_state_q == GF_IDLE) begin
                            gf_A_d    = T1_buf;      // Z1
                            gf_k_d    = T2_buf;      // ZINV (stashed)
                            gf_Acc_d  = '0;
                            gfmul_trigger = 1'b1;
                            ita_mul_pending_n = 1'b1;
                        end
                    end

                    // 31: ITA_SELF_PASS — verify CHECK=1, restore ZINV
                    ITA_SELF_PASS: begin
                        $display("[ITA-SELF] CHECK = Z1 × ZINV = %h %s",
                            ita_acc_q,
                            (ita_acc_q == 256'h1) ? "PASS" : "FAIL");
                        ita_acc_d  = T2_buf;          // restore ZINV for XAFF
                        ita_uPC_n  = ITA_READ_X1;
                    end

                    // 32: ITA_READ_X1 — launch VRF read for X1 (respect HDC priority)
                    ITA_READ_X1: begin
                        if (ecc_vrf_grant) begin
                            ecc_vrf_rd = 1'b1;
                            ecc_rd_reg = ECC_SLOT0;
                            ecc_rd_sub = 2'd0;
                            ita_uPC_n  = ITA_WAIT_X1;
                        end
                    end

                    // 33: ITA_WAIT_X1 — BRAM pipeline delay
                    ITA_WAIT_X1: begin
                        ita_uPC_n = ITA_LATCH_X1;
                    end

                    // 34: ITA_LATCH_X1 — latch X1 into T1_buf
                    ITA_LATCH_X1: begin
                        T1_buf_d  = {vrf_ra_pipe[3], vrf_ra_pipe[2], vrf_ra_pipe[1], vrf_ra_pipe[0]};
                        ita_uPC_n = ITA_XAFF_MUL;
                    end

                    // 35: ITA_XAFF_MUL — XAFF = X1 × ZINV
                    ITA_XAFF_MUL: begin
                        if (!ita_mul_pending_q && gf_state_q == GF_IDLE) begin
                            gf_A_d    = T1_buf;      // X1
                            gf_k_d    = T2_buf;      // ZINV (still in T2_buf)
                            gf_Acc_d  = '0;
                            gfmul_trigger = 1'b1;
                            ita_mul_pending_n = 1'b1;
                        end
                    end

                    // 36: ITA_DONE — XAFF → gf_Acc for ECC_FETCH
                    ITA_DONE: begin
                        gf_Acc_d  = ita_acc_q;       // XAFF visible to ECC_FETCH
                        ecc_top_n = ECC_DONE;
                        ita_uPC_n = ITA_READ_Z1;
                    end

                    default: ita_uPC_n = ITA_READ_Z1;
                endcase
            end
            ECC_DONE: ;
            default: ecc_top_n = ECC_IDLE;
        endcase

        // GF Multiply machine — must run AFTER ladder (reads gfmul_trigger)
        case (gf_state_q)
            GF_IDLE: if (gfmul_trigger) begin
                gf_state_n = GF_LOAD; gf_loop_n = '0;
            end
            GF_LOAD: begin
                gf_state_n = GF_ACTIVE;
            end
            GF_ACTIVE: begin
                if (gf_k_q[0] == 1'b1) begin
                    if (lane_valid_in && lane_owner_in == OWNER_ECC)
                        gf_state_n = GF_W1;
                end else begin
                    gf_state_n = GF_SHIFT;
                end
            end
            GF_W1: gf_state_n = GF_W2;
            GF_W2: begin
                // Advance only when ECC result arrives AND was awaited
                if (lane_o_owner[0] == OWNER_ECC && lanes_out_valid[0]
                    && gf_wait_result_q)
                    gf_state_n = GF_SHIFT;
            end
            GF_SHIFT: begin
                gf_loop_n = gf_loop_q + 1;
                if (gf_loop_q == 255) gf_state_n = GF_DONE;
                else gf_state_n = GF_ACTIVE;
            end
            GF_DONE: ;
            default: gf_state_n = GF_IDLE;
        endcase
    end

    // =========================================================================
    // Sequential Logic
    // =========================================================================
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= ST_IDLE; gf_state_q <= GF_IDLE; gf_k_q <= '0;
            gf_A_q <= '0; gf_Acc_q <= '0; gf_loop_q <= '0;
            send_cnt_q <= '0; recv_cnt_q <= '0; total_popcnt_q <= '0;
            saved_vd_q <= '0; saved_vs1_q <= '0; saved_vs2_q <= '0;
            result_valid_q <= 1'b0; result_data_q <= '0;
            vrf_read_launched <= 1'b0; pipe_wr_pending <= 1'b0; pipe_vd_q <= '0;
            ecc_top_q <= ECC_IDLE; ecc_uPC_q <= '0;
            ladder_k_q <= '0; saved_ecc_k_q <= '0; ladder_step <= '0;
            ladder_sub_q <= '0; T1_buf<='0; T2_buf<='0; T4_buf<='0;
            wr_pending <= 1'b0;
            gf_fetch_pending_q <= 1'b0;
            ita_uPC_q  <= ITA_READ_Z1; ita_cnt_q  <= '0;
            ita_acc_q  <= '0;
            ita_sqr_active_q <= '0; ita_mul_pending_q <= '0;
            gf_wait_result_q <= '0;
            ecc_vrf_read_data_q <= '0; ecc_vrf_read_launched_q <= '0;
            for (int i = 0; i < 4; i++) begin vrf_ra_addr[i] <= '0; vrf_rb_addr[i] <= '0; end
        end else begin
            state_q <= state_n; send_cnt_q <= send_cnt_n; recv_cnt_q <= recv_cnt_n;
            total_popcnt_q <= total_popcnt_n;
            saved_vd_q <= saved_vd_n; saved_vs1_q <= saved_vs1_n; saved_vs2_q <= saved_vs2_n;
            saved_op_q <= saved_op_n;
            result_valid_q <= result_valid_n; result_data_q <= result_data_n;
            gf_fetch_pending_q <= gf_fetch_pending_n;

            gf_state_q <= gf_state_n; gf_loop_q <= gf_loop_n;
            ecc_top_q <= ecc_top_n; ecc_uPC_q <= ecc_uPC_n;
            ladder_sub_q <= ladder_sub_n;
            // Register _d wires → _q
            gf_A_q <= gf_A_d; gf_k_q <= gf_k_d; gf_Acc_q <= gf_Acc_d;
            saved_ecc_k_q <= saved_ecc_k_d;
            ladder_k_q <= ladder_k_d; ladder_step <= ladder_step_d;
            T1_buf <= T1_buf_d; T2_buf <= T2_buf_d; T4_buf <= T4_buf_d;
            ita_uPC_q <= ita_uPC_n; ita_cnt_q <= ita_cnt_n;
            ita_acc_q <= ita_acc_d;
            ita_sqr_active_q <= ita_sqr_active_n;
            ita_mul_pending_q <= ita_mul_pending_n;
            gf_wait_result_q <= gf_wait_result_n;

            if (gf_state_q == GF_SHIFT) begin
                gf_k_q <= gf_k_q >> 1;
                gf_A_q <= (gf_A_q[255]) ? ((gf_A_q << 1) ^ POLY_MASK) : (gf_A_q << 1);
            end
            if (lane_o_owner[0] == OWNER_ECC && lanes_out_valid[0]) begin
                gf_Acc_q <= {lanes_out_ecc[3], lanes_out_ecc[2], lanes_out_ecc[1], lanes_out_ecc[0]};
                gf_wait_result_q <= 1'b0;   // result captured, clear outstanding
            end

            // ── VRF trace (short) ──
        if (ecc_vrf_wr)
            $display("[VRF-WR-ECC] t=%0t step=%0d sub=%0d reg=%0d.%0d",
                     $time, ladder_step, ladder_sub_q, ecc_wr_reg, ecc_wr_sub);
        if (state_q == ST_EXECUTE && lanes_out_valid[0] && lane_o_owner[0] == OWNER_HDC
            && (saved_op_q == HDEC_BIND || saved_op_q == HDEC_BINARIZE
                || saved_op_q == HDEC_PERMUTE))
            $display("[VRF-WR-HDC] t=%0t reg=%0d sub=%0d",
                     $time, saved_vd_q[3:0], recv_cnt_q[1:0]);
        if (state_q == ST_IDLE && valid_i && operator_i == HDEC_INGEST)
            $display("[VRF-WR-ING] t=%0t reg=%0d sub=%0d",
                     $time, operand_b_i[3:0], recv_cnt_q[3:2]);

            // ECC VRF Store (from ladder/ITA controller)
            if (ecc_vrf_wr) begin
                for (int i = 0; i < 4; i++) begin
                    automatic logic [5:0] wa = {ecc_wr_reg, ecc_wr_sub};
                    case (i)
                        0: vrf_b0[wa] <= ecc_wr_data[63:0];
                        1: vrf_b1[wa] <= ecc_wr_data[127:64];
                        2: vrf_b2[wa] <= ecc_wr_data[191:128];
                        3: vrf_b3[wa] <= ecc_wr_data[255:192];
                    endcase
                end
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

            // ECC VRF read — ITA uses BRAM Port A (safe: HDC idle during ITA)
            if (ecc_vrf_rd && ecc_top_q == ECC_ITA) begin
                for (int i = 0; i < 4; i++)
                    vrf_ra_addr[i] <= {ecc_rd_reg, ecc_rd_sub};
            end
            // Latch read data one cycle after launch
            if (ecc_vrf_read_launched_q) begin
                ecc_vrf_read_data_q <= {vrf_ra_pipe[3], vrf_ra_pipe[2], vrf_ra_pipe[1], vrf_ra_pipe[0]};
            end
            ecc_vrf_read_launched_q <= ecc_vrf_rd && ecc_top_q == ECC_ITA;

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

            // ── VRF overlap detection: HDC must not write ECC regs (14-15) ──
            if ((state_q == ST_EXECUTE && lanes_out_valid[0] && lane_o_owner[0] == OWNER_HDC
                 && (saved_op_q == HDEC_BIND || saved_op_q == HDEC_BINARIZE
                     || saved_op_q == HDEC_PERMUTE)
                 && (saved_vd_q[3:0] >= 4'd14)))
                $display("[ERROR_HDC_WR_ECC_REG] t=%0t reg=%0d", $time, saved_vd_q[3:0]);
            if (ecc_vrf_wr && (ecc_wr_reg < 4'd14))
                $display("[ERROR_ECC_WR_HDC_REG] t=%0t reg=%0d", $time, ecc_wr_reg);
        end
    end

endmodule
