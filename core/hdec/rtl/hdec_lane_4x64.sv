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

package hdec_vv25_equation_pkg;

    localparam int HDEC_VV25_BYTE_SOURCE_BASE = 256;
    localparam int HDEC_VV25_BYTE_PAIR_SOURCE_BASE = 288;
    localparam int HDEC_VV25_SHORT_PARITY_SOURCE_BASE = 304;
    localparam int HDEC_VV25_TAIL_PARITY_SOURCE_BASE = 318;
    localparam int HDEC_VV25_NODE_SOURCE_BASE = 326;
    localparam int HDEC_VV25_XOR_NODE_COUNT = 14;

    // Seven rows pair a short diagonal with the complementary tail of a long
    // diagonal.  The final row carries D7, D23 and the two halves of D15.
    // Every 16x16 partial product appears exactly once in these 32 bytes.
    localparam int HDEC_VV25_MATRIX_DIAG [0:255] = '{
        14,14,14,14,14,14,14,14,0,14,14,14,14,14,14,14,
        16,16,16,16,16,16,16,16,30,16,16,16,16,16,16,16,
        13,13,13,13,13,13,13,13,1,1,13,13,13,13,13,13,
        17,17,17,17,17,17,17,17,29,29,17,17,17,17,17,17,
        12,12,12,12,12,12,12,12,2,2,2,12,12,12,12,12,
        18,18,18,18,18,18,18,18,28,28,28,18,18,18,18,18,
        11,11,11,11,11,11,11,11,3,3,3,3,11,11,11,11,
        19,19,19,19,19,19,19,19,27,27,27,27,19,19,19,19,
        10,10,10,10,10,10,10,10,4,4,4,4,4,10,10,10,
        20,20,20,20,20,20,20,20,26,26,26,26,26,20,20,20,
        9,9,9,9,9,9,9,9,5,5,5,5,5,5,9,9,
        21,21,21,21,21,21,21,21,25,25,25,25,25,25,21,21,
        8,8,8,8,8,8,8,8,6,6,6,6,6,6,6,8,
        22,22,22,22,22,22,22,22,24,24,24,24,24,24,24,22,
        7,7,7,7,7,7,7,7,23,23,23,23,23,23,23,23,
        15,15,15,15,15,15,15,15,15,15,15,15,15,15,15,15
    };

    localparam int HDEC_VV25_MATRIX_TERM [0:255] = '{
        0,1,2,3,4,5,6,7,0,8,9,10,11,12,13,14,
        0,1,2,3,4,5,6,7,0,8,9,10,11,12,13,14,
        0,1,2,3,4,5,6,7,0,1,8,9,10,11,12,13,
        0,1,2,3,4,5,6,7,0,1,8,9,10,11,12,13,
        0,1,2,3,4,5,6,7,0,1,2,8,9,10,11,12,
        0,1,2,3,4,5,6,7,0,1,2,8,9,10,11,12,
        0,1,2,3,4,5,6,7,0,1,2,3,8,9,10,11,
        0,1,2,3,4,5,6,7,0,1,2,3,8,9,10,11,
        0,1,2,3,4,5,6,7,0,1,2,3,4,8,9,10,
        0,1,2,3,4,5,6,7,0,1,2,3,4,8,9,10,
        0,1,2,3,4,5,6,7,0,1,2,3,4,5,8,9,
        0,1,2,3,4,5,6,7,0,1,2,3,4,5,8,9,
        0,1,2,3,4,5,6,7,0,1,2,3,4,5,6,8,
        0,1,2,3,4,5,6,7,0,1,2,3,4,5,6,8,
        0,1,2,3,4,5,6,7,0,1,2,3,4,5,6,7,
        0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15
    };

    // Sources select registered matrix bits (0..255), byte parities
    // (256..287), row-count byte-pair parities (288..303), fourteen short
    // section parities from the real mixed-byte POPCOUNTs (304..317), eight
    // tail-section parities (318..325), or native XOR1 nodes (326+).
    localparam int HDEC_VV25_XOR_NODE_LHS [0:13] = '{
        288,289,290,291,292,293,294,295,272,274,298,299,280,282
    };

    localparam int HDEC_VV25_XOR_NODE_RHS [0:13] = '{
        304,305,306,307,308,309,310,311,320,321,314,315,324,325
    };

    localparam int HDEC_VV25_DIAG_SOURCE [0:30] = '{
        304,306,308,310,312,314,316,284,338,336,334,332,330,328,326,303,
        327,329,331,333,335,337,339,285,317,315,313,311,309,307,305
    };

    function automatic int hdec_vv25_diag_len(input int diag_idx);
        if (diag_idx < 16)
            hdec_vv25_diag_len = diag_idx + 1;
        else
            hdec_vv25_diag_len = 31 - diag_idx;
    endfunction

    function automatic int hdec_vv25_matrix_diag(input int flat_idx);
        hdec_vv25_matrix_diag = HDEC_VV25_MATRIX_DIAG[flat_idx];
    endfunction

    function automatic int hdec_vv25_matrix_term(input int flat_idx);
        hdec_vv25_matrix_term = HDEC_VV25_MATRIX_TERM[flat_idx];
    endfunction

    function automatic int hdec_vv25_xor_node_lhs(input int node_idx);
        hdec_vv25_xor_node_lhs = HDEC_VV25_XOR_NODE_LHS[node_idx];
    endfunction

    function automatic int hdec_vv25_xor_node_rhs(input int node_idx);
        hdec_vv25_xor_node_rhs = HDEC_VV25_XOR_NODE_RHS[node_idx];
    endfunction

    function automatic int hdec_vv25_diag_source(input int diag_idx);
        hdec_vv25_diag_source = HDEC_VV25_DIAG_SOURCE[diag_idx];
    endfunction

