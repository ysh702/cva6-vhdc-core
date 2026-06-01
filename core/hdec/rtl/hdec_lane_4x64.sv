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

    // ── Lane-local Typed Result Fabric ─────────────────────────────────────
    input  hdec_lane_mode_e                   lane_mode_i,
    output logic [LANE_WIDTH-1:0]             lane_vec_result_o,
    output logic [15:0]                       lane_narrow_result_o,

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

    // ── Shift-Align Compute Path (4-bit granular, lane-local) ───────────────
    input  logic                              shift_valid_i,
    input  logic [LANE_WIDTH-1:0]             shift_src_a_i,
    input  logic [LANE_WIDTH-1:0]             shift_src_b_i,
    input  logic [3:0]                        shift_nibble_i,
    output logic [LANE_WIDTH-1:0]             shift_result_o,

    // ── Clip Compute Path (HDC counter threshold) ───────────────────────────
    input  logic                              clip_valid_i,
    input  logic [LANE_WIDTH-1:0]             clip_counter_i,
    input  logic [3:0]                        clip_threshold_i,
    output logic [15:0]                       clip_bits_o
);

    // ── XOR Front-End Core ──────────────────────────────────────────────────
    logic bool_active;
    logic [LANE_WIDTH-1:0] bool_src_a, bool_src_b;
    assign bool_active = bool_valid_i &&
                         ((lane_mode_i == HDEC_LANE_MODE_XOR) ||
                          (lane_mode_i == HDEC_LANE_MODE_POPCOUNT));
    assign bool_src_a = bool_active ? bool_src_a_i : '0;
    assign bool_src_b = bool_active ? bool_src_b_i : '0;

    logic [LANE_WIDTH-1:0] bool_result;

    hdec_lane_boolean_mask i_boolean_mask (
        .src_a_i (bool_src_a),
        .src_b_i (bool_src_b),
        .result_o(bool_result)
    );

    assign bool_result_o = bool_result;
    logic [6:0] popcount_count;
    assign popcount_count = 7'($countones(bool_result));
    assign popcount_count_o = popcount_count;

    // ── HDCU CNT array update ──────────────────────────────────────────────
    logic cnt_active;
    logic [LANE_WIDTH-1:0] cnt_hv_word, cnt_old_counter;
    logic [1:0]            cnt_subgroup;
    logic [LANE_WIDTH-1:0] cnt_new_counter;
    assign cnt_active      = cnt_valid_i && (lane_mode_i == HDEC_LANE_MODE_COUNTER);
    assign cnt_hv_word     = cnt_active ? cnt_hv_word_i     : '0;
    assign cnt_old_counter = cnt_active ? cnt_old_counter_i : '0;
    assign cnt_subgroup    = cnt_active ? cnt_subgroup_i    : '0;

    hdec_cnt_array i_cnt_array (
        .clear_i         (1'b0),
        .update_i        (cnt_active),
        .old_counter_i   (cnt_old_counter),
        .hv_word_i       (cnt_hv_word),
        .subgroup_i      (cnt_subgroup),
        .clip_threshold_i('0),
        .new_counter_o   (cnt_new_counter),
        .clip_bits_o     ()
    );
    assign cnt_new_counter_o = cnt_new_counter;

    // ── Shift-Align Core ───────────────────────────────────────────────────
    logic shift_active;
    logic [LANE_WIDTH-1:0] shift_src_a, shift_src_b;
    logic [3:0]            shift_nibble;
    logic [LANE_WIDTH-1:0] shift_result;
    assign shift_active = shift_valid_i && (lane_mode_i == HDEC_LANE_MODE_SHIFT);
    assign shift_src_a  = shift_active ? shift_src_a_i  : '0;
    assign shift_src_b  = shift_active ? shift_src_b_i  : '0;
    assign shift_nibble = shift_active ? shift_nibble_i : '0;

    hdec_lane_shift_align i_shift_align (
        .src_a_i       (shift_src_a),
        .src_b_i       (shift_src_b),
        .nibble_shift_i(shift_nibble),
        .result_o      (shift_result)
    );
    assign shift_result_o = shift_result;

    // ── Clip Core ──────────────────────────────────────────────────────────
    logic clip_active;
    logic [LANE_WIDTH-1:0] clip_counter;
    logic [3:0]            clip_threshold;
    logic [15:0]           clip_bits;
    assign clip_active    = clip_valid_i && (lane_mode_i == HDEC_LANE_MODE_CLIP);
    assign clip_counter   = clip_active ? clip_counter_i   : '0;
    assign clip_threshold = clip_active ? clip_threshold_i : '0;

    hdec_lane_clip i_clip (
        .counter_i  (clip_counter),
        .threshold_i(clip_threshold),
        .bits_o     (clip_bits)
    );
    assign clip_bits_o = clip_bits;

    // ── Lane-local Typed Result Selection ──────────────────────────────────
    always_comb begin
        lane_vec_result_o    = '0;
        lane_narrow_result_o = '0;
        unique case (lane_mode_i)
        HDEC_LANE_MODE_XOR:
            lane_vec_result_o = bool_result;
        HDEC_LANE_MODE_POPCOUNT:
            lane_narrow_result_o = {9'b0, popcount_count};
        HDEC_LANE_MODE_COUNTER:
            lane_vec_result_o = cnt_new_counter;
        HDEC_LANE_MODE_CLIP:
            lane_narrow_result_o = clip_bits;
        HDEC_LANE_MODE_SHIFT:
            lane_vec_result_o = shift_result;
        default: begin
            lane_vec_result_o    = '0;
            lane_narrow_result_o = '0;
        end
        endcase
    end

    // ── Legacy Passthrough Shell Registers ──────────────────────────────────
    typedef enum logic [2:0] { LS_IDLE, LS_P0, LS_P1, LS_P2, LS_P3 } lane_state_t;
    lane_state_t lane_state_q, lane_state_n;

    // Passthrough slot 0
    logic [LANE_WIDTH-1:0] p0_data_q, p0_data_d;
    hdec_op_t              p0_op_q,   p0_op_d;
    logic [1:0]            p0_owner_q, p0_owner_d;

    // Passthrough slot 1
    logic [LANE_WIDTH-1:0] p1_data_q, p1_data_d;
    hdec_op_t              p1_op_q,   p1_op_d;
    logic [1:0]            p1_owner_q, p1_owner_d;

    // Passthrough slot 2
    logic [LANE_WIDTH-1:0] p2_data_q, p2_data_d;
    hdec_op_t              p2_op_q,   p2_op_d;
    logic [1:0]            p2_owner_q, p2_owner_d;

    // Passthrough slot 3
    logic [LANE_WIDTH-1:0] p3_data_q, p3_data_d;
    logic [1:0]            p3_owner_q, p3_owner_d;

    // ── Combinational ───────────────────────────────────────────────────────
    always_comb begin
        lane_state_n = lane_state_q;
        ctrl_ready_o = 1'b0;
        res_valid_o  = 1'b0;

        // Pipeline defaults: hold
        p0_data_d  = p0_data_q;   p0_op_d    = p0_op_q;   p0_owner_d  = p0_owner_q;
        p1_data_d  = p1_data_q;   p1_op_d    = p1_op_q;   p1_owner_d  = p1_owner_q;
        p2_data_d  = p2_data_q;   p2_op_d    = p2_op_q;   p2_owner_d  = p2_owner_q;
        p3_data_d  = p3_data_q;   p3_owner_d = p3_owner_q;

        // VRF defaults
        vrf_ra_addr_o = '0;  vrf_we_o = 1'b0;  vrf_wa_addr_o = '0;  vrf_wdata_o = '0;

        // Reserved port defaults
        neighbor_out_o = neighbor_in_i;   // passthrough
        carry_out_o    = '0;  borrow_out_o = '0;  count_out_o = '0;  flag_out_o = '0;
        local_wb_data_o = '0; local_wb_addr_o = '0; local_wb_we_o = '0;
        res_data_o      = '0; res_owner_o = OWNER_NONE;

        // ── FSM ────────────────────────────────────────────────────────────
        case (lane_state_q)
            LS_IDLE: begin
                ctrl_ready_o = 1'b1;
                if (ctrl_valid_i) begin
                    if (ctrl_is_write_i) begin
                        vrf_we_o      = 1'b1;
                        vrf_wa_addr_o = ctrl_wr_reg_i;
                        vrf_wdata_o   = ctrl_wr_data_i;
                    end
                    if (ctrl_is_read_i) begin
                        vrf_ra_addr_o = ctrl_rd_reg_i;
                    end
                    p0_data_d   = ctrl_is_read_i ? vrf_ra_data_i : ctrl_wr_data_i;
                    p0_op_d     = ctrl_op_i;
                    p0_owner_d  = ctrl_owner_i;
                    lane_state_n = LS_P0;
                end
            end

            LS_P0: begin
                p1_data_d   = p0_data_q;
                p1_op_d     = p0_op_q;
                p1_owner_d  = p0_owner_q;
                lane_state_n = LS_P1;
            end

            LS_P1: begin
                p2_data_d   = p1_data_q;
                p2_op_d     = p1_op_q;
                p2_owner_d  = p1_owner_q;
                lane_state_n = LS_P2;
            end

            LS_P2: begin
                p3_data_d   = p2_data_q;
                p3_owner_d  = p2_owner_q;
                lane_state_n = LS_P3;
            end

            LS_P3: begin
                res_valid_o  = 1'b1;
                res_data_o   = p3_data_q;
                res_owner_o  = p3_owner_q;
                if (res_ready_i)
                    lane_state_n = LS_IDLE;
            end

            default: lane_state_n = LS_IDLE;
        endcase
    end

    // ── Sequential ──────────────────────────────────────────────────────────
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            lane_state_q <= LS_IDLE;
            p0_data_q  <= '0;  p0_op_q  <= HDEC_VWR64;  p0_owner_q  <= OWNER_NONE;
            p1_data_q  <= '0;  p1_op_q  <= HDEC_VWR64;  p1_owner_q  <= OWNER_NONE;
            p2_data_q  <= '0;  p2_op_q  <= HDEC_VWR64;  p2_owner_q  <= OWNER_NONE;
            p3_data_q  <= '0;                        p3_owner_q  <= OWNER_NONE;
        end else begin
            lane_state_q <= lane_state_n;
            p0_data_q  <= p0_data_d;   p0_op_q   <= p0_op_d;   p0_owner_q  <= p0_owner_d;
            p1_data_q  <= p1_data_d;   p1_op_q   <= p1_op_d;   p1_owner_q  <= p1_owner_d;
            p2_data_q  <= p2_data_d;   p2_op_q   <= p2_op_d;   p2_owner_q  <= p2_owner_d;
            p3_data_q  <= p3_data_d;                             p3_owner_q  <= p3_owner_d;
        end
    end

endmodule
