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
    input  logic                              clk_i,
    input  logic                              rst_ni,

    // ── XOR Front-End Compute Path ──────────────────────────────────────────
    input  logic [2:0]                        bool_tag_i,
    input  logic [LANE_WIDTH-1:0]             bool_src_a_i,
    input  logic [LANE_WIDTH-1:0]             bool_src_b_i,
    input  logic [LANE_WIDTH-1:0]             bool_src_c_i,
    input  logic [LANE_WIDTH-1:0]             bool_src_d_i,
    input  logic [LANE_WIDTH-1:0]             ecc_reduce_src_a_i,
    input  logic [LANE_WIDTH-1:0]             ecc_reduce_src_b_i,
    output logic [LANE_WIDTH-1:0]             bool_result_q_o,
    output logic [LANE_WIDTH-1:0]             ecc_reduce_word_o,

    // ── HDC-only popcount path ──────────────────────────────────────────────
    output logic [1:0][5:0]                   popcount_part_q_o,

    // ── HDCU CNT array update path ─────────────────────────────────────────
    input  logic [LANE_WIDTH-1:0]             cnt_hv_word_i,
    input  logic [LANE_WIDTH-1:0]             cnt_old_counter_i,
    input  logic [1:0]                        cnt_subgroup_i,
    output logic [LANE_WIDTH-1:0]             cnt_new_counter_o,

    // ── Shift-Align Compute Path (bit-granular, lane-local) ─────────────────
    input  logic [LANE_WIDTH-1:0]             shift_src_a_i,
    input  logic [LANE_WIDTH-1:0]             shift_src_b_i,
    input  logic [5:0]                        shift_bit_i,
    output logic [LANE_WIDTH-1:0]             shift_result_o,

    // ── Clip Compute Path (HDC counter non-zero predicate) ──────────────────
    input  logic [LANE_WIDTH-1:0]             clip_counter_i,
    output logic [15:0]                       clip_bits_o,

    input  logic [31:0]                       ecc_diag_a_i,
    input  logic [31:0]                       ecc_diag_b_i,
    output logic [7:0]                        ecc_diag_parity_o
);

    // ── XOR Front-End Core ──────────────────────────────────────────────────
    logic        pop_q;
    logic [LANE_WIDTH-1:0] bool_xor_word;
    logic [LANE_WIDTH-1:0] bool_product_word;
    logic [63:0] bool_result_q;
    logic [1:0][5:0] popcount_part_count;

    function automatic logic ecc_diag32_line_parity(
        input logic [31:0] a_word,
        input logic [31:0] b_word,
        input int unsigned diag_idx
    );
        logic parity;
        begin
            parity = 1'b0;
            for (int unsigned bit_idx = 0; bit_idx < 32; bit_idx++) begin
                if ((diag_idx >= bit_idx) && ((diag_idx - bit_idx) < 32))
                    parity ^= a_word[bit_idx] & b_word[diag_idx - bit_idx];
            end
            ecc_diag32_line_parity = parity;
        end
    endfunction

    function automatic logic [1:0] ecc_diag32_even_parity(
        input logic [31:0] a_word,
        input logic [31:0] b_word,
        input logic [1:0]  slot_group
    );
        begin
            unique case (slot_group)
            2'd0: ecc_diag32_even_parity = {ecc_diag32_line_parity(a_word, b_word, LANE_ID * 2 + 1),
                                            ecc_diag32_line_parity(a_word, b_word, LANE_ID * 2)};
            2'd1: ecc_diag32_even_parity = {ecc_diag32_line_parity(a_word, b_word, 16 + LANE_ID * 2 + 1),
                                            ecc_diag32_line_parity(a_word, b_word, 16 + LANE_ID * 2)};
            2'd2: ecc_diag32_even_parity = {ecc_diag32_line_parity(a_word, b_word, 32 + LANE_ID * 2 + 1),
                                            ecc_diag32_line_parity(a_word, b_word, 32 + LANE_ID * 2)};
            default: ecc_diag32_even_parity = {ecc_diag32_line_parity(a_word, b_word, 48 + LANE_ID * 2 + 1),
                                               ecc_diag32_line_parity(a_word, b_word, 48 + LANE_ID * 2)};
            endcase
        end
    endfunction

    function automatic logic [1:0] ecc_diag32_pair_parity(
        input logic [31:0] a_word,
        input logic [31:0] b_word,
        input logic [1:0]  slot_group
    );
        begin
            unique case (slot_group)
            2'd0: ecc_diag32_pair_parity = {ecc_diag32_line_parity(a_word, b_word, 8 + LANE_ID * 2 + 1),
                                            ecc_diag32_line_parity(a_word, b_word, 8 + LANE_ID * 2)};
            2'd1: ecc_diag32_pair_parity = {ecc_diag32_line_parity(a_word, b_word, 24 + LANE_ID * 2 + 1),
                                            ecc_diag32_line_parity(a_word, b_word, 24 + LANE_ID * 2)};
            2'd2: ecc_diag32_pair_parity = {ecc_diag32_line_parity(a_word, b_word, 40 + LANE_ID * 2 + 1),
                                            ecc_diag32_line_parity(a_word, b_word, 40 + LANE_ID * 2)};
            default: ecc_diag32_pair_parity = {ecc_diag32_line_parity(a_word, b_word, 56 + LANE_ID * 2 + 1),
                                               ecc_diag32_line_parity(a_word, b_word, 56 + LANE_ID * 2)};
            endcase
        end
    endfunction

    function automatic logic [3:0] ecc_diag32_quad_parity(
        input logic [31:0] a_word,
        input logic [31:0] b_word,
        input logic [1:0]  slot_group
    );
        begin
            unique case (slot_group)
            2'd0: ecc_diag32_quad_parity = {
                ecc_diag32_line_parity(a_word, b_word, 8 + LANE_ID * 2 + 1),
                ecc_diag32_line_parity(a_word, b_word, 8 + LANE_ID * 2),
                ecc_diag32_line_parity(a_word, b_word, LANE_ID * 2 + 1),
                ecc_diag32_line_parity(a_word, b_word, LANE_ID * 2)};
            2'd1: ecc_diag32_quad_parity = {
                ecc_diag32_line_parity(a_word, b_word, 24 + LANE_ID * 2 + 1),
                ecc_diag32_line_parity(a_word, b_word, 24 + LANE_ID * 2),
                ecc_diag32_line_parity(a_word, b_word, 16 + LANE_ID * 2 + 1),
                ecc_diag32_line_parity(a_word, b_word, 16 + LANE_ID * 2)};
            2'd2: ecc_diag32_quad_parity = {
                ecc_diag32_line_parity(a_word, b_word, 40 + LANE_ID * 2 + 1),
                ecc_diag32_line_parity(a_word, b_word, 40 + LANE_ID * 2),
                ecc_diag32_line_parity(a_word, b_word, 32 + LANE_ID * 2 + 1),
                ecc_diag32_line_parity(a_word, b_word, 32 + LANE_ID * 2)};
            default: ecc_diag32_quad_parity = {
                ecc_diag32_line_parity(a_word, b_word, 56 + LANE_ID * 2 + 1),
                ecc_diag32_line_parity(a_word, b_word, 56 + LANE_ID * 2),
                ecc_diag32_line_parity(a_word, b_word, 48 + LANE_ID * 2 + 1),
                ecc_diag32_line_parity(a_word, b_word, 48 + LANE_ID * 2)};
            endcase
        end
    endfunction

    function automatic logic [7:0] ecc_diag32_oct_parity(
        input logic [31:0] a_word,
        input logic [31:0] b_word
    );
        begin
            ecc_diag32_oct_parity = {
                ecc_diag32_line_parity(a_word, b_word, 16 + LANE_ID * 4 + 3),
                ecc_diag32_line_parity(a_word, b_word, 16 + LANE_ID * 4 + 2),
                ecc_diag32_line_parity(a_word, b_word, 16 + LANE_ID * 4 + 1),
                ecc_diag32_line_parity(a_word, b_word, 16 + LANE_ID * 4),
                ecc_diag32_line_parity(a_word, b_word, LANE_ID * 4 + 3),
                ecc_diag32_line_parity(a_word, b_word, LANE_ID * 4 + 2),
                ecc_diag32_line_parity(a_word, b_word, LANE_ID * 4 + 1),
                ecc_diag32_line_parity(a_word, b_word, LANE_ID * 4)};
        end
    endfunction

    assign bool_result_q_o = bool_result_q;
    assign bool_xor_word = bool_src_a_i ^ bool_src_b_i;
    assign bool_product_word = bool_src_a_i & bool_src_b_i;
    assign ecc_reduce_word_o = ecc_reduce_src_a_i ^ ecc_reduce_src_b_i
                             ^ bool_src_c_i ^ bool_src_d_i;
    assign popcount_part_count[0] = 6'($countones(bool_result_q[31:0]));
    assign popcount_part_count[1] = 6'($countones(bool_result_q[63:32]));

    assign ecc_diag_parity_o =
        ecc_diag32_oct_parity(ecc_diag_a_i, ecc_diag_b_i);

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            pop_q             <= 1'b0;
            bool_result_q     <= '0;
            popcount_part_q_o <= '0;
        end else begin
            pop_q <= bool_tag_i[2];
            if (bool_tag_i[0])
                bool_result_q <= bool_product_word;
            else if (bool_tag_i[1])
                bool_result_q <= bool_xor_word;
            if (pop_q)
                popcount_part_q_o <= popcount_part_count;
        end
    end

    // ── HDCU CNT array update ──────────────────────────────────────────────
    hdec_cnt_array i_cnt_array (
        .old_counter_i   (cnt_old_counter_i),
        .hv_word_i       (cnt_hv_word_i),
        .subgroup_i      (cnt_subgroup_i),
        .new_counter_o   (cnt_new_counter_o)
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
        .bits_o     (clip_bits_o)
    );

endmodule