endpackage

// The native XOR1 body has no HDC/ECC mode and no third operand.  Every node
// is exactly the original two-input XOR; operand selection lives outside it.
module hdec_xor1_native_224 (
    input  logic [223:0] lhs_i,
    input  logic [223:0] rhs_i,
    output logic [223:0] node_o
);
    for (genvar node_idx = 0; node_idx < 224; node_idx++) begin : gen_native_xor_node
        assign node_o[node_idx] = lhs_i[node_idx] ^ rhs_i[node_idx];
    end
endmodule

// One physical native XOR1 array.  The wrapper only selects its operands.
// In VV25, all 32 POPCOUNT-byte parities and short native-XOR1 corrections
// jointly solve complementary short/long diagonal pairs.
module hdec_xor1_shared_8x32
    import hdec_pkg::*;
    import hdec_resource_pkg::*;
    import hdec_vv25_equation_pkg::*;
(
    input  logic                     diag_mode_i,
    input  logic [7:0][31:0]         matrix_product_i,
    input  logic [31:0]              pop_byte_parity_i,
    input  logic [15:0]              pop_byte_pair_parity_i,
    input  logic [13:0]              pop_short_parity_i,
    input  logic [7:0]               pop_tail_parity_i,

    input  logic [127:0] legacy_acc_i,
    input  logic [63:0]  legacy_sub_product_i,
    input  logic [1:0]   legacy_sub_idx_i,
    input  logic [31:0]  legacy_leaf_a_i,
    input  logic [31:0]  legacy_leaf_xor_a_i,
    input  logic [31:0]  legacy_leaf_b_i,
    input  logic [31:0]  legacy_leaf_xor_b_i,

    output logic [30:0]  diag16_product_o,
    output logic [127:0] legacy_accum_o,
    output logic [31:0]  legacy_lowxor_a_o,
    output logic [31:0]  legacy_lowxor_b_o
);

    logic [223:0] legacy_lhs;
    logic [223:0] legacy_rhs;
    logic [223:0] xor_node;
    logic [223:0] native_lhs;
    logic [223:0] native_rhs;
    logic [127:0] legacy_acc_rhs;

    logic [HDEC_VV25_XOR_NODE_COUNT-1:0] diag_node_lhs;
    logic [HDEC_VV25_XOR_NODE_COUNT-1:0] diag_node_rhs;
    logic [HDEC_VV25_XOR_NODE_COUNT-1:0] diag_node;

    // Exact VV22 behavior.  Nodes 0..31 compute sub_hi^sub_lo once and both
    // possible middle rows reuse it.  Nodes 32..159 fold into the accumulator;
    // nodes 160..223 are the original leaf-A/leaf-B low-XOR paths.
    always_comb begin
        legacy_lhs = '0;
        legacy_rhs = '0;
        legacy_acc_rhs = '0;

        for (int bit_idx = 0; bit_idx < 32; bit_idx++) begin
            legacy_lhs[bit_idx] = legacy_sub_product_i[bit_idx];
            legacy_rhs[bit_idx] = legacy_sub_product_i[32 + bit_idx];
        end

        unique case (legacy_sub_idx_i)
            2'd0: legacy_acc_rhs = {
                32'b0, legacy_sub_product_i[63:32], xor_node[31:0],
                legacy_sub_product_i[31:0]
            };
            2'd1: legacy_acc_rhs = {
                legacy_sub_product_i[63:32], xor_node[31:0],
                legacy_sub_product_i[31:0], 32'b0
            };
            2'd2: legacy_acc_rhs = {
                32'b0, legacy_sub_product_i[63:32],
                legacy_sub_product_i[31:0], 32'b0
            };
            default: legacy_acc_rhs = '0;
        endcase

        for (int bit_idx = 0; bit_idx < 128; bit_idx++) begin
            legacy_lhs[32 + bit_idx] = legacy_acc_i[bit_idx];
            legacy_rhs[32 + bit_idx] = legacy_acc_rhs[bit_idx];
        end
        for (int bit_idx = 0; bit_idx < 32; bit_idx++) begin
            legacy_lhs[160 + bit_idx] = legacy_leaf_a_i[bit_idx];
            legacy_rhs[160 + bit_idx] = legacy_leaf_xor_a_i[bit_idx];
            legacy_lhs[192 + bit_idx] = legacy_leaf_b_i[bit_idx];
            legacy_rhs[192 + bit_idx] = legacy_leaf_xor_b_i[bit_idx];
        end
    end

    // A diagonal output is a fixed alias of one registered matrix bit, one
    // real POPCOUNT intermediate, or one earlier native XOR1 node.  No
    // separate ECC reduction operator exists outside the shared units.
    for (genvar diag_idx = 0; diag_idx < 31; diag_idx++) begin : gen_diag_output
        localparam int DIAG_SOURCE = hdec_vv25_diag_source(diag_idx);
        if (DIAG_SOURCE < HDEC_VV25_BYTE_SOURCE_BASE) begin : gen_matrix_source
            assign diag16_product_o[diag_idx] =
                matrix_product_i[DIAG_SOURCE / 32][DIAG_SOURCE % 32];
        end else if (DIAG_SOURCE < HDEC_VV25_BYTE_PAIR_SOURCE_BASE) begin : gen_byte_source
            assign diag16_product_o[diag_idx] =
                pop_byte_parity_i[DIAG_SOURCE - HDEC_VV25_BYTE_SOURCE_BASE];
        end else if (DIAG_SOURCE < HDEC_VV25_SHORT_PARITY_SOURCE_BASE) begin : gen_pair_source
            assign diag16_product_o[diag_idx] =
                pop_byte_pair_parity_i[
                    DIAG_SOURCE - HDEC_VV25_BYTE_PAIR_SOURCE_BASE
                ];
        end else if (DIAG_SOURCE < HDEC_VV25_TAIL_PARITY_SOURCE_BASE) begin : gen_short_source
            assign diag16_product_o[diag_idx] =
                pop_short_parity_i[
                    DIAG_SOURCE - HDEC_VV25_SHORT_PARITY_SOURCE_BASE
                ];
        end else if (DIAG_SOURCE < HDEC_VV25_NODE_SOURCE_BASE) begin : gen_tail_source
            assign diag16_product_o[diag_idx] =
                pop_tail_parity_i[
                    DIAG_SOURCE - HDEC_VV25_TAIL_PARITY_SOURCE_BASE
                ];
        end else begin : gen_node_source
            assign diag16_product_o[diag_idx] =
                diag_node[DIAG_SOURCE - HDEC_VV25_NODE_SOURCE_BASE];
        end
    end

    for (genvar logical_node = 0;
         logical_node < HDEC_VV25_XOR_NODE_COUNT;
         logical_node++) begin : gen_diag_node_wires
        localparam int LHS_SOURCE = hdec_vv25_xor_node_lhs(logical_node);
        localparam int RHS_SOURCE = hdec_vv25_xor_node_rhs(logical_node);
        if (LHS_SOURCE < HDEC_VV25_BYTE_SOURCE_BASE) begin : gen_lhs_matrix
            assign diag_node_lhs[logical_node] =
                matrix_product_i[LHS_SOURCE / 32][LHS_SOURCE % 32];
        end else if (LHS_SOURCE < HDEC_VV25_BYTE_PAIR_SOURCE_BASE) begin : gen_lhs_byte
            assign diag_node_lhs[logical_node] =
                pop_byte_parity_i[LHS_SOURCE - HDEC_VV25_BYTE_SOURCE_BASE];
        end else if (LHS_SOURCE < HDEC_VV25_SHORT_PARITY_SOURCE_BASE) begin : gen_lhs_pair
            assign diag_node_lhs[logical_node] =
                pop_byte_pair_parity_i[
                    LHS_SOURCE - HDEC_VV25_BYTE_PAIR_SOURCE_BASE
                ];
        end else if (LHS_SOURCE < HDEC_VV25_TAIL_PARITY_SOURCE_BASE) begin : gen_lhs_short
            assign diag_node_lhs[logical_node] =
                pop_short_parity_i[
                    LHS_SOURCE - HDEC_VV25_SHORT_PARITY_SOURCE_BASE
                ];
        end else if (LHS_SOURCE < HDEC_VV25_NODE_SOURCE_BASE) begin : gen_lhs_tail
            assign diag_node_lhs[logical_node] =
                pop_tail_parity_i[
                    LHS_SOURCE - HDEC_VV25_TAIL_PARITY_SOURCE_BASE
                ];
        end else begin : gen_lhs_node
            assign diag_node_lhs[logical_node] =
                diag_node[LHS_SOURCE - HDEC_VV25_NODE_SOURCE_BASE];
        end
        if (RHS_SOURCE < HDEC_VV25_BYTE_SOURCE_BASE) begin : gen_rhs_matrix
            assign diag_node_rhs[logical_node] =
                matrix_product_i[RHS_SOURCE / 32][RHS_SOURCE % 32];
        end else if (RHS_SOURCE < HDEC_VV25_BYTE_PAIR_SOURCE_BASE) begin : gen_rhs_byte
            assign diag_node_rhs[logical_node] =
                pop_byte_parity_i[RHS_SOURCE - HDEC_VV25_BYTE_SOURCE_BASE];
        end else if (RHS_SOURCE < HDEC_VV25_SHORT_PARITY_SOURCE_BASE) begin : gen_rhs_pair
            assign diag_node_rhs[logical_node] =
                pop_byte_pair_parity_i[
                    RHS_SOURCE - HDEC_VV25_BYTE_PAIR_SOURCE_BASE
                ];
        end else if (RHS_SOURCE < HDEC_VV25_TAIL_PARITY_SOURCE_BASE) begin : gen_rhs_short
            assign diag_node_rhs[logical_node] =
                pop_short_parity_i[
                    RHS_SOURCE - HDEC_VV25_SHORT_PARITY_SOURCE_BASE
                ];
        end else if (RHS_SOURCE < HDEC_VV25_NODE_SOURCE_BASE) begin : gen_rhs_tail
            assign diag_node_rhs[logical_node] =
                pop_tail_parity_i[
                    RHS_SOURCE - HDEC_VV25_TAIL_PARITY_SOURCE_BASE
                ];
        end else begin : gen_rhs_node
            assign diag_node_rhs[logical_node] =
                diag_node[RHS_SOURCE - HDEC_VV25_NODE_SOURCE_BASE];
        end
    end

    // Only fourteen native nodes receive diagonal operands.  They occupy an
    // idle part of the middle-XOR bank; the original leaf-A/leaf-B low-XOR
    // nodes therefore remain live in the same cycle and can prepare the next
    // Karatsuba operand pair.
    always_comb begin
        native_lhs = legacy_lhs;
        native_rhs = legacy_rhs;
        for (int logical_node = 0;
             logical_node < HDEC_VV25_XOR_NODE_COUNT;
             logical_node++) begin
            if (diag_mode_i) begin
                native_lhs[logical_node] = diag_node_lhs[logical_node];
                native_rhs[logical_node] = diag_node_rhs[logical_node];
            end
        end
    end

    for (genvar logical_node = 0;
         logical_node < HDEC_VV25_XOR_NODE_COUNT;
         logical_node++) begin : gen_live_node_map
        assign diag_node[logical_node] = xor_node[logical_node];
    end

    hdec_xor1_native_224 i_native_xor1 (
        .lhs_i  (native_lhs),
        .rhs_i  (native_rhs),
        .node_o (xor_node)
    );

    assign legacy_accum_o   = xor_node[159:32];
    assign legacy_lowxor_a_o = xor_node[191:160];
    assign legacy_lowxor_b_o = xor_node[223:192];

