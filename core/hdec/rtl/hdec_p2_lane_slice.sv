// =============================================================================
// hdec_p2_lane_slice.sv - Lane-local P2 control, compute, and P2/P3 capture
// =============================================================================

module hdec_p2_lane_slice
    import hdec_pkg::*;
    import hdec_resource_pkg::*;
#(
    parameter int LANE_ID = 0
) (
    input  logic                          clk_i,
    input  logic                          rst_ni,
    input  hdec_p2_lane_ctrl_t            p2_lane_ctrl_d_i,

    input  logic [LANE_WIDTH-1:0]         bool_src_a_i,
    input  logic [LANE_WIDTH-1:0]         bool_src_b_i,
    input  logic [LANE_WIDTH-1:0]         cnt_hv_word_i,
    input  logic [LANE_WIDTH-1:0]         cnt_old_counter_i,
    input  logic [LANE_WIDTH-1:0]         shift_src_a_i,
    input  logic [LANE_WIDTH-1:0]         shift_src_b_i,
    input  logic [LANE_WIDTH-1:0]         clip_counter_i,

    output logic [LANE_WIDTH-1:0]         lane_vec64_q_o,
    output logic [6:0]                    lane_pop7_q_o,
    output logic [15:0]                   lane_clip16_q_o
);

    hdec_p2_lane_ctrl_t p2_lane_ctrl_q;

    logic bool_valid;
    logic [LANE_WIDTH-1:0] bool_result;
    logic [6:0] popcount_count;
    logic [LANE_WIDTH-1:0] cnt_new_counter;
    logic [LANE_WIDTH-1:0] shift_result;
    logic [15:0] clip_bits;
    logic [LANE_WIDTH-1:0] vec64_result;
    logic [LANE_WIDTH-1:0] lane_result_q;
    logic [6:0] lane_popcnt_q;
    logic [15:0] lane_clip_q;

    assign lane_vec64_q_o = lane_result_q;
    assign lane_pop7_q_o = lane_popcnt_q;
    assign lane_clip16_q_o = lane_clip_q;

    assign bool_valid = p2_lane_ctrl_q.do_xor_only |
                        p2_lane_ctrl_q.do_popcount_diff;

    assign vec64_result =
        ({LANE_WIDTH{p2_lane_ctrl_q.do_xor_only}} & bool_result) |
        ({LANE_WIDTH{p2_lane_ctrl_q.do_counter}}  & cnt_new_counter) |
        ({LANE_WIDTH{p2_lane_ctrl_q.do_shift}}    & shift_result);

    hdec_lane_4x64 #(.LANE_ID(LANE_ID)) i_lane (
        .clk_i,
        .rst_ni,
        .vrf_ra_addr_o(),
        .vrf_ra_data_i('0),
        .vrf_we_o(),
        .vrf_wa_addr_o(),
        .vrf_wdata_o(),
        .ctrl_valid_i('0),
        .ctrl_ready_o(),
        .ctrl_owner_i('0),
        .ctrl_op_i(HDEC_VWR64),
        .ctrl_rd_reg_i('0),
        .ctrl_wr_reg_i('0),
        .ctrl_wr_data_i('0),
        .ctrl_is_write_i('0),
        .ctrl_is_read_i('0),
        .res_valid_o(),
        .res_ready_i('0),
        .res_data_o(),
        .res_owner_o(),
        .neighbor_in_i('0),
        .neighbor_out_o(),
        .carry_in_i('0),
        .carry_out_o(),
        .borrow_in_i('0),
        .borrow_out_o(),
        .count_in_i('0),
        .count_out_o(),
        .flag_in_i('0),
        .flag_out_o(),
        .local_wb_data_o(),
        .local_wb_addr_o(),
        .local_wb_we_o(),
        .bool_valid_i(bool_valid),
        .bool_src_a_i(bool_src_a_i),
        .bool_src_b_i(bool_src_b_i),
        .bool_result_o(bool_result),
        .popcount_count_o(popcount_count),
        .cnt_valid_i(p2_lane_ctrl_q.do_counter),
        .cnt_hv_word_i(cnt_hv_word_i),
        .cnt_old_counter_i(cnt_old_counter_i),
        .cnt_subgroup_i(p2_lane_ctrl_q.subgroup),
        .cnt_new_counter_o(cnt_new_counter),
        .shift_valid_i(p2_lane_ctrl_q.do_shift),
        .shift_src_a_i(shift_src_a_i),
        .shift_src_b_i(shift_src_b_i),
        .shift_nibble_i(p2_lane_ctrl_q.perm_nibble),
        .shift_result_o(shift_result),
        .clip_valid_i(p2_lane_ctrl_q.do_clip),
        .clip_counter_i(clip_counter_i),
        .clip_threshold_i(p2_lane_ctrl_q.threshold),
        .clip_bits_o(clip_bits)
    );

`ifndef SYNTHESIS
    always_comb begin
        assert ($onehot0({
            p2_lane_ctrl_q.do_xor_only,
            p2_lane_ctrl_q.do_popcount_diff,
            p2_lane_ctrl_q.do_counter,
            p2_lane_ctrl_q.do_clip,
            p2_lane_ctrl_q.do_shift
        })) else $error("HDEC lane %0d P2 compute control is not one-hot", LANE_ID);

        assert ($onehot0({
            p2_lane_ctrl_q.capture_vec,
            p2_lane_ctrl_q.capture_pop,
            p2_lane_ctrl_q.capture_clip
        })) else $error("HDEC lane %0d P2 capture control is not one-hot", LANE_ID);

        assert (!(p2_lane_ctrl_q.capture_vec &&
                  !(p2_lane_ctrl_q.do_xor_only ||
                    p2_lane_ctrl_q.do_counter ||
                    p2_lane_ctrl_q.do_shift)));
        assert (p2_lane_ctrl_q.capture_pop ==
                p2_lane_ctrl_q.do_popcount_diff);
        assert (p2_lane_ctrl_q.capture_clip ==
                p2_lane_ctrl_q.do_clip);
    end
`endif

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            p2_lane_ctrl_q <= '0;
            lane_result_q <= '0;
            lane_popcnt_q <= '0;
            lane_clip_q <= '0;
        end else begin
            p2_lane_ctrl_q <= p2_lane_ctrl_d_i;
            if (p2_lane_ctrl_q.capture_vec)
                lane_result_q <= vec64_result;
            if (p2_lane_ctrl_q.capture_pop)
                lane_popcnt_q <= popcount_count;
            if (p2_lane_ctrl_q.capture_clip)
                lane_clip_q <= clip_bits;
        end
    end

endmodule
