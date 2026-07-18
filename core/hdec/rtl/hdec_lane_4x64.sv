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

// One physical 224-node XOR1 array.  In VV22 mode it implements the shared
// 32-bit Karatsuba middle term, the 128-bit sub-product fold, and both 32-bit
// low-XOR outputs.  In VV23 diagonal mode, 64 logical reduction nodes map onto
// the live VV22 low-XOR nodes 160..223 and 23 map onto original nodes 0..22.
// Each mapped LUT therefore selects either its original two-input XOR or a
// three-input diagonal XOR.  There is no ECC-private XOR array or fourth AND.
module hdec_xor1_shared_8x32
    import hdec_pkg::*;
    import hdec_resource_pkg::*;
(
    input  logic                     diag_mode_i,
    input  logic [7:0][31:0]         matrix_product_i,
    input  logic [7:0]               matrix_parity_i,

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
    logic [223:0] diag_lhs;
    logic [223:0] diag_rhs;
    logic [223:0] diag_aux;
    logic [223:0] xor_node;
    logic [127:0] legacy_acc_rhs;

    logic [86:0]      diag_node_lhs;
    logic [86:0]      diag_node_rhs;
    logic [86:0]      diag_node_aux;
    logic [86:0]      diag_node;
    logic [7:0][3:0]  diag_segment;

    function automatic int hdec_diag_row_node_base(input int row_idx);
        case (row_idx)
            0: hdec_diag_row_node_base = 0;
            1: hdec_diag_row_node_base = 9;
            2: hdec_diag_row_node_base = 20;
            3: hdec_diag_row_node_base = 30;
            4: hdec_diag_row_node_base = 42;
            5: hdec_diag_row_node_base = 53;
            6: hdec_diag_row_node_base = 66;
            default: hdec_diag_row_node_base = 78;
        endcase
    endfunction

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

    // Rows 0..6 contain four diagonal segments A/B/C/D.  XOR1 directly reduces
    // A, B and C with three-input nodes, then obtains D from the full row
    // parity supplied by POPCOUNT.  This is the explicit AND->POPCOUNT/XOR1
    // cooperation: XOR1 cannot complete the fourth diagonal without POPCOUNT.
    for (genvar rid = 0; rid < 7; rid++) begin : gen_direct_rows_0_6
        localparam int EDGE_LEN   = rid + 1;
        localparam int LONG_LEN   = 16 - EDGE_LEN;
        localparam int ROW_BASE   = hdec_diag_row_node_base(rid);
        localparam int A_NODES    = EDGE_LEN / 2;
        localparam int B_BASE     = ROW_BASE + A_NODES;
        localparam int B_NODES    = EDGE_LEN / 2;
        localparam int C_BASE     = B_BASE + B_NODES;
        localparam int C_NODES    = LONG_LEN / 2;
        localparam int SOLVE_BASE = C_BASE + C_NODES;

        if (EDGE_LEN == 1) begin : gen_a_wire
            assign diag_segment[rid][0] = matrix_product_i[rid][0];
        end else begin : gen_a_tree
            for (genvar node_idx = 0; node_idx < A_NODES; node_idx++) begin : gen_node
                if (node_idx == 0) begin : gen_first
                    assign diag_node_lhs[ROW_BASE] = matrix_product_i[rid][0];
                    assign diag_node_rhs[ROW_BASE] = matrix_product_i[rid][1];
                    assign diag_node_aux[ROW_BASE] = (EDGE_LEN >= 3)
                                                       ? matrix_product_i[rid][2]
                                                       : 1'b0;
                end else begin : gen_follow
                    assign diag_node_lhs[ROW_BASE + node_idx] =
                        diag_node[ROW_BASE + node_idx - 1];
                    assign diag_node_rhs[ROW_BASE + node_idx] =
                        matrix_product_i[rid][2 * node_idx + 1];
                    assign diag_node_aux[ROW_BASE + node_idx] =
                        ((2 * node_idx + 2) < EDGE_LEN)
                        ? matrix_product_i[rid][2 * node_idx + 2] : 1'b0;
                end
            end
            assign diag_segment[rid][0] = diag_node[ROW_BASE + A_NODES - 1];
        end

        if (EDGE_LEN == 1) begin : gen_b_wire
            assign diag_segment[rid][1] = matrix_product_i[rid][EDGE_LEN];
        end else begin : gen_b_tree
            for (genvar node_idx = 0; node_idx < B_NODES; node_idx++) begin : gen_node
                if (node_idx == 0) begin : gen_first
                    assign diag_node_lhs[B_BASE] = matrix_product_i[rid][EDGE_LEN];
                    assign diag_node_rhs[B_BASE] = matrix_product_i[rid][EDGE_LEN + 1];
                    assign diag_node_aux[B_BASE] = (EDGE_LEN >= 3)
                        ? matrix_product_i[rid][EDGE_LEN + 2] : 1'b0;
                end else begin : gen_follow
                    assign diag_node_lhs[B_BASE + node_idx] =
                        diag_node[B_BASE + node_idx - 1];
                    assign diag_node_rhs[B_BASE + node_idx] =
                        matrix_product_i[rid][EDGE_LEN + 2 * node_idx + 1];
                    assign diag_node_aux[B_BASE + node_idx] =
                        ((2 * node_idx + 2) < EDGE_LEN)
                        ? matrix_product_i[rid][EDGE_LEN + 2 * node_idx + 2]
                        : 1'b0;
                end
            end
            assign diag_segment[rid][1] = diag_node[B_BASE + B_NODES - 1];
        end

        for (genvar node_idx = 0; node_idx < C_NODES; node_idx++) begin : gen_c_tree
            if (node_idx == 0) begin : gen_first
                assign diag_node_lhs[C_BASE] = matrix_product_i[rid][2 * EDGE_LEN];
                assign diag_node_rhs[C_BASE] = matrix_product_i[rid][2 * EDGE_LEN + 1];
                assign diag_node_aux[C_BASE] = matrix_product_i[rid][2 * EDGE_LEN + 2];
            end else begin : gen_follow
                assign diag_node_lhs[C_BASE + node_idx] =
                    diag_node[C_BASE + node_idx - 1];
                assign diag_node_rhs[C_BASE + node_idx] =
                    matrix_product_i[rid][2 * EDGE_LEN + 2 * node_idx + 1];
                assign diag_node_aux[C_BASE + node_idx] =
                    ((2 * node_idx + 2) < LONG_LEN)
                    ? matrix_product_i[rid][2 * EDGE_LEN + 2 * node_idx + 2]
                    : 1'b0;
            end
        end
        assign diag_segment[rid][2] = diag_node[C_BASE + C_NODES - 1];

        assign diag_node_lhs[SOLVE_BASE] = diag_segment[rid][0];
        assign diag_node_rhs[SOLVE_BASE] = diag_segment[rid][1];
        assign diag_node_aux[SOLVE_BASE] = diag_segment[rid][2];
        assign diag_node_lhs[SOLVE_BASE + 1] = matrix_parity_i[rid];
        assign diag_node_rhs[SOLVE_BASE + 1] = diag_node[SOLVE_BASE];
        assign diag_node_aux[SOLVE_BASE + 1] = 1'b0;
        assign diag_segment[rid][3] = diag_node[SOLVE_BASE + 1];
    end

    // Row 7 contains A(8), B(16), C(8).  A and C use four nodes each; B is
    // recovered in one node from the complete POPCOUNT parity.
    for (genvar node_idx = 0; node_idx < 4; node_idx++) begin : gen_row7_a
        if (node_idx == 0) begin : gen_first
            assign diag_node_lhs[78] = matrix_product_i[7][0];
            assign diag_node_rhs[78] = matrix_product_i[7][1];
            assign diag_node_aux[78] = matrix_product_i[7][2];
        end else begin : gen_follow
            assign diag_node_lhs[78 + node_idx] = diag_node[77 + node_idx];
            assign diag_node_rhs[78 + node_idx] = matrix_product_i[7][2 * node_idx + 1];
            assign diag_node_aux[78 + node_idx] = ((2 * node_idx + 2) < 8)
                ? matrix_product_i[7][2 * node_idx + 2] : 1'b0;
        end
    end
    for (genvar node_idx = 0; node_idx < 4; node_idx++) begin : gen_row7_c
        if (node_idx == 0) begin : gen_first
            assign diag_node_lhs[82] = matrix_product_i[7][24];
            assign diag_node_rhs[82] = matrix_product_i[7][25];
            assign diag_node_aux[82] = matrix_product_i[7][26];
        end else begin : gen_follow
            assign diag_node_lhs[82 + node_idx] = diag_node[81 + node_idx];
            assign diag_node_rhs[82 + node_idx] = matrix_product_i[7][24 + 2 * node_idx + 1];
            assign diag_node_aux[82 + node_idx] = ((2 * node_idx + 2) < 8)
                ? matrix_product_i[7][24 + 2 * node_idx + 2] : 1'b0;
        end
    end
    assign diag_segment[7][0] = diag_node[81];
    assign diag_segment[7][2] = diag_node[85];
    assign diag_node_lhs[86] = matrix_parity_i[7];
    assign diag_node_rhs[86] = diag_segment[7][0];
    assign diag_node_aux[86] = diag_segment[7][2];
    assign diag_segment[7][1] = diag_node[86];
    assign diag_segment[7][3] = 1'b0;

    // Logical nodes 0..63 occupy every live VV22 low-XOR node.  Nodes 64..86
    // occupy original XOR1 nodes 0..22.  No node exists outside XOR1.
    always_comb begin
        diag_lhs = '0;
        diag_rhs = '0;
        diag_aux = '0;
        for (int logical_node = 0; logical_node < 64; logical_node++) begin
            diag_lhs[160 + logical_node] = diag_node_lhs[logical_node];
            diag_rhs[160 + logical_node] = diag_node_rhs[logical_node];
            diag_aux[160 + logical_node] = diag_node_aux[logical_node];
        end
        for (int logical_node = 64; logical_node < 87; logical_node++) begin
            diag_lhs[logical_node - 64] = diag_node_lhs[logical_node];
            diag_rhs[logical_node - 64] = diag_node_rhs[logical_node];
            diag_aux[logical_node - 64] = diag_node_aux[logical_node];
        end
    end

    for (genvar logical_node = 0; logical_node < 64; logical_node++) begin : gen_live_node_map
        assign diag_node[logical_node] = xor_node[160 + logical_node];
    end
    for (genvar logical_node = 64; logical_node < 87; logical_node++) begin : gen_legacy_node_map
        assign diag_node[logical_node] = xor_node[logical_node - 64];
    end

    for (genvar rid = 0; rid < 7; rid++) begin : gen_diag_product_rows_0_6
        assign diag16_product_o[rid]      = diag_segment[rid][0];
        assign diag16_product_o[30-rid]   = diag_segment[rid][1];
        assign diag16_product_o[14-rid]   = diag_segment[rid][2];
        assign diag16_product_o[16+rid]   = diag_segment[rid][3];
    end
    assign diag16_product_o[7]  = diag_segment[7][0];
    assign diag16_product_o[15] = diag_segment[7][1];
    assign diag16_product_o[23] = diag_segment[7][2];

    // This generate block is the only XOR primitive description in XOR1.
    for (genvar node_idx = 0; node_idx < 224; node_idx++) begin : gen_shared_xor_node
        assign xor_node[node_idx] = diag_mode_i
            ? (diag_lhs[node_idx] ^ diag_rhs[node_idx] ^ diag_aux[node_idx])
            : (legacy_lhs[node_idx] ^ legacy_rhs[node_idx]);
    end

    assign legacy_accum_o   = xor_node[159:32];
    assign legacy_lowxor_a_o = xor_node[191:160];
    assign legacy_lowxor_b_o = xor_node[223:192];

endmodule

// Shared GF(2) contribution row tile.
// The physical shape is eight 32-bit rows packed into the existing 4x64 payload.
// HDC chunks and the VV23 16x16 diagonal matrix both enter as paired rows; the
// operator only sees row-wise bit pairs, not algorithm-specific lane control.
module hdec_gf2_contribution_row_tile_8x32
    import hdec_pkg::*;
    import hdec_resource_pkg::*;
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

    function automatic logic [3:0] hdec_popcount8_fixed(input logic [7:0] bits);
        hdec_popcount8_fixed =
            4'(bits[0]) + 4'(bits[1]) + 4'(bits[2]) + 4'(bits[3]) +
            4'(bits[4]) + 4'(bits[5]) + 4'(bits[6]) + 4'(bits[7]);
    endfunction

    // Four byte counters per row retain the complete eight-row POPCOUNT while
    // their LSBs expose byte parity to the same XOR1.  No POPCOUNT lane is
    // disabled or split away from the 256-bit AND result.
    logic [LANE_NUM*2-1:0][3:0][3:0] matrix_byte_count;
    logic [LANE_NUM*2-1:0][3:0]      matrix_byte_parity;

    for (genvar rid = 0; rid < LANE_NUM*2; rid++) begin : gen_bitmatrix_row
        assign matrix_product_o[rid] = matrix_src_a_i[rid] & matrix_src_b_i[rid];
        for (genvar byte_idx = 0; byte_idx < 4; byte_idx++) begin : gen_byte_count
            assign matrix_byte_count[rid][byte_idx] = hdec_popcount8_fixed(
                matrix_product_q_i[rid][8 * byte_idx +: 8]
            );
            assign matrix_byte_parity[rid][byte_idx] =
                matrix_byte_count[rid][byte_idx][0];
        end
        assign matrix_count_o[rid] =
              {2'b0, matrix_byte_count[rid][0]}
            + {2'b0, matrix_byte_count[rid][1]}
            + {2'b0, matrix_byte_count[rid][2]}
            + {2'b0, matrix_byte_count[rid][3]};
        assign matrix_parity_o[rid] = matrix_count_o[rid][0];
    end

    hdec_xor1_shared_8x32 i_xor1 (
        .diag_mode_i              (xor1_diag_mode_i),
        .matrix_product_i         (matrix_product_q_i),
        .matrix_parity_i          (matrix_parity_o),
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
        int edge_len;
        begin
            if (row_idx < 7) begin
                edge_len = row_idx + 1;
                if (column_idx < edge_len)
                    hdec_diag16_a_index = column_idx;
                else if (column_idx < 2 * edge_len)
                    hdec_diag16_a_index = 16 - edge_len + column_idx - edge_len;
                else if (column_idx < edge_len + 16)
                    hdec_diag16_a_index = column_idx - 2 * edge_len;
                else
                    hdec_diag16_a_index = column_idx - 16;
            end else begin
                if (column_idx < 8)
                    hdec_diag16_a_index = column_idx;
                else if (column_idx < 24)
                    hdec_diag16_a_index = column_idx - 8;
                else
                    hdec_diag16_a_index = column_idx - 16;
            end
        end
    endfunction

    function automatic int hdec_diag16_b_index(
        input int row_idx,
        input int column_idx
    );
        int edge_len;
        begin
            if (row_idx < 7) begin
                edge_len = row_idx + 1;
                if (column_idx < edge_len)
                    hdec_diag16_b_index = edge_len - 1 - column_idx;
                else if (column_idx < edge_len + 16)
                    hdec_diag16_b_index = 15 + edge_len - column_idx;
                else
                    hdec_diag16_b_index = 31 + edge_len - column_idx;
            end else begin
                if (column_idx < 8)
                    hdec_diag16_b_index = 7 - column_idx;
                else if (column_idx < 24)
                    hdec_diag16_b_index = 23 - column_idx;
                else
                    hdec_diag16_b_index = 39 - column_idx;
            end
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
        int unsigned edge_len;
        begin
            product = '0;
            for (int rid = 0; rid < 7; rid++) begin
                edge_len = rid + 1;
                product[rid] = hdec_xor_range_ref(matrix[rid], 0, edge_len);
                product[30-rid] = hdec_xor_range_ref(matrix[rid], edge_len, edge_len);
                product[14-rid] = hdec_xor_range_ref(
                    matrix[rid], 2 * edge_len, 16 - edge_len
                );
                product[16+rid] = hdec_xor_range_ref(
                    matrix[rid], 16 + edge_len, 16 - edge_len
                );
            end
            product[7]  = hdec_xor_range_ref(matrix[7], 0, 8);
            product[15] = hdec_xor_range_ref(matrix[7], 8, 16);
            product[23] = hdec_xor_range_ref(matrix[7], 24, 8);
            hdec_diag16_matrix_ref = product;
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
    // This assertion block is the executable shared-dataflow proof: on every
    // diagonal capture, all 256 registered AND bits are consumed by the full
    // eight-row POPCOUNT and by the mode-selected original XOR1 instance.
    always_ff @(posedge clk_i) begin
        if (rst_ni && xor1_diag_mode_i) begin
            for (int rid = 0; rid < LANE_NUM*2; rid++) begin
                if (matrix_count[rid] !== $countones(matrix_product_q[rid]))
                    $error("VV23 full POPCOUNT mismatch row=%0d matrix=%h count=%0d",
                           rid, matrix_product_q[rid], matrix_count[rid]);
            end
            if (diag16_product !== hdec_diag16_matrix_ref(matrix_product_q))
                $error("VV23 shared XOR1 diagonal product mismatch got=%h expected=%h",
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
