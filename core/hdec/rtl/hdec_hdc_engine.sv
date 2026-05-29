// =============================================================================
// hdec_hdc_engine.sv — HDC Engine Top (Controller Placeholders)
// =============================================================================
// Instantiates clear, bind, sim, perm, cntadd, cntclip, match controllers.
// Routes start/busy/done/status from each controller.
// HDCU Phase: only clear_ctrl does real work; rest return NOT_IMPLEMENTED.
// Real FSM control resides in hdec_top.sv.
// =============================================================================

module hdec_hdc_engine
    import hdec_pkg::*;
    import hdec_resource_pkg::*;
(
    input  logic        clk_i,
    input  logic        rst_ni,

    // ── Command from Decoder ────────────────────────────────────────────────
    input  logic                    decode_valid_i,
    output logic                    decode_ready_o,
    input  hdec_op_t                decode_op_i,
    input  logic [VRF_IDX_W-1:0]    decode_rd_reg_i,    // vs1 / src
    input  logic [VRF_IDX_W-1:0]    decode_wr_reg_i,    // vd / dst
    input  logic [VRF_IDX_W-1:0]    decode_vrf_reg_i,   // vs2

    // ── VRF Write Interface (to top/vrf) ────────────────────────────────────
    output logic [VRF_IDX_W-1:0]    vrf_wr_addr_o,
    output logic                    vrf_wr_en_o,
    output logic [LANE_NUM-1:0]     vrf_wr_bank_en_o,
    output logic                    vrf_wr_req_o,

    // ── Result ──────────────────────────────────────────────────────────────
    output logic                    result_valid_o,
    output logic [63:0]             result_data_o
);

    // ── Controller Start Pulses ────────────────────────────────────────────
    logic clear_start, bind_start, sim_start, perm_start, cntadd_start, cntclip_start, match_start;

    // ── Controller Done / Status ────────────────────────────────────────────
    logic [6:0] ctrl_done;
    logic [6:0] ctrl_busy;
    logic [1:0] clear_status, bind_status, sim_status, perm_status, cntadd_status, cntclip_status, match_status;

    always_comb begin
        // Defaults
        clear_start   = 1'b0; bind_start = 1'b0; sim_start = 1'b0;
        perm_start    = 1'b0; cntadd_start = 1'b0; cntclip_start = 1'b0;
        match_start   = 1'b0;
        decode_ready_o = 1'b1;

        result_valid_o = 1'b0;
        result_data_o  = 64'b0;

        // Route based on opcode
        if (decode_valid_i) begin
            unique case (decode_op_i)
                HDEC_HCLR, HDEC_HCNTCLR: clear_start    = 1'b1;
                HDEC_HBIND:              bind_start     = 1'b1;
                HDEC_HSIM:               sim_start      = 1'b1;
                HDEC_HPERM:              perm_start     = 1'b1;
                HDEC_HCNTADD:            cntadd_start   = 1'b1;
                HDEC_HCNTCLIP:           cntclip_start  = 1'b1;
                HDEC_HMATCH:             match_start    = 1'b1;
                default: ;
            endcase
        end

        // OR-reduce all done signals for result
        if (|ctrl_done) begin
            result_valid_o = 1'b1;
            // Return NOT_IMPLEMENTED for placeholders, OK for clear
            if (ctrl_done[0])                         // clear_ctrl
                result_data_o = {62'b0, clear_status};
            else if (ctrl_done[1] || ctrl_done[2] || ctrl_done[3] ||
                     ctrl_done[4] || ctrl_done[5] || ctrl_done[6])
                result_data_o = {62'b0, STATUS_NOT_IMPLEMENTED};
        end
    end

    // ── 0: Clear Controller (hclr / hcntclr) ───────────────────────────────
    hdec_hdc_clear_ctrl i_clear (
        .clk_i, .rst_ni,
        .start_i     (clear_start),
        .busy_o      (ctrl_busy[0]),
        .done_o      (ctrl_done[0]),
        .status_o    (clear_status),
        .opcode_i    (decode_op_i),
        .base_slot_i (decode_wr_reg_i),
        .vrf_wr_addr_o (vrf_wr_addr_o),
        .vrf_wr_en_o   (vrf_wr_en_o),
        .vrf_wr_bank_en_o (vrf_wr_bank_en_o),
        .vrf_wr_req_o (vrf_wr_req_o)
    );

    // ── 1-6: HDC Placeholder Controllers ────────────────────────────────────
    logic dummy_vrf_rd, dummy_vrf_wr;

    hdec_hdc_bind_ctrl   i_bind   (.clk_i,.rst_ni,.start_i(bind_start),   .busy_o(ctrl_busy[1]),.done_o(ctrl_done[1]),.status_o(bind_status),    .opcode_i(decode_op_i),.src_slot_i(decode_rd_reg_i),.dst_slot_i(decode_wr_reg_i),.chunk_idx_i('0),.vrf_rd_req_o(dummy_vrf_rd),.vrf_wr_req_o(dummy_vrf_wr));
    hdec_hdc_sim_ctrl    i_sim    (.clk_i,.rst_ni,.start_i(sim_start),    .busy_o(ctrl_busy[2]),.done_o(ctrl_done[2]),.status_o(sim_status),     .opcode_i(decode_op_i),.src_slot_i(decode_rd_reg_i),.dst_slot_i(decode_wr_reg_i),.chunk_idx_i('0),.vrf_rd_req_o(dummy_vrf_rd),.vrf_wr_req_o(dummy_vrf_wr));
    hdec_hdc_perm_ctrl   i_perm   (.clk_i,.rst_ni,.start_i(perm_start),   .busy_o(ctrl_busy[3]),.done_o(ctrl_done[3]),.status_o(perm_status),    .opcode_i(decode_op_i),.src_slot_i(decode_rd_reg_i),.dst_slot_i(decode_wr_reg_i),.chunk_idx_i('0),.vrf_rd_req_o(dummy_vrf_rd),.vrf_wr_req_o(dummy_vrf_wr));
    hdec_hdc_bundle_ctrl i_cntadd (.clk_i,.rst_ni,.start_i(cntadd_start), .busy_o(ctrl_busy[4]),.done_o(ctrl_done[4]),.status_o(cntadd_status),  .opcode_i(decode_op_i),.src_slot_i(decode_rd_reg_i),.dst_slot_i(decode_wr_reg_i),.chunk_idx_i('0),.vrf_rd_req_o(dummy_vrf_rd),.vrf_wr_req_o(dummy_vrf_wr));
    hdec_hdc_clip_ctrl   i_cntclip(.clk_i,.rst_ni,.start_i(cntclip_start),.busy_o(ctrl_busy[5]),.done_o(ctrl_done[5]),.status_o(cntclip_status), .opcode_i(decode_op_i),.src_slot_i(decode_rd_reg_i),.dst_slot_i(decode_wr_reg_i),.chunk_idx_i('0),.vrf_rd_req_o(dummy_vrf_rd),.vrf_wr_req_o(dummy_vrf_wr));
    hdec_hdc_search_ctrl i_match  (.clk_i,.rst_ni,.start_i(match_start),  .busy_o(ctrl_busy[6]),.done_o(ctrl_done[6]),.status_o(match_status),   .opcode_i(decode_op_i),.src_slot_i(decode_rd_reg_i),.dst_slot_i(decode_wr_reg_i),.chunk_idx_i('0),.vrf_rd_req_o(dummy_vrf_rd),.vrf_wr_req_o(dummy_vrf_wr));

endmodule
