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

package hdec_vv24_diag_pkg;

    localparam logic [255:0] HDEC_VV24_POP_MASK =
        256'h0103070f1f3f7fff01ff03ff07ff7fff7fff07ff03ff01ffff7f3f1f0f070301;

    localparam int HDEC_VV24_MATRIX_DIAG [0:255] = '{
        0,11,11,11,11,11,11,11,1,1,11,11,11,11,11,12,
        2,2,2,12,12,12,12,12,3,3,3,3,12,12,12,12,
        4,4,4,4,4,12,12,12,5,5,5,5,5,5,13,13,
        6,6,6,6,6,6,6,13,7,7,7,7,7,7,7,7,
        8,8,8,8,8,8,8,8,8,13,13,13,13,13,13,13,
        9,9,9,9,9,9,9,9,9,9,13,13,13,13,15,15,
        10,10,10,10,10,10,10,10,10,10,10,15,15,15,15,15,
        14,14,14,14,14,14,14,14,14,14,14,14,14,14,14,15,
        16,16,16,16,16,16,16,16,16,16,16,16,16,16,16,15,
        20,20,20,20,20,20,20,20,20,20,20,15,15,15,15,15,
        21,21,21,21,21,21,21,21,21,21,15,15,17,17,17,17,
        22,22,22,22,22,22,22,22,22,17,17,17,17,17,17,17,
        23,23,23,23,23,23,23,23,24,24,24,24,24,24,24,17,
        25,25,25,25,25,25,17,17,26,26,26,26,26,18,18,18,
        27,27,27,27,18,18,18,18,28,28,28,18,18,18,18,18,
        29,29,18,19,19,19,19,19,30,19,19,19,19,19,19,19
    };

    localparam int HDEC_VV24_MATRIX_TERM [0:255] = '{
        0,0,1,2,3,4,5,6,0,1,7,8,9,10,11,0,
        0,1,2,1,2,3,4,5,0,1,2,3,6,7,8,9,
        0,1,2,3,4,10,11,12,0,1,2,3,4,5,0,1,
        0,1,2,3,4,5,6,2,0,1,2,3,4,5,6,7,
        0,1,2,3,4,5,6,7,8,3,4,5,6,7,8,9,
        0,1,2,3,4,5,6,7,8,9,10,11,12,13,0,1,
        0,1,2,3,4,5,6,7,8,9,10,2,3,4,5,6,
        0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,7,
        0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,8,
        0,1,2,3,4,5,6,7,8,9,10,9,10,11,12,13,
        0,1,2,3,4,5,6,7,8,9,14,15,0,1,2,3,
        0,1,2,3,4,5,6,7,8,4,5,6,7,8,9,10,
        0,1,2,3,4,5,6,7,0,1,2,3,4,5,6,11,
        0,1,2,3,4,5,12,13,0,1,2,3,4,0,1,2,
        0,1,2,3,3,4,5,6,0,1,2,7,8,9,10,11,
        0,1,12,0,1,2,3,4,0,5,6,7,8,9,10,11
    };

    localparam int HDEC_VV24_POP_BYTE_BASE [0:30] = '{
        0,1,2,3,4,5,6,7,8,10,12,14,14,14,14,16,
        16,18,18,18,18,20,22,24,25,26,27,28,29,30,31
    };

    // Balanced binary trees over the 87 native XOR1 nodes.  A source below
    // 256 names a registered AND-matrix bit; a source at or above 256 names
    // an earlier native node.  This is fixed wiring outside XOR1, not another
    // reduction operator.
    localparam int HDEC_VV24_XOR_NODE_LHS [0:86] = '{
        1,3,5,7,11,13,256,258,260,262,265,15,20,22,28,30,37,267,269,
        271,273,275,276,46,55,74,76,78,90,92,279,281,283,286,288,289,
        94,107,109,111,143,156,158,170,292,294,296,298,300,302,304,172,
        174,185,187,189,191,214,307,309,311,314,316,317,221,223,229,231,
        236,238,320,322,324,326,328,329,243,245,247,250,252,254,332,334,
        336,338,341
    };

    localparam int HDEC_VV24_XOR_NODE_RHS [0:86] = '{
        2,4,6,10,12,14,257,259,261,263,264,19,21,23,29,31,38,268,270,
        272,274,39,277,47,73,75,77,79,91,93,280,282,284,287,285,290,
        95,108,110,127,155,157,159,171,293,295,297,299,301,303,305,173,
        175,186,188,190,207,215,308,310,312,315,313,318,222,228,230,235,
        237,239,321,323,325,327,242,330,244,246,249,251,253,255,333,335,
        337,339,340
    };

    localparam int HDEC_VV24_XOR_DIAG_SOURCE [0:30] = '{
        -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,266,278,291,-1,306,
        -1,319,331,342,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1
    };

    localparam int HDEC_VV24_MATRIX_FLAT [0:30][0:15] = '{
        '{0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        '{8,9,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        '{16,17,18,0,0,0,0,0,0,0,0,0,0,0,0,0},
        '{24,25,26,27,0,0,0,0,0,0,0,0,0,0,0,0},
        '{32,33,34,35,36,0,0,0,0,0,0,0,0,0,0,0},
        '{40,41,42,43,44,45,0,0,0,0,0,0,0,0,0,0},
        '{48,49,50,51,52,53,54,0,0,0,0,0,0,0,0,0},
        '{56,57,58,59,60,61,62,63,0,0,0,0,0,0,0,0},
        '{64,65,66,67,68,69,70,71,72,0,0,0,0,0,0,0},
        '{80,81,82,83,84,85,86,87,88,89,0,0,0,0,0,0},
        '{96,97,98,99,100,101,102,103,104,105,106,0,0,0,0,0},
        '{1,2,3,4,5,6,7,10,11,12,13,14,0,0,0,0},
        '{15,19,20,21,22,23,28,29,30,31,37,38,39,0,0,0},
        '{46,47,55,73,74,75,76,77,78,79,90,91,92,93,0,0},
        '{112,113,114,115,116,117,118,119,120,121,122,123,124,125,126,0},
        '{94,95,107,108,109,110,111,127,143,155,156,157,158,159,170,171},
        '{128,129,130,131,132,133,134,135,136,137,138,139,140,141,142,0},
        '{172,173,174,175,185,186,187,188,189,190,191,207,214,215,0,0},
        '{221,222,223,228,229,230,231,235,236,237,238,239,242,0,0,0},
        '{243,244,245,246,247,249,250,251,252,253,254,255,0,0,0,0},
        '{144,145,146,147,148,149,150,151,152,153,154,0,0,0,0,0},
        '{160,161,162,163,164,165,166,167,168,169,0,0,0,0,0,0},
        '{176,177,178,179,180,181,182,183,184,0,0,0,0,0,0,0},
        '{192,193,194,195,196,197,198,199,0,0,0,0,0,0,0,0},
        '{200,201,202,203,204,205,206,0,0,0,0,0,0,0,0,0},
        '{208,209,210,211,212,213,0,0,0,0,0,0,0,0,0,0},
        '{216,217,218,219,220,0,0,0,0,0,0,0,0,0,0,0},
        '{224,225,226,227,0,0,0,0,0,0,0,0,0,0,0,0},
        '{232,233,234,0,0,0,0,0,0,0,0,0,0,0,0,0},
        '{240,241,0,0,0,0,0,0,0,0,0,0,0,0,0,0},
        '{248,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
    };

    function automatic int hdec_vv24_diag_len(input int diag_idx);
        if (diag_idx < 16)
            hdec_vv24_diag_len = diag_idx + 1;
        else
            hdec_vv24_diag_len = 31 - diag_idx;
    endfunction

    // Probe D gives seven balanced middle-length diagonals to XOR1.  The other
    // 24 complete diagonals fill the same 32 physical byte counters.
    function automatic bit hdec_vv24_pop_owner(input int diag_idx);
        int diag_len;
        begin
            diag_len = hdec_vv24_diag_len(diag_idx);
            hdec_vv24_pop_owner = (diag_len != 12) && (diag_len != 13)
                                  && (diag_len != 14) && (diag_len != 16);
        end
    endfunction

    function automatic int hdec_vv24_pop_byte_base(input int diag_idx);
        hdec_vv24_pop_byte_base = HDEC_VV24_POP_BYTE_BASE[diag_idx];
    endfunction

    function automatic bit hdec_vv24_is_pop_position(input int flat_idx);
        hdec_vv24_is_pop_position = HDEC_VV24_POP_MASK[flat_idx];
    endfunction

    function automatic int hdec_vv24_matrix_diag(input int flat_idx);
        hdec_vv24_matrix_diag = HDEC_VV24_MATRIX_DIAG[flat_idx];
    endfunction

    function automatic int hdec_vv24_matrix_term(input int flat_idx);
        hdec_vv24_matrix_term = HDEC_VV24_MATRIX_TERM[flat_idx];
    endfunction

    function automatic int hdec_vv24_matrix_flat(
        input int diag_idx,
        input int term_idx
    );
        hdec_vv24_matrix_flat = HDEC_VV24_MATRIX_FLAT[diag_idx][term_idx];
    endfunction

    function automatic int hdec_vv24_xor_node_lhs(input int node_idx);
        hdec_vv24_xor_node_lhs = HDEC_VV24_XOR_NODE_LHS[node_idx];
    endfunction

    function automatic int hdec_vv24_xor_node_rhs(input int node_idx);
        hdec_vv24_xor_node_rhs = HDEC_VV24_XOR_NODE_RHS[node_idx];
    endfunction

    function automatic int hdec_vv24_xor_diag_source(input int diag_idx);
        hdec_vv24_xor_diag_source = HDEC_VV24_XOR_DIAG_SOURCE[diag_idx];
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
// POPCOUNT and XOR1 own disjoint complete diagonals and never solve one
// another's parity.
module hdec_xor1_shared_8x32
    import hdec_pkg::*;
    import hdec_resource_pkg::*;
    import hdec_vv24_diag_pkg::*;
