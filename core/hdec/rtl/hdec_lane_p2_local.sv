// =============================================================================
// hdec_lane_p2_local.sv - P2 lane-local decode wrapper
// =============================================================================
// Keeps hdec_top as a sequencer: TOP sends compact lane_ctrl plus payloads,
// this wrapper derives the local core valid signals near hdec_lane_4x64.
// =============================================================================

module hdec_lane_p2_local
    import hdec_pkg::*;
    import hdec_resource_pkg::*;
#(
    parameter int LANE_ID = 0
) (
    input  logic                    clk_i,
    input  logic                    rst_ni,

    input  hdec_lane_ctrl_t         lane_ctrl_i,

    input  logic [LANE_WIDTH-1:0]   bool_src_a_i,
    input  logic [LANE_WIDTH-1:0]   bool_src_b_i,

    input  logic [LANE_WIDTH-1:0]   cnt_hv_word_i,
    input  logic [LANE_WIDTH-1:0]   cnt_old_counter_i,

    input  logic [LANE_WIDTH-1:0]   shift_src_a_i,
    input  logic [LANE_WIDTH-1:0]   shift_src_b_i,

    input  logic [LANE_WIDTH-1:0]   clip_counter_i,

    output logic [LANE_WIDTH-1:0]   vec64_result_o,
    output logic [6:0]              pop7_result_o,
    output logic [15:0]             clip16_result_o
);

    logic bool_valid;
    logic cnt_valid;
    logic shift_valid;
    logic clip_valid;

    logic [LANE_WIDTH-1:0] bool_result;
    logic [LANE_WIDTH-1:0] cnt_result;
    logic [LANE_WIDTH-1:0] shift_result;
    logic [6:0]            pop7_result;
    logic [15:0]           clip16_result;

    assign bool_valid  = lane_ctrl_i.valid &&
                         ((lane_ctrl_i.op == HDEC_LANE_XOR) ||
                          (lane_ctrl_i.op == HDEC_LANE_POPCOUNT_DIFF));
    assign cnt_valid   = lane_ctrl_i.valid && (lane_ctrl_i.op == HDEC_LANE_CNTADD);
    assign shift_valid = lane_ctrl_i.valid && (lane_ctrl_i.op == HDEC_LANE_SHIFT);
    assign clip_valid  = lane_ctrl_i.valid && (lane_ctrl_i.op == HDEC_LANE_CLIP);

    hdec_lane_4x64 #(.LANE_ID(LANE_ID)) i_lane (
        .clk_i, .rst_ni,
        .vrf_ra_addr_o(), .vrf_ra_data_i('0),
        .vrf_we_o(), .vrf_wa_addr_o(), .vrf_wdata_o(),
        .ctrl_valid_i('0), .ctrl_ready_o(), .ctrl_owner_i('0), .ctrl_op_i(HDEC_VWR64),
        .ctrl_rd_reg_i('0), .ctrl_wr_reg_i('0), .ctrl_wr_data_i('0),
        .ctrl_is_write_i('0), .ctrl_is_read_i('0),
        .res_valid_o(), .res_ready_i('0), .res_data_o(), .res_owner_o(),
        .neighbor_in_i('0), .neighbor_out_o(), .carry_in_i('0), .carry_out_o(),
        .borrow_in_i('0), .borrow_out_o(), .count_in_i('0), .count_out_o(),
        .flag_in_i('0), .flag_out_o(), .local_wb_data_o(), .local_wb_addr_o(),
        .local_wb_we_o(),
        .bool_valid_i(bool_valid),
        .bool_src_a_i(bool_src_a_i),
        .bool_src_b_i(bool_src_b_i),
        .bool_result_o(bool_result),
        .popcount_count_o(pop7_result),
        .cnt_valid_i(cnt_valid),
        .cnt_hv_word_i(cnt_hv_word_i),
        .cnt_old_counter_i(cnt_old_counter_i),
        .cnt_subgroup_i(lane_ctrl_i.subgroup),
        .cnt_new_counter_o(cnt_result),
        .shift_valid_i(shift_valid),
        .shift_src_a_i(shift_src_a_i),
        .shift_src_b_i(shift_src_b_i),
        .shift_nibble_i(lane_ctrl_i.perm),
        .shift_result_o(shift_result),
        .clip_valid_i(clip_valid),
        .clip_counter_i(clip_counter_i),
        .clip_threshold_i(lane_ctrl_i.threshold),
        .clip_bits_o(clip16_result)
    );

    always_comb begin
        unique case (lane_ctrl_i.op)
            HDEC_LANE_XOR:    vec64_result_o = bool_result;
            HDEC_LANE_CNTADD: vec64_result_o = cnt_result;
            HDEC_LANE_SHIFT:  vec64_result_o = shift_result;
            default:          vec64_result_o = '0;
        endcase
    end

    assign pop7_result_o  = pop7_result;
    assign clip16_result_o = clip16_result;

endmodule
