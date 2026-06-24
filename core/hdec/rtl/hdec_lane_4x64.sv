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
    parameter int LANE_ID = 0,   // 0, 1, 2, or 3
    parameter bit ENABLE_ECC_REDUCE = 1'b1
) (
    input  logic                              clk_i,
    input  logic                              rst_ni,

    // ── XOR Front-End Compute Path ──────────────────────────────────────────
    input  logic [1:0]                        bool_tag_i,
    input  logic                              pop_en_i,
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
    // ── Clip Compute Path (HDC counter non-zero predicate) ──────────────────
    input  logic [LANE_WIDTH-1:0]             clip_counter_i,
    output logic [15:0]                       clip_bits_o,

    input  logic [31:0]                       ecc_diag_a_i,
    input  logic [31:0]                       ecc_diag_b_i,
    output logic [7:0]                        ecc_diag_parity_o,
    output logic [7:0]                        ecc_diag_pop_parity_o
);

    // ── XOR Front-End Core ──────────────────────────────────────────────────
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

    function automatic logic ecc_diag32_line_pop_parity(
        input logic [31:0] a_word,
        input logic [31:0] b_word,
        input int unsigned diag_idx
    );
        logic [31:0] terms;
        begin
            terms = '0;
            for (int unsigned bit_idx = 0; bit_idx < 32; bit_idx++) begin
                if ((diag_idx >= bit_idx) && ((diag_idx - bit_idx) < 32))
                    terms[bit_idx] = a_word[bit_idx] & b_word[diag_idx - bit_idx];
            end
            ecc_diag32_line_pop_parity = ^terms;
        end
    endfunction

    function automatic logic [31:0] ecc_bitrev32_local(input logic [31:0] word);
        ecc_bitrev32_local = {word[0],  word[1],  word[2],  word[3],
                              word[4],  word[5],  word[6],  word[7],
                              word[8],  word[9],  word[10], word[11],
                              word[12], word[13], word[14], word[15],
                              word[16], word[17], word[18], word[19],
                              word[20], word[21], word[22], word[23],
                              word[24], word[25], word[26], word[27],
                              word[28], word[29], word[30], word[31]};
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

    function automatic logic [7:0] ecc_diag32_oct_pop_parity(
        input logic [31:0] a_word,
        input logic [31:0] b_word
    );
        begin
            ecc_diag32_oct_pop_parity = {
                (LANE_ID == 3) ? 1'b0 : ecc_diag32_line_pop_parity(a_word, b_word, 16 + LANE_ID * 4 + 3),
                ecc_diag32_line_pop_parity(a_word, b_word, 16 + LANE_ID * 4 + 2),
                ecc_diag32_line_pop_parity(a_word, b_word, 16 + LANE_ID * 4 + 1),
                ecc_diag32_line_pop_parity(a_word, b_word, 16 + LANE_ID * 4),
                ecc_diag32_line_pop_parity(a_word, b_word, LANE_ID * 4 + 3),
                ecc_diag32_line_pop_parity(a_word, b_word, LANE_ID * 4 + 2),
                ecc_diag32_line_pop_parity(a_word, b_word, LANE_ID * 4 + 1),
                ecc_diag32_line_pop_parity(a_word, b_word, LANE_ID * 4)};
        end
    endfunction

    assign bool_result_q_o = bool_result_q;
    assign bool_xor_word = bool_src_a_i ^ bool_src_b_i;
    assign bool_product_word = bool_src_a_i & bool_src_b_i;
    generate
        if (ENABLE_ECC_REDUCE) begin : gen_ecc_reduce_word
            assign ecc_reduce_word_o = ecc_reduce_src_a_i ^ ecc_reduce_src_b_i
                                   ^ bool_src_c_i ^ bool_src_d_i;
        end else begin : gen_no_ecc_reduce_word
            assign ecc_reduce_word_o = '0;
        end
    endgenerate
    assign popcount_part_count[0] = 6'($countones(bool_result_q[31:0]));
    assign popcount_part_count[1] = 6'($countones(bool_result_q[63:32]));

    assign ecc_diag_parity_o =
        ecc_diag32_oct_parity(ecc_diag_a_i, ecc_diag_b_i);
    assign ecc_diag_pop_parity_o =
        ecc_diag32_oct_pop_parity(ecc_bitrev32_local(ecc_diag_a_i),
                                  ecc_bitrev32_local(ecc_diag_b_i));

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            bool_result_q     <= '0;
            popcount_part_q_o <= '0;
        end else begin
            if (bool_tag_i[0])
                bool_result_q <= bool_product_word;
            else if (bool_tag_i[1])
                bool_result_q <= bool_xor_word;
            if (pop_en_i)
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
    // ── Clip Core ──────────────────────────────────────────────────────────
    hdec_lane_clip i_clip (
        .counter_i  (clip_counter_i),
        .bits_o     (clip_bits_o)
    );