(
    input  logic                     diag_mode_i,
    input  logic [7:0][31:0]         matrix_product_i,
    input  logic [30:0]              diag_pop_parity_i,

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
    logic [223:0] xor_node;
    logic [223:0] native_lhs;
    logic [223:0] native_rhs;
    logic [127:0] legacy_acc_rhs;

    logic [86:0] diag_node_lhs;
    logic [86:0] diag_node_rhs;
    logic [86:0] diag_node;

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

    // Twelve complete diagonals (lengths 1..5 and 9, mirrored) belong to
    // XOR1.  All seven complete diagonals use exactly 87 original two-input
    // nodes: the 64 live low-XOR nodes 160..223 and live legacy nodes 0..22.
    for (genvar diag_idx = 0; diag_idx < 31; diag_idx++) begin : gen_diag_owner
        localparam int DIAG_SOURCE = hdec_vv24_xor_diag_source(diag_idx);
        if (hdec_vv24_pop_owner(diag_idx)) begin : gen_pop_owner
            assign diag16_product_o[diag_idx] = diag_pop_parity_i[diag_idx];
        end else if (DIAG_SOURCE < 256) begin : gen_xor_wire
            assign diag16_product_o[diag_idx] =
                matrix_product_i[DIAG_SOURCE / 32][DIAG_SOURCE % 32];
        end else begin : gen_xor_tree_result
            assign diag16_product_o[diag_idx] = diag_node[DIAG_SOURCE - 256];
        end
    end

    for (genvar logical_node = 0; logical_node < 87; logical_node++) begin : gen_diag_node_wires
        localparam int LHS_SOURCE = hdec_vv24_xor_node_lhs(logical_node);
        localparam int RHS_SOURCE = hdec_vv24_xor_node_rhs(logical_node);
        if (LHS_SOURCE < 256) begin : gen_lhs_matrix
            assign diag_node_lhs[logical_node] =
                matrix_product_i[LHS_SOURCE / 32][LHS_SOURCE % 32];
        end else begin : gen_lhs_node
            assign diag_node_lhs[logical_node] = diag_node[LHS_SOURCE - 256];
        end
        if (RHS_SOURCE < 256) begin : gen_rhs_matrix
            assign diag_node_rhs[logical_node] =
                matrix_product_i[RHS_SOURCE / 32][RHS_SOURCE % 32];
        end else begin : gen_rhs_node
            assign diag_node_rhs[logical_node] = diag_node[RHS_SOURCE - 256];
        end
    end

    always_comb begin
        diag_lhs = '0;
        diag_rhs = '0;
        for (int logical_node = 0; logical_node < 87; logical_node++) begin
            if (logical_node < 64) begin
                diag_lhs[160 + logical_node] = diag_node_lhs[logical_node];
                diag_rhs[160 + logical_node] = diag_node_rhs[logical_node];
            end else begin
                diag_lhs[logical_node - 64] = diag_node_lhs[logical_node];
                diag_rhs[logical_node - 64] = diag_node_rhs[logical_node];
            end
        end
    end

    for (genvar logical_node = 0; logical_node < 87; logical_node++) begin : gen_live_node_map
        if (logical_node < 64) begin : gen_lowxor_node
            assign diag_node[logical_node] = xor_node[160 + logical_node];
        end else begin : gen_legacy_node
            assign diag_node[logical_node] = xor_node[logical_node - 64];
        end
    end

    // Mode selection is outside the native operator.
    assign native_lhs = diag_mode_i ? diag_lhs : legacy_lhs;
    assign native_rhs = diag_mode_i ? diag_rhs : legacy_rhs;

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
// HDC chunks and the VV23 16x16 diagonal matrix both enter as paired rows; the
// operator only sees row-wise bit pairs, not algorithm-specific lane control.
module hdec_gf2_contribution_row_tile_8x32
    import hdec_pkg::*;
    import hdec_resource_pkg::*;
    import hdec_vv24_diag_pkg::*;
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
        logic [1:0] pair_count [0:3];
        logic [2:0] quad_count [0:1];
        begin
            pair_count[0] = 2'(bits[0]) + 2'(bits[1]);
            pair_count[1] = 2'(bits[2]) + 2'(bits[3]);
            pair_count[2] = 2'(bits[4]) + 2'(bits[5]);
            pair_count[3] = 2'(bits[6]) + 2'(bits[7]);
            quad_count[0] = {1'b0, pair_count[0]} + {1'b0, pair_count[1]};
            quad_count[1] = {1'b0, pair_count[2]} + {1'b0, pair_count[3]};
            hdec_popcount8_fixed = {1'b0, quad_count[0]}
                                 + {1'b0, quad_count[1]};
        end
    endfunction

    // Four byte counters per row retain the complete eight-row POPCOUNT while
    // their LSBs expose byte parity to the same XOR1.  No POPCOUNT lane is
    // disabled or split away from the 256-bit AND result.
    logic [LANE_NUM*2-1:0][3:0][3:0] matrix_byte_count;
    logic [LANE_NUM*2-1:0][3:0]      matrix_byte_parity;
    logic [LANE_NUM*2-1:0][31:0]     matrix_pop_view;
    logic [31:0][3:0]                 matrix_byte_count_flat;
    logic [30:0]                      diag_pop_parity;

    for (genvar rid = 0; rid < LANE_NUM*2; rid++) begin : gen_bitmatrix_row
        assign matrix_product_o[rid] = matrix_src_a_i[rid] & matrix_src_b_i[rid];
        for (genvar byte_idx = 0; byte_idx < 4; byte_idx++) begin : gen_byte_count
            for (genvar bit_idx = 0; bit_idx < 8; bit_idx++) begin : gen_pop_view
                localparam int FLAT = rid * 32 + byte_idx * 8 + bit_idx;
                if (hdec_vv24_is_pop_position(FLAT)) begin : gen_pop_owned
                    assign matrix_pop_view[rid][byte_idx * 8 + bit_idx] =
                        matrix_product_q_i[rid][byte_idx * 8 + bit_idx];
                end else begin : gen_xor_owned
                    assign matrix_pop_view[rid][byte_idx * 8 + bit_idx] =
                        matrix_product_q_i[rid][byte_idx * 8 + bit_idx]
                        & ~xor1_diag_mode_i;
                end
            end
            assign matrix_byte_count[rid][byte_idx] = hdec_popcount8_fixed(
                matrix_pop_view[rid][8 * byte_idx +: 8]
            );
            assign matrix_byte_parity[rid][byte_idx] =
                matrix_byte_count[rid][byte_idx][0];
            assign matrix_byte_count_flat[rid * 4 + byte_idx] =
                matrix_byte_count[rid][byte_idx];
        end
        assign matrix_count_o[rid] =
              {2'b0, matrix_byte_count[rid][0]}
            + {2'b0, matrix_byte_count[rid][1]}
            + {2'b0, matrix_byte_count[rid][2]}
            + {2'b0, matrix_byte_count[rid][3]};
        assign matrix_parity_o[rid] = matrix_count_o[rid][0];
    end

    for (genvar diag_idx = 0; diag_idx < 31; diag_idx++) begin : gen_pop_diagonal
        localparam int DIAG_LEN = hdec_vv24_diag_len(diag_idx);
        localparam int BYTE_BASE = hdec_vv24_pop_byte_base(diag_idx);
        if (hdec_vv24_pop_owner(diag_idx)) begin : gen_owned
            if (DIAG_LEN <= 8) begin : gen_one_byte
                assign diag_pop_parity[diag_idx] =
                    matrix_byte_count_flat[BYTE_BASE][0];
            end else begin : gen_two_bytes
                logic [4:0] diag_count_sum;
                assign diag_count_sum =
                    {1'b0, matrix_byte_count_flat[BYTE_BASE]}
                    + {1'b0, matrix_byte_count_flat[BYTE_BASE + 1]};
                assign diag_pop_parity[diag_idx] = diag_count_sum[0];
            end
        end else begin : gen_not_owned
            assign diag_pop_parity[diag_idx] = 1'b0;
        end
    end

    hdec_xor1_shared_8x32 i_xor1 (
        .diag_mode_i              (xor1_diag_mode_i),
        .matrix_product_i         (matrix_product_q_i),
        .diag_pop_parity_i        (diag_pop_parity),
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
    import hdec_vv24_diag_pkg::*;
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
            diag_idx = hdec_vv24_matrix_diag(flat_idx);
            term_idx = hdec_vv24_matrix_term(flat_idx);
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
            diag_idx = hdec_vv24_matrix_diag(flat_idx);
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
                diag_idx = hdec_vv24_matrix_diag(flat_idx);
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
        int flat_idx;
        begin
            count = '0;
            for (int column_idx = 0; column_idx < 32; column_idx++) begin
                flat_idx = row_idx * 32 + column_idx;
                if (hdec_vv24_is_pop_position(flat_idx))
                    count += 6'(matrix[row_idx][column_idx]);
            end
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
    // Executable ownership proof: the POPCOUNT-owned cells are counted once;
    // the complementary cells feed native XOR1, and the combined 31 outputs
    // reproduce all 256 registered AND partial products.
    always_ff @(posedge clk_i) begin
        if (rst_ni && xor1_diag_mode_i) begin
            for (int rid = 0; rid < LANE_NUM*2; rid++) begin
                if (matrix_count[rid]
                    !== hdec_diag16_popcount_row_ref(matrix_product_q, rid))
                    $error("VV24 owned POPCOUNT mismatch row=%0d matrix=%h count=%0d",
                           rid, matrix_product_q[rid], matrix_count[rid]);
            end
            if (diag16_product !== hdec_diag16_matrix_ref(matrix_product_q))
                $error("VV24 independent diagonal product mismatch got=%h expected=%h",
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
