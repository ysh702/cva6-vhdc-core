// hdec_top.sv — HDCU Phase: VRF mgmt + HDC compute FSM
// HDCU instruction subset: VWR64, VRD64, HCLR, HCNTCLR, HCNTADD,
// HBIND, HPERM, HSIM, HCNTCLIP, HMATCH, VADDR.
// No bundle, no add/sub counter, no BMCA.
module hdec_top import hdec_pkg::*; import hdec_resource_pkg::*; (
    input logic clk_i, rst_ni, valid_i, output logic ready_o,
    input hdec_op_t operator_i, input logic [63:0] operand_a_i, operand_b_i,
    output logic valid_o, output logic [63:0] result_o
);
    logic [LANE_NUM-1:0][VRF_IDX_W-1:0] vrf_ra, vrf_ra_q;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] vrf_rd;
    logic [LANE_NUM-1:0] vrf_we, vrf_we_q;
    logic [LANE_NUM-1:0][VRF_IDX_W-1:0] vrf_wa, vrf_wa_q;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] vrf_wd, vrf_wd_q;
    hdec_vrf_64x256 i_vrf(.clk_i,.rst_ni,.bank_ra_addr_i(vrf_ra_q),.bank_ra_data_o(vrf_rd),.bank_we_i(vrf_we_q),.bank_wa_addr_i(vrf_wa_q),.bank_wdata_i(vrf_wd_q),.vrf_ready_o());
    logic [VRF_BNK_W-1:0] vaddr_bank_q,vaddr_bank_n; logic [VRF_IDX_W-1:0] vaddr_idx_q,vaddr_idx_n;

    // ── State Machine ───────────────────────────────────────────────────────
    typedef enum logic [4:0] {
        S_IDLE, S_EXEC, S_VWR_WAIT, S_RD_WAIT, S_RD_CAPTURE, S_RESULT, S_CLR, S_CLR_DRAIN,
        S_HSIM_INIT, S_HMATCH_INIT,
        S_UOP_P1_RD0, S_UOP_P1_RD0_WAIT, S_UOP_P1_RD1, S_UOP_P1_RD1_WAIT,
        S_UOP_P2_LANE, S_UOP_P3_GLOBAL, S_UOP_P3_POP_CAPTURE, S_UOP_P3_VRF_WAIT, S_UOP_P3_ACCUM, S_UOP_P4_RESP,
        S_UOP_CLIP_WRITE,
        S_ECC_LOAD_A_WAIT, S_ECC_LOAD_A, S_ECC_LOAD_B_WAIT, S_ECC_LOAD_B,
        S_ECC_KPD32_FORM,
        S_ECC_DIAG_ISSUE, S_ECC_DIAG_WAIT, S_ECC_DIAG_ACCUM,
        S_ECC_LEAF_FOLD,
        S_ECC_WRITE_WORD, S_ECC_WRITE_DRAIN
    } st_t;
    st_t st_q, st_n;

    logic [63:0] res_q,res_n; hdec_op_t op_q,op_n; logic [63:0] a_q,a_n,b_q,b_n; logic [VRF_BNK_W-1:0] bk_q,bk_n;
    logic [3:0] clr_cnt_q,clr_cnt_n; logic [VRF_IDX_W-1:0] clr_base_q,clr_base_n;

    // ── HBIND registers ─────────────────────────────────────────────────────
    logic [1:0] chunk_cnt_q,chunk_cnt_n;
    logic [VRF_IDX_W-1:0] hb_dst_base_q,hb_dst_base_n, hb_src0_base_q,hb_src0_base_n, hb_src1_base_q,hb_src1_base_n;

    // ── HSIM / HMATCH registers ─────────────────────────────────────────────
    logic [VRF_IDX_W-1:0] hsim_src0_base_q,hsim_src0_base_n, hsim_src1_base_q,hsim_src1_base_n;
    logic [10:0] hsim_total_q,hsim_total_n;
    logic [2:0] hmatch_last_idx_q,hmatch_last_idx_n;
    logic [2:0] hmatch_best_idx_q,hmatch_best_idx_n;
    logic [3:0] hmatch_class_slot_q,hmatch_class_slot_n;
    logic [10:0] hmatch_best_dist_q,hmatch_best_dist_n;
    logic signed [11:0] hmatch_budget_q,hmatch_budget_n;
    logic hmatch_update_q,hmatch_update_n;

    // ── HPERM registers ─────────────────────────────────────────────────────
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] hperm_a_q,hperm_a_n;
    logic [VRF_IDX_W-1:0] hperm_dst_base_q,hperm_dst_base_n, hperm_src_base_q,hperm_src_base_n;
    logic [3:0] hperm_word_off_q,hperm_word_off_n, hperm_nibble_q,hperm_nibble_n;
    logic [1:0] hperm_lane_base_q,hperm_lane_base_n;

    // ── HCNTADD registers ───────────────────────────────────────────────────
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] hcntadd_hv_q,hcntadd_hv_n;
    logic [2:0] hcntadd_hv_slot_q,hcntadd_hv_slot_n;
    logic [1:0] hcntadd_chunk_q,hcntadd_chunk_n, hcntadd_subgroup_q,hcntadd_subgroup_n;
    logic hcntadd_acc_sel_q,hcntadd_acc_sel_n;
    logic [VRF_IDX_W-1:0] hcntadd_acc_base;

    // ── HCNTCLIP registers ──────────────────────────────────────────────────
    logic [VRF_IDX_W-1:0] hcntclip_dst_base_q,hcntclip_dst_base_n,hcntclip_acc_base;
    logic hcntclip_acc_sel_q,hcntclip_acc_sel_n;
    logic [3:0] hcntclip_threshold_q,hcntclip_threshold_n;
    logic [1:0] hcntclip_chunk_q,hcntclip_chunk_n,hcntclip_subgroup_q,hcntclip_subgroup_n;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] hcntclip_word_q,hcntclip_word_n,hcntclip_word_with_result;
    // hcntclip_acc_base selects the active counter bank; per-entry addresses are
    // formed locally in the uop stages.

    // ── UOP Pipeline Registers ──────────────────────────────────────────────
    // P0: decode + uop issue
    // P1: VRF read address / read wait / uop alignment (VRF output latched in vrf_rd)
    // P2: VRF read data (vrf_rd) directly feeds Lane local compute
    // P2/P3 boundary: lane_*_q registers cut the critical combinational path
    hdec_uop_t uop_p0_q, uop_p0_n, uop_p1_q, uop_p1_n, uop_p2_q, uop_p2_n, uop_p3_q, uop_p3_n;

    // ── Lane compute wires ──────────────────────────────────────────────────
    logic                                hdc_pop_issue, hdc_xor_issue;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] hdc_src0_q, hdc_src0_n;
    logic [LANE_NUM-1:0]                 lane_xor_only_valid;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] lane_bool_result;
    logic [LANE_NUM-1:0]                 lane_cnt_valid;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] lane_cnt_new_counter;
    logic [LANE_NUM-1:0]                 lane_shift_valid;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] lane_shift_a,lane_shift_b,lane_shift_result;
    logic [3:0]                          lane_shift_nibble;
    logic [LANE_NUM-1:0]                 lane_clip_valid;
    logic [LANE_NUM-1:0][15:0]           lane_clip_bits;

    // ── Lane Boundary Registers (P2→P3 cut, split by payload width) ─────────
    // Keep full-width lane_result_q only for true 64-bit lane payloads:
    //   HBIND/HPERM/HCNTADD.
    // Narrow payloads use dedicated registers to avoid feeding zero-extended
    // popcount/clip results into the shared 4×64-bit result mux:
    //   HSIM/HMATCH: lane_popcnt_q[lid]
    //   HCNTCLIP:    lane_clip_q[lid]
    // HDC is single-uop: uop_p3_q determines which payload is live.
    //
    // Future evaluation: HBIND fast bypass
    //   HBIND XOR is shallow; skipping lane_result_q and writing directly to
    //   VRF could save 1 cycle per chunk. Requires Vivado OOC timing proof
    //   that HBIND path is not the critical path before enabling.
    //   Do NOT implement now — keep single active writeback path.
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] lane_result_q, lane_result_n;
    logic [LANE_NUM-1:0][1:0][5:0]       lane_popcnt_part_q;
    logic [LANE_NUM-1:0][15:0]           lane_clip_q, lane_clip_n;

    // ── Scalar Response Registers (P4) ──────────────────────────────────────
    logic [63:0] scalar_response_q, scalar_response_n;
    logic        response_valid_q, response_valid_n;
    hdec_op_t    p4_arch_op_q, p4_arch_op_n;
    logic [10:0] group_dist_q, group_dist_n, group_dist_sum;
    logic signed [11:0] hmatch_budget_step;
    logic        hmatch_budget_step_nonnegative;

    // ── ECC V1 diagonal multiply shadow state ───────────────────────────────
    logic [VRF_IDX_W-1:0] ecc_src_a_q, ecc_src_a_n;
    logic [VRF_IDX_W-1:0] ecc_src_b_q, ecc_src_b_n;
    logic [VRF_IDX_W-1:0] ecc_dst_q,   ecc_dst_n;
    logic [255:0]         ecc_a_q,     ecc_a_n;
    logic [255:0]         ecc_b_q,     ecc_b_n;
    logic [511:0]         ecc_product_q, ecc_product_n;
    logic [31:0]          ecc_leaf_a_q,  ecc_leaf_a_n;
    logic [31:0]          ecc_leaf_b_q,  ecc_leaf_b_n;
    logic [63:0]          ecc_leaf_prod_q, ecc_leaf_prod_n;
    logic [8:0]           ecc_k_q,     ecc_k_n;
    logic [4:0]           ecc_leaf_id_q, ecc_leaf_id_n;
    logic [5:0]           ecc_diag_base_q, ecc_diag_base_n;
    logic                 ecc_pipe0_valid_q, ecc_pipe0_valid_n;
    logic                 ecc_pipe1_valid_q, ecc_pipe1_valid_n;
    logic [5:0]           ecc_pipe0_diag_q, ecc_pipe0_diag_n;
    logic [5:0]           ecc_pipe1_diag_q, ecc_pipe1_diag_n;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] ecc_partial_vec;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] pop_src_a;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] pop_src_b;
    logic [7:0]           ecc_diag8_parity;
    logic                pop_d_mux;
    logic                xor_d_mux;
    logic                ecc_issue_pop;

    // ── Combinational helpers ───────────────────────────────────────────────
    assign hcntadd_acc_base = hcntadd_acc_sel_q ? 6'd48 : 6'd32;
    assign hcntclip_acc_base = hcntclip_acc_sel_q ? 6'd48 : 6'd32;
    assign hmatch_budget_step = hmatch_budget_q - $signed({1'b0, group_dist_q});
    assign hmatch_budget_step_nonnegative = !hmatch_budget_step[11];
    assign hdc_pop_issue = (st_q == S_UOP_P2_LANE) && uop_p2_q.valid
                         && ((uop_p2_q.op_type == UOP_HSIM_CHUNK)
                          || (uop_p2_q.op_type == UOP_HMATCH_CHUNK));
    assign hdc_xor_issue = (st_q == S_UOP_P2_LANE) && uop_p2_q.valid
                         && ((uop_p2_q.op_type == UOP_HBIND_CHUNK)
                          || (uop_p2_q.op_type == UOP_HSIM_CHUNK)
                          || (uop_p2_q.op_type == UOP_HMATCH_CHUNK));
    assign ecc_issue_pop = (st_q == S_ECC_DIAG_ISSUE);
    assign pop_d_mux     = hdc_pop_issue || ecc_issue_pop;
    assign xor_d_mux     = hdc_xor_issue || ecc_issue_pop;
    assign ecc_diag8_parity = {lane_popcnt_part_q[3][1][0], lane_popcnt_part_q[3][0][0],
                               lane_popcnt_part_q[2][1][0], lane_popcnt_part_q[2][0][0],
                               lane_popcnt_part_q[1][1][0], lane_popcnt_part_q[1][0][0],
                               lane_popcnt_part_q[0][1][0], lane_popcnt_part_q[0][0][0]};
    assign ecc_partial_vec[0] = {ecc_diag32_partial(ecc_leaf_a_q, ecc_leaf_b_q, {1'b0, ecc_diag_base_q} + 7'd1),
                                 ecc_diag32_partial(ecc_leaf_a_q, ecc_leaf_b_q, {1'b0, ecc_diag_base_q} + 7'd0)};
    assign ecc_partial_vec[1] = {ecc_diag32_partial(ecc_leaf_a_q, ecc_leaf_b_q, {1'b0, ecc_diag_base_q} + 7'd3),
                                 ecc_diag32_partial(ecc_leaf_a_q, ecc_leaf_b_q, {1'b0, ecc_diag_base_q} + 7'd2)};
    assign ecc_partial_vec[2] = {ecc_diag32_partial(ecc_leaf_a_q, ecc_leaf_b_q, {1'b0, ecc_diag_base_q} + 7'd5),
                                 ecc_diag32_partial(ecc_leaf_a_q, ecc_leaf_b_q, {1'b0, ecc_diag_base_q} + 7'd4)};
    assign ecc_partial_vec[3] = {ecc_diag32_partial(ecc_leaf_a_q, ecc_leaf_b_q, {1'b0, ecc_diag_base_q} + 7'd7),
                                 ecc_diag32_partial(ecc_leaf_a_q, ecc_leaf_b_q, {1'b0, ecc_diag_base_q} + 7'd6)};

    function automatic hdec_op_t p4_arch_from_uop(input hdec_uop_type_e op_type);
        unique case (op_type)
            UOP_HSIM_CHUNK:       p4_arch_from_uop = HDEC_HSIM;
            UOP_HMATCH_CHUNK:     p4_arch_from_uop = HDEC_HMATCH;
            UOP_HCNTCLIP_READ:    p4_arch_from_uop = HDEC_HCNTCLIP;
            default:              p4_arch_from_uop = HDEC_VWR64;
        endcase
    endfunction

    function automatic logic [63:0] hperm_pick_word(input logic [2:0] sel, input logic [3:0][63:0] blk_a, input logic [3:0][63:0] blk_b);
        case(sel)
            3'd0: hperm_pick_word = blk_a[0];
            3'd1: hperm_pick_word = blk_a[1];
            3'd2: hperm_pick_word = blk_a[2];
            3'd3: hperm_pick_word = blk_a[3];
            3'd4: hperm_pick_word = blk_b[0];
            3'd5: hperm_pick_word = blk_b[1];
            3'd6: hperm_pick_word = blk_b[2];
            3'd7: hperm_pick_word = blk_b[3];
            default: hperm_pick_word = '0;
        endcase
    endfunction

    function automatic logic [VRF_IDX_W-1:0] hperm_read_addr(
        input logic [VRF_IDX_W-1:0] base,
        input logic [1:0] chunk,
        input logic [3:0] word_off,
        input logic next_word
    );
        hperm_read_addr = base + {4'b0, chunk} + {4'b0, word_off[3:2]} + VRF_IDX_W'(next_word);
    endfunction

    function automatic logic [31:0] ecc_limb32(input logic [255:0] value, input logic [2:0] idx);
        unique case (idx)
            3'd0: ecc_limb32 = value[31:0];
            3'd1: ecc_limb32 = value[63:32];
            3'd2: ecc_limb32 = value[95:64];
            3'd3: ecc_limb32 = value[127:96];
            3'd4: ecc_limb32 = value[159:128];
            3'd5: ecc_limb32 = value[191:160];
            3'd6: ecc_limb32 = value[223:192];
            3'd7: ecc_limb32 = value[255:224];
            default: ecc_limb32 = '0;
        endcase
    endfunction

    function automatic logic [5:0] ecc_kpd32_leaf_path(input logic [4:0] leaf_id);
        unique case (leaf_id)
            5'd0:  ecc_kpd32_leaf_path = {2'd0, 2'd0, 2'd0};
            5'd1:  ecc_kpd32_leaf_path = {2'd0, 2'd0, 2'd1};
            5'd2:  ecc_kpd32_leaf_path = {2'd0, 2'd0, 2'd2};
            5'd3:  ecc_kpd32_leaf_path = {2'd0, 2'd1, 2'd0};
            5'd4:  ecc_kpd32_leaf_path = {2'd0, 2'd1, 2'd1};
            5'd5:  ecc_kpd32_leaf_path = {2'd0, 2'd1, 2'd2};
            5'd6:  ecc_kpd32_leaf_path = {2'd0, 2'd2, 2'd0};
            5'd7:  ecc_kpd32_leaf_path = {2'd0, 2'd2, 2'd1};
            5'd8:  ecc_kpd32_leaf_path = {2'd0, 2'd2, 2'd2};
            5'd9:  ecc_kpd32_leaf_path = {2'd1, 2'd0, 2'd0};
            5'd10: ecc_kpd32_leaf_path = {2'd1, 2'd0, 2'd1};
            5'd11: ecc_kpd32_leaf_path = {2'd1, 2'd0, 2'd2};
            5'd12: ecc_kpd32_leaf_path = {2'd1, 2'd1, 2'd0};
            5'd13: ecc_kpd32_leaf_path = {2'd1, 2'd1, 2'd1};
            5'd14: ecc_kpd32_leaf_path = {2'd1, 2'd1, 2'd2};
            5'd15: ecc_kpd32_leaf_path = {2'd1, 2'd2, 2'd0};
            5'd16: ecc_kpd32_leaf_path = {2'd1, 2'd2, 2'd1};
            5'd17: ecc_kpd32_leaf_path = {2'd1, 2'd2, 2'd2};
            5'd18: ecc_kpd32_leaf_path = {2'd2, 2'd0, 2'd0};
            5'd19: ecc_kpd32_leaf_path = {2'd2, 2'd0, 2'd1};
            5'd20: ecc_kpd32_leaf_path = {2'd2, 2'd0, 2'd2};
            5'd21: ecc_kpd32_leaf_path = {2'd2, 2'd1, 2'd0};
            5'd22: ecc_kpd32_leaf_path = {2'd2, 2'd1, 2'd1};
            5'd23: ecc_kpd32_leaf_path = {2'd2, 2'd1, 2'd2};
            5'd24: ecc_kpd32_leaf_path = {2'd2, 2'd2, 2'd0};
            5'd25: ecc_kpd32_leaf_path = {2'd2, 2'd2, 2'd1};
            5'd26: ecc_kpd32_leaf_path = {2'd2, 2'd2, 2'd2};
            default: ecc_kpd32_leaf_path = '0;
        endcase
    endfunction

    function automatic logic [31:0] ecc_kpd32_select(
        input logic [31:0] lo_word,
        input logic [31:0] hi_word,
        input logic [1:0]  sel
    );
        unique case (sel)
            2'd0: ecc_kpd32_select = lo_word;
            2'd1: ecc_kpd32_select = lo_word ^ hi_word;
            2'd2: ecc_kpd32_select = hi_word;
            default: ecc_kpd32_select = '0;
        endcase
    endfunction

    function automatic logic [31:0] ecc_kpd32_leaf_word(
        input logic [255:0] value,
        input logic [4:0]   leaf_id
    );
        logic [5:0] path;
        logic [31:0] s0_0, s0_1, s0_2, s0_3;
        logic [31:0] s1_0, s1_1;
        begin
            path = ecc_kpd32_leaf_path(leaf_id);
            s0_0 = ecc_kpd32_select(ecc_limb32(value, 3'd0), ecc_limb32(value, 3'd4), path[5:4]);
            s0_1 = ecc_kpd32_select(ecc_limb32(value, 3'd1), ecc_limb32(value, 3'd5), path[5:4]);
            s0_2 = ecc_kpd32_select(ecc_limb32(value, 3'd2), ecc_limb32(value, 3'd6), path[5:4]);
            s0_3 = ecc_kpd32_select(ecc_limb32(value, 3'd3), ecc_limb32(value, 3'd7), path[5:4]);
            s1_0 = ecc_kpd32_select(s0_0, s0_2, path[3:2]);
            s1_1 = ecc_kpd32_select(s0_1, s0_3, path[3:2]);
            ecc_kpd32_leaf_word = ecc_kpd32_select(s1_0, s1_1, path[1:0]);
        end
    endfunction

    function automatic logic [31:0] ecc_diag32_partial(
        input logic [31:0] a_word,
        input logic [31:0] b_word,
        input logic [6:0]  diag_idx
    );
        logic [31:0] partial;
        int signed b_idx;
        begin
            partial = '0;
            for (int signed i = 0; i < 32; i++) begin
                b_idx = int'(diag_idx) - i;
                if ((b_idx >= 0) && (b_idx < 32))
                    partial[i] = a_word[i] & b_word[b_idx];
            end
            ecc_diag32_partial = partial;
        end
    endfunction

    function automatic logic [63:0] ecc_product_word(
        input logic [511:0] product,
        input logic [2:0]   word_idx
    );
        unique case (word_idx)
            3'd0: ecc_product_word = product[63:0];
            3'd1: ecc_product_word = product[127:64];
            3'd2: ecc_product_word = product[191:128];
            3'd3: ecc_product_word = product[255:192];
            3'd4: ecc_product_word = product[319:256];
            3'd5: ecc_product_word = product[383:320];
            3'd6: ecc_product_word = product[447:384];
            3'd7: ecc_product_word = product[511:448];
            default: ecc_product_word = '0;
        endcase
    endfunction

    function automatic logic [63:0] ecc_kpd32_leaf_store_pack(
        input logic [63:0] leaf_product,
        input logic [5:0]   diag_base,
        input logic [7:0]   parity
    );
        logic [63:0] updated;
        begin
            updated = leaf_product;
            unique case (diag_base)
                6'd0:  updated[7:0]   = parity;
                6'd8:  updated[15:8]  = parity;
                6'd16: updated[23:16] = parity;
                6'd24: updated[31:24] = parity;
                6'd32: updated[39:32] = parity;
                6'd40: updated[47:40] = parity;
                6'd48: updated[55:48] = parity;
                6'd56: begin
                    updated[62:56] = parity[6:0];
                    updated[63]    = 1'b0;
                end
                default: updated = leaf_product;
            endcase
            ecc_kpd32_leaf_store_pack = updated;
        end
    endfunction

    function automatic logic [511:0] ecc_shift_leaf64(
        input logic [63:0] leaf_product,
        input logic [8:0]  offset
    );
        logic [511:0] shifted;
        begin
            shifted = '0;
            unique case (offset)
                9'd0:   shifted[63:0]    = leaf_product;
                9'd32:  shifted[95:32]   = leaf_product;
                9'd64:  shifted[127:64]  = leaf_product;
                9'd96:  shifted[159:96]  = leaf_product;
                9'd128: shifted[191:128] = leaf_product;
                9'd160: shifted[223:160] = leaf_product;
                9'd192: shifted[255:192] = leaf_product;
                9'd224: shifted[287:224] = leaf_product;
                9'd256: shifted[319:256] = leaf_product;
                9'd288: shifted[351:288] = leaf_product;
                9'd320: shifted[383:320] = leaf_product;
                9'd352: shifted[415:352] = leaf_product;
                9'd384: shifted[447:384] = leaf_product;
                9'd416: shifted[479:416] = leaf_product;
                9'd448: shifted[511:448] = leaf_product;
                default: shifted = '0;
            endcase
            ecc_shift_leaf64 = shifted;
        end
    endfunction

    function automatic logic [511:0] ecc_kpd32_fold_leaf(
        input logic [511:0] product,
        input logic [4:0]   leaf_id,
        input logic [63:0]  leaf_product
    );
        logic [511:0] mask;
        begin
            mask = '0;
            unique case (leaf_id)
                5'd0:  mask = ecc_shift_leaf64(leaf_product, 9'd0)   ^ ecc_shift_leaf64(leaf_product, 9'd32)  ^ ecc_shift_leaf64(leaf_product, 9'd64)  ^ ecc_shift_leaf64(leaf_product, 9'd96)
                              ^ ecc_shift_leaf64(leaf_product, 9'd128) ^ ecc_shift_leaf64(leaf_product, 9'd160) ^ ecc_shift_leaf64(leaf_product, 9'd192) ^ ecc_shift_leaf64(leaf_product, 9'd224);
                5'd1:  mask = ecc_shift_leaf64(leaf_product, 9'd32)  ^ ecc_shift_leaf64(leaf_product, 9'd96)  ^ ecc_shift_leaf64(leaf_product, 9'd160) ^ ecc_shift_leaf64(leaf_product, 9'd224);
                5'd2:  mask = ecc_shift_leaf64(leaf_product, 9'd32)  ^ ecc_shift_leaf64(leaf_product, 9'd64)  ^ ecc_shift_leaf64(leaf_product, 9'd96)  ^ ecc_shift_leaf64(leaf_product, 9'd128)
                              ^ ecc_shift_leaf64(leaf_product, 9'd160) ^ ecc_shift_leaf64(leaf_product, 9'd192) ^ ecc_shift_leaf64(leaf_product, 9'd224) ^ ecc_shift_leaf64(leaf_product, 9'd256);
                5'd3:  mask = ecc_shift_leaf64(leaf_product, 9'd64)  ^ ecc_shift_leaf64(leaf_product, 9'd96)  ^ ecc_shift_leaf64(leaf_product, 9'd192) ^ ecc_shift_leaf64(leaf_product, 9'd224);
                5'd4:  mask = ecc_shift_leaf64(leaf_product, 9'd96)  ^ ecc_shift_leaf64(leaf_product, 9'd224);
                5'd5:  mask = ecc_shift_leaf64(leaf_product, 9'd96)  ^ ecc_shift_leaf64(leaf_product, 9'd128) ^ ecc_shift_leaf64(leaf_product, 9'd224) ^ ecc_shift_leaf64(leaf_product, 9'd256);
                5'd6:  mask = ecc_shift_leaf64(leaf_product, 9'd64)  ^ ecc_shift_leaf64(leaf_product, 9'd96)  ^ ecc_shift_leaf64(leaf_product, 9'd128) ^ ecc_shift_leaf64(leaf_product, 9'd160)
                              ^ ecc_shift_leaf64(leaf_product, 9'd192) ^ ecc_shift_leaf64(leaf_product, 9'd224) ^ ecc_shift_leaf64(leaf_product, 9'd256) ^ ecc_shift_leaf64(leaf_product, 9'd288);
                5'd7:  mask = ecc_shift_leaf64(leaf_product, 9'd96)  ^ ecc_shift_leaf64(leaf_product, 9'd160) ^ ecc_shift_leaf64(leaf_product, 9'd224) ^ ecc_shift_leaf64(leaf_product, 9'd288);
                5'd8:  mask = ecc_shift_leaf64(leaf_product, 9'd96)  ^ ecc_shift_leaf64(leaf_product, 9'd128) ^ ecc_shift_leaf64(leaf_product, 9'd160) ^ ecc_shift_leaf64(leaf_product, 9'd192)
                              ^ ecc_shift_leaf64(leaf_product, 9'd224) ^ ecc_shift_leaf64(leaf_product, 9'd256) ^ ecc_shift_leaf64(leaf_product, 9'd288) ^ ecc_shift_leaf64(leaf_product, 9'd320);
                5'd9:  mask = ecc_shift_leaf64(leaf_product, 9'd128) ^ ecc_shift_leaf64(leaf_product, 9'd160) ^ ecc_shift_leaf64(leaf_product, 9'd192) ^ ecc_shift_leaf64(leaf_product, 9'd224);
                5'd10: mask = ecc_shift_leaf64(leaf_product, 9'd160) ^ ecc_shift_leaf64(leaf_product, 9'd224);
                5'd11: mask = ecc_shift_leaf64(leaf_product, 9'd160) ^ ecc_shift_leaf64(leaf_product, 9'd192) ^ ecc_shift_leaf64(leaf_product, 9'd224) ^ ecc_shift_leaf64(leaf_product, 9'd256);
                5'd12: mask = ecc_shift_leaf64(leaf_product, 9'd192) ^ ecc_shift_leaf64(leaf_product, 9'd224);
                5'd13: mask = ecc_shift_leaf64(leaf_product, 9'd224);
                5'd14: mask = ecc_shift_leaf64(leaf_product, 9'd224) ^ ecc_shift_leaf64(leaf_product, 9'd256);
                5'd15: mask = ecc_shift_leaf64(leaf_product, 9'd192) ^ ecc_shift_leaf64(leaf_product, 9'd224) ^ ecc_shift_leaf64(leaf_product, 9'd256) ^ ecc_shift_leaf64(leaf_product, 9'd288);
                5'd16: mask = ecc_shift_leaf64(leaf_product, 9'd224) ^ ecc_shift_leaf64(leaf_product, 9'd288);
                5'd17: mask = ecc_shift_leaf64(leaf_product, 9'd224) ^ ecc_shift_leaf64(leaf_product, 9'd256) ^ ecc_shift_leaf64(leaf_product, 9'd288) ^ ecc_shift_leaf64(leaf_product, 9'd320);
                5'd18: mask = ecc_shift_leaf64(leaf_product, 9'd128) ^ ecc_shift_leaf64(leaf_product, 9'd160) ^ ecc_shift_leaf64(leaf_product, 9'd192) ^ ecc_shift_leaf64(leaf_product, 9'd224)
                              ^ ecc_shift_leaf64(leaf_product, 9'd256) ^ ecc_shift_leaf64(leaf_product, 9'd288) ^ ecc_shift_leaf64(leaf_product, 9'd320) ^ ecc_shift_leaf64(leaf_product, 9'd352);
                5'd19: mask = ecc_shift_leaf64(leaf_product, 9'd160) ^ ecc_shift_leaf64(leaf_product, 9'd224) ^ ecc_shift_leaf64(leaf_product, 9'd288) ^ ecc_shift_leaf64(leaf_product, 9'd352);
                5'd20: mask = ecc_shift_leaf64(leaf_product, 9'd160) ^ ecc_shift_leaf64(leaf_product, 9'd192) ^ ecc_shift_leaf64(leaf_product, 9'd224) ^ ecc_shift_leaf64(leaf_product, 9'd256)
                              ^ ecc_shift_leaf64(leaf_product, 9'd288) ^ ecc_shift_leaf64(leaf_product, 9'd320) ^ ecc_shift_leaf64(leaf_product, 9'd352) ^ ecc_shift_leaf64(leaf_product, 9'd384);
                5'd21: mask = ecc_shift_leaf64(leaf_product, 9'd192) ^ ecc_shift_leaf64(leaf_product, 9'd224) ^ ecc_shift_leaf64(leaf_product, 9'd320) ^ ecc_shift_leaf64(leaf_product, 9'd352);
                5'd22: mask = ecc_shift_leaf64(leaf_product, 9'd224) ^ ecc_shift_leaf64(leaf_product, 9'd352);
                5'd23: mask = ecc_shift_leaf64(leaf_product, 9'd224) ^ ecc_shift_leaf64(leaf_product, 9'd256) ^ ecc_shift_leaf64(leaf_product, 9'd352) ^ ecc_shift_leaf64(leaf_product, 9'd384);
                5'd24: mask = ecc_shift_leaf64(leaf_product, 9'd192) ^ ecc_shift_leaf64(leaf_product, 9'd224) ^ ecc_shift_leaf64(leaf_product, 9'd256) ^ ecc_shift_leaf64(leaf_product, 9'd288)
                              ^ ecc_shift_leaf64(leaf_product, 9'd320) ^ ecc_shift_leaf64(leaf_product, 9'd352) ^ ecc_shift_leaf64(leaf_product, 9'd384) ^ ecc_shift_leaf64(leaf_product, 9'd416);
                5'd25: mask = ecc_shift_leaf64(leaf_product, 9'd224) ^ ecc_shift_leaf64(leaf_product, 9'd288) ^ ecc_shift_leaf64(leaf_product, 9'd352) ^ ecc_shift_leaf64(leaf_product, 9'd416);
                5'd26: mask = ecc_shift_leaf64(leaf_product, 9'd224) ^ ecc_shift_leaf64(leaf_product, 9'd256) ^ ecc_shift_leaf64(leaf_product, 9'd288) ^ ecc_shift_leaf64(leaf_product, 9'd320)
                              ^ ecc_shift_leaf64(leaf_product, 9'd352) ^ ecc_shift_leaf64(leaf_product, 9'd384) ^ ecc_shift_leaf64(leaf_product, 9'd416) ^ ecc_shift_leaf64(leaf_product, 9'd448);
                default: mask = '0;
            endcase
            ecc_kpd32_fold_leaf = product ^ mask;
        end
    endfunction

    // ── 4× Lane instances ───────────────────────────────────────────────────
    for (genvar lid = 0; lid < LANE_NUM; lid++) begin : gen_lane
        assign pop_src_a[lid] = ecc_issue_pop ? ecc_partial_vec[lid]
                              : hdc_xor_issue ? hdc_src0_q[lid]
                              : vrf_rd[lid];
        assign pop_src_b[lid] = ecc_issue_pop ? '0 : vrf_rd[lid];

        hdec_p2_pop_slice i_p2_pop_slice (
            .clk_i,
            .rst_ni,
            .pop_d_i          (pop_d_mux),
            .xor_d_i          (xor_d_mux),
            .src_a_i          (pop_src_a[lid]),
            .src_b_i          (pop_src_b[lid]),
            .xor_only_valid_o (lane_xor_only_valid[lid]),
            .xor_result_o     (lane_bool_result[lid]),
            .popcount_part_q_o(lane_popcnt_part_q[lid])
        );

        hdec_lane_4x64 #(.LANE_ID(lid)) i_lane (
            .clk_i, .rst_ni,
            .vrf_ra_addr_o(), .vrf_ra_data_i('0),
            .vrf_we_o(), .vrf_wa_addr_o(), .vrf_wdata_o(),
            .ctrl_valid_i('0), .ctrl_ready_o(), .ctrl_owner_i('0), .ctrl_op_i(HDEC_VWR64),
            .ctrl_rd_reg_i('0), .ctrl_wr_reg_i('0), .ctrl_wr_data_i('0),
            .ctrl_is_write_i('0), .ctrl_is_read_i('0),
            .res_valid_o(), .res_ready_i('0), .res_data_o(), .res_owner_o(),
            .neighbor_in_i('0), .neighbor_out_o(), .carry_in_i('0), .carry_out_o(),
            .borrow_in_i('0), .borrow_out_o(), .count_in_i('0), .count_out_o(),
            .flag_in_i('0), .flag_out_o(), .local_wb_data_o(), .local_wb_addr_o(), .local_wb_we_o(),
            .bool_valid_i(1'b0),
            .bool_src_a_i('0),
            .bool_src_b_i('0),
            .bool_result_o(),
            .popcount_count_o(),
            .cnt_valid_i(lane_cnt_valid[lid]),
            .cnt_hv_word_i(hcntadd_hv_q[lid]),
            .cnt_old_counter_i(vrf_rd[lid]),
            .cnt_subgroup_i(hcntadd_subgroup_q),
            .cnt_new_counter_o(lane_cnt_new_counter[lid]),
            .shift_valid_i(lane_shift_valid[lid]),
            .shift_src_a_i(lane_shift_a[lid]),
            .shift_src_b_i(lane_shift_b[lid]),
            .shift_nibble_i(lane_shift_nibble),
            .shift_result_o(lane_shift_result[lid]),
            .clip_valid_i(lane_clip_valid[lid]),
            .clip_counter_i(vrf_rd[lid]),
            .clip_threshold_i(hcntclip_threshold_q),
            .clip_bits_o(lane_clip_bits[lid])
        );
    end

    assign group_dist_sum = {5'b0, lane_popcnt_part_q[0][0]} + {5'b0, lane_popcnt_part_q[0][1]}
                          + {5'b0, lane_popcnt_part_q[1][0]} + {5'b0, lane_popcnt_part_q[1][1]}
                          + {5'b0, lane_popcnt_part_q[2][0]} + {5'b0, lane_popcnt_part_q[2][1]}
                          + {5'b0, lane_popcnt_part_q[3][0]} + {5'b0, lane_popcnt_part_q[3][1]};

    // ── Main FSM ────────────────────────────────────────────────────────────
    always_comb begin
        st_n=st_q; ready_o=(st_q==S_IDLE); valid_o=(st_q==S_RESULT); result_o=response_valid_q?scalar_response_q:res_q;
        res_n='0; op_n=op_q; a_n=a_q; b_n=b_q; bk_n=bk_q; vaddr_bank_n=vaddr_bank_q; vaddr_idx_n=vaddr_idx_q;
        clr_cnt_n=clr_cnt_q; clr_base_n=clr_base_q;
        chunk_cnt_n=chunk_cnt_q;
        hb_dst_base_n=hb_dst_base_q; hb_src0_base_n=hb_src0_base_q; hb_src1_base_n=hb_src1_base_q;
        hsim_src0_base_n=hsim_src0_base_q; hsim_src1_base_n=hsim_src1_base_q; hsim_total_n=hsim_total_q;
        group_dist_n=group_dist_q;
        hmatch_last_idx_n=hmatch_last_idx_q; hmatch_best_idx_n=hmatch_best_idx_q; hmatch_class_slot_n=hmatch_class_slot_q; hmatch_best_dist_n=hmatch_best_dist_q;
        hmatch_budget_n=hmatch_budget_q; hmatch_update_n=hmatch_update_q;
        hperm_a_n=hperm_a_q; hperm_dst_base_n=hperm_dst_base_q; hperm_src_base_n=hperm_src_base_q;
        hperm_word_off_n=hperm_word_off_q; hperm_nibble_n=hperm_nibble_q; hperm_lane_base_n=hperm_lane_base_q;
        hcntadd_hv_n=hcntadd_hv_q; hcntadd_hv_slot_n=hcntadd_hv_slot_q; hcntadd_chunk_n=hcntadd_chunk_q; hcntadd_subgroup_n=hcntadd_subgroup_q; hcntadd_acc_sel_n=hcntadd_acc_sel_q;
        hcntclip_dst_base_n=hcntclip_dst_base_q; hcntclip_acc_sel_n=hcntclip_acc_sel_q; hcntclip_threshold_n=hcntclip_threshold_q; hcntclip_chunk_n=hcntclip_chunk_q; hcntclip_subgroup_n=hcntclip_subgroup_q; hcntclip_word_n=hcntclip_word_q; hcntclip_word_with_result=hcntclip_word_q;
        uop_p0_n=uop_p0_q; uop_p1_n=uop_p1_q; uop_p2_n=uop_p2_q; uop_p3_n=uop_p3_q;
        hdc_src0_n=hdc_src0_q;
        lane_result_n=lane_result_q; lane_clip_n=lane_clip_q;
        scalar_response_n=scalar_response_q; response_valid_n=response_valid_q; p4_arch_op_n=p4_arch_op_q;
        ecc_src_a_n=ecc_src_a_q; ecc_src_b_n=ecc_src_b_q; ecc_dst_n=ecc_dst_q;
        ecc_a_n=ecc_a_q; ecc_b_n=ecc_b_q; ecc_product_n=ecc_product_q;
        ecc_leaf_a_n=ecc_leaf_a_q; ecc_leaf_b_n=ecc_leaf_b_q; ecc_leaf_prod_n=ecc_leaf_prod_q; ecc_k_n=ecc_k_q;
        ecc_leaf_id_n=ecc_leaf_id_q; ecc_diag_base_n=ecc_diag_base_q;
        ecc_pipe0_valid_n=1'b0; ecc_pipe0_diag_n=ecc_pipe0_diag_q;
        ecc_pipe1_valid_n=ecc_pipe0_valid_q; ecc_pipe1_diag_n=ecc_pipe0_diag_q;
        lane_cnt_valid='0;
        lane_shift_valid='0;
        lane_shift_a='0; lane_shift_b='0; lane_shift_nibble=hperm_nibble_q;
        lane_clip_valid='0;
        vrf_ra='0; vrf_we='0; vrf_wa='0; vrf_wd='0;

        case(st_q)
        S_IDLE: if(valid_i&&ready_o)begin op_n=operator_i;a_n=operand_a_i;b_n=operand_b_i;st_n=S_EXEC;end

        S_EXEC: begin uop_p0_n='0; unique case(op_q)
            HDEC_VADDR: begin vaddr_bank_n=a_q[7:6];vaddr_idx_n=a_q[5:0];res_n='0;st_n=S_RESULT;end
            HDEC_VWR64: begin vrf_we[vaddr_bank_q]=1'b1;vrf_wa[vaddr_bank_q]=vaddr_idx_q;vrf_wd[vaddr_bank_q]=a_q;res_n='0;st_n=S_VWR_WAIT;end
            HDEC_VRD64: begin vrf_ra[vaddr_bank_q]=vaddr_idx_q;bk_n=vaddr_bank_q;st_n=S_RD_WAIT;end

            HDEC_ECC_MUL: begin
                if (a_q[17:12] == 6'd63) begin
                    res_n={62'b0,STATUS_ERROR};st_n=S_RESULT;
                end else begin
                    ecc_dst_n   = a_q[17:12];
                    ecc_src_a_n = a_q[11:6];
                    ecc_src_b_n = a_q[5:0];
                    ecc_a_n     = '0;
                    ecc_b_n     = '0;
                    ecc_product_n = '0;
                    ecc_leaf_a_n  = '0;
                    ecc_leaf_b_n  = '0;
                    ecc_leaf_prod_n = '0;
                    ecc_leaf_id_n = '0;
                    ecc_diag_base_n = '0;
                    ecc_pipe0_valid_n = 1'b0;
                    ecc_pipe1_valid_n = 1'b0;
                    ecc_k_n     = '0;
                    vrf_ra[0]=a_q[11:6]; vrf_ra[1]=a_q[11:6];
                    vrf_ra[2]=a_q[11:6]; vrf_ra[3]=a_q[11:6];
                    st_n=S_ECC_LOAD_A_WAIT;
                end
            end

            HDEC_ECC_STATUS: begin
                res_n={56'b0, ecc_dst_q, STATUS_OK};
                st_n=S_RESULT;
            end

            HDEC_HCLR: begin
                clr_base_n={a_q[3:0],2'b00};clr_cnt_n=4'd0;st_n=S_CLR;
            end

            HDEC_HCNTCLR: begin
                clr_base_n=a_q[0]?6'd48:6'd32;clr_cnt_n=4'd0;st_n=S_CLR;
            end

            HDEC_HCNTADD: begin
                if(a_q[3])begin res_n={62'b0,STATUS_ERROR};st_n=S_RESULT;end
                else begin
                    hcntadd_hv_slot_n=a_q[2:0];
                    hcntadd_acc_sel_n=a_q[4];
                    hcntadd_chunk_n=2'd0;
                    hcntadd_subgroup_n=2'd0;
                    uop_p0_n.valid       = 1'b1;
                    uop_p0_n.op_type     = UOP_HCNTADD_SUBGROUP;
                    uop_p0_n.chunk_idx   = 2'd0;
                    uop_p0_n.subgroup_idx= 2'd0;
                    uop_p0_n.src0_addr   = {1'b0, a_q[2:0], 2'b00};
                    uop_p0_n.src1_addr   = a_q[4] ? 6'd48 : 6'd32;
                    uop_p0_n.dst_addr    = a_q[4] ? 6'd48 : 6'd32;
                    uop_p0_n.use_counter = 1'b1;
                    st_n=S_UOP_P1_RD0;
                end
            end

            HDEC_HBIND: begin
                hb_dst_base_n ={a_q[3:0], 2'b00};
                hb_src0_base_n={a_q[7:4], 2'b00};
                hb_src1_base_n={a_q[11:8],2'b00};
                chunk_cnt_n=2'd0;
                uop_p0_n.valid        = 1'b1;
                uop_p0_n.op_type      = UOP_HBIND_CHUNK;
                uop_p0_n.src0_addr    = hb_src0_base_n;
                uop_p0_n.src1_addr    = hb_src1_base_n;
                uop_p0_n.dst_addr     = hb_dst_base_n;
                uop_p0_n.chunk_idx    = 2'd0;
                st_n=S_UOP_P1_RD0;
            end

            HDEC_HSIM: begin
                hsim_src0_base_n={a_q[3:0],2'b00};
                hsim_src1_base_n={a_q[7:4],2'b00};
                st_n=S_HSIM_INIT;
            end

            HDEC_HMATCH: begin
                hsim_src0_base_n={a_q[3:0],2'b00};
                hsim_src1_base_n={a_q[7:4],2'b00};
                hmatch_class_slot_n=a_q[7:4];
                hmatch_last_idx_n=a_q[10:8] - 3'd1;
                if((a_q[15:8] == 8'd0) || (({5'b0,a_q[7:4]} + {1'b0,a_q[15:8]} - 9'd1) > 9'd7))begin
                    res_n={62'b0,STATUS_ERROR};st_n=S_RESULT;
                end else begin
                    st_n=S_HMATCH_INIT;
                end
            end

            HDEC_HCNTCLIP: begin
                hcntclip_dst_base_n={a_q[2:0],2'b00};
                hcntclip_acc_sel_n=a_q[3];
                hcntclip_threshold_n=a_q[7:4];
                hcntclip_chunk_n=2'd0;
                hcntclip_subgroup_n=2'd0;
                hcntclip_word_n='0;
                uop_p0_n.valid       = 1'b1;
                uop_p0_n.op_type     = UOP_HCNTCLIP_READ;
                uop_p0_n.chunk_idx   = 2'd0;
                uop_p0_n.subgroup_idx= 2'd0;
                uop_p0_n.src0_addr   = (a_q[3] ? 6'd48 : 6'd32);
                uop_p0_n.src1_addr   = (a_q[3] ? 6'd48 : 6'd32);
                uop_p0_n.use_clip    = 1'b1;
                st_n=S_UOP_P1_RD0;
            end

            HDEC_HPERM: begin
                if((a_q[9:8] != 2'b00) || (a_q[3:0] == a_q[7:4]))begin res_n={62'b0,STATUS_ERROR};st_n=S_RESULT;end
                else begin
                    hperm_dst_base_n={a_q[3:0],2'b00};
                    hperm_src_base_n={a_q[7:4],2'b00};
                    hperm_word_off_n=a_q[17:14];
                    hperm_nibble_n=a_q[13:10];
                    hperm_lane_base_n=a_q[15:14];
                    chunk_cnt_n=2'd0;
                    uop_p0_n.valid       = 1'b1;
                    uop_p0_n.op_type     = UOP_HPERM_CHUNK;
                    uop_p0_n.chunk_idx   = 2'd0;
                    uop_p0_n.src0_addr   = hperm_read_addr(hperm_src_base_n, 2'd0, a_q[17:14], 1'b0);
                    uop_p0_n.src1_addr   = hperm_read_addr(hperm_src_base_n, 2'd0, a_q[17:14], 1'b1);
                    uop_p0_n.dst_addr    = hperm_dst_base_n;
                    uop_p0_n.perm_nibble = hperm_nibble_n;
                    uop_p0_n.use_shift   = 1'b1;
                    st_n=S_UOP_P1_RD0;
                end
            end

            default: begin res_n={62'b0,STATUS_NOT_IMPLEMENTED};st_n=S_RESULT;end
        endcase end

        S_VWR_WAIT: begin res_n='0;st_n=S_RESULT;end

        S_RD_WAIT: begin st_n=S_RD_CAPTURE;end

        S_RD_CAPTURE: begin res_n=vrf_rd[bk_q];st_n=S_RESULT;end

        // ── ECC V1 raw GF(2) diagonal multiply ─────────────────────────────
        S_ECC_LOAD_A_WAIT: begin
            st_n=S_ECC_LOAD_A;
        end

        S_ECC_LOAD_A: begin
            ecc_a_n = {vrf_rd[3], vrf_rd[2], vrf_rd[1], vrf_rd[0]};
            vrf_ra[0]=ecc_src_b_q; vrf_ra[1]=ecc_src_b_q;
            vrf_ra[2]=ecc_src_b_q; vrf_ra[3]=ecc_src_b_q;
            st_n=S_ECC_LOAD_B_WAIT;
        end

        S_ECC_LOAD_B_WAIT: begin
            st_n=S_ECC_LOAD_B;
        end

        S_ECC_LOAD_B: begin
            ecc_b_n    = {vrf_rd[3], vrf_rd[2], vrf_rd[1], vrf_rd[0]};
            ecc_product_n = '0;
            ecc_leaf_prod_n = '0;
            ecc_leaf_id_n = 5'd0;
            ecc_diag_base_n = 6'd0;
            ecc_k_n = '0;
            ecc_pipe0_valid_n = 1'b0;
            ecc_pipe1_valid_n = 1'b0;
            st_n=S_ECC_KPD32_FORM;
        end

        S_ECC_KPD32_FORM: begin
            ecc_leaf_a_n = ecc_kpd32_leaf_word(ecc_a_q, ecc_leaf_id_q);
            ecc_leaf_b_n = ecc_kpd32_leaf_word(ecc_b_q, ecc_leaf_id_q);
            ecc_leaf_prod_n = '0;
            ecc_diag_base_n = 6'd0;
            st_n=S_ECC_DIAG_ISSUE;
        end

        S_ECC_DIAG_ISSUE: begin
            if (ecc_pipe1_valid_q)
                ecc_leaf_prod_n = ecc_kpd32_leaf_store_pack(ecc_leaf_prod_q, ecc_pipe1_diag_q, ecc_diag8_parity);
            ecc_pipe0_valid_n = 1'b1;
            ecc_pipe0_diag_n  = ecc_diag_base_q;
            if (ecc_diag_base_q == 6'd56) begin
                st_n=S_ECC_DIAG_WAIT;
            end else begin
                ecc_diag_base_n = ecc_diag_base_q + 6'd8;
                st_n=S_ECC_DIAG_ISSUE;
            end
        end

        S_ECC_DIAG_WAIT: begin
            if (ecc_pipe1_valid_q)
                ecc_leaf_prod_n = ecc_kpd32_leaf_store_pack(ecc_leaf_prod_q, ecc_pipe1_diag_q, ecc_diag8_parity);
            st_n=S_ECC_DIAG_ACCUM;
        end

        S_ECC_DIAG_ACCUM: begin
            if (ecc_pipe1_valid_q)
                ecc_leaf_prod_n = ecc_kpd32_leaf_store_pack(ecc_leaf_prod_q, ecc_pipe1_diag_q, ecc_diag8_parity);
            st_n=S_ECC_LEAF_FOLD;
        end

        S_ECC_LEAF_FOLD: begin
            ecc_product_n = ecc_kpd32_fold_leaf(ecc_product_q, ecc_leaf_id_q, ecc_leaf_prod_q);
            if (ecc_leaf_id_q == 5'd26) begin
                ecc_k_n = '0;
                st_n=S_ECC_WRITE_WORD;
            end else begin
                ecc_leaf_id_n = ecc_leaf_id_q + 5'd1;
                st_n=S_ECC_KPD32_FORM;
            end
        end

        S_ECC_WRITE_WORD: begin
            vrf_we[ecc_k_q[1:0]]=1'b1;
            vrf_wa[ecc_k_q[1:0]]=ecc_dst_q + {5'b0, ecc_k_q[2]};
            vrf_wd[ecc_k_q[1:0]]=ecc_product_word(ecc_product_q, ecc_k_q[2:0]);
            if (ecc_k_q[2:0] == 3'd7) begin
                res_n={56'b0, ecc_dst_q, STATUS_OK};
                st_n=S_ECC_WRITE_DRAIN;
            end else begin
                ecc_k_n=ecc_k_q + 9'd1;
                st_n=S_ECC_WRITE_WORD;
            end
        end

        // ── S_CLR: shared by HCLR (4 entries) and HCNTCLR (16 entries) ──────
        S_ECC_WRITE_DRAIN: begin
            res_n={56'b0, ecc_dst_q, STATUS_OK};
            st_n=S_RESULT;
        end

        S_CLR: begin
            vrf_we='1;
            vrf_wa[0]=clr_base_q+clr_cnt_q; vrf_wa[1]=clr_base_q+clr_cnt_q;
            vrf_wa[2]=clr_base_q+clr_cnt_q; vrf_wa[3]=clr_base_q+clr_cnt_q;
            vrf_wd='0;
            if((op_q==HDEC_HCLR&&clr_cnt_q==4'd3)||(op_q==HDEC_HCNTCLR&&clr_cnt_q==4'd15))begin res_n='0;st_n=S_CLR_DRAIN;end
            else clr_cnt_n=clr_cnt_q+4'd1;
        end

        S_CLR_DRAIN: begin
            res_n='0;
            st_n=S_RESULT;
        end

        // Keep operand decode/validation out of the hot uop and HMATCH CE cones.
        S_HSIM_INIT: begin
            hsim_total_n='0;
            uop_p0_n='0;
            uop_p0_n.valid        = 1'b1;
            uop_p0_n.op_type      = UOP_HSIM_CHUNK;
            uop_p0_n.src0_addr    = hsim_src0_base_q;
            uop_p0_n.src1_addr    = hsim_src1_base_q;
            uop_p0_n.chunk_idx    = 2'd0;
            st_n=S_UOP_P1_RD0;
        end

        S_HMATCH_INIT: begin
            hmatch_best_idx_n=3'd0;
            hmatch_best_dist_n=11'd1025;
            hmatch_budget_n=12'sd1024;
            hmatch_update_n=1'b0;
            hsim_total_n='0;
            uop_p0_n='0;
            uop_p0_n.valid        = 1'b1;
            uop_p0_n.op_type      = UOP_HMATCH_CHUNK;
            uop_p0_n.src0_addr    = hsim_src0_base_q;
            uop_p0_n.src1_addr    = hsim_src1_base_q;
            uop_p0_n.chunk_idx    = 2'd0;
            uop_p0_n.class_idx    = 3'd0;
            uop_p0_n.is_last_class = (hmatch_last_idx_q == 3'd0);
            st_n=S_UOP_P1_RD0;
        end

        // ── UOP Pipeline ─────────────────────────────────────────────────────
        S_UOP_P1_RD0: begin
            if ((uop_p0_q.op_type == UOP_HMATCH_CHUNK) && (uop_p0_q.chunk_idx == 2'd0)
                    && (uop_p0_q.class_idx != uop_p3_q.class_idx)) begin
                if (hmatch_update_q) begin
                    hmatch_best_dist_n = hsim_total_q;
                    hmatch_best_idx_n  = uop_p3_q.class_idx;
                end
                hmatch_update_n = 1'b0;
                hsim_total_n    = '0;
                hmatch_budget_n = (hmatch_update_q ? $signed({1'b0, hsim_total_q})
                                                    : $signed({1'b0, hmatch_best_dist_q})) - 12'sd1;
            end
            uop_p1_n       = uop_p0_q;
            uop_p0_n.valid = 1'b0;
            if (uop_p0_q.op_type == UOP_HPERM_CHUNK)
                chunk_cnt_n = uop_p0_q.chunk_idx;
            vrf_ra[0]=uop_p0_q.src0_addr; vrf_ra[1]=uop_p0_q.src0_addr;
            vrf_ra[2]=uop_p0_q.src0_addr; vrf_ra[3]=uop_p0_q.src0_addr;
            st_n=S_UOP_P1_RD0_WAIT;
        end

        S_UOP_P1_RD0_WAIT: begin
            st_n=S_UOP_P1_RD1;
        end

        S_UOP_P1_RD1: begin
            uop_p2_n       = uop_p1_q;
            uop_p1_n.valid = 1'b0;
            if (uop_p1_q.op_type == UOP_HPERM_CHUNK) begin
                hperm_a_n = vrf_rd;
            end else begin
                if (uop_p1_q.op_type == UOP_HCNTADD_SUBGROUP) hcntadd_hv_n = vrf_rd;
                if ((uop_p1_q.op_type == UOP_HBIND_CHUNK)
                 || (uop_p1_q.op_type == UOP_HSIM_CHUNK)
                 || (uop_p1_q.op_type == UOP_HMATCH_CHUNK))
                    hdc_src0_n = vrf_rd;
            end
            vrf_ra[0]=uop_p1_q.src1_addr; vrf_ra[1]=uop_p1_q.src1_addr;
            vrf_ra[2]=uop_p1_q.src1_addr; vrf_ra[3]=uop_p1_q.src1_addr;
            st_n=S_UOP_P1_RD1_WAIT;
        end

        S_UOP_P1_RD1_WAIT: begin
            st_n=S_UOP_P2_LANE;
        end

        S_UOP_P2_LANE: begin
            uop_p3_n           = uop_p2_q;
            uop_p2_n.valid     = 1'b0;
`ifndef SYNTHESIS
            assert ($onehot0({
                    ((uop_p2_q.op_type == UOP_HSIM_CHUNK)
                  || (uop_p2_q.op_type == UOP_HMATCH_CHUNK)),
                    uop_p2_q.use_counter,
                    uop_p2_q.use_shift,
                    uop_p2_q.use_clip,
                    (uop_p2_q.op_type == UOP_HBIND_CHUNK)
                }))
                else $error("HDEC P2 invalid compute mode flags: op_type=%0d",
                            uop_p2_q.op_type);
`endif
            if (uop_p2_q.use_counter)
                lane_cnt_valid = '1;
            if (uop_p2_q.use_shift) begin
                lane_shift_valid = '1;
                lane_shift_nibble = uop_p2_q.perm_nibble;
                lane_shift_a[0]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd0,hperm_a_q,vrf_rd);
                lane_shift_a[1]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd1,hperm_a_q,vrf_rd);
                lane_shift_a[2]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd2,hperm_a_q,vrf_rd);
                lane_shift_a[3]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd3,hperm_a_q,vrf_rd);
                lane_shift_b[0]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd1,hperm_a_q,vrf_rd);
                lane_shift_b[1]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd2,hperm_a_q,vrf_rd);
                lane_shift_b[2]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd3,hperm_a_q,vrf_rd);
                lane_shift_b[3]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd4,hperm_a_q,vrf_rd);
            end
            if (uop_p2_q.use_clip)
                lane_clip_valid = '1;
            if (uop_p2_q.valid && uop_p2_q.use_counter)
                lane_result_n = lane_cnt_new_counter;
            else if (uop_p2_q.valid && uop_p2_q.use_shift)
                lane_result_n = lane_shift_result;
            else if (uop_p2_q.valid && uop_p2_q.use_clip) begin
                lane_clip_n[0] = lane_clip_bits[0];
                lane_clip_n[1] = lane_clip_bits[1];
                lane_clip_n[2] = lane_clip_bits[2];
                lane_clip_n[3] = lane_clip_bits[3];
            end
            st_n=S_UOP_P3_GLOBAL;
        end

        S_UOP_P3_GLOBAL: begin
            uop_p3_n.valid  = 1'b0;
            p4_arch_op_n    = p4_arch_from_uop(uop_p3_q.op_type);
            unique case (uop_p3_q.op_type)
            UOP_HBIND_CHUNK: begin
                vrf_we = '1;
                vrf_wa[0]=uop_p3_q.dst_addr; vrf_wa[1]=uop_p3_q.dst_addr;
                vrf_wa[2]=uop_p3_q.dst_addr; vrf_wa[3]=uop_p3_q.dst_addr;
                vrf_wd = lane_bool_result;
                if (uop_p3_q.chunk_idx == 2'd3) st_n = S_UOP_P4_RESP;
                else begin
                    uop_p0_n = uop_p3_q; uop_p0_n.valid = 1'b1;
                    uop_p0_n.chunk_idx = uop_p3_q.chunk_idx + 2'd1;
                    uop_p0_n.src0_addr = hb_src0_base_q + (uop_p3_q.chunk_idx + 2'd1);
                    uop_p0_n.src1_addr = hb_src1_base_q + (uop_p3_q.chunk_idx + 2'd1);
                    uop_p0_n.dst_addr  = hb_dst_base_q  + (uop_p3_q.chunk_idx + 2'd1);
                    st_n = S_UOP_P1_RD0;
                end
            end
            UOP_HSIM_CHUNK, UOP_HMATCH_CHUNK: begin
                st_n = S_UOP_P3_POP_CAPTURE;
            end
            UOP_HCNTADD_SUBGROUP: begin
                vrf_we = '1;
                vrf_wa[0]=uop_p3_q.dst_addr;
                vrf_wa[1]=vrf_wa[0]; vrf_wa[2]=vrf_wa[0]; vrf_wa[3]=vrf_wa[0];
                vrf_wd = lane_result_q;
                if (uop_p3_q.subgroup_idx < 2'd3) begin
                    hcntadd_subgroup_n = uop_p3_q.subgroup_idx + 2'd1;
                    vrf_ra[0]=hcntadd_acc_base+{2'b00,uop_p3_q.chunk_idx,2'b00}+{4'b0,hcntadd_subgroup_n};
                    vrf_ra[1]=vrf_ra[0]; vrf_ra[2]=vrf_ra[0]; vrf_ra[3]=vrf_ra[0];
                    // Advance uop to P2 directly (skip P1_RD0/P1_RD1)
                    uop_p2_n = uop_p3_q; uop_p2_n.valid = 1'b1;
                    uop_p2_n.subgroup_idx = hcntadd_subgroup_n;
                    uop_p2_n.dst_addr = uop_p3_q.dst_addr + 6'd1;
                    uop_p1_n.valid = 1'b0; uop_p0_n.valid = 1'b0;
                    st_n = S_UOP_P3_VRF_WAIT;
                end else if (uop_p3_q.chunk_idx < 2'd3) begin
                    hcntadd_subgroup_n = 2'd0;
                    hcntadd_chunk_n    = uop_p3_q.chunk_idx + 2'd1;
                    uop_p0_n = uop_p3_q; uop_p0_n.valid = 1'b1;
                    uop_p0_n.chunk_idx    = hcntadd_chunk_n;
                    uop_p0_n.subgroup_idx = 2'd0;
                    uop_p0_n.src0_addr = {1'b0,hcntadd_hv_slot_q,2'b00}+{4'b0,hcntadd_chunk_n};
                    uop_p0_n.src1_addr = hcntadd_acc_base+{2'b00,hcntadd_chunk_n,2'b00};
                    uop_p0_n.dst_addr  = hcntadd_acc_base+{2'b00,hcntadd_chunk_n,2'b00};
                    st_n = S_UOP_P1_RD0;
                end else st_n = S_UOP_P4_RESP;
            end
            UOP_HCNTCLIP_READ: begin
            hcntclip_word_with_result = hcntclip_word_q;
                hcntclip_word_with_result[0][{uop_p3_q.subgroup_idx,4'b0000} +: 16] = lane_clip_q[0];
                hcntclip_word_with_result[1][{uop_p3_q.subgroup_idx,4'b0000} +: 16] = lane_clip_q[1];
                hcntclip_word_with_result[2][{uop_p3_q.subgroup_idx,4'b0000} +: 16] = lane_clip_q[2];
                hcntclip_word_with_result[3][{uop_p3_q.subgroup_idx,4'b0000} +: 16] = lane_clip_q[3];
                hcntclip_word_n = hcntclip_word_with_result;
                if (uop_p3_q.subgroup_idx < 2'd3) begin
                    hcntclip_subgroup_n = uop_p3_q.subgroup_idx + 2'd1;
                    vrf_ra[0]=hcntclip_acc_base+{2'b00,uop_p3_q.chunk_idx,2'b00}+{4'b0,hcntclip_subgroup_n};
                    vrf_ra[1]=vrf_ra[0]; vrf_ra[2]=vrf_ra[0]; vrf_ra[3]=vrf_ra[0];
                    uop_p2_n = uop_p3_q; uop_p2_n.valid = 1'b1;
                    uop_p2_n.subgroup_idx = hcntclip_subgroup_n;
                    uop_p1_n.valid = 1'b0; uop_p0_n.valid = 1'b0;
                    st_n = S_UOP_P3_VRF_WAIT;
                end else begin
                    // word complete; go to dedicated write state
                    hcntclip_subgroup_n = 2'd0;
                    st_n = S_UOP_CLIP_WRITE;
                end
            end
            UOP_HPERM_CHUNK: begin
                vrf_we = '1;
                vrf_wa[0]=uop_p3_q.dst_addr; vrf_wa[1]=uop_p3_q.dst_addr;
                vrf_wa[2]=uop_p3_q.dst_addr; vrf_wa[3]=uop_p3_q.dst_addr;
                vrf_wd = lane_result_q;
                if (uop_p3_q.chunk_idx == 2'd3) st_n = S_UOP_P4_RESP;
                else begin
                    chunk_cnt_n = uop_p3_q.chunk_idx + 2'd1;
                    uop_p0_n = uop_p3_q; uop_p0_n.valid = 1'b1;
                    uop_p0_n.chunk_idx = chunk_cnt_n;
                    uop_p0_n.src0_addr = hperm_read_addr(hperm_src_base_q, chunk_cnt_n, hperm_word_off_q, 1'b0);
                    uop_p0_n.src1_addr = hperm_read_addr(hperm_src_base_q, chunk_cnt_n, hperm_word_off_q, 1'b1);
                    uop_p0_n.dst_addr  = hperm_dst_base_q + {4'b0, chunk_cnt_n};
                    st_n = S_UOP_P1_RD0;
                end
            end
            default: st_n = S_UOP_P4_RESP;
            endcase
        end

        // ── HCNTCLIP writeback (dedicated state, avoids pipeline timing issues) ─
        S_UOP_P3_VRF_WAIT: begin
            st_n=S_UOP_P2_LANE;
        end

        S_UOP_P3_POP_CAPTURE: begin
            group_dist_n = group_dist_sum;
            st_n=S_UOP_P3_ACCUM;
        end

        S_UOP_P3_ACCUM: begin
            hsim_total_n = hsim_total_q + group_dist_q;
            if (uop_p3_q.op_type == UOP_HMATCH_CHUNK)
                hmatch_budget_n = hmatch_budget_step;
            if (uop_p3_q.chunk_idx == 2'd3) begin
                if (uop_p3_q.op_type == UOP_HMATCH_CHUNK) begin
                    hmatch_update_n = hmatch_budget_step_nonnegative;
                    if (uop_p3_q.is_last_class) begin
                        st_n = S_UOP_P4_RESP;
                    end else begin
                        hmatch_class_slot_n = hmatch_class_slot_q + 4'd1;
                        uop_p0_n = uop_p3_q; uop_p0_n.valid = 1'b1;
                        uop_p0_n.chunk_idx   = 2'd0;
                        uop_p0_n.class_idx   = uop_p3_q.class_idx + 3'd1;
                        uop_p0_n.is_last_class = (uop_p3_q.class_idx + 3'd1 == hmatch_last_idx_q);
                        uop_p0_n.src0_addr   = hsim_src0_base_q;
                        uop_p0_n.src1_addr   = {hmatch_class_slot_n, 2'b00};
                        st_n = S_UOP_P1_RD0;
                    end
                end else begin
                    st_n = S_UOP_P4_RESP;
                end
            end else begin
                uop_p0_n = uop_p3_q; uop_p0_n.valid = 1'b1;
                uop_p0_n.chunk_idx = uop_p3_q.chunk_idx + 2'd1;
                uop_p0_n.src0_addr = hsim_src0_base_q + (uop_p3_q.chunk_idx + 2'd1);
                if (uop_p3_q.op_type == UOP_HMATCH_CHUNK)
                    uop_p0_n.src1_addr = {hmatch_class_slot_q, 2'b00} + (uop_p3_q.chunk_idx + 2'd1);
                else
                    uop_p0_n.src1_addr = hsim_src1_base_q + (uop_p3_q.chunk_idx + 2'd1);
                if (uop_p3_q.op_type == UOP_HMATCH_CHUNK)
                    uop_p0_n.is_last_class = uop_p3_q.is_last_class;
                st_n = S_UOP_P1_RD0;
            end
        end

        S_UOP_CLIP_WRITE: begin
            vrf_we = '1;
            vrf_wa[0]=hcntclip_dst_base_q+hcntclip_chunk_q; vrf_wa[1]=hcntclip_dst_base_q+hcntclip_chunk_q;
            vrf_wa[2]=hcntclip_dst_base_q+hcntclip_chunk_q; vrf_wa[3]=hcntclip_dst_base_q+hcntclip_chunk_q;
            vrf_wd = hcntclip_word_q;
            hcntclip_word_n = '0;
            hcntclip_subgroup_n = 2'd0;
            p4_arch_op_n = HDEC_HCNTCLIP;
            if (hcntclip_chunk_q == 2'd3) st_n = S_UOP_P4_RESP;
            else begin
                hcntclip_chunk_n = hcntclip_chunk_q + 2'd1;
                uop_p0_n = '0;
                uop_p0_n.valid = 1'b1;
                uop_p0_n.op_type = UOP_HCNTCLIP_READ;
                uop_p0_n.chunk_idx = hcntclip_chunk_n;
                uop_p0_n.subgroup_idx = 2'd0;
                uop_p0_n.src0_addr = hcntclip_acc_base+{2'b00,hcntclip_chunk_n,2'b00};
                uop_p0_n.src1_addr = hcntclip_acc_base+{2'b00,hcntclip_chunk_n,2'b00};
                uop_p0_n.use_clip = 1'b1;
                st_n = S_UOP_P1_RD0;
            end
        end

        S_UOP_P4_RESP: begin
            scalar_response_n = '0;
            response_valid_n  = 1'b1;
            if (p4_arch_op_q == HDEC_HSIM) begin
                scalar_response_n = {53'b0, hsim_total_q};
                st_n = S_RESULT;
            end else if (p4_arch_op_q == HDEC_HMATCH) begin
                hmatch_update_n = 1'b0;
                if (hmatch_update_q) begin
                    hmatch_best_dist_n = hsim_total_q;
                    hmatch_best_idx_n  = uop_p3_q.class_idx;
                end
                if (hmatch_update_q)
                    scalar_response_n = {50'b0, uop_p3_q.class_idx, hsim_total_q};
                else
                    scalar_response_n = {50'b0, hmatch_best_idx_q, hmatch_best_dist_q};
                st_n = S_RESULT;
            end else st_n = S_RESULT;
        end

        S_RESULT: begin response_valid_n=1'b0;st_n=S_IDLE;end
        default: st_n=S_IDLE;
        endcase
    end

    // ── Sequential ──────────────────────────────────────────────────────────
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni)begin
            st_q<=S_IDLE;res_q<='0;op_q<=HDEC_VWR64;a_q<='0;b_q<='0;bk_q<='0;
            vaddr_bank_q<='0;vaddr_idx_q<='0;clr_cnt_q<='0;clr_base_q<='0;
            chunk_cnt_q<='0;
            hb_dst_base_q<='0;hb_src0_base_q<='0;hb_src1_base_q<='0;
            hsim_src0_base_q<='0;hsim_src1_base_q<='0;hsim_total_q<='0;group_dist_q<='0;
            hmatch_last_idx_q<='0;hmatch_best_idx_q<='0;hmatch_class_slot_q<='0;hmatch_best_dist_q<='0;hmatch_budget_q<='0;hmatch_update_q<=1'b0;
            hperm_a_q<='0;hperm_dst_base_q<='0;hperm_src_base_q<='0;hperm_word_off_q<='0;hperm_nibble_q<='0;hperm_lane_base_q<='0;
            hcntadd_hv_q<='0;hcntadd_hv_slot_q<='0;hcntadd_chunk_q<='0;hcntadd_subgroup_q<='0;hcntadd_acc_sel_q<='0;
            hcntclip_dst_base_q<='0;hcntclip_acc_sel_q<='0;hcntclip_threshold_q<='0;hcntclip_chunk_q<='0;hcntclip_subgroup_q<='0;hcntclip_word_q<='0;
            vrf_ra_q<='0;vrf_we_q<='0;vrf_wa_q<='0;vrf_wd_q<='0;
            uop_p0_q<='0;uop_p1_q<='0;uop_p2_q<='0;uop_p3_q<='0;
            hdc_src0_q<='0;
            lane_result_q<='0;lane_clip_q<='0;
            scalar_response_q<='0;response_valid_q<='0;p4_arch_op_q<=HDEC_VWR64;
            ecc_src_a_q<='0;ecc_src_b_q<='0;ecc_dst_q<='0;ecc_a_q<='0;ecc_b_q<='0;ecc_product_q<='0;
            ecc_leaf_a_q<='0;ecc_leaf_b_q<='0;ecc_leaf_prod_q<='0;ecc_k_q<='0;ecc_leaf_id_q<='0;ecc_diag_base_q<='0;
            ecc_pipe0_valid_q<=1'b0;ecc_pipe1_valid_q<=1'b0;ecc_pipe0_diag_q<='0;ecc_pipe1_diag_q<='0;
        end
        else begin
            st_q<=st_n;res_q<=res_n;op_q<=op_n;a_q<=a_n;b_q<=b_n;bk_q<=bk_n;
            vaddr_bank_q<=vaddr_bank_n;vaddr_idx_q<=vaddr_idx_n;clr_cnt_q<=clr_cnt_n;clr_base_q<=clr_base_n;
            chunk_cnt_q<=chunk_cnt_n;
            hb_dst_base_q<=hb_dst_base_n;hb_src0_base_q<=hb_src0_base_n;hb_src1_base_q<=hb_src1_base_n;
            hsim_src0_base_q<=hsim_src0_base_n;hsim_src1_base_q<=hsim_src1_base_n;hsim_total_q<=hsim_total_n;group_dist_q<=group_dist_n;
            hmatch_last_idx_q<=hmatch_last_idx_n;hmatch_best_idx_q<=hmatch_best_idx_n;hmatch_class_slot_q<=hmatch_class_slot_n;hmatch_best_dist_q<=hmatch_best_dist_n;hmatch_budget_q<=hmatch_budget_n;hmatch_update_q<=hmatch_update_n;
            hperm_a_q<=hperm_a_n;hperm_dst_base_q<=hperm_dst_base_n;hperm_src_base_q<=hperm_src_base_n;hperm_word_off_q<=hperm_word_off_n;hperm_nibble_q<=hperm_nibble_n;hperm_lane_base_q<=hperm_lane_base_n;
            hcntadd_hv_q<=hcntadd_hv_n;hcntadd_hv_slot_q<=hcntadd_hv_slot_n;hcntadd_chunk_q<=hcntadd_chunk_n;hcntadd_subgroup_q<=hcntadd_subgroup_n;hcntadd_acc_sel_q<=hcntadd_acc_sel_n;
            hcntclip_dst_base_q<=hcntclip_dst_base_n;hcntclip_acc_sel_q<=hcntclip_acc_sel_n;hcntclip_threshold_q<=hcntclip_threshold_n;hcntclip_chunk_q<=hcntclip_chunk_n;hcntclip_subgroup_q<=hcntclip_subgroup_n;hcntclip_word_q<=hcntclip_word_n;
            vrf_ra_q<=vrf_ra;vrf_we_q<=vrf_we;vrf_wa_q<=vrf_wa;vrf_wd_q<=vrf_wd;
            uop_p0_q<=uop_p0_n;uop_p1_q<=uop_p1_n;uop_p2_q<=uop_p2_n;uop_p3_q<=uop_p3_n;
            hdc_src0_q<=hdc_src0_n;
            lane_result_q<=lane_result_n;lane_clip_q<=lane_clip_n;
            scalar_response_q<=scalar_response_n;response_valid_q<=response_valid_n;p4_arch_op_q<=p4_arch_op_n;
            ecc_src_a_q<=ecc_src_a_n;ecc_src_b_q<=ecc_src_b_n;ecc_dst_q<=ecc_dst_n;ecc_a_q<=ecc_a_n;ecc_b_q<=ecc_b_n;ecc_product_q<=ecc_product_n;
            ecc_leaf_a_q<=ecc_leaf_a_n;ecc_leaf_b_q<=ecc_leaf_b_n;ecc_leaf_prod_q<=ecc_leaf_prod_n;ecc_k_q<=ecc_k_n;ecc_leaf_id_q<=ecc_leaf_id_n;ecc_diag_base_q<=ecc_diag_base_n;
            ecc_pipe0_valid_q<=ecc_pipe0_valid_n;ecc_pipe1_valid_q<=ecc_pipe1_valid_n;ecc_pipe0_diag_q<=ecc_pipe0_diag_n;ecc_pipe1_diag_q<=ecc_pipe1_diag_n;
        end
    end
endmodule