endmodule

// Aggressive vector payload fabric:
// one P2/P3 payload register for HBIND, HSIM/HMATCH, HCNTADD, HCNTCLIP and
// HPERM, while the actual math remains four 64-bit slices.
module hdec_vector_payload_4x64
    import hdec_pkg::*;
    import hdec_resource_pkg::*;
#(
    parameter bit ENABLE_ECC_REDUCE = 1'b1
) (
    input  logic                                clk_i,
    input  logic                                rst_ni,

    input  logic                                payload_xor_i,
    input  logic                                payload_pop_i,
    input  logic                                payload_cnt_i,
    input  logic                                payload_clip_i,
    input  logic                                hperm_we_i,
    input  logic [1:0]                          hperm_slot_i,
    input  logic [LANE_WIDTH-1:0]               hperm_word_i,

    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0] bool_src_a_i,
    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0] bool_src_b_i,
    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0] bool_src_c_i,
    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0] bool_src_d_i,
    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0] ecc_reduce_src_a_i,
    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0] ecc_reduce_src_b_i,

    output logic [LANE_NUM-1:0][LANE_WIDTH-1:0] payload_q_o,
    output logic [LANE_NUM-1:0][LANE_WIDTH-1:0] ecc_reduce_word_o,

    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0] cnt_hv_word_i,
    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0] cnt_old_counter_i,
    input  logic [1:0]                          cnt_subgroup_i,

    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0] clip_counter_i,

    input  logic [31:0]                         ecc_diag_a_i,
    input  logic [31:0]                         ecc_diag_b_i,
    output logic [LANE_NUM-1:0][7:0]            ecc_diag_parity_o,
    output logic [LANE_NUM-1:0][7:0]            ecc_diag_pop_parity_o
);

    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] bool_xor_word;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] bool_product_word;
    logic [LANE_NUM-1:0][1:0][5:0]       popcount_part_count;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] cnt_new_counter;
    logic [LANE_NUM-1:0][15:0]           clip_bits;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] payload_q;

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

    function automatic logic ecc_diag32_line_pop_parity(
        input logic [31:0] a_word,
        input logic [31:0] b_word,
        input int unsigned diag_idx
    );
        logic [31:0] terms;
        begin
            terms = '0;
            for (int unsigned bit_idx = 0; bit_idx < 32; bit_idx++) begin
                if ((diag_idx >= bit_idx) && ((diag_idx - bit_idx) < 32))
                    terms[bit_idx] = a_word[bit_idx] & b_word[diag_idx - bit_idx];
            end
            ecc_diag32_line_pop_parity = ^terms;
        end
    endfunction

    function automatic logic [31:0] ecc_bitrev32_local(input logic [31:0] word);
        ecc_bitrev32_local = {word[0],  word[1],  word[2],  word[3],
                              word[4],  word[5],  word[6],  word[7],
                              word[8],  word[9],  word[10], word[11],
                              word[12], word[13], word[14], word[15],
                              word[16], word[17], word[18], word[19],
                              word[20], word[21], word[22], word[23],
                              word[24], word[25], word[26], word[27],
                              word[28], word[29], word[30], word[31]};
    endfunction

    assign payload_q_o = payload_q;

    for (genvar lid = 0; lid < LANE_NUM; lid++) begin : gen_payload_slice
        assign bool_xor_word[lid] = bool_src_a_i[lid] ^ bool_src_b_i[lid];
        assign bool_product_word[lid] = bool_src_a_i[lid] & bool_src_b_i[lid];
        assign popcount_part_count[lid][0] = 6'($countones(bool_product_word[lid][31:0]));
        assign popcount_part_count[lid][1] = 6'($countones(bool_product_word[lid][63:32]));

        hdec_cnt_array i_cnt_array (
            .old_counter_i   (cnt_old_counter_i[lid]),
            .hv_word_i       (cnt_hv_word_i[lid]),
            .subgroup_i      (cnt_subgroup_i),
            .new_counter_o   (cnt_new_counter[lid])
        );

        hdec_lane_clip i_clip (
            .counter_i  (clip_counter_i[lid]),
            .bits_o     (clip_bits[lid])
        );

        assign ecc_diag_parity_o[lid] = {
            ecc_diag32_line_parity(ecc_diag_a_i, ecc_diag_b_i, 16 + lid * 4 + 3),
            ecc_diag32_line_parity(ecc_diag_a_i, ecc_diag_b_i, 16 + lid * 4 + 2),
            ecc_diag32_line_parity(ecc_diag_a_i, ecc_diag_b_i, 16 + lid * 4 + 1),
            ecc_diag32_line_parity(ecc_diag_a_i, ecc_diag_b_i, 16 + lid * 4),
            ecc_diag32_line_parity(ecc_diag_a_i, ecc_diag_b_i, lid * 4 + 3),
            ecc_diag32_line_parity(ecc_diag_a_i, ecc_diag_b_i, lid * 4 + 2),
            ecc_diag32_line_parity(ecc_diag_a_i, ecc_diag_b_i, lid * 4 + 1),
            ecc_diag32_line_parity(ecc_diag_a_i, ecc_diag_b_i, lid * 4)};
        assign ecc_diag_pop_parity_o[lid] = {
            (lid == 3) ? 1'b0 : ecc_diag32_line_pop_parity(ecc_bitrev32_local(ecc_diag_a_i), ecc_bitrev32_local(ecc_diag_b_i), 16 + lid * 4 + 3),
            ecc_diag32_line_pop_parity(ecc_bitrev32_local(ecc_diag_a_i), ecc_bitrev32_local(ecc_diag_b_i), 16 + lid * 4 + 2),
            ecc_diag32_line_pop_parity(ecc_bitrev32_local(ecc_diag_a_i), ecc_bitrev32_local(ecc_diag_b_i), 16 + lid * 4 + 1),
            ecc_diag32_line_pop_parity(ecc_bitrev32_local(ecc_diag_a_i), ecc_bitrev32_local(ecc_diag_b_i), 16 + lid * 4),
            ecc_diag32_line_pop_parity(ecc_bitrev32_local(ecc_diag_a_i), ecc_bitrev32_local(ecc_diag_b_i), lid * 4 + 3),
            ecc_diag32_line_pop_parity(ecc_bitrev32_local(ecc_diag_a_i), ecc_bitrev32_local(ecc_diag_b_i), lid * 4 + 2),
            ecc_diag32_line_pop_parity(ecc_bitrev32_local(ecc_diag_a_i), ecc_bitrev32_local(ecc_diag_b_i), lid * 4 + 1),
            ecc_diag32_line_pop_parity(ecc_bitrev32_local(ecc_diag_a_i), ecc_bitrev32_local(ecc_diag_b_i), lid * 4)};
    end

    generate
        if (ENABLE_ECC_REDUCE) begin : gen_ecc_reduce_word_payload
            for (genvar lid = 0; lid < LANE_NUM; lid++) begin : gen_reduce_slice
                assign ecc_reduce_word_o[lid] = ecc_reduce_src_a_i[lid] ^ ecc_reduce_src_b_i[lid]
                                             ^ bool_src_c_i[lid] ^ bool_src_d_i[lid];
            end
        end else begin : gen_no_ecc_reduce_word_payload
            assign ecc_reduce_word_o = '0;
        end
    endgenerate

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            payload_q <= '0;
        end else if (hperm_we_i) begin
            payload_q[hperm_slot_i] <= hperm_word_i;
        end else if (payload_xor_i) begin
            payload_q <= bool_xor_word;
        end else if (payload_pop_i) begin
            for (int lid = 0; lid < LANE_NUM; lid++) begin
                payload_q[lid] <= {52'b0, popcount_part_count[lid][1], popcount_part_count[lid][0]};
            end
        end else if (payload_cnt_i) begin
            payload_q <= cnt_new_counter;
        end else if (payload_clip_i) begin
            for (int lid = 0; lid < LANE_NUM; lid++) begin
                payload_q[lid] <= {48'b0, clip_bits[lid]};
            end
        end
    end

endmodule

// 256-bit vector-facing fabric, implemented as four 64-bit compute slices.
// This removes the lane wrapper/control boundary from hdec_top while keeping
// the physically small 64-bit local operators.
module hdec_vector_4x64
    import hdec_pkg::*;
    import hdec_resource_pkg::*;
#(
    parameter bit ENABLE_ECC_REDUCE = 1'b1
) (
    input  logic                              clk_i,
    input  logic                              rst_ni,

    input  logic [1:0]                        bool_tag_i,
    input  logic                              pop_en_i,
    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0] bool_src_a_i,
    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0] bool_src_b_i,
    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0] bool_src_c_i,
    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0] bool_src_d_i,
    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0] ecc_reduce_src_a_i,
    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0] ecc_reduce_src_b_i,
    output logic [LANE_NUM-1:0][LANE_WIDTH-1:0] bool_result_q_o,
    output logic [LANE_NUM-1:0][LANE_WIDTH-1:0] ecc_reduce_word_o,

    output logic [LANE_NUM-1:0][1:0][5:0]     popcount_part_q_o,

    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0] cnt_hv_word_i,
    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0] cnt_old_counter_i,
    input  logic [1:0]                        cnt_subgroup_i,
    output logic [LANE_NUM-1:0][LANE_WIDTH-1:0] cnt_new_counter_o,

    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0] clip_counter_i,
    output logic [LANE_NUM-1:0][15:0]         clip_bits_o,

    input  logic [31:0]                       ecc_diag_a_i,
    input  logic [31:0]                       ecc_diag_b_i,
    output logic [LANE_NUM-1:0][7:0]          ecc_diag_parity_o,
    output logic [LANE_NUM-1:0][7:0]          ecc_diag_pop_parity_o
);

    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] bool_xor_word;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] bool_product_word;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] bool_result_q;
    logic [LANE_NUM-1:0][1:0][5:0]       popcount_part_count;

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

    function automatic logic ecc_diag32_line_pop_parity(
        input logic [31:0] a_word,
        input logic [31:0] b_word,
        input int unsigned diag_idx
    );
        logic [31:0] terms;
        begin
            terms = '0;
            for (int unsigned bit_idx = 0; bit_idx < 32; bit_idx++) begin
                if ((diag_idx >= bit_idx) && ((diag_idx - bit_idx) < 32))
                    terms[bit_idx] = a_word[bit_idx] & b_word[diag_idx - bit_idx];
            end
            ecc_diag32_line_pop_parity = ^terms;
        end
    endfunction

    function automatic logic [31:0] ecc_bitrev32_local(input logic [31:0] word);
        ecc_bitrev32_local = {word[0],  word[1],  word[2],  word[3],
                              word[4],  word[5],  word[6],  word[7],
                              word[8],  word[9],  word[10], word[11],
                              word[12], word[13], word[14], word[15],
                              word[16], word[17], word[18], word[19],
                              word[20], word[21], word[22], word[23],
                              word[24], word[25], word[26], word[27],
                              word[28], word[29], word[30], word[31]};
    endfunction

    function automatic logic [7:0] ecc_diag32_oct_parity(
        input int unsigned lane_id,
        input logic [31:0] a_word,
        input logic [31:0] b_word
    );
        begin
            ecc_diag32_oct_parity = {
                ecc_diag32_line_parity(a_word, b_word, 16 + lane_id * 4 + 3),
                ecc_diag32_line_parity(a_word, b_word, 16 + lane_id * 4 + 2),
                ecc_diag32_line_parity(a_word, b_word, 16 + lane_id * 4 + 1),
                ecc_diag32_line_parity(a_word, b_word, 16 + lane_id * 4),
                ecc_diag32_line_parity(a_word, b_word, lane_id * 4 + 3),
                ecc_diag32_line_parity(a_word, b_word, lane_id * 4 + 2),
                ecc_diag32_line_parity(a_word, b_word, lane_id * 4 + 1),
                ecc_diag32_line_parity(a_word, b_word, lane_id * 4)};
        end
    endfunction

    function automatic logic [7:0] ecc_diag32_oct_pop_parity(
        input int unsigned lane_id,
        input logic [31:0] a_word,
        input logic [31:0] b_word
    );
        begin
            ecc_diag32_oct_pop_parity = {
                (lane_id == 3) ? 1'b0 : ecc_diag32_line_pop_parity(a_word, b_word, 16 + lane_id * 4 + 3),
                ecc_diag32_line_pop_parity(a_word, b_word, 16 + lane_id * 4 + 2),
                ecc_diag32_line_pop_parity(a_word, b_word, 16 + lane_id * 4 + 1),
                ecc_diag32_line_pop_parity(a_word, b_word, 16 + lane_id * 4),
                ecc_diag32_line_pop_parity(a_word, b_word, lane_id * 4 + 3),
                ecc_diag32_line_pop_parity(a_word, b_word, lane_id * 4 + 2),
                ecc_diag32_line_pop_parity(a_word, b_word, lane_id * 4 + 1),
                ecc_diag32_line_pop_parity(a_word, b_word, lane_id * 4)};
        end
    endfunction

    assign bool_result_q_o = bool_result_q;

    for (genvar lid = 0; lid < LANE_NUM; lid++) begin : gen_slice
        assign bool_xor_word[lid] = bool_src_a_i[lid] ^ bool_src_b_i[lid];
        assign bool_product_word[lid] = bool_src_a_i[lid] & bool_src_b_i[lid];
        assign popcount_part_count[lid][0] = 6'($countones(bool_result_q[lid][31:0]));
        assign popcount_part_count[lid][1] = 6'($countones(bool_result_q[lid][63:32]));

        hdec_cnt_array i_cnt_array (
            .old_counter_i   (cnt_old_counter_i[lid]),
            .hv_word_i       (cnt_hv_word_i[lid]),
            .subgroup_i      (cnt_subgroup_i),
            .new_counter_o   (cnt_new_counter_o[lid])
        );

        hdec_lane_clip i_clip (
            .counter_i  (clip_counter_i[lid]),
            .bits_o     (clip_bits_o[lid])
        );

        always_ff @(posedge clk_i or negedge rst_ni) begin
            if (!rst_ni) begin
                bool_result_q[lid]     <= '0;
                popcount_part_q_o[lid] <= '0;
            end else begin
                if (bool_tag_i[0])
                    bool_result_q[lid] <= bool_product_word[lid];
                else if (bool_tag_i[1])
                    bool_result_q[lid] <= bool_xor_word[lid];
                if (pop_en_i)
                    popcount_part_q_o[lid] <= popcount_part_count[lid];
            end
        end

        assign ecc_diag_parity_o[lid] = {
            ecc_diag32_line_parity(ecc_diag_a_i, ecc_diag_b_i, 16 + lid * 4 + 3),
            ecc_diag32_line_parity(ecc_diag_a_i, ecc_diag_b_i, 16 + lid * 4 + 2),
            ecc_diag32_line_parity(ecc_diag_a_i, ecc_diag_b_i, 16 + lid * 4 + 1),
            ecc_diag32_line_parity(ecc_diag_a_i, ecc_diag_b_i, 16 + lid * 4),
            ecc_diag32_line_parity(ecc_diag_a_i, ecc_diag_b_i, lid * 4 + 3),
            ecc_diag32_line_parity(ecc_diag_a_i, ecc_diag_b_i, lid * 4 + 2),
            ecc_diag32_line_parity(ecc_diag_a_i, ecc_diag_b_i, lid * 4 + 1),
            ecc_diag32_line_parity(ecc_diag_a_i, ecc_diag_b_i, lid * 4)};
        assign ecc_diag_pop_parity_o[lid] = {
            (lid == 3) ? 1'b0 : ecc_diag32_line_pop_parity(ecc_bitrev32_local(ecc_diag_a_i), ecc_bitrev32_local(ecc_diag_b_i), 16 + lid * 4 + 3),
            ecc_diag32_line_pop_parity(ecc_bitrev32_local(ecc_diag_a_i), ecc_bitrev32_local(ecc_diag_b_i), 16 + lid * 4 + 2),
            ecc_diag32_line_pop_parity(ecc_bitrev32_local(ecc_diag_a_i), ecc_bitrev32_local(ecc_diag_b_i), 16 + lid * 4 + 1),
            ecc_diag32_line_pop_parity(ecc_bitrev32_local(ecc_diag_a_i), ecc_bitrev32_local(ecc_diag_b_i), 16 + lid * 4),
            ecc_diag32_line_pop_parity(ecc_bitrev32_local(ecc_diag_a_i), ecc_bitrev32_local(ecc_diag_b_i), lid * 4 + 3),
            ecc_diag32_line_pop_parity(ecc_bitrev32_local(ecc_diag_a_i), ecc_bitrev32_local(ecc_diag_b_i), lid * 4 + 2),
            ecc_diag32_line_pop_parity(ecc_bitrev32_local(ecc_diag_a_i), ecc_bitrev32_local(ecc_diag_b_i), lid * 4 + 1),
            ecc_diag32_line_pop_parity(ecc_bitrev32_local(ecc_diag_a_i), ecc_bitrev32_local(ecc_diag_b_i), lid * 4)};
    end

    generate
        if (ENABLE_ECC_REDUCE) begin : gen_ecc_reduce_word_vec
            for (genvar lid = 0; lid < LANE_NUM; lid++) begin : gen_reduce_slice
                assign ecc_reduce_word_o[lid] = ecc_reduce_src_a_i[lid] ^ ecc_reduce_src_b_i[lid]
                                             ^ bool_src_c_i[lid] ^ bool_src_d_i[lid];
            end
        end else begin : gen_no_ecc_reduce_word_vec
            assign ecc_reduce_word_o = '0;
        end
    endgenerate

endmodule