endmodule

// Shared GF(2) contribution row tile.
// The physical shape is eight 32-bit rows packed into the existing 4x64 payload.
// HDC chunks and the VV25 16x16 equation matrix both enter as paired rows; the
// operator only sees row-wise bit pairs, not algorithm-specific lane control.
module hdec_gf2_contribution_row_tile_8x32
    import hdec_pkg::*;
    import hdec_resource_pkg::*;
    import hdec_vv25_equation_pkg::*;
(
    input  logic [LANE_NUM*2-1:0][31:0] matrix_src_a_i,
    input  logic [LANE_NUM*2-1:0][31:0] matrix_src_b_i,
    input  logic [LANE_NUM*2-1:0][31:0] matrix_product_q_i,
    input  logic                             xor1_diag_mode_i,
    input  logic [127:0]                     xor1_legacy_acc_i,
    input  logic [63:0]                      xor1_legacy_sub_product_i,
    input  logic [1:0]                       xor1_legacy_sub_idx_i,
    input  logic [31:0]                      xor1_legacy_leaf_a_i,
    input  logic [31:0]                      xor1_legacy_leaf_xor_a_i,
    input  logic [31:0]                      xor1_legacy_leaf_b_i,
    input  logic [31:0]                      xor1_legacy_leaf_xor_b_i,

    output logic [LANE_NUM*2-1:0][31:0] matrix_product_o,
    output logic [LANE_NUM*2-1:0][5:0]  matrix_count_o,
    output logic [LANE_NUM*2-1:0]       matrix_parity_o,
    output logic [30:0]                  diag16_product_o,
    output logic [127:0]                 xor1_legacy_accum_o,
    output logic [31:0]                  xor1_legacy_lowxor_a_o,
    output logic [31:0]                  xor1_legacy_lowxor_b_o
);

    // Eight mixed bytes use short/tail section counts that both feed the
    // normal byte count.  Lengths 1, 2 and 4 keep the balanced HDC tree and
    // expose an already-existing bit/pair/quad LSB.  No ECC-only counter is
    // placed beside the complete 32-bit POPCOUNT.
    logic [LANE_NUM*2-1:0][3:0][3:0]      matrix_byte_count;
    logic [LANE_NUM*2-1:0][1:0][4:0]      matrix_byte_pair_count;
    logic [31:0]                            matrix_byte_parity_flat;
    logic [15:0]                            matrix_byte_pair_parity_flat;
    logic [13:0]                            matrix_short_parity_flat;
    logic [7:0]                             matrix_tail_parity_flat;

    for (genvar rid = 0; rid < LANE_NUM*2; rid++) begin : gen_bitmatrix_row
        assign matrix_product_o[rid] = matrix_src_a_i[rid] & matrix_src_b_i[rid];
        for (genvar byte_idx = 0; byte_idx < 4; byte_idx++) begin : gen_byte_count
            if (((rid == 2) || (rid == 4) || (rid == 5) || (rid == 6))
                && ((byte_idx == 1) || (byte_idx == 3))) begin : gen_partitioned_byte
                localparam int SHORT_LEN = rid + 1;
                localparam int TAIL_LEN = 8 - SHORT_LEN;
                localparam int BYTE_BASE = byte_idx * 8;
                localparam int SIDE = (byte_idx == 3) ? 1 : 0;
                localparam int TAIL_BASE = (rid == 2) ? 0
                                             : (rid == 4) ? 2
                                             : (rid == 5) ? 4 : 6;
                logic [3:0] short_count;
                logic [3:0] tail_count;

                assign short_count = 4'($countones(
                    matrix_product_q_i[rid][BYTE_BASE +: SHORT_LEN]
                ));
                assign tail_count = 4'($countones(
                    matrix_product_q_i[rid][BYTE_BASE + SHORT_LEN +: TAIL_LEN]
                ));
                assign matrix_byte_count[rid][byte_idx] =
                    short_count + tail_count;
                assign matrix_short_parity_flat[rid * 2 + SIDE] =
                    short_count[0];
                assign matrix_tail_parity_flat[TAIL_BASE + SIDE] =
                    tail_count[0];
            end else begin : gen_balanced_byte
                logic [3:0][1:0] bit_pair_count;
                logic [1:0][2:0] quad_count;

                for (genvar pair_idx = 0; pair_idx < 4; pair_idx++) begin : gen_bit_pair_count
                    assign bit_pair_count[pair_idx] =
                        2'(matrix_product_q_i[rid][byte_idx * 8 + pair_idx * 2])
                        + 2'(matrix_product_q_i[rid][byte_idx * 8 + pair_idx * 2 + 1]);
                end
                for (genvar quad_idx = 0; quad_idx < 2; quad_idx++) begin : gen_quad_count
                    assign quad_count[quad_idx] =
                        {1'b0, bit_pair_count[quad_idx * 2]}
                        + {1'b0, bit_pair_count[quad_idx * 2 + 1]};
                end
                assign matrix_byte_count[rid][byte_idx] =
                    {1'b0, quad_count[0]} + {1'b0, quad_count[1]};
                if ((byte_idx == 1) || (byte_idx == 3)) begin : gen_native_short_tap
                    localparam int SIDE = (byte_idx == 3) ? 1 : 0;
                    if (rid == 0) begin : gen_short_len1
                        assign matrix_short_parity_flat[rid * 2 + SIDE] =
                            matrix_product_q_i[rid][byte_idx * 8];
                    end else if (rid == 1) begin : gen_short_len2
                        assign matrix_short_parity_flat[rid * 2 + SIDE] =
                            bit_pair_count[0][0];
                    end else if (rid == 3) begin : gen_short_len4
                        assign matrix_short_parity_flat[rid * 2 + SIDE] =
                            quad_count[0][0];
                    end
                end
            end
            assign matrix_byte_parity_flat[rid * 4 + byte_idx] =
                matrix_byte_count[rid][byte_idx][0];
        end
        for (genvar side = 0; side < 2; side++) begin : gen_byte_pair_count
            assign matrix_byte_pair_count[rid][side] =
                {1'b0, matrix_byte_count[rid][side * 2]}
                + {1'b0, matrix_byte_count[rid][side * 2 + 1]};
            assign matrix_byte_pair_parity_flat[rid * 2 + side] =
                matrix_byte_pair_count[rid][side][0];
        end
        assign matrix_count_o[rid] =
            {1'b0, matrix_byte_pair_count[rid][0]}
            + {1'b0, matrix_byte_pair_count[rid][1]};
        assign matrix_parity_o[rid] = matrix_count_o[rid][0];
    end

    hdec_xor1_shared_8x32 i_xor1 (
        .diag_mode_i              (xor1_diag_mode_i),
        .matrix_product_i         (matrix_product_q_i),
        .pop_byte_parity_i        (matrix_byte_parity_flat),
        .pop_byte_pair_parity_i   (matrix_byte_pair_parity_flat),
        .pop_short_parity_i       (matrix_short_parity_flat),
        .pop_tail_parity_i        (matrix_tail_parity_flat),
        .legacy_acc_i             (xor1_legacy_acc_i),
        .legacy_sub_product_i     (xor1_legacy_sub_product_i),
        .legacy_sub_idx_i         (xor1_legacy_sub_idx_i),
        .legacy_leaf_a_i          (xor1_legacy_leaf_a_i),
        .legacy_leaf_xor_a_i      (xor1_legacy_leaf_xor_a_i),
        .legacy_leaf_b_i          (xor1_legacy_leaf_b_i),
        .legacy_leaf_xor_b_i      (xor1_legacy_leaf_xor_b_i),
        .diag16_product_o         (diag16_product_o),
        .legacy_accum_o           (xor1_legacy_accum_o),
        .legacy_lowxor_a_o        (xor1_legacy_lowxor_a_o),
        .legacy_lowxor_b_o        (xor1_legacy_lowxor_b_o)
    );

endmodule

// Aggressive vector payload fabric:
// one P2/P3 payload register for HBIND, HSIM/HMATCH, HCNTADD, HCNTCLIP and
// HPERM, while the actual math remains four 64-bit slices.
module hdec_vector_payload_4x64
    import hdec_pkg::*;
    import hdec_resource_pkg::*;
    import hdec_vv25_equation_pkg::*;
#(
    parameter bit ENABLE_ECC_REDUCE = 1'b1
) (
    input  logic                                clk_i,
    input  logic                                rst_ni,

    input  logic                                payload_xor_i,
    input  logic                                payload_product_i,
    input  logic                                payload_pop_i,
    input  logic                                payload_bitband_i,
    input  logic                                payload_cnt_i,
    input  logic                                payload_clip_i,
    input  logic                                hperm_we_i,
    input  logic [1:0]                          hperm_slot_i,
    input  logic [LANE_WIDTH-1:0]               hperm_word_i,

    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0] bool_src_a_i,
    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0] bool_src_b_i,
    input  logic [15:0]                         bitmatrix_src_a_i,
    input  logic [15:0]                         bitmatrix_src_b_i,
    input  logic                                xor1_diag_mode_i,
    input  logic [127:0]                        xor1_legacy_acc_i,
    input  logic [63:0]                         xor1_legacy_sub_product_i,
    input  logic [1:0]                          xor1_legacy_sub_idx_i,
    input  logic [31:0]                         xor1_legacy_leaf_a_i,
    input  logic [31:0]                         xor1_legacy_leaf_xor_a_i,
    input  logic [31:0]                         xor1_legacy_leaf_b_i,
    input  logic [31:0]                         xor1_legacy_leaf_xor_b_i,
    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0] xor0_contribution_packet_i,

    output logic [LANE_NUM-1:0][LANE_WIDTH-1:0] payload_q_o,
    output logic [LANE_NUM-1:0][1:0][5:0]       payload_pop_q_o,
    output logic [232:0]                        xor0_field_packet_o,
    output logic [31:0]                         bitmatrix_product_o,
    output logic [127:0]                        xor1_legacy_accum_o,
    output logic [31:0]                         xor1_legacy_lowxor_a_o,
    output logic [31:0]                         xor1_legacy_lowxor_b_o,

    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0] cnt_hv_word_i,
    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0] cnt_old_counter_i,
    input  logic [1:0]                          cnt_subgroup_i,

    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0] clip_counter_i
);

    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] xor0_merged_packet;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] tile_product_word;
    logic [LANE_NUM*2-1:0][31:0]         matrix_src_a;
    logic [LANE_NUM*2-1:0][31:0]         matrix_src_b;
    logic [LANE_NUM*2-1:0][31:0]         matrix_product_q;
    logic [LANE_NUM*2-1:0][31:0]         matrix_product;
    logic [LANE_NUM*2-1:0][31:0]         diag16_matrix_src_a;
    logic [LANE_NUM*2-1:0][31:0]         diag16_matrix_src_b;
    logic [LANE_NUM*2-1:0][5:0]          matrix_count;
    logic [LANE_NUM*2-1:0]               matrix_parity;
    logic [30:0]                          diag16_product;
    logic [LANE_NUM-1:0][1:0][5:0]       matrix_count_by_lane;
    logic [LANE_NUM-1:0][1:0][5:0]       popcount_part_q;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] cnt_new_counter;
    logic [LANE_NUM-1:0][15:0]           clip_bits;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] payload_q;

    // Constant elaboration-time index maps.  Every packed matrix bit below is
    // therefore a wire alias of one 16-bit operand bit, not a runtime shifter,
    // decoder, or ECC-private data-preparation array.
    function automatic int hdec_diag16_a_index(
        input int row_idx,
        input int column_idx
    );
        int flat_idx;
        int diag_idx;
        int term_idx;
        int a_start;
        begin
            flat_idx = row_idx * 32 + column_idx;
            diag_idx = hdec_vv25_matrix_diag(flat_idx);
            term_idx = hdec_vv25_matrix_term(flat_idx);
            a_start = (diag_idx > 15) ? (diag_idx - 15) : 0;
            hdec_diag16_a_index = a_start + term_idx;
        end
    endfunction

    function automatic int hdec_diag16_b_index(
        input int row_idx,
        input int column_idx
    );
        int flat_idx;
        int diag_idx;
        int a_idx;
        begin
            flat_idx = row_idx * 32 + column_idx;
            diag_idx = hdec_vv25_matrix_diag(flat_idx);
            a_idx = hdec_diag16_a_index(row_idx, column_idx);
            hdec_diag16_b_index = diag_idx - a_idx;
        end
    endfunction

    // synthesis translate_off
    function automatic logic hdec_xor_range_ref(
        input logic [31:0] row,
        input int unsigned start_idx,
        input int unsigned bit_count
    );
        logic parity;
        begin
            parity = 1'b0;
            for (int bit_idx = 0; bit_idx < 32; bit_idx++) begin
                if ((bit_idx >= start_idx) && (bit_idx < (start_idx + bit_count)))
                    parity ^= row[bit_idx];
            end
            hdec_xor_range_ref = parity;
        end
    endfunction

    function automatic logic [30:0] hdec_diag16_matrix_ref(
        input logic [LANE_NUM*2-1:0][31:0] matrix
    );
        logic [30:0] product;
        int diag_idx;
        begin
            product = '0;
            for (int flat_idx = 0; flat_idx < 256; flat_idx++) begin
                diag_idx = hdec_vv25_matrix_diag(flat_idx);
                product[diag_idx] ^=
                    matrix[flat_idx / 32][flat_idx % 32];
            end
            hdec_diag16_matrix_ref = product;
        end
    endfunction

    function automatic logic [5:0] hdec_diag16_popcount_row_ref(
        input logic [LANE_NUM*2-1:0][31:0] matrix,
        input int row_idx
    );
        logic [5:0] count;
        begin
            count = '0;
            for (int column_idx = 0; column_idx < 32; column_idx++)
                count += 6'(matrix[row_idx][column_idx]);
            hdec_diag16_popcount_row_ref = count;
        end
    endfunction
    // synthesis translate_on

    assign payload_q_o = payload_q;
    assign payload_pop_q_o = popcount_part_q;
    assign bitmatrix_product_o = {1'b0, diag16_product};
    assign xor0_field_packet_o = {xor0_merged_packet[3][40:0],
                                  xor0_merged_packet[2],
                                  xor0_merged_packet[1],
                                  xor0_merged_packet[0]};
    for (genvar rid = 0; rid < LANE_NUM*2; rid++) begin : gen_diag16_matrix_row_wires
        for (genvar column_idx = 0; column_idx < 32; column_idx++) begin : gen_diag16_matrix_column_wire
            localparam int A_INDEX = hdec_diag16_a_index(rid, column_idx);
            localparam int B_INDEX = hdec_diag16_b_index(rid, column_idx);
            assign diag16_matrix_src_a[rid][column_idx] = bitmatrix_src_a_i[A_INDEX];
            assign diag16_matrix_src_b[rid][column_idx] = bitmatrix_src_b_i[B_INDEX];
        end
    end

    // XOR0 is the vector merge stage of the same GF(2) contribution operator.
    // It deliberately stays at the payload boundary: moving it into the row tile
    // makes Vivado keep extra packet ports and increases LUTs.
    generate
        if (ENABLE_ECC_REDUCE) begin : gen_xor0_external_packet
            for (genvar lid = 0; lid < LANE_NUM; lid++) begin : gen_xor0_slice
                assign xor0_merged_packet[lid] =
                    bool_src_a_i[lid] ^ xor0_contribution_packet_i[lid];
            end
        end else begin : gen_xor0_hdc_packet
            for (genvar lid = 0; lid < LANE_NUM; lid++) begin : gen_xor0_slice
                assign xor0_merged_packet[lid] = bool_src_a_i[lid] ^ bool_src_b_i[lid];
            end
        end
    endgenerate

    for (genvar lid = 0; lid < LANE_NUM; lid++) begin : gen_payload_slice
        localparam int ROW_LO = lid * 2;
        localparam int ROW_HI = lid * 2 + 1;
        assign matrix_src_a[ROW_LO] = payload_bitband_i ? diag16_matrix_src_a[ROW_LO] : bool_src_a_i[lid][31:0];
        assign matrix_src_b[ROW_LO] = payload_bitband_i ? diag16_matrix_src_b[ROW_LO] : bool_src_b_i[lid][31:0];
        assign matrix_src_a[ROW_HI] = payload_bitband_i ? diag16_matrix_src_a[ROW_HI] : bool_src_a_i[lid][63:32];
        assign matrix_src_b[ROW_HI] = payload_bitband_i ? diag16_matrix_src_b[ROW_HI] : bool_src_b_i[lid][63:32];
        assign matrix_product_q[ROW_LO] = payload_q[lid][31:0];
        assign matrix_product_q[ROW_HI] = payload_q[lid][63:32];
        assign tile_product_word[lid] = {matrix_product[ROW_HI], matrix_product[ROW_LO]};
        assign matrix_count_by_lane[lid][0] = matrix_count[ROW_LO];
        assign matrix_count_by_lane[lid][1] = matrix_count[ROW_HI];

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

    end

    hdec_gf2_contribution_row_tile_8x32 i_gf2_contribution_row_tile (
        .matrix_src_a_i      (matrix_src_a),
        .matrix_src_b_i      (matrix_src_b),
        .matrix_product_q_i  (matrix_product_q),
        .xor1_diag_mode_i    (xor1_diag_mode_i),
        .xor1_legacy_acc_i   (xor1_legacy_acc_i),
        .xor1_legacy_sub_product_i(xor1_legacy_sub_product_i),
        .xor1_legacy_sub_idx_i(xor1_legacy_sub_idx_i),
        .xor1_legacy_leaf_a_i(xor1_legacy_leaf_a_i),
        .xor1_legacy_leaf_xor_a_i(xor1_legacy_leaf_xor_a_i),
        .xor1_legacy_leaf_b_i(xor1_legacy_leaf_b_i),
        .xor1_legacy_leaf_xor_b_i(xor1_legacy_leaf_xor_b_i),
        .matrix_product_o    (matrix_product),
        .matrix_count_o      (matrix_count),
        .matrix_parity_o     (matrix_parity),
        .diag16_product_o    (diag16_product),
        .xor1_legacy_accum_o (xor1_legacy_accum_o),
        .xor1_legacy_lowxor_a_o(xor1_legacy_lowxor_a_o),
        .xor1_legacy_lowxor_b_o(xor1_legacy_lowxor_b_o)
    );

    // synthesis translate_off
    // Executable reuse proof: all 256 registered AND products enter the same
    // 32 byte counters, and their byte equations plus native XOR1 corrections
    // reproduce the complete 31-diagonal product.
    always_ff @(posedge clk_i) begin
        if (rst_ni && xor1_diag_mode_i) begin
            for (int rid = 0; rid < LANE_NUM*2; rid++) begin
                if (matrix_count[rid]
                    !== hdec_diag16_popcount_row_ref(matrix_product_q, rid))
                    $error("VV25 full POPCOUNT mismatch row=%0d matrix=%h count=%0d",
                           rid, matrix_product_q[rid], matrix_count[rid]);
            end
            if (diag16_product !== hdec_diag16_matrix_ref(matrix_product_q))
                $error("VV25 collaborative diagonal product mismatch got=%h expected=%h",
                       diag16_product, hdec_diag16_matrix_ref(matrix_product_q));
        end
    end
    // synthesis translate_on

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            payload_q <= '0;
            popcount_part_q <= '0;
        end else if (hperm_we_i) begin
            payload_q[hperm_slot_i] <= hperm_word_i;
        end else begin
            if (payload_pop_i) begin
                popcount_part_q <= matrix_count_by_lane;
            end
            if (payload_xor_i) begin
                payload_q <= xor0_merged_packet;
            end else if (payload_product_i) begin
                payload_q <= tile_product_word;
            end else if (payload_cnt_i) begin
                payload_q <= cnt_new_counter;
            end else if (payload_clip_i) begin
                for (int lid = 0; lid < LANE_NUM; lid++) begin
                    payload_q[lid] <= {48'b0, clip_bits[lid]};
                end
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
