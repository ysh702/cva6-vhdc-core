// =============================================================================
// hdec_lane_4x64.sv — 64-bit Lane Shell with HDCU Static Function Blocks
// =============================================================================
// HDCU Phase: XOR, popcount, CNT array update, clip, shift-align.
// No bundle, no add/sub counter, no BMCA.
// =============================================================================

module hdec_lane_4x64
    import hdec_pkg::*;
    import hdec_resource_pkg::*;
#(
    parameter int LANE_ID = 0   // 0, 1, 2, or 3
) (
    input  logic        clk_i,
    input  logic        rst_ni,

    // ── VRF Bank Connection (this lane ↔ its bank) ──────────────────────────
    output logic [VRF_IDX_W-1:0]              vrf_ra_addr_o,
    input  logic [LANE_WIDTH-1:0]             vrf_ra_data_i,
    output logic                              vrf_we_o,
    output logic [VRF_IDX_W-1:0]              vrf_wa_addr_o,
    output logic [LANE_WIDTH-1:0]             vrf_wdata_o,

    // ── Control Interface (from engine / cmd_decode) ────────────────────────
    input  logic                              ctrl_valid_i,
    output logic                              ctrl_ready_o,
    input  logic [1:0]                        ctrl_owner_i,
    input  hdec_op_t                          ctrl_op_i,
    input  logic [VRF_IDX_W-1:0]              ctrl_rd_reg_i,
    input  logic [VRF_IDX_W-1:0]              ctrl_wr_reg_i,
    input  logic [LANE_WIDTH-1:0]             ctrl_wr_data_i,
    input  logic                              ctrl_is_write_i,
    input  logic                              ctrl_is_read_i,

    // ── Result Interface (to engine) ────────────────────────────────────────
    output logic                              res_valid_o,
    input  logic                              res_ready_i,
    output logic [LANE_WIDTH-1:0]             res_data_o,
    output logic [1:0]                        res_owner_o,

    // ── Neighbor Lane Interface (reserved) ──────────────────────────────────
    input  logic [LANE_WIDTH-1:0]             neighbor_in_i,
    output logic [LANE_WIDTH-1:0]             neighbor_out_o,

    // ── Carry / Borrow / Count / Flag (reserved) ────────────────────────────
    input  logic                              carry_in_i,
    output logic                              carry_out_o,
    input  logic                              borrow_in_i,
    output logic                              borrow_out_o,
    input  logic [6:0]                        count_in_i,
    output logic [6:0]                        count_out_o,
    input  logic                              flag_in_i,
    output logic                              flag_out_o,

    // ── Local Writeback (reserved) ──────────────────────────────────────────
    output logic [LANE_WIDTH-1:0]             local_wb_data_o,
    output logic [VRF_IDX_W-1:0]              local_wb_addr_o,
    output logic                              local_wb_we_o,

    // ── XOR Front-End Compute Path ──────────────────────────────────────────
    input  logic                              bool_valid_i,
    input  logic [LANE_WIDTH-1:0]             bool_src_a_i,
    input  logic [LANE_WIDTH-1:0]             bool_src_b_i,
    output logic [LANE_WIDTH-1:0]             bool_result_o,

    // ── HDC-only popcount path ──────────────────────────────────────────────
    output logic [6:0]                        popcount_count_o,

    // ── HDCU CNT array update path ─────────────────────────────────────────
    input  logic                              cnt_valid_i,
    input  logic [LANE_WIDTH-1:0]             cnt_hv_word_i,
    input  logic [LANE_WIDTH-1:0]             cnt_old_counter_i,
    input  logic [1:0]                        cnt_subgroup_i,
    output logic [LANE_WIDTH-1:0]             cnt_new_counter_o,

    // ── Shift-Align Compute Path (bit-granular, lane-local) ─────────────────
    input  logic                              shift_valid_i,
    input  logic [LANE_WIDTH-1:0]             shift_src_a_i,
    input  logic [LANE_WIDTH-1:0]             shift_src_b_i,
    input  logic [5:0]                        shift_bit_i,
    output logic [LANE_WIDTH-1:0]             shift_result_o,

    // ── Clip Compute Path (HDC counter threshold) ───────────────────────────
    input  logic                              clip_valid_i,
    input  logic [LANE_WIDTH-1:0]             clip_counter_i,
    input  logic [3:0]                        clip_threshold_i,
    output logic [15:0]                       clip_bits_o
);

    // ── XOR Front-End Core ──────────────────────────────────────────────────
    assign bool_result_o = bool_src_a_i ^ bool_src_b_i;
    assign popcount_count_o = 7'($countones(bool_result_o));

    // ── HDCU CNT array update ──────────────────────────────────────────────
    hdec_cnt_array i_cnt_array (
        .clear_i         (1'b0),
        .update_i        (cnt_valid_i),
        .old_counter_i   (cnt_old_counter_i),
        .hv_word_i       (cnt_hv_word_i),
        .subgroup_i      (cnt_subgroup_i),
        .clip_threshold_i('0),
        .new_counter_o   (cnt_new_counter_o),
        .clip_bits_o     ()
    );

    // ── Shift-Align Core ───────────────────────────────────────────────────
    hdec_lane_shift_align i_shift_align (
        .src_a_i       (shift_src_a_i),
        .src_b_i       (shift_src_b_i),
        .bit_shift_i   (shift_bit_i),
        .result_o      (shift_result_o)
    );

    // ── Clip Core ──────────────────────────────────────────────────────────
    hdec_lane_clip i_clip (
        .counter_i  (clip_counter_i),
        .threshold_i(clip_threshold_i),
        .bits_o     (clip_bits_o)
    );

    // The top-level HDEC pipeline uses only the static function blocks above.
    // The old per-lane command shell is intentionally tied off here.
    assign ctrl_ready_o    = 1'b1;
    assign res_valid_o     = 1'b0;
    assign res_data_o      = '0;
    assign res_owner_o     = OWNER_NONE;

    assign vrf_ra_addr_o   = '0;
    assign vrf_we_o        = 1'b0;
    assign vrf_wa_addr_o   = '0;
    assign vrf_wdata_o     = '0;

    assign neighbor_out_o  = neighbor_in_i;
    assign carry_out_o     = 1'b0;
    assign borrow_out_o    = 1'b0;
    assign count_out_o     = '0;
    assign flag_out_o      = 1'b0;

    assign local_wb_data_o = '0;
    assign local_wb_addr_o = '0;
    assign local_wb_we_o   = 1'b0;

endmodule
