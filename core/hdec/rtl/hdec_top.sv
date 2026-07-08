// hdec_top.sv — HDCU Phase: VRF mgmt + HDC compute FSM
// HDCU instruction subset: VWR64, VRD64, HCLR, HCNTCLR, HCNTADD,
// HBIND, HPERM, HSIM, HCNTCLIP, HMATCH, VADDR.
// No bundle, no add/sub counter, no BMCA.
module hdec_top import hdec_pkg::*; import hdec_resource_pkg::*; #(
    parameter bit ECC_STATUS_CYCLE_COUNT = 1'b0,
    parameter bit ECC_DEBUG_FIELD_OPS    = 1'b0
) (
    input logic clk_i, rst_ni, valid_i, output logic ready_o,
    input hdec_op_t operator_i, input logic [63:0] operand_a_i, operand_b_i,
    output logic valid_o, output logic [63:0] result_o
);
    logic [VRF_IDX_W-1:0] vrf_ra, vrf_ra_q;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] vrf_rd;
    logic [LANE_NUM-1:0] vrf_we;
    logic [LANE_NUM-1:0] vrf_we_direct;
    logic [VRF_IDX_W-1:0] vrf_wa;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] vrf_wd;
    typedef struct packed {
        logic [VRF_IDX_W-1:0]                 ra;
        logic [VRF_IDX_W-1:0]                 wa;
        logic [LANE_NUM-1:0][LANE_WIDTH-1:0]  wd;
    } hdec_vrf_req_t;
    hdec_vrf_req_t vrf_req;
    (* keep_hierarchy = "yes" *)
    hdec_vrf_64x256 i_vrf(.clk_i,.row_ra_addr_i(vrf_ra_q),.bank_ra_data_o(vrf_rd),.bank_we_i(vrf_we),.row_wa_addr_i(vrf_wa),.bank_wdata_i(vrf_wd),.vrf_ready_o());
    logic [VRF_BNK_W-1:0] vaddr_bank_q,vaddr_bank_n; logic [VRF_IDX_W-1:0] vaddr_idx_q,vaddr_idx_n;

    // ── State Machine ───────────────────────────────────────────────────────
    typedef enum logic [6:0] {
        S_IDLE, S_EXEC, S_VWR_WAIT, S_RD_WAIT, S_RD_CAPTURE, S_RESULT, S_CLR, S_CLR_DRAIN,
        S_HSIM_INIT, S_HMATCH_INIT, S_HPERM_LANE64,
        S_UOP_P1_RD0, S_UOP_P1_RD0_WAIT, S_UOP_P1_RD1, S_UOP_P1_RD1_WAIT,
        S_UOP_P2_LANE, S_UOP_P3_GLOBAL, S_UOP_P3_POP_CAPTURE, S_UOP_P3_VRF_WAIT, S_UOP_P3_ACCUM, S_UOP_P4_RESP,
        S_UOP_CLIP_WRITE,
        S_ECC_LOAD_A_WAIT, S_ECC_LOAD_A, S_ECC_LOAD_B_WAIT, S_ECC_LOAD_B,
        S_ECC_DIAG_ISSUE, S_ECC_DIAG_CAPTURE,
        S_ECC_LEAF_FOLD,
        S_ECC_WRITE_PAIR, S_ECC_WRITE_DRAIN,
        S_ECC_REDUCE_LOAD_LO_WAIT, S_ECC_REDUCE_LOAD_LO, S_ECC_REDUCE_LOAD_HI_WAIT, S_ECC_REDUCE_WRITE,
        S_ECC_INV_INIT, S_ECC_INV_COPY_WAIT, S_ECC_INV_COPY_WRITE, S_ECC_INV_STEP, S_ECC_INV_ISSUE_SQR,
        S_ECC_INV_AFTER_SQR, S_ECC_INV_AFTER_MUL,
        S_ECC_PMUL_INIT, S_ECC_PMUL_CONST_WRITE, S_ECC_PMUL_READ_SCALAR_WAIT, S_ECC_PMUL_READ_SCALAR,
        S_ECC_PMUL_STEP, S_ECC_PMUL_STEP_NEXT,
        S_ECC_BG_DISPATCH, S_ECC_JOB_DONE,
        S_ECC_SQR_WRITE, S_HSPREAD_LO_WRITE, S_HSPREAD_HI_WRITE,
        S_RD_WAIT2,
        S_ECC_LOAD_A_WAIT2,
        S_ECC_REDUCE_LOAD_LO_WAIT2,
        S_ECC_INV_COPY_WAIT2, S_ECC_PMUL_READ_SCALAR_WAIT2,
        S_UOP_P1_RD0_WAIT2, S_UOP_P3_VRF_WAIT2
    } st_t;
    (* fsm_encoding = "one_hot" *) st_t st_q, st_n;

    logic [63:0] res_q,res_n; hdec_op_t op_q,op_n; logic [63:0] a_q,a_n;
    logic [3:0] clr_cnt_q,clr_cnt_n; logic [VRF_IDX_W-1:0] clr_base_q,clr_base_n;

    // ── HSIM / HMATCH registers ─────────────────────────────────────────────
    logic [VRF_IDX_W-1:0] hsim_src0_base_q,hsim_src0_base_n, hsim_src1_base_q,hsim_src1_base_n;
    logic [10:0] hsim_total_q,hsim_total_n;
    logic [2:0] hmatch_last_idx_q,hmatch_last_idx_n;
    logic [2:0] hmatch_best_idx_q,hmatch_best_idx_n;
    logic [3:0] hmatch_class_slot_q,hmatch_class_slot_n;
    logic [10:0] hmatch_best_dist_q,hmatch_best_dist_n;
    logic hmatch_update_q,hmatch_update_n;
    logic [3:0] hmatch_req_base;
    logic [3:0] hmatch_req_count_lo;
    logic [3:0] hmatch_req_max_count;
    logic       hmatch_req_invalid;

    // ── HPERM registers ─────────────────────────────────────────────────────
    logic [VRF_IDX_W-1:0] hperm_dst_base_q,hperm_dst_base_n;
    logic [1:0] hperm_bit_low_q,hperm_bit_low_n;
    logic hperm_spread_q,hperm_spread_n;
    logic [1:0] hperm_lane_base_q,hperm_lane_base_n;
    logic [VRF_IDX_W-1:0] hspread_dst_base;

    // ── HCNTCLIP registers ──────────────────────────────────────────────────
    logic [VRF_IDX_W-1:0] hcntclip_dst_base_q,hcntclip_dst_base_n,hcntclip_acc_base;
    logic [VRF_IDX_W-1:0] hdc_cnt_base0, hdc_cnt_base1;
    logic interleave_active;
    logic hcntclip_acc_sel_q,hcntclip_acc_sel_n;
    logic [1:0] hcntclip_chunk_q,hcntclip_chunk_n;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] hcntclip_word_with_result;
    // hcntclip_acc_base selects the active counter bank; per-entry addresses are
    // formed locally in the uop stages.

    // ── UOP Pipeline Registers ──────────────────────────────────────────────
    // P0: decode + uop issue
    // P1: VRF read address / read wait (uop stays in P0 until the second read)
    // P2: VRF read data (vrf_rd) directly feeds Lane local compute
    // P2/P3 boundary: lane_*_q registers cut the critical combinational path
    hdec_uop_t uop_p0_q, uop_p0_n, uop_p2_q, uop_p2_n, uop_p3_q, uop_p3_n;

    // ── Lane compute wires ──────────────────────────────────────────────────
    logic                                hdc_pop_product_issue, hdc_pop_capture, hdc_xor_issue;
    logic                                p2_is_pop_q, p2_is_pop_n;
    logic                                p2_is_hbind_q, p2_is_hbind_n;
    logic                                uop_p2_use_counter, uop_p2_use_shift, uop_p2_use_clip;
    logic                                p2_lane_compute_q, p2_lane_compute_n;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] hdc_src0_q, hdc_src0_n;
    logic                                hdc_src0_we, hdc_src0_acc_we;
    logic [5:0]                          lane_shift_bit;
    logic [1:0]                          hperm_lane_slot_q,hperm_lane_slot_n;
    logic                                hperm_lane_phase_q,hperm_lane_phase_n;
    logic [2:0]                          hperm_word_sel,hperm_next_sel;
    logic [127:0]                        hperm_wide_word;
    logic [71:0]                         hperm_stage_q,hperm_stage_n;
    logic [LANE_WIDTH-1:0]               hperm_lane_word;
    logic                                hperm_stage_we,hperm_lane_clear,hperm_lane_we;

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
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] vec_payload_q;
    logic [LANE_NUM-1:0][1:0][5:0]       vec_popcount_q;

    // ── Scalar Response Registers (P4) ──────────────────────────────────────
    logic [8:0]  group_dist_q, group_dist_n, group_dist_sum;
    logic [10:0] hsim_total_step;

    // ── ECC V1 diagonal multiply shadow state ───────────────────────────────
    logic [VRF_IDX_W-1:0] ecc_src_a_q, ecc_src_a_n;
    logic [VRF_IDX_W-1:0] ecc_src_b_q, ecc_src_b_n;
    logic [VRF_IDX_W-1:0] ecc_dst_q,   ecc_dst_n;
    logic [VRF_IDX_W-1:0] ecc_acc_dst_q, ecc_acc_dst_n;
    logic [31:0]          ecc_leaf_a_q,  ecc_leaf_a_n;
    logic [31:0]          ecc_leaf_b_q,  ecc_leaf_b_n;
    logic [63:0]          ecc_leaf_prod_q, ecc_leaf_prod_n;
    logic [31:0]          ecc_leaf_xor_a_q, ecc_leaf_xor_a_n;
    logic [31:0]          ecc_leaf_xor_b_q, ecc_leaf_xor_b_n;
    logic [127:0]         ecc_leaf128_prod_q, ecc_leaf128_prod_n;
    logic [1:0]           ecc_kpd64_sub_q, ecc_kpd64_sub_n;
    logic [1:0]           ecc_fold_word_q, ecc_fold_word_n;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] ecc_reduce_src0;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] ecc_reduce_src1;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] ecc_reduce_src2;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] ecc_reduce_src3;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] lane_ecc_reduce_word;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] ecc_direct_reduce_word;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] ecc_square_reduce_word;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] xor0_contribution_packet;
    logic [232:0]                        xor0_field_packet;
    logic [31:0]          ecc_leaf_a_lowxor_xor1;
    logic [31:0]          ecc_leaf_b_lowxor_xor1;
    logic [63:0]          ecc_leaf_prod_store_w;
    logic [63:0]          ecc_leaf_prod_group7_w;
    logic [127:0]         ecc_sub32_capture_accum_xor1;
    logic [2:0]           ecc_diag_group_q, ecc_diag_group_n;
    logic [2:0]           ecc_diag_issue_group;
    logic                 ecc_diag_product_issue;
    logic                 ecc_diag_group7_lookahead_issue;
    logic [31:0]          ecc_leaf_b_matrix_rev;
    logic [31:0]          ecc_bitband_src_a;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] ecc_bitband_src_b;
    logic [LANE_NUM*2-1:0]               ecc_bitband_parity_row;
    logic                                ecc_autoreduce_fast;
    logic [5:0]           ecc_leaf_path_q, ecc_leaf_path_n;
    logic [5:0]           ecc_next_leaf_path;
    (* ram_style = "distributed" *) logic [127:0] ecc_product_pair [0:3];
    logic                 ecc_product_we;
    logic [127:0]         ecc_product_pair_rdata;
    logic [127:0]         ecc_product_pair_hold_q;
    logic [127:0]         ecc_product_pair_wdata;
    logic [63:0]          ecc_product_even_contrib;
    logic [63:0]          ecc_product_odd_contrib;
    logic [VRF_IDX_W-1:0] ecc_product_wb_addr;
    logic                 ecc_autoreduce_q, ecc_autoreduce_n;
    logic                 ecc_raw_product_q, ecc_raw_product_n;
    logic                 ecc_mac_q, ecc_mac_n;
    logic [6:0]           ecc_sqr_repeat_q, ecc_sqr_repeat_n;
    logic                 ecc_leaf_first;
    logic                 ecc_leaf_last;
    logic [6:0]           ecc_leaf64_offset_mask;
    localparam logic [VRF_IDX_W-1:0] ECC_PMUL_R0X = 6'd32;
    localparam logic [VRF_IDX_W-1:0] ECC_PMUL_R0Y = 6'd34;
    localparam logic [VRF_IDX_W-1:0] ECC_PMUL_R0Z = 6'd36;
    localparam logic [VRF_IDX_W-1:0] ECC_PMUL_R1X = 6'd38;
    localparam logic [VRF_IDX_W-1:0] ECC_PMUL_R1Y = 6'd40;
    localparam logic [VRF_IDX_W-1:0] ECC_PMUL_R1Z = 6'd42;
    localparam logic [VRF_IDX_W-1:0] ECC_PMUL_T0  = 6'd44;
    localparam logic [VRF_IDX_W-1:0] ECC_PMUL_T1  = 6'd46;
    localparam logic [VRF_IDX_W-1:0] ECC_PMUL_T2  = 6'd48;
    localparam logic [VRF_IDX_W-1:0] ECC_PMUL_T3  = 6'd50;
    localparam logic [VRF_IDX_W-1:0] ECC_PMUL_T4  = 6'd52;
    localparam logic [VRF_IDX_W-1:0] ECC_PMUL_T5  = 6'd54;
    localparam logic [VRF_IDX_W-1:0] ECC_PMUL_T6  = 6'd56;
    localparam logic [VRF_IDX_W-1:0] ECC_PMUL_T7  = 6'd58;
    localparam logic [VRF_IDX_W-1:0] ECC_PMUL_T8  = 6'd60;
    localparam logic [VRF_IDX_W-1:0] ECC_PMUL_T9  = 6'd62;
    localparam int unsigned ECC_STATUS_BG_BIT = 29;
    typedef enum logic [1:0] {
        ECC_JOB_NONE = 2'd0,
        ECC_JOB_INV  = 2'd1,
        ECC_JOB_PMUL = 2'd2
    } ecc_job_kind_e;
    typedef enum logic [3:0] {
        ECC_PHASE_NONE          = 4'd0,
        ECC_PHASE_INV_SQR       = 4'd1,
        ECC_PHASE_INV_MUL       = 4'd2,
        ECC_PHASE_INV_COPY_INIT = 4'd3,
        ECC_PHASE_INV_COPY_TMP  = 4'd4,
        ECC_PHASE_PMUL_FIELD    = 4'd5,
        ECC_PHASE_PMUL_ADD      = 4'd6,
        ECC_PHASE_PMUL_COPY     = 4'd7
    } ecc_job_phase_e;
    typedef enum logic [2:0] {
        ECC_PMUL_SUB_NONE       = 3'd0,
        ECC_PMUL_SUB_INIT       = 3'd1,
        ECC_PMUL_SUB_COPY_POINT = 3'd2,
        ECC_PMUL_SUB_ADD        = 3'd3,
        ECC_PMUL_SUB_DBL        = 3'd4,
        ECC_PMUL_SUB_AFFINE     = 3'd5,
        ECC_PMUL_SUB_ZERO_OUT   = 3'd6
    } ecc_pmul_subop_e;
    ecc_job_kind_e      ecc_job_kind_q, ecc_job_kind_n;
    ecc_job_phase_e     ecc_job_phase_q, ecc_job_phase_n;
    logic               ecc_job_active_q, ecc_job_active_n;
    logic               ecc_job_done_q, ecc_job_done_n;
    logic               ecc_job_bg_q, ecc_job_bg_n;
    logic [15:0]        ecc_job_cycle_q, ecc_job_cycle_n;
    logic [15:0]        ecc_job_cycle_status;
    logic [3:0]         ecc_leaf_read_path;
    logic [63:0]        ecc_leaf_lowxor_rd;
    logic [3:0]         ecc_inv_step_q, ecc_inv_step_n;
    logic [VRF_IDX_W-1:0] ecc_job_src_q, ecc_job_src_n;
    logic [VRF_IDX_W-1:0] ecc_job_dst_q, ecc_job_dst_n;
    (* fsm_encoding = "one_hot" *) ecc_pmul_subop_e ecc_pmul_subop_q, ecc_pmul_subop_n;
    logic [5:0]         ecc_pmul_step_q, ecc_pmul_step_n;
    logic [7:0]         ecc_pmul_bit_q, ecc_pmul_bit_n;
    logic               ecc_pmul_scalar_bit_q, ecc_pmul_scalar_bit_n;
    logic               ecc_pmul_r0_inf_q, ecc_pmul_r0_inf_n;
    logic               ecc_pmul_const_one_from_dst;
    logic [VRF_IDX_W-1:0] ecc_pmul_result_q, ecc_pmul_result_n;
    logic [VRF_IDX_W-1:0] ecc_pmul_point_q, ecc_pmul_point_n;
    logic [VRF_IDX_W-1:0] ecc_pmul_add_out_x;
    logic [VRF_IDX_W-1:0] ecc_pmul_add_out_z;
    logic [VRF_IDX_W-1:0] ecc_pmul_dbl_x;
    logic [VRF_IDX_W-1:0] ecc_pmul_dbl_z;

    // ── Combinational helpers ───────────────────────────────────────────────
    assign interleave_active = ecc_job_bg_q;
    assign hdc_cnt_base0 = interleave_active ? 6'd16 : 6'd32;
    assign hdc_cnt_base1 = interleave_active ? 6'd24 : 6'd48;
    assign hcntclip_acc_base = hcntclip_acc_sel_q ? hdc_cnt_base1 : hdc_cnt_base0;
    assign hmatch_req_base = a_q[7:4];
    assign hmatch_req_count_lo = a_q[11:8];
    assign hmatch_req_max_count = 4'd8 - hmatch_req_base;
    assign hmatch_req_invalid = (a_q[15:8] == 8'd0) || (|a_q[15:12])
                              || hmatch_req_base[3]
                              || (hmatch_req_count_lo > hmatch_req_max_count);
    assign hsim_total_step = hsim_total_q + {2'b00, group_dist_q};
    assign hdc_pop_product_issue = p2_lane_compute_q && p2_is_pop_q;
    assign hdc_pop_capture = (st_q == S_UOP_P3_GLOBAL)
                          && ((uop_p3_q.op_type == UOP_HSIM_CHUNK)
                           || (uop_p3_q.op_type == UOP_HMATCH_CHUNK));
    assign hdc_xor_issue = p2_lane_compute_q && p2_is_hbind_q;
    assign hspread_dst_base = hperm_dst_base_q;
    assign uop_p2_use_counter = (uop_p2_q.op_type == UOP_HCNTADD_SUBGROUP);
    assign uop_p2_use_shift   = (uop_p2_q.op_type == UOP_HPERM_CHUNK);
    assign uop_p2_use_clip    = (uop_p2_q.op_type == UOP_HCNTCLIP_READ);
    assign ecc_next_leaf_path = {2'b00, ecc_kpd64_path_inc(ecc_leaf_path_q[3:0])};
    assign ecc_leaf_read_path = (st_q == S_ECC_LEAF_FOLD) ? ecc_next_leaf_path[3:0] : ecc_leaf_path_q[3:0];
    assign ecc_leaf_lowxor_rd = ecc_kpd64_leaf_lowxor_pack({vrf_rd[3], vrf_rd[2], vrf_rd[1], vrf_rd[0]}, ecc_leaf_read_path);
    assign ecc_leaf_first = (ecc_leaf_path_q[3:0] == 4'b00_00);
    assign ecc_leaf_last  = (ecc_leaf_path_q[3:0] == 4'b10_10);
    assign ecc_job_cycle_status = ECC_STATUS_CYCLE_COUNT ? ecc_job_cycle_q : 16'd0;
    assign ecc_product_pair_rdata = ecc_product_pair[ecc_fold_word_q];
    assign ecc_leaf64_offset_mask = ecc_kpd64_leaf_offset_mask(ecc_leaf_path_q[3:0]);
    assign ecc_product_even_contrib = ecc_kpd64_fold_word_contrib(ecc_leaf64_offset_mask, {ecc_fold_word_q, 1'b0}, ecc_leaf128_prod_q);
    assign ecc_product_odd_contrib  = ecc_kpd64_fold_word_contrib(ecc_leaf64_offset_mask, {ecc_fold_word_q, 1'b1}, ecc_leaf128_prod_q);
    assign ecc_square_reduce_word = ecc_square_reduce233_loop(vrf_rd);
    assign ecc_product_pair_wdata = ecc_leaf_first
                                  ? {ecc_product_odd_contrib, ecc_product_even_contrib}
                                  : ({ecc_product_odd_contrib, ecc_product_even_contrib}
                                   ^ ecc_product_pair_rdata);
    assign ecc_product_wb_addr = ecc_dst_q + {5'b0, ecc_fold_word_q[1]};
    assign ecc_pmul_add_out_x = ecc_pmul_scalar_bit_q ? ECC_PMUL_R0X : ECC_PMUL_R1X;
    assign ecc_pmul_add_out_z = ecc_pmul_scalar_bit_q ? ECC_PMUL_R0Z : ECC_PMUL_R1Z;
    assign ecc_pmul_dbl_x = ecc_pmul_scalar_bit_q ? ECC_PMUL_R1X : ECC_PMUL_R0X;
    assign ecc_pmul_dbl_z = ecc_pmul_scalar_bit_q ? ECC_PMUL_R1Z : ECC_PMUL_R0Z;
    assign ecc_pmul_const_one_from_dst = (ecc_dst_q == ECC_PMUL_R0X)
                                      || (ecc_dst_q == ECC_PMUL_R1Z)
                                      || (ecc_dst_q == ECC_PMUL_T9);
    assign ecc_diag_group7_lookahead_issue = (st_q == S_ECC_DIAG_CAPTURE)
                                          && (ecc_diag_group_q == 3'd7)
                                          && (ecc_kpd64_sub_q < 2'd2);
    assign ecc_autoreduce_fast = ecc_autoreduce_q && !ECC_DEBUG_FIELD_OPS;
    assign ecc_diag_product_issue = (st_q == S_ECC_DIAG_ISSUE)
                                 || ((st_q == S_ECC_DIAG_CAPTURE)
                                     && ((ecc_diag_group_q != 3'd7)
                                         || ecc_diag_group7_lookahead_issue));
    assign ecc_diag_issue_group = ((st_q == S_ECC_DIAG_CAPTURE) && (ecc_diag_group_q == 3'd7))
                                ? 3'd0
                                : ((st_q == S_ECC_DIAG_CAPTURE)
                                   ? (ecc_diag_group_q + 3'd1)
                                   : ecc_diag_group_q);
    assign ecc_leaf_b_matrix_rev = ecc_leaf_b_q;
    assign ecc_bitband_src_a = ecc_leaf_a_q;
    assign ecc_bitband_src_b = ecc_diag32_bitband_b_words(ecc_leaf_b_matrix_rev, ecc_diag_issue_group);

    function automatic logic ecc_inv_step_needs_tmp(input logic [3:0] step);
        unique case (step)
            4'd2, 4'd4, 4'd5, 4'd7, 4'd8, 4'd9: ecc_inv_step_needs_tmp = 1'b1;
            default: ecc_inv_step_needs_tmp = 1'b0;
        endcase
    endfunction

    function automatic logic ecc_inv_step_has_mul(input logic [3:0] step);
        ecc_inv_step_has_mul = (step != 4'd10);
    endfunction

    function automatic logic ecc_inv_step_mul_src_is_orig(input logic [3:0] step);
        unique case (step)
            4'd0, 4'd1, 4'd3, 4'd6: ecc_inv_step_mul_src_is_orig = 1'b1;
            default: ecc_inv_step_mul_src_is_orig = 1'b0;
        endcase
    endfunction

    function automatic logic [6:0] ecc_inv_step_sqr_repeat(input logic [3:0] step);
        unique case (step)
            4'd2: ecc_inv_step_sqr_repeat = 7'd2;   // 3 squares total
            4'd4: ecc_inv_step_sqr_repeat = 7'd6;   // 7 squares total
            4'd5: ecc_inv_step_sqr_repeat = 7'd13;  // 14 squares total
            4'd7: ecc_inv_step_sqr_repeat = 7'd28;  // 29 squares total
            4'd8: ecc_inv_step_sqr_repeat = 7'd57;  // 58 squares total
            4'd9: ecc_inv_step_sqr_repeat = 7'd115; // 116 squares total
            default: ecc_inv_step_sqr_repeat = 7'd0; // 1 square total
        endcase
    endfunction

    function automatic logic ecc_pmul_subop_last(input ecc_pmul_subop_e subop,
                                                 input logic [5:0] step);
        unique case (subop)
            ECC_PMUL_SUB_INIT:       ecc_pmul_subop_last = (step == 6'd3);
            ECC_PMUL_SUB_COPY_POINT: ecc_pmul_subop_last = (step == 6'd2);
            ECC_PMUL_SUB_ADD:        ecc_pmul_subop_last = (step == 6'd8);
            ECC_PMUL_SUB_DBL:        ecc_pmul_subop_last = (step == 6'd5);
            ECC_PMUL_SUB_AFFINE:     ecc_pmul_subop_last = (step == 6'd26);
            ECC_PMUL_SUB_ZERO_OUT:   ecc_pmul_subop_last = (step == 6'd1);
            default:                 ecc_pmul_subop_last = 1'b1;
        endcase
    endfunction

    function automatic logic ecc_scalar_bit_from_row(input logic [3:0][63:0] row,
                                                     input logic [7:0] bit_idx);
        unique case (bit_idx[7:6])
            2'd0: ecc_scalar_bit_from_row = row[0][bit_idx[5:0]];
            2'd1: ecc_scalar_bit_from_row = row[1][bit_idx[5:0]];
            2'd2: ecc_scalar_bit_from_row = row[2][bit_idx[5:0]];
            default: ecc_scalar_bit_from_row = row[3][bit_idx[5:0]];
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

    function automatic logic [71:0] hperm_byte_window(
        input logic [127:0] wide_word,
        input logic [2:0]   byte_sel
    );
        begin
            unique case (byte_sel)
            3'd0: hperm_byte_window = wide_word[71:0];
            3'd1: hperm_byte_window = wide_word[79:8];
            3'd2: hperm_byte_window = wide_word[87:16];
            3'd3: hperm_byte_window = wide_word[95:24];
            3'd4: hperm_byte_window = wide_word[103:32];
            3'd5: hperm_byte_window = wide_word[111:40];
            3'd6: hperm_byte_window = wide_word[119:48];
            default: hperm_byte_window = wide_word[127:56];
            endcase
        end
    endfunction

    function automatic logic [63:0] hperm_low_shift(
        input logic [71:0] window,
        input logic [2:0]  bit_sel
    );
        begin
            unique case (bit_sel)
            3'd0: hperm_low_shift = window[63:0];
            3'd1: hperm_low_shift = window[64:1];
            3'd2: hperm_low_shift = window[65:2];
            3'd3: hperm_low_shift = window[66:3];
            3'd4: hperm_low_shift = window[67:4];
            3'd5: hperm_low_shift = window[68:5];
            3'd6: hperm_low_shift = window[69:6];
            default: hperm_low_shift = window[70:7];
            endcase
        end
    endfunction

    function automatic logic [63:0] hspread_half64(
        input logic [63:0] word,
        input logic        hi_half
    );
        logic [31:0] half_word;
        begin
            half_word = hi_half ? word[63:32] : word[31:0];
            hspread_half64 = '0;
            for (int bit_idx = 0; bit_idx < 32; bit_idx++)
                hspread_half64[bit_idx << 1] = half_word[bit_idx];
        end
    endfunction

    function automatic logic [232:0] ecc_square_reduce233(
        input logic [LANE_NUM-1:0][LANE_WIDTH-1:0] src
    );
        logic [232:0] src_flat;
        logic [232:0] reduced;
        begin
            src_flat = {src[3][40:0], src[2], src[1], src[0]};
            reduced = '0;
            reduced[0] = src_flat[0] ^ src_flat[196];
            reduced[1] = src_flat[117];
            reduced[2] = src_flat[1] ^ src_flat[197];
            reduced[3] = src_flat[118];
            reduced[4] = src_flat[2] ^ src_flat[198];
            reduced[5] = src_flat[119];
            reduced[6] = src_flat[3] ^ src_flat[199];
            reduced[7] = src_flat[120];
            reduced[8] = src_flat[4] ^ src_flat[200];
            reduced[9] = src_flat[121];
            reduced[10] = src_flat[5] ^ src_flat[201];
            reduced[11] = src_flat[122];
            reduced[12] = src_flat[6] ^ src_flat[202];
            reduced[13] = src_flat[123];
            reduced[14] = src_flat[7] ^ src_flat[203];
            reduced[15] = src_flat[124];
            reduced[16] = src_flat[8] ^ src_flat[204];
            reduced[17] = src_flat[125];
            reduced[18] = src_flat[9] ^ src_flat[205];
            reduced[19] = src_flat[126];
            reduced[20] = src_flat[10] ^ src_flat[206];
            reduced[21] = src_flat[127];
            reduced[22] = src_flat[11] ^ src_flat[207];
            reduced[23] = src_flat[128];
            reduced[24] = src_flat[12] ^ src_flat[208];
            reduced[25] = src_flat[129];
            reduced[26] = src_flat[13] ^ src_flat[209];
            reduced[27] = src_flat[130];
            reduced[28] = src_flat[14] ^ src_flat[210];
            reduced[29] = src_flat[131];
            reduced[30] = src_flat[15] ^ src_flat[211];
            reduced[31] = src_flat[132];
            reduced[32] = src_flat[16] ^ src_flat[212];
            reduced[33] = src_flat[133];
            reduced[34] = src_flat[17] ^ src_flat[213];
            reduced[35] = src_flat[134];
            reduced[36] = src_flat[18] ^ src_flat[214];
            reduced[37] = src_flat[135];
            reduced[38] = src_flat[19] ^ src_flat[215];
            reduced[39] = src_flat[136];
            reduced[40] = src_flat[20] ^ src_flat[216];
            reduced[41] = src_flat[137];
            reduced[42] = src_flat[21] ^ src_flat[217];
            reduced[43] = src_flat[138];
            reduced[44] = src_flat[22] ^ src_flat[218];
            reduced[45] = src_flat[139];
            reduced[46] = src_flat[23] ^ src_flat[219];
            reduced[47] = src_flat[140];
            reduced[48] = src_flat[24] ^ src_flat[220];
            reduced[49] = src_flat[141];
            reduced[50] = src_flat[25] ^ src_flat[221];
            reduced[51] = src_flat[142];
            reduced[52] = src_flat[26] ^ src_flat[222];
            reduced[53] = src_flat[143];
            reduced[54] = src_flat[27] ^ src_flat[223];
            reduced[55] = src_flat[144];
            reduced[56] = src_flat[28] ^ src_flat[224];
            reduced[57] = src_flat[145];
            reduced[58] = src_flat[29] ^ src_flat[225];
            reduced[59] = src_flat[146];
            reduced[60] = src_flat[30] ^ src_flat[226];
            reduced[61] = src_flat[147];
            reduced[62] = src_flat[31] ^ src_flat[227];
            reduced[63] = src_flat[148];
            reduced[64] = src_flat[32] ^ src_flat[228];
            reduced[65] = src_flat[149];
            reduced[66] = src_flat[33] ^ src_flat[229];
            reduced[67] = src_flat[150];
            reduced[68] = src_flat[34] ^ src_flat[230];
            reduced[69] = src_flat[151];
            reduced[70] = src_flat[35] ^ src_flat[231];
            reduced[71] = src_flat[152];
            reduced[72] = src_flat[36] ^ src_flat[232];
            reduced[73] = src_flat[153];
            reduced[74] = src_flat[37] ^ src_flat[196];
            reduced[75] = src_flat[117] ^ src_flat[154];
            reduced[76] = src_flat[38] ^ src_flat[197];
            reduced[77] = src_flat[118] ^ src_flat[155];
            reduced[78] = src_flat[39] ^ src_flat[198];
            reduced[79] = src_flat[119] ^ src_flat[156];
            reduced[80] = src_flat[40] ^ src_flat[199];
            reduced[81] = src_flat[120] ^ src_flat[157];
            reduced[82] = src_flat[41] ^ src_flat[200];
            reduced[83] = src_flat[121] ^ src_flat[158];
            reduced[84] = src_flat[42] ^ src_flat[201];
            reduced[85] = src_flat[122] ^ src_flat[159];
            reduced[86] = src_flat[43] ^ src_flat[202];
            reduced[87] = src_flat[123] ^ src_flat[160];
            reduced[88] = src_flat[44] ^ src_flat[203];
            reduced[89] = src_flat[124] ^ src_flat[161];
            reduced[90] = src_flat[45] ^ src_flat[204];
            reduced[91] = src_flat[125] ^ src_flat[162];
            reduced[92] = src_flat[46] ^ src_flat[205];
            reduced[93] = src_flat[126] ^ src_flat[163];
            reduced[94] = src_flat[47] ^ src_flat[206];
            reduced[95] = src_flat[127] ^ src_flat[164];
            reduced[96] = src_flat[48] ^ src_flat[207];
            reduced[97] = src_flat[128] ^ src_flat[165];
            reduced[98] = src_flat[49] ^ src_flat[208];
            reduced[99] = src_flat[129] ^ src_flat[166];
            reduced[100] = src_flat[50] ^ src_flat[209];
            reduced[101] = src_flat[130] ^ src_flat[167];
            reduced[102] = src_flat[51] ^ src_flat[210];
            reduced[103] = src_flat[131] ^ src_flat[168];
            reduced[104] = src_flat[52] ^ src_flat[211];
            reduced[105] = src_flat[132] ^ src_flat[169];
            reduced[106] = src_flat[53] ^ src_flat[212];
            reduced[107] = src_flat[133] ^ src_flat[170];
            reduced[108] = src_flat[54] ^ src_flat[213];
            reduced[109] = src_flat[134] ^ src_flat[171];
            reduced[110] = src_flat[55] ^ src_flat[214];
            reduced[111] = src_flat[135] ^ src_flat[172];
            reduced[112] = src_flat[56] ^ src_flat[215];
            reduced[113] = src_flat[136] ^ src_flat[173];
            reduced[114] = src_flat[57] ^ src_flat[216];
            reduced[115] = src_flat[137] ^ src_flat[174];
            reduced[116] = src_flat[58] ^ src_flat[217];
            reduced[117] = src_flat[138] ^ src_flat[175];
            reduced[118] = src_flat[59] ^ src_flat[218];
            reduced[119] = src_flat[139] ^ src_flat[176];
            reduced[120] = src_flat[60] ^ src_flat[219];
            reduced[121] = src_flat[140] ^ src_flat[177];
            reduced[122] = src_flat[61] ^ src_flat[220];
            reduced[123] = src_flat[141] ^ src_flat[178];
            reduced[124] = src_flat[62] ^ src_flat[221];
            reduced[125] = src_flat[142] ^ src_flat[179];
            reduced[126] = src_flat[63] ^ src_flat[222];
            reduced[127] = src_flat[143] ^ src_flat[180];
            reduced[128] = src_flat[64] ^ src_flat[223];
            reduced[129] = src_flat[144] ^ src_flat[181];
            reduced[130] = src_flat[65] ^ src_flat[224];
            reduced[131] = src_flat[145] ^ src_flat[182];
            reduced[132] = src_flat[66] ^ src_flat[225];
            reduced[133] = src_flat[146] ^ src_flat[183];
            reduced[134] = src_flat[67] ^ src_flat[226];
            reduced[135] = src_flat[147] ^ src_flat[184];
            reduced[136] = src_flat[68] ^ src_flat[227];
            reduced[137] = src_flat[148] ^ src_flat[185];
            reduced[138] = src_flat[69] ^ src_flat[228];
            reduced[139] = src_flat[149] ^ src_flat[186];
            reduced[140] = src_flat[70] ^ src_flat[229];
            reduced[141] = src_flat[150] ^ src_flat[187];
            reduced[142] = src_flat[71] ^ src_flat[230];
            reduced[143] = src_flat[151] ^ src_flat[188];
            reduced[144] = src_flat[72] ^ src_flat[231];
            reduced[145] = src_flat[152] ^ src_flat[189];
            reduced[146] = src_flat[73] ^ src_flat[232];
            reduced[147] = src_flat[153] ^ src_flat[190];
            reduced[148] = src_flat[74];
            reduced[149] = src_flat[154] ^ src_flat[191];
            reduced[150] = src_flat[75];
            reduced[151] = src_flat[155] ^ src_flat[192];
            reduced[152] = src_flat[76];
            reduced[153] = src_flat[156] ^ src_flat[193];
            reduced[154] = src_flat[77];
            reduced[155] = src_flat[157] ^ src_flat[194];
            reduced[156] = src_flat[78];
            reduced[157] = src_flat[158] ^ src_flat[195];
            reduced[158] = src_flat[79];
            reduced[159] = src_flat[159] ^ src_flat[196];
            reduced[160] = src_flat[80];
            reduced[161] = src_flat[160] ^ src_flat[197];
            reduced[162] = src_flat[81];
            reduced[163] = src_flat[161] ^ src_flat[198];
            reduced[164] = src_flat[82];
            reduced[165] = src_flat[162] ^ src_flat[199];
            reduced[166] = src_flat[83];
            reduced[167] = src_flat[163] ^ src_flat[200];
            reduced[168] = src_flat[84];
            reduced[169] = src_flat[164] ^ src_flat[201];
            reduced[170] = src_flat[85];
            reduced[171] = src_flat[165] ^ src_flat[202];
            reduced[172] = src_flat[86];
            reduced[173] = src_flat[166] ^ src_flat[203];
            reduced[174] = src_flat[87];
            reduced[175] = src_flat[167] ^ src_flat[204];
            reduced[176] = src_flat[88];
            reduced[177] = src_flat[168] ^ src_flat[205];
            reduced[178] = src_flat[89];
            reduced[179] = src_flat[169] ^ src_flat[206];
            reduced[180] = src_flat[90];
            reduced[181] = src_flat[170] ^ src_flat[207];
            reduced[182] = src_flat[91];
            reduced[183] = src_flat[171] ^ src_flat[208];
            reduced[184] = src_flat[92];
            reduced[185] = src_flat[172] ^ src_flat[209];
            reduced[186] = src_flat[93];
            reduced[187] = src_flat[173] ^ src_flat[210];
            reduced[188] = src_flat[94];
            reduced[189] = src_flat[174] ^ src_flat[211];
            reduced[190] = src_flat[95];
            reduced[191] = src_flat[175] ^ src_flat[212];
            reduced[192] = src_flat[96];
            reduced[193] = src_flat[176] ^ src_flat[213];
            reduced[194] = src_flat[97];
            reduced[195] = src_flat[177] ^ src_flat[214];
            reduced[196] = src_flat[98];
            reduced[197] = src_flat[178] ^ src_flat[215];
            reduced[198] = src_flat[99];
            reduced[199] = src_flat[179] ^ src_flat[216];
            reduced[200] = src_flat[100];
            reduced[201] = src_flat[180] ^ src_flat[217];
            reduced[202] = src_flat[101];
            reduced[203] = src_flat[181] ^ src_flat[218];
            reduced[204] = src_flat[102];
            reduced[205] = src_flat[182] ^ src_flat[219];
            reduced[206] = src_flat[103];
            reduced[207] = src_flat[183] ^ src_flat[220];
            reduced[208] = src_flat[104];
            reduced[209] = src_flat[184] ^ src_flat[221];
            reduced[210] = src_flat[105];
            reduced[211] = src_flat[185] ^ src_flat[222];
            reduced[212] = src_flat[106];
            reduced[213] = src_flat[186] ^ src_flat[223];
            reduced[214] = src_flat[107];
            reduced[215] = src_flat[187] ^ src_flat[224];
            reduced[216] = src_flat[108];
            reduced[217] = src_flat[188] ^ src_flat[225];
            reduced[218] = src_flat[109];
            reduced[219] = src_flat[189] ^ src_flat[226];
            reduced[220] = src_flat[110];
            reduced[221] = src_flat[190] ^ src_flat[227];
            reduced[222] = src_flat[111];
            reduced[223] = src_flat[191] ^ src_flat[228];
            reduced[224] = src_flat[112];
            reduced[225] = src_flat[192] ^ src_flat[229];
            reduced[226] = src_flat[113];
            reduced[227] = src_flat[193] ^ src_flat[230];
            reduced[228] = src_flat[114];
            reduced[229] = src_flat[194] ^ src_flat[231];
            reduced[230] = src_flat[115];
            reduced[231] = src_flat[195] ^ src_flat[232];
            reduced[232] = src_flat[116];
            ecc_square_reduce233 = reduced;
        end
    endfunction

    function automatic logic [LANE_NUM-1:0][LANE_WIDTH-1:0] ecc_square_reduce233_loop(
        input logic [LANE_NUM-1:0][LANE_WIDTH-1:0] src
    );
        logic [232:0] src_flat;
        logic [232:0] reduced;
        logic [LANE_NUM-1:0][LANE_WIDTH-1:0] reduced_word;
        begin
            src_flat = {src[3][40:0], src[2], src[1], src[0]};
            reduced = '0;
            for (int unsigned i = 0; i < 117; i++) begin
                reduced[2 * i] = reduced[2 * i] ^ src_flat[i];
            end
            for (int unsigned i = 117; i < 196; i++) begin
                reduced[(2 * i) - 233] = reduced[(2 * i) - 233] ^ src_flat[i];
                reduced[(2 * i) - 159] = reduced[(2 * i) - 159] ^ src_flat[i];
            end
            for (int unsigned i = 196; i < 233; i++) begin
                reduced[(2 * i) - 233] = reduced[(2 * i) - 233] ^ src_flat[i];
                reduced[(2 * i) - 392] = reduced[(2 * i) - 392] ^ src_flat[i];
                reduced[(2 * i) - 318] = reduced[(2 * i) - 318] ^ src_flat[i];
            end
            reduced_word[0] = reduced[63:0];
            reduced_word[1] = reduced[127:64];
            reduced_word[2] = reduced[191:128];
            reduced_word[3] = {23'b0, reduced[232:192]};
            ecc_square_reduce233_loop = reduced_word;
        end
    endfunction

    function automatic logic [3:0] ecc_kpd64_path_inc(input logic [3:0] path);
        logic [1:0] d1, d0;
        begin
            d1 = path[3:2];
            d0 = path[1:0];
            if (d0 != 2'd2) begin
                d0 = d0 + 2'd1;
            end else begin
                d0 = 2'd0;
                d1 = d1 + 2'd1;
            end
            ecc_kpd64_path_inc = {d1, d0};
        end
    endfunction

    function automatic logic [63:0] ecc_limb64(input logic [255:0] value, input logic [1:0] idx);
        unique case (idx)
            2'd0: ecc_limb64 = value[63:0];
            2'd1: ecc_limb64 = value[127:64];
            2'd2: ecc_limb64 = value[191:128];
            2'd3: ecc_limb64 = value[255:192];
            default: ecc_limb64 = '0;
        endcase
    endfunction

    function automatic logic [63:0] ecc_kpd64_select(
        input logic [63:0] lo_word,
        input logic [63:0] hi_word,
        input logic [1:0]  sel
    );
        unique case (sel)
            2'd0: ecc_kpd64_select = lo_word;
            2'd1: ecc_kpd64_select = lo_word ^ hi_word;
            2'd2: ecc_kpd64_select = hi_word;
            default: ecc_kpd64_select = '0;
        endcase
    endfunction

    function automatic logic [63:0] ecc_kpd64_leaf_word(
        input logic [255:0] value,
        input logic [3:0]   path
    );
        logic [63:0] s0_0, s0_1;
        begin
            s0_0 = ecc_kpd64_select(ecc_limb64(value, 2'd0), ecc_limb64(value, 2'd2), path[3:2]);
            s0_1 = ecc_kpd64_select(ecc_limb64(value, 2'd1), ecc_limb64(value, 2'd3), path[3:2]);
            ecc_kpd64_leaf_word = ecc_kpd64_select(s0_0, s0_1, path[1:0]);
        end
    endfunction

    function automatic logic [63:0] ecc_kpd64_leaf_lowxor_pack(
        input logic [255:0] value,
        input logic [3:0]   path
    );
        logic [63:0] word;
        begin
            word = ecc_kpd64_leaf_word(value, path);
            ecc_kpd64_leaf_lowxor_pack = {word[31:0] ^ word[63:32], word[31:0]};
        end
    endfunction

    function automatic logic [6:0] ecc_kpd64_leaf_offset_mask(input logic [3:0] path);
        unique case (path)
            4'b00_00: ecc_kpd64_leaf_offset_mask = 7'h0f;
            4'b00_01: ecc_kpd64_leaf_offset_mask = 7'h0a;
            4'b00_10: ecc_kpd64_leaf_offset_mask = 7'h1e;
            4'b01_00: ecc_kpd64_leaf_offset_mask = 7'h0c;
            4'b01_01: ecc_kpd64_leaf_offset_mask = 7'h08;
            4'b01_10: ecc_kpd64_leaf_offset_mask = 7'h18;
            4'b10_00: ecc_kpd64_leaf_offset_mask = 7'h3c;
            4'b10_01: ecc_kpd64_leaf_offset_mask = 7'h28;
            4'b10_10: ecc_kpd64_leaf_offset_mask = 7'h78;
            default:   ecc_kpd64_leaf_offset_mask = '0;
        endcase
    endfunction

    function automatic logic [31:0] ecc_bitrev32_top(input logic [31:0] word);
        ecc_bitrev32_top = {word[0],  word[1],  word[2],  word[3],
                            word[4],  word[5],  word[6],  word[7],
                            word[8],  word[9],  word[10], word[11],
                            word[12], word[13], word[14], word[15],
                            word[16], word[17], word[18], word[19],
                            word[20], word[21], word[22], word[23],
                            word[24], word[25], word[26], word[27],
                            word[28], word[29], word[30], word[31]};
    endfunction

    function automatic logic [31:0] ecc_diag32_bitband_window(
        input logic [31:0] b_rev,
        input logic [5:0]  diag_idx
    );
        begin
            if (diag_idx <= 6'd31)
                ecc_diag32_bitband_window = b_rev >> (6'd31 - diag_idx);
            else
                ecc_diag32_bitband_window = b_rev << (diag_idx - 6'd31);
        end
    endfunction

    function automatic logic [LANE_NUM-1:0][63:0] ecc_diag32_bitband_b_words(
        input logic [31:0] b_rev,
        input logic [2:0]  group_idx
    );
        logic [LANE_NUM-1:0][63:0] words;
        logic [5:0] diag_base;
        logic [5:0] diag_idx;
        logic [31:0] row_word;
        begin
            words = '0;
            diag_base = {group_idx, 3'b000};
            for (int rid = 0; rid < LANE_NUM*2; rid++) begin
                diag_idx = diag_base + rid[5:0];
                row_word = (diag_idx <= 6'd62)
                         ? ecc_diag32_bitband_window(b_rev, diag_idx)
                         : 32'b0;

                if (rid[0])
                    words[rid >> 1][63:32] = row_word;
                else
                    words[rid >> 1][31:0] = row_word;
            end
            ecc_diag32_bitband_b_words = words;
        end
    endfunction

    function automatic logic [63:0] ecc_diag32_leaf_store_bitband(
        input logic [63:0] current_product,
        input logic [2:0]  group_idx,
        input logic [LANE_NUM*2-1:0] parity_row
    );
        logic [63:0] updated;
        begin
            updated = current_product;
            unique case (group_idx)
                3'd0: updated[0 +: 8] = parity_row;
                3'd1: updated[8 +: 8] = parity_row;
                3'd2: updated[16 +: 8] = parity_row;
                3'd3: updated[24 +: 8] = parity_row;
                3'd4: updated[32 +: 8] = parity_row;
                3'd5: updated[40 +: 8] = parity_row;
                3'd6: updated[48 +: 8] = parity_row;
                3'd7: updated[56 +: 7] = parity_row[6:0];
                default: begin
                end
            endcase
            updated[63] = 1'b0;
            ecc_diag32_leaf_store_bitband = updated;
        end
    endfunction

    function automatic logic [63:0] ecc_kpd64_fold_word_contrib(
        input logic [6:0]   mask,
        input logic [2:0]   word_idx,
        input logic [127:0] leaf_product
    );
        logic [7:0]  mask_ext;
        logic [63:0] contrib;
        begin
            mask_ext = {1'b0, mask};
            contrib = '0;
            if (mask_ext[word_idx])
                contrib ^= leaf_product[63:0];
            if ((word_idx != 3'd0) && mask_ext[word_idx - 3'd1])
                contrib ^= leaf_product[127:64];
            ecc_kpd64_fold_word_contrib = contrib;
        end
    endfunction

    function automatic logic [127:0] ecc_kpd64_sub32_accum(
        input logic [127:0] acc,
        input logic [1:0]   sub_idx,
        input logic [63:0]  sub_product
    );
        logic [3:0][31:0] acc_row;
        logic [31:0]      sub_lo;
        logic [31:0]      sub_hi;
        begin
            acc_row[0] = acc[31:0];
            acc_row[1] = acc[63:32];
            acc_row[2] = acc[95:64];
            acc_row[3] = acc[127:96];
            sub_lo = sub_product[31:0];
            sub_hi = sub_product[63:32];
            unique case (sub_idx)
                2'd0: begin
                    acc_row[0] ^= sub_lo;
                    acc_row[1] ^= (sub_hi ^ sub_lo);
                    acc_row[2] ^= sub_hi;
                end
                2'd1: begin
                    acc_row[1] ^= sub_lo;
                    acc_row[2] ^= (sub_hi ^ sub_lo);
                    acc_row[3] ^= sub_hi;
                end
                2'd2: begin
                    acc_row[1] ^= sub_lo;
                    acc_row[2] ^= sub_hi;
                end
                default: begin
                end
            endcase
            ecc_kpd64_sub32_accum = {acc_row[3], acc_row[2], acc_row[1], acc_row[0]};
        end
    endfunction

    function automatic logic [LANE_NUM-1:0][LANE_WIDTH-1:0] ecc_kpd64_fold_reduce_packet(
        input logic [6:0]   mask,
        input logic [1:0]   fold_word,
        input logic [127:0] leaf_product
    );
        logic [63:0] even_contrib;
        logic [63:0] odd_contrib;
        logic [LANE_NUM-1:0][LANE_WIDTH-1:0] packet;
        begin
            packet = '0;
            even_contrib = ecc_kpd64_fold_word_contrib(mask, {fold_word, 1'b0}, leaf_product);
            odd_contrib  = ecc_kpd64_fold_word_contrib(mask, {fold_word, 1'b1}, leaf_product);
            unique case (fold_word)
                2'd0: begin
                    packet[0] = even_contrib;
                    packet[1] = odd_contrib;
                end
                2'd1: begin
                    packet[0] = {41'b0, odd_contrib[63:41]};
                    packet[1] = {31'b0, odd_contrib[63:41], 10'b0};
                    packet[2] = even_contrib;
                    packet[3] = {23'b0, odd_contrib[40:0]};
                end
                2'd2: begin
                    packet[0] = {even_contrib[40:0], 23'b0};
                    packet[1] = {odd_contrib[40:0], even_contrib[63:41]}
                              ^ {even_contrib[30:0], 33'b0};
                    packet[2] = {41'b0, odd_contrib[63:41]}
                              ^ {odd_contrib[30:0], even_contrib[63:31]};
                    packet[3] = {23'b0, 8'b0, odd_contrib[63:31]};
                end
                default: begin
                    packet[0] = {odd_contrib[7:0], even_contrib[63:8]}
                              ^ {18'b0, odd_contrib[63:18]};
                    packet[1] = {even_contrib[61:8], odd_contrib[17:8]};
                    packet[2] = {even_contrib[40:0], 23'b0}
                              ^ {odd_contrib[61:0], even_contrib[63:62]};
                    packet[3] = {23'b0, ({odd_contrib[17:0], even_contrib[63:41]}
                                    ^ {even_contrib[7:0], 33'b0}
                                    ^ {39'b0, odd_contrib[63:62]})};
                end
            endcase
            ecc_kpd64_fold_reduce_packet = packet;
        end
    endfunction

    function automatic logic [LANE_NUM-1:0][LANE_WIDTH-1:0] ecc_kpd64_leaf_reduce_packet(
        input logic [6:0]   mask,
        input logic [127:0] leaf_product
    );
        logic [LANE_NUM-1:0][LANE_WIDTH-1:0] packet;
        begin
            packet = ecc_kpd64_fold_reduce_packet(mask, 2'd0, leaf_product)
                   ^ ecc_kpd64_fold_reduce_packet(mask, 2'd1, leaf_product)
                   ^ ecc_kpd64_fold_reduce_packet(mask, 2'd2, leaf_product)
                   ^ ecc_kpd64_fold_reduce_packet(mask, 2'd3, leaf_product);
            ecc_kpd64_leaf_reduce_packet = packet;
        end
    endfunction

    assign ecc_leaf_prod_store_w = ecc_diag32_leaf_store_bitband(
        ecc_leaf_prod_q,
        ecc_diag_group_q,
        ecc_bitband_parity_row
    );
    assign ecc_leaf_prod_group7_w = {1'b0, ecc_bitband_parity_row[6:0], ecc_leaf_prod_q[55:0]};
    assign ecc_sub32_capture_accum_xor1 = ecc_kpd64_sub32_accum(
        ecc_leaf128_prod_q,
        ecc_kpd64_sub_q,
        ecc_leaf_prod_group7_w
    );
    assign ecc_leaf_a_lowxor_xor1 = ecc_leaf_a_q ^ ecc_leaf_xor_a_q;
    assign ecc_leaf_b_lowxor_xor1 = ecc_leaf_b_q ^ ecc_leaf_xor_b_q;

    assign ecc_direct_reduce_word = ecc_kpd64_leaf_reduce_packet(
        ecc_leaf64_offset_mask,
        ecc_leaf128_prod_q
    );

    always_comb begin
        xor0_contribution_packet = 'x;
        if (hdc_xor_issue) begin
            xor0_contribution_packet = vrf_rd;
        end else if (hdc_src0_acc_we) begin
            xor0_contribution_packet = ecc_direct_reduce_word;
        end
    end

    generate
        if (ECC_DEBUG_FIELD_OPS) begin : gen_debug_reduce_sources
            assign lane_ecc_reduce_word = (ecc_reduce_src0 ^ ecc_reduce_src1)
                                        ^ (ecc_reduce_src2 ^ ecc_reduce_src3);

            assign ecc_reduce_src0[0] = hdc_src0_q[0];
            assign ecc_reduce_src1[0] = {vrf_rd[0][40:0], hdc_src0_q[3][63:41]};
            assign ecc_reduce_src2[0] = {vrf_rd[3][7:0], vrf_rd[2][63:8]};
            assign ecc_reduce_src3[0] = {18'b0, vrf_rd[3][63:18]};

            assign ecc_reduce_src0[1] = hdc_src0_q[1];
            assign ecc_reduce_src1[1] = {vrf_rd[1][40:0], vrf_rd[0][63:41]};
            assign ecc_reduce_src2[1] = {vrf_rd[0][30:0], hdc_src0_q[3][63:41], 10'b0};
            assign ecc_reduce_src3[1] = {vrf_rd[2][61:8], vrf_rd[3][17:8]};

            assign ecc_reduce_src0[2] = hdc_src0_q[2];
            assign ecc_reduce_src1[2] = {vrf_rd[2][40:0], vrf_rd[1][63:41]};
            assign ecc_reduce_src2[2] = {vrf_rd[1][30:0], vrf_rd[0][63:31]};
            assign ecc_reduce_src3[2] = {vrf_rd[3][61:0], vrf_rd[2][63:62]};

            assign ecc_reduce_src0[3] = {23'b0, hdc_src0_q[3][40:0]};
            assign ecc_reduce_src1[3] = {23'b0, vrf_rd[3][17:0], vrf_rd[2][63:41]};
            assign ecc_reduce_src2[3] = {23'b0, vrf_rd[2][7:0], vrf_rd[1][63:31]};
            assign ecc_reduce_src3[3] = {62'b0, vrf_rd[3][63:62]};
        end else begin : gen_no_debug_reduce_sources
            assign lane_ecc_reduce_word = '0;
            assign ecc_reduce_src0 = '0;
            assign ecc_reduce_src1 = '0;
            assign ecc_reduce_src2 = '0;
            assign ecc_reduce_src3 = '0;
        end
    endgenerate

    // ── 4× Lane instances ───────────────────────────────────────────────────
    hdec_vector_payload_4x64 #(
        .ENABLE_ECC_REDUCE(1'b1)
    ) i_vec (
        .clk_i(clk_i), .rst_ni(rst_ni),
        .payload_xor_i(hdc_xor_issue),
        .payload_product_i(hdc_pop_product_issue || ecc_diag_product_issue),
        .payload_pop_i(hdc_pop_capture),
        .payload_bitband_i(ecc_diag_product_issue),
        .payload_cnt_i(p2_lane_compute_q && uop_p2_use_counter),
        .payload_clip_i(p2_lane_compute_q && uop_p2_use_clip),
        .hperm_we_i(hperm_lane_we),
        .hperm_slot_i(hperm_lane_slot_q),
        .hperm_word_i(hperm_lane_word),
        .bool_src_a_i(hdc_src0_q),
        .bool_src_b_i(vrf_rd),
        .bitband_src_a_i(ecc_bitband_src_a),
        .bitband_src_b_i(ecc_bitband_src_b),
        .xor0_contribution_packet_i(xor0_contribution_packet),
        .payload_q_o(vec_payload_q),
        .payload_pop_q_o(vec_popcount_q),
        .xor0_field_packet_o(xor0_field_packet),
        .cnt_hv_word_i(hdc_src0_q),
        .cnt_old_counter_i(vrf_rd),
        .cnt_subgroup_i(uop_p2_q.subgroup_idx),
        .clip_counter_i(vrf_rd),
        .bitband_parity_o(ecc_bitband_parity_row)
    );

    assign group_dist_sum = {3'b000, vec_popcount_q[0][0]} + {3'b000, vec_popcount_q[0][1]}
                          + {3'b000, vec_popcount_q[1][0]} + {3'b000, vec_popcount_q[1][1]}
                          + {3'b000, vec_popcount_q[2][0]} + {3'b000, vec_popcount_q[2][1]}
                          + {3'b000, vec_popcount_q[3][0]} + {3'b000, vec_popcount_q[3][1]};

    // ── Main FSM ────────────────────────────────────────────────────────────
    always_comb begin
        st_n=st_q; ready_o=(st_q==S_IDLE); valid_o=(st_q==S_RESULT); result_o=res_q;
        res_n=res_q; op_n=op_q; a_n=a_q; vaddr_bank_n=vaddr_bank_q; vaddr_idx_n=vaddr_idx_q;
        clr_cnt_n=clr_cnt_q; clr_base_n=clr_base_q;
        hsim_src0_base_n=hsim_src0_base_q; hsim_src1_base_n=hsim_src1_base_q; hsim_total_n=hsim_total_q;
        group_dist_n=group_dist_q;
        hmatch_last_idx_n=hmatch_last_idx_q; hmatch_best_idx_n=hmatch_best_idx_q; hmatch_class_slot_n=hmatch_class_slot_q; hmatch_best_dist_n=hmatch_best_dist_q; hmatch_update_n=hmatch_update_q;
        hperm_dst_base_n=hperm_dst_base_q;
        hperm_bit_low_n=hperm_bit_low_q; hperm_spread_n=hperm_spread_q; hperm_lane_base_n=hperm_lane_base_q;
        hcntclip_dst_base_n=hcntclip_dst_base_q; hcntclip_acc_sel_n=hcntclip_acc_sel_q; hcntclip_chunk_n=hcntclip_chunk_q; hcntclip_word_with_result=hdc_src0_q;
        uop_p0_n=uop_p0_q; uop_p2_n=uop_p2_q; uop_p3_n=uop_p3_q;
        p2_is_pop_n=p2_is_pop_q; p2_is_hbind_n=p2_is_hbind_q;
        hdc_src0_n='x;
        hdc_src0_we=1'b0;
        hdc_src0_acc_we=1'b0;
        hperm_lane_slot_n=hperm_lane_slot_q;
        hperm_lane_phase_n=hperm_lane_phase_q;
        hperm_word_sel='0;
        hperm_next_sel='0;
        hperm_wide_word='x;
        hperm_stage_n=hperm_stage_q;
        hperm_lane_word='x;
        hperm_stage_we=1'b0;
        hperm_lane_clear=1'b0;
        hperm_lane_we=1'b0;
        // P3 consumes these one-cycle payloads; later values are don't-care.
        p2_lane_compute_n=1'b0;
        ecc_src_a_n=ecc_src_a_q; ecc_src_b_n=ecc_src_b_q; ecc_dst_n=ecc_dst_q; ecc_acc_dst_n=ecc_acc_dst_q;
        ecc_leaf_a_n=ecc_leaf_a_q; ecc_leaf_b_n=ecc_leaf_b_q;
        ecc_leaf_prod_n=ecc_leaf_prod_q;
        ecc_leaf_xor_a_n=ecc_leaf_xor_a_q; ecc_leaf_xor_b_n=ecc_leaf_xor_b_q;
        ecc_leaf128_prod_n=ecc_leaf128_prod_q; ecc_kpd64_sub_n=ecc_kpd64_sub_q;
        ecc_leaf_path_n=ecc_leaf_path_q;
        ecc_fold_word_n=ecc_fold_word_q;
        ecc_diag_group_n=ecc_diag_group_q;
        ecc_product_we=1'b0;
        ecc_autoreduce_n=ecc_autoreduce_q; ecc_raw_product_n=ecc_raw_product_q;
        ecc_mac_n=ecc_mac_q; ecc_sqr_repeat_n=ecc_sqr_repeat_q;
        ecc_job_kind_n=ecc_job_kind_q; ecc_job_phase_n=ecc_job_phase_q;
        ecc_job_active_n=ecc_job_active_q; ecc_job_done_n=ecc_job_done_q;
        ecc_job_bg_n=ecc_job_bg_q;
        if (ECC_STATUS_CYCLE_COUNT)
            ecc_job_cycle_n=ecc_job_cycle_q + (ecc_job_active_q ? 16'd1 : 16'd0);
        else
            ecc_job_cycle_n='0;
        ecc_inv_step_n=ecc_inv_step_q; ecc_job_src_n=ecc_job_src_q; ecc_job_dst_n=ecc_job_dst_q;
        ecc_pmul_subop_n=ecc_pmul_subop_q;
        ecc_pmul_step_n=ecc_pmul_step_q; ecc_pmul_bit_n=ecc_pmul_bit_q;
        ecc_pmul_scalar_bit_n=ecc_pmul_scalar_bit_q;
        ecc_pmul_r0_inf_n=ecc_pmul_r0_inf_q;
        ecc_pmul_result_n=ecc_pmul_result_q; ecc_pmul_point_n=ecc_pmul_point_q;
        lane_shift_bit='0;
        vrf_req.ra='0; vrf_req.wa='x; vrf_req.wd='x;
        vrf_we_direct='0;

        case(st_q)
        S_IDLE: begin
            if(valid_i&&ready_o)begin
                op_n=operator_i;a_n=operand_a_i;st_n=S_EXEC;
            end
        end

        S_EXEC: begin uop_p0_n='0; unique case(op_q)
            HDEC_VADDR: begin vaddr_bank_n=a_q[7:6];vaddr_idx_n=a_q[5:0];res_n='0;st_n=S_RESULT;end
            HDEC_VWR64: begin vrf_req.wa=vaddr_idx_q;vrf_req.wd[vaddr_bank_q]=a_q;res_n='0;st_n=S_VWR_WAIT;end
            HDEC_VRD64: begin vrf_req.ra=vaddr_idx_q;st_n=S_RD_WAIT;end

            HDEC_ECC_MUL: begin
                if (!ECC_DEBUG_FIELD_OPS) begin
                    res_n={62'b0,STATUS_NOT_IMPLEMENTED};st_n=S_RESULT;
                end else begin
                    if ((a_q[17:12] == 6'd63)
                     || (a_q[32] && ((a_q[23:18] == a_q[17:12])
                                   || (a_q[23:18] == (a_q[17:12] + 6'd1))))) begin
                        ecc_autoreduce_n=1'b0; ecc_raw_product_n=1'b0;
                        ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                        res_n={62'b0,STATUS_ERROR};st_n=S_RESULT;
                    end else begin
                        ecc_dst_n   = a_q[17:12];
                        ecc_acc_dst_n = a_q[23:18];
                        ecc_src_a_n = a_q[11:6];
                        ecc_src_b_n = a_q[5:0];
                        ecc_autoreduce_n = a_q[31] | a_q[32];
                        ecc_raw_product_n = ~(a_q[31] | a_q[32]);
                        ecc_mac_n = a_q[32];
                        ecc_sqr_repeat_n='0;
                        vrf_req.ra=a_q[11:6];
                        st_n=S_ECC_LOAD_A_WAIT;
                    end
                end
            end

            HDEC_ECC_STATUS: begin
                if (a_q[31] && !ECC_DEBUG_FIELD_OPS) begin
                    res_n={62'b0,STATUS_NOT_IMPLEMENTED};st_n=S_RESULT;
                end else if ((a_q[31] || a_q[30]) && ecc_job_active_q) begin
                    res_n={62'b0,STATUS_ERROR};st_n=S_RESULT;
                end else begin
                if (a_q[31] || a_q[30]) begin
                    ecc_job_src_n=a_q[5:0];
                    ecc_job_dst_n=a_q[17:12];
                    ecc_job_bg_n=a_q[ECC_STATUS_BG_BIT];
                end
                if (a_q[31]) begin
                    if ((a_q[17:12] > 6'd61)
                     || (a_q[5:0] == a_q[17:12])
                     || (a_q[5:0] == (a_q[17:12] + 6'd1))
                     || (a_q[5:0] == (a_q[17:12] + 6'd2))) begin
                        res_n={62'b0,STATUS_ERROR};st_n=S_RESULT;
                    end else begin
                        ecc_job_kind_n=ECC_JOB_INV;
                        ecc_job_phase_n=ECC_PHASE_NONE;
                        ecc_job_active_n=1'b1;
                        ecc_job_done_n=1'b0;
                        ecc_job_cycle_n='0;
                        ecc_inv_step_n='0;
                        ecc_dst_n=a_q[17:12];
                        if (a_q[ECC_STATUS_BG_BIT]) begin
                            res_n={32'b0, 16'b0, 6'b0, a_q[17:12], 2'b01, STATUS_OK};
                            st_n=S_RESULT;
                        end else begin
                            st_n=S_ECC_INV_INIT;
                        end
                    end
                end else if (a_q[30]) begin
                    if ((a_q[17:12] > 6'd30)
                     || (a_q[11:6] > 6'd30)
                     || (a_q[5:0] > 6'd31)) begin
                        res_n={62'b0,STATUS_ERROR};st_n=S_RESULT;
                    end else begin
                        ecc_job_kind_n=ECC_JOB_PMUL;
                        ecc_job_phase_n=ECC_PHASE_NONE;
                        ecc_job_active_n=1'b1;
                        ecc_job_done_n=1'b0;
                        ecc_job_cycle_n='0;
                        ecc_pmul_result_n=a_q[17:12];
                        ecc_pmul_point_n=a_q[11:6];
                        ecc_pmul_bit_n=8'd232;
                        ecc_pmul_scalar_bit_n=1'b0;
                        ecc_pmul_r0_inf_n=1'b1;
                        ecc_pmul_subop_n=ECC_PMUL_SUB_INIT;
                        ecc_pmul_step_n='0;
                        if (a_q[ECC_STATUS_BG_BIT]) begin
                            res_n={32'b0, 16'b0, 6'b0, a_q[17:12], 2'b01, STATUS_OK};
                            st_n=S_RESULT;
                        end else begin
                            st_n=S_ECC_PMUL_INIT;
                        end
                    end
                end else begin
                    res_n={32'b0, ecc_job_cycle_status, 6'b0, ecc_job_dst_q,
                           ecc_job_done_q, ecc_job_active_q, STATUS_OK};
                    if (ecc_job_kind_q == ECC_JOB_PMUL)
                        res_n={32'b0, ecc_job_cycle_status, 6'b0, ecc_pmul_result_q,
                               ecc_job_done_q, ecc_job_active_q, STATUS_OK};
                    st_n=S_RESULT;
                end
                end
            end

            HDEC_ECC_ADD: begin
                if (!ECC_DEBUG_FIELD_OPS) begin
                    res_n={62'b0,STATUS_NOT_IMPLEMENTED};st_n=S_RESULT;
                end else begin
                    uop_p0_n.valid        = 1'b1;
                    uop_p0_n.op_type      = UOP_HBIND_CHUNK;
                    uop_p0_n.src0_addr    = a_q[11:6];
                    uop_p0_n.src1_addr    = a_q[5:0];
                    uop_p0_n.dst_addr     = a_q[17:12];
                    uop_p0_n.chunk_idx    = 2'd3;
                    st_n=S_UOP_P1_RD0;
                end
            end

            HDEC_ECC_ALIGN: begin
                if (!ECC_DEBUG_FIELD_OPS) begin
                    res_n={62'b0,STATUS_NOT_IMPLEMENTED};st_n=S_RESULT;
                end else begin
                    hperm_dst_base_n       = a_q[17:12];
                    hperm_bit_low_n        = a_q[19:18];
                    hperm_spread_n         = 1'b0;
                    hperm_lane_base_n      = a_q[25:24];
                    uop_p0_n.valid         = 1'b1;
                    uop_p0_n.op_type       = UOP_HPERM_CHUNK;
                    uop_p0_n.chunk_idx     = 2'd3;
                    uop_p0_n.src0_addr     = a_q[5:0];
                    uop_p0_n.src1_addr     = a_q[11:6];
                    uop_p0_n.dst_addr      = a_q[17:12];
                    uop_p0_n.perm_nibble   = a_q[23:20];
                    st_n=S_UOP_P1_RD0;
                end
            end

            HDEC_ECC_REDUCE: begin
                if (!ECC_DEBUG_FIELD_OPS) begin
                    res_n={62'b0,STATUS_NOT_IMPLEMENTED};st_n=S_RESULT;
                end else begin
                    ecc_autoreduce_n=1'b0; ecc_raw_product_n=1'b0;
                    ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    if (a_q[5:0] == 6'd63) begin
                        res_n={62'b0,STATUS_ERROR};st_n=S_RESULT;
                    end else begin
                        ecc_dst_n = a_q[17:12];
                        ecc_src_a_n = a_q[5:0];
                        vrf_req.ra=a_q[5:0];
                        st_n=S_ECC_REDUCE_LOAD_LO_WAIT;
                    end
                end
            end

            HDEC_HCLR: begin
                clr_base_n={a_q[3:0],2'b00};clr_cnt_n=4'd0;st_n=S_CLR;
            end

            HDEC_HCNTCLR: begin
                clr_base_n=a_q[0]?hdc_cnt_base1:hdc_cnt_base0;clr_cnt_n=4'd0;st_n=S_CLR;
            end

            HDEC_HCNTADD: begin
                if(a_q[3])begin res_n={62'b0,STATUS_ERROR};st_n=S_RESULT;end
                else begin
                    uop_p0_n.valid       = 1'b1;
                    uop_p0_n.op_type     = UOP_HCNTADD_SUBGROUP;
                    uop_p0_n.chunk_idx   = 2'd0;
                    uop_p0_n.subgroup_idx= 2'd0;
                    uop_p0_n.src0_addr   = {1'b0, a_q[2:0], 2'b00};
                    uop_p0_n.src1_addr   = a_q[4] ? hdc_cnt_base1 : hdc_cnt_base0;
                    uop_p0_n.dst_addr    = a_q[4] ? hdc_cnt_base1 : hdc_cnt_base0;
                    st_n=S_UOP_P1_RD0;
                end
            end

            HDEC_HBIND: begin
                uop_p0_n.valid        = 1'b1;
                uop_p0_n.op_type      = UOP_HBIND_CHUNK;
                uop_p0_n.src0_addr    = {a_q[7:4], 2'b00};
                uop_p0_n.src1_addr    = {a_q[11:8],2'b00};
                uop_p0_n.dst_addr     = {a_q[3:0], 2'b00};
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
                if(hmatch_req_invalid)begin
                    res_n={62'b0,STATUS_ERROR};st_n=S_RESULT;
                end else begin
                    st_n=S_HMATCH_INIT;
                end
            end

            HDEC_HCNTCLIP: begin
                hcntclip_dst_base_n={a_q[2:0],2'b00};
                hcntclip_acc_sel_n=a_q[3];
                // Low-area bit-plane mode fixes clip to the non-zero predicate.
                hcntclip_chunk_n=2'd0;
                uop_p0_n.valid       = 1'b1;
                uop_p0_n.op_type     = UOP_HCNTCLIP_READ;
                uop_p0_n.chunk_idx   = 2'd0;
                uop_p0_n.subgroup_idx= 2'd0;
                uop_p0_n.src0_addr   = (a_q[3] ? hdc_cnt_base1 : hdc_cnt_base0);
                uop_p0_n.src1_addr   = (a_q[3] ? hdc_cnt_base1 : hdc_cnt_base0);
                st_n=S_UOP_P1_RD0;
            end

            HDEC_HPERM: begin
                if (a_q[18]) begin
                    if (!ECC_DEBUG_FIELD_OPS) begin
                        res_n={62'b0,STATUS_NOT_IMPLEMENTED};st_n=S_RESULT;
                    end else if ((a_q[5:0] == 6'd63)
                     || (a_q[20] && ((a_q[17:12] == a_q[5:0])
                                   || (a_q[17:12] == (a_q[5:0] + 6'd1))))) begin
                        ecc_autoreduce_n=1'b0; ecc_raw_product_n=1'b0;
                        ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                        res_n={62'b0,STATUS_ERROR};st_n=S_RESULT;
                    end else begin
                        hperm_dst_base_n=a_q[5:0];
                        hperm_spread_n=1'b1;
                        ecc_dst_n=a_q[5:0];
                        ecc_acc_dst_n=a_q[17:12];
                        ecc_autoreduce_n=a_q[19] | a_q[20];
                        ecc_mac_n=a_q[20];
                        ecc_sqr_repeat_n=(a_q[19] | a_q[20]) ? {3'b0, a_q[27:24]} : 7'd0;
                        vrf_req.ra=a_q[11:6];
                        st_n=S_RD_WAIT;
                    end
                end else if(a_q[3:0] == a_q[7:4])begin res_n={62'b0,STATUS_ERROR};st_n=S_RESULT;end
                else begin
                    hperm_dst_base_n={a_q[3:0],2'b00};
                    hperm_bit_low_n=a_q[9:8];
                    hperm_spread_n=1'b0;
                    hperm_lane_base_n=a_q[15:14];
                    uop_p0_n.valid       = 1'b1;
                    uop_p0_n.op_type     = UOP_HPERM_CHUNK;
                    uop_p0_n.chunk_idx   = 2'd0;
                    uop_p0_n.src0_addr   = hperm_read_addr({a_q[7:4],2'b00}, 2'd0, a_q[17:14], 1'b0);
                    uop_p0_n.src1_addr   = hperm_read_addr({a_q[7:4],2'b00}, 2'd0, a_q[17:14], 1'b1);
                    uop_p0_n.dst_addr    = hperm_dst_base_n;
                    uop_p0_n.perm_nibble = a_q[13:10];
                    st_n=S_UOP_P1_RD0;
                end
            end

            default: begin res_n={62'b0,STATUS_NOT_IMPLEMENTED};st_n=S_RESULT;end
        endcase end

        S_VWR_WAIT: begin res_n='0;st_n=S_RESULT;end

        S_RD_WAIT: begin
            st_n=S_RD_WAIT2;
        end

        S_RD_WAIT2: begin
            if (ecc_autoreduce_q
             && (((op_q == HDEC_HPERM) && hperm_spread_q)
              || (ecc_job_active_q && (ecc_job_phase_q == ECC_PHASE_INV_SQR))
              || (ecc_job_active_q && hperm_spread_q && (ecc_job_phase_q == ECC_PHASE_PMUL_FIELD))))
                st_n=S_ECC_SQR_WRITE;
            else if (((op_q == HDEC_HPERM) && hperm_spread_q)
                  || (ecc_job_active_q && (ecc_job_phase_q == ECC_PHASE_INV_SQR))
                  || (ecc_job_active_q && hperm_spread_q && (ecc_job_phase_q == ECC_PHASE_PMUL_FIELD)))
                st_n=S_HSPREAD_LO_WRITE;
            else
                st_n=S_RD_CAPTURE;
        end

        S_RD_CAPTURE: begin res_n=vrf_rd[vaddr_bank_q];st_n=S_RESULT;end

        S_ECC_SQR_WRITE: begin
            vrf_req.wa=hspread_dst_base;
            vrf_req.wd=ecc_square_reduce_word;
            hperm_spread_n=1'b0;
            ecc_dst_n=hspread_dst_base;
            ecc_autoreduce_n=1'b0;
            if (ecc_mac_q && (ecc_sqr_repeat_q == 7'd0)) begin
                uop_p0_n='0;
                uop_p0_n.valid     = 1'b1;
                uop_p0_n.op_type   = UOP_HBIND_CHUNK;
                uop_p0_n.src0_addr = ecc_acc_dst_q;
                uop_p0_n.src1_addr = hspread_dst_base;
                uop_p0_n.dst_addr  = ecc_acc_dst_q;
                uop_p0_n.chunk_idx = 2'd3;
                st_n=S_UOP_P1_RD0;
            end else begin
                st_n=S_ECC_WRITE_DRAIN;
            end
        end

        S_HSPREAD_LO_WRITE: begin
            vrf_req.wa=hspread_dst_base;
            hdc_src0_n[2] = vrf_rd[2];
            hdc_src0_n[3] = vrf_rd[3];
            hdc_src0_we=1'b1;
            vrf_req.wd[0]=hspread_half64(vrf_rd[0], 1'b0);
            vrf_req.wd[1]=hspread_half64(vrf_rd[0], 1'b1);
            vrf_req.wd[2]=hspread_half64(vrf_rd[1], 1'b0);
            vrf_req.wd[3]=hspread_half64(vrf_rd[1], 1'b1);
            st_n=S_HSPREAD_HI_WRITE;
        end

        S_HSPREAD_HI_WRITE: begin
            vrf_req.wa=hspread_dst_base + 6'd1;
            vrf_req.wd[0]=hspread_half64(hdc_src0_q[2], 1'b0);
            vrf_req.wd[1]=hspread_half64(hdc_src0_q[2], 1'b1);
            vrf_req.wd[2]=hspread_half64(hdc_src0_q[3], 1'b0);
            vrf_req.wd[3]=hspread_half64(hdc_src0_q[3], 1'b1);
            hperm_spread_n=1'b0;
            res_n={62'b0,STATUS_OK};
            st_n=S_RESULT;
        end

        // ── ECC V1 raw GF(2) diagonal multiply ─────────────────────────────
        S_ECC_LOAD_A_WAIT: begin
            ecc_leaf_path_n = '0;
            if (ecc_autoreduce_q) begin
                hdc_src0_n = '0;
                hdc_src0_we=1'b1;
            end
            st_n=S_ECC_LOAD_A_WAIT2;
        end

        S_ECC_LOAD_A_WAIT2: begin
            vrf_req.ra=ecc_src_b_q;
            st_n=S_ECC_LOAD_A;
        end

        S_ECC_LOAD_A: begin
            ecc_leaf_a_n = ecc_leaf_lowxor_rd[31:0];
            ecc_leaf_xor_a_n = ecc_leaf_lowxor_rd[63:32];
            vrf_req.ra=ecc_src_b_q;
            st_n=S_ECC_LOAD_B_WAIT;
        end

        S_ECC_LOAD_B_WAIT: begin
            st_n=S_ECC_LOAD_B;
        end

        S_ECC_LOAD_B: begin
            ecc_leaf_b_n = ecc_bitrev32_top(ecc_leaf_lowxor_rd[31:0]);
            ecc_leaf_xor_b_n = ecc_bitrev32_top(ecc_leaf_lowxor_rd[63:32]);
            ecc_leaf128_prod_n = '0;
            ecc_kpd64_sub_n = 2'd0;
            ecc_leaf_prod_n = '0;
            ecc_diag_group_n = '0;
            ecc_leaf_path_n = '0;
            ecc_fold_word_n = 2'd0;
            st_n=S_ECC_DIAG_ISSUE;
        end

        S_ECC_DIAG_ISSUE: begin
            st_n=S_ECC_DIAG_CAPTURE;
        end

        S_ECC_DIAG_CAPTURE: begin
            ecc_leaf_prod_n = (ecc_diag_group_q == 3'd7) ? ecc_leaf_prod_group7_w
                                                         : ecc_leaf_prod_store_w;
            if (ecc_diag_group_q == 3'd7) begin
                if (ecc_kpd64_sub_q < 2'd2) begin
                    ecc_leaf128_prod_n = ecc_sub32_capture_accum_xor1;
                    ecc_kpd64_sub_n = ecc_kpd64_sub_q + 2'd1;
                    ecc_leaf_prod_n = '0;
                    ecc_diag_group_n = '0;
                    st_n=S_ECC_DIAG_CAPTURE;
                end else begin
                    ecc_leaf128_prod_n = ecc_sub32_capture_accum_xor1;
                    ecc_kpd64_sub_n = 2'd3;
                    ecc_leaf_prod_n = '0;
                    ecc_diag_group_n = '0;
                    if (!ecc_leaf_last)
                        vrf_req.ra=ecc_src_a_q;
                    st_n=S_ECC_LEAF_FOLD;
                end
            end else begin
                if (ecc_autoreduce_fast
                    && !ecc_leaf_last && (ecc_kpd64_sub_q == 2'd2)) begin
                    if (ecc_diag_group_q == 3'd5)
                        vrf_req.ra=ecc_src_a_q;
                    else if (ecc_diag_group_q == 3'd6)
                        vrf_req.ra=ecc_src_b_q;
                end
                if (ecc_diag_group_q == 3'd6) begin
                    if (ecc_kpd64_sub_q == 2'd0) begin
                        ecc_leaf_a_n = ecc_leaf_a_lowxor_xor1;
                        ecc_leaf_b_n = ecc_leaf_b_lowxor_xor1;
                    end else if (ecc_kpd64_sub_q == 2'd1) begin
                        ecc_leaf_a_n = ecc_leaf_xor_a_q;
                        ecc_leaf_b_n = ecc_leaf_xor_b_q;
                    end
                end
                ecc_diag_group_n = ecc_diag_group_q + 3'd1;
                st_n=S_ECC_DIAG_CAPTURE;
            end
        end

        S_ECC_LEAF_FOLD: begin
            ecc_product_we = ECC_DEBUG_FIELD_OPS && ecc_raw_product_q;
            if (ecc_autoreduce_fast) begin
                if (ecc_leaf_last) begin
                    hdc_src0_acc_we=1'b1;
                    ecc_fold_word_n = 2'd0;
                    st_n=S_ECC_WRITE_PAIR;
                end else if (ecc_fold_word_q == 2'd0) begin
                    hdc_src0_acc_we=1'b1;
                    ecc_leaf_a_n = ecc_leaf_lowxor_rd[31:0];
                    ecc_leaf_xor_a_n = ecc_leaf_lowxor_rd[63:32];
                    ecc_fold_word_n = 2'd1;
                    st_n=S_ECC_LEAF_FOLD;
                end else begin
                    ecc_leaf_b_n = ecc_bitrev32_top(ecc_leaf_lowxor_rd[31:0]);
                    ecc_leaf_xor_b_n = ecc_bitrev32_top(ecc_leaf_lowxor_rd[63:32]);
                    ecc_fold_word_n = 2'd0;
                    ecc_leaf_path_n = ecc_next_leaf_path;
                    ecc_leaf128_prod_n = '0;
                    ecc_kpd64_sub_n = 2'd0;
                    st_n=S_ECC_DIAG_ISSUE;
                end
            end else begin
                if (!ecc_leaf_last) begin
                unique case (ecc_fold_word_q)
                    2'd0: begin
                        vrf_req.ra=ecc_src_b_q;
                    end
                    2'd1: begin
                    end
                    2'd2: begin
                        ecc_leaf_a_n = ecc_leaf_lowxor_rd[31:0];
                        ecc_leaf_xor_a_n = ecc_leaf_lowxor_rd[63:32];
                    end
                    default: begin
                        ecc_leaf_b_n = ecc_bitrev32_top(ecc_leaf_lowxor_rd[31:0]);
                        ecc_leaf_xor_b_n = ecc_bitrev32_top(ecc_leaf_lowxor_rd[63:32]);
                    end
                endcase
                end
                if (ecc_autoreduce_q && (ecc_fold_word_q == 2'd3)) begin
                    hdc_src0_acc_we=1'b1;
                end
                if (ecc_fold_word_q == 2'd3) begin
                    ecc_fold_word_n = 2'd0;
                    if (ecc_leaf_last) begin
                        st_n=S_ECC_WRITE_PAIR;
                    end else begin
                        ecc_leaf_path_n = ecc_next_leaf_path;
                        ecc_leaf128_prod_n = '0;
                        ecc_kpd64_sub_n = 2'd0;
                        st_n=S_ECC_DIAG_ISSUE;
                    end
                end else begin
                    ecc_fold_word_n = ecc_fold_word_q + 2'd1;
                    st_n=S_ECC_LEAF_FOLD;
                end
            end
        end

        S_ECC_WRITE_PAIR: begin
            if (ecc_autoreduce_q) begin
                vrf_req.wa=ecc_dst_q;
                vrf_req.wd=hdc_src0_q;
                ecc_autoreduce_n=1'b0;
                if (ecc_mac_q && (ecc_sqr_repeat_q == 7'd0)) begin
                    uop_p0_n='0;
                    uop_p0_n.valid     = 1'b1;
                    uop_p0_n.op_type   = UOP_HBIND_CHUNK;
                    uop_p0_n.src0_addr = ecc_acc_dst_q;
                    uop_p0_n.src1_addr = ecc_dst_q;
                    uop_p0_n.dst_addr  = ecc_acc_dst_q;
                    uop_p0_n.chunk_idx = 2'd3;
                    st_n=S_UOP_P1_RD0;
                end else if (ecc_sqr_repeat_q == 7'd0) begin
                    res_n={56'b0, ecc_dst_q, STATUS_OK};
                    if (ecc_job_active_q && (ecc_job_phase_q == ECC_PHASE_INV_SQR)) begin
                        st_n=S_ECC_INV_AFTER_SQR;
                    end else if (ecc_job_active_q && (ecc_job_phase_q == ECC_PHASE_INV_MUL)) begin
                        st_n=S_ECC_INV_AFTER_MUL;
                    end else if (ecc_job_active_q && (ecc_job_phase_q == ECC_PHASE_PMUL_FIELD)) begin
                        ecc_job_phase_n=ECC_PHASE_NONE;
                        st_n=S_ECC_PMUL_STEP_NEXT;
                    end else begin
                        st_n=S_ECC_WRITE_DRAIN;
                    end
                end else begin
                    st_n=S_ECC_WRITE_DRAIN;
                end
            end else if (ECC_DEBUG_FIELD_OPS) begin
                vrf_req.wa=ecc_product_wb_addr;
                if (!ecc_fold_word_q[0]) begin
                    ecc_fold_word_n=ecc_fold_word_q + 2'd1;
                    st_n=S_ECC_WRITE_PAIR;
                end else begin
                    vrf_req.wd[0]=ecc_product_pair_hold_q[63:0];
                    vrf_req.wd[1]=ecc_product_pair_hold_q[127:64];
                    vrf_req.wd[2]=ecc_product_pair_rdata[63:0];
                    vrf_req.wd[3]=ecc_product_pair_rdata[127:64];
                    if (ecc_fold_word_q[1]) begin
                        if (ecc_autoreduce_q)
                            ecc_src_a_n = ecc_dst_q;
                        ecc_raw_product_n = 1'b0;
                        st_n=S_ECC_WRITE_DRAIN;
                    end else begin
                        ecc_fold_word_n = 2'd2;
                        st_n=S_ECC_WRITE_PAIR;
                    end
                end
            end else begin
                st_n=S_ECC_WRITE_DRAIN;
            end
        end

        // ── S_CLR: shared by HCLR (4 entries) and HCNTCLR (16 entries) ──────
        S_ECC_WRITE_DRAIN: begin
            if (ECC_DEBUG_FIELD_OPS && ecc_autoreduce_q) begin
                vrf_req.ra=ecc_src_a_q;
                st_n=S_ECC_REDUCE_LOAD_LO_WAIT;
            end else if (ecc_sqr_repeat_q != 7'd0) begin
                hperm_dst_base_n=ecc_dst_q;
                hperm_spread_n=1'b1;
                ecc_src_a_n=ecc_dst_q;
                ecc_autoreduce_n=1'b1;
                ecc_sqr_repeat_n=ecc_sqr_repeat_q - 7'd1;
                vrf_req.ra=ecc_dst_q;
                st_n=S_RD_WAIT;
            end else begin
                if (ecc_job_active_q && (ecc_job_phase_q == ECC_PHASE_INV_SQR)) begin
                    st_n=S_ECC_INV_AFTER_SQR;
                end else if (ecc_job_active_q && (ecc_job_phase_q == ECC_PHASE_INV_MUL)) begin
                    st_n=S_ECC_INV_AFTER_MUL;
                end else if (ecc_job_active_q && (ecc_job_phase_q == ECC_PHASE_PMUL_FIELD)) begin
                    ecc_job_phase_n=ECC_PHASE_NONE;
                    st_n=S_ECC_PMUL_STEP_NEXT;
                end else begin
                    res_n={56'b0, ecc_dst_q, STATUS_OK};
                    st_n=S_RESULT;
                end
            end
        end

        S_ECC_REDUCE_LOAD_LO_WAIT: begin
            st_n=S_ECC_REDUCE_LOAD_LO_WAIT2;
        end

        S_ECC_REDUCE_LOAD_LO_WAIT2: begin
            vrf_req.ra=ecc_src_a_q + 6'd1;
            st_n=S_ECC_REDUCE_LOAD_LO;
        end

        S_ECC_REDUCE_LOAD_LO: begin
            hdc_src0_n = vrf_rd;
            hdc_src0_we=1'b1;
            vrf_req.ra=ecc_src_a_q + 6'd1;
            st_n=S_ECC_REDUCE_LOAD_HI_WAIT;
        end

        S_ECC_REDUCE_LOAD_HI_WAIT: begin
            st_n=S_ECC_REDUCE_WRITE;
        end

        S_ECC_REDUCE_WRITE: begin
            vrf_req.wa=ecc_dst_q;
            vrf_req.wd[0]=lane_ecc_reduce_word[0];
            vrf_req.wd[1]=lane_ecc_reduce_word[1];
            vrf_req.wd[2]=lane_ecc_reduce_word[2];
            vrf_req.wd[3]=lane_ecc_reduce_word[3];
            ecc_autoreduce_n=1'b0;
            if (ecc_mac_q && (ecc_sqr_repeat_q == 7'd0)) begin
                uop_p0_n='0;
                uop_p0_n.valid     = 1'b1;
                uop_p0_n.op_type   = UOP_HBIND_CHUNK;
                uop_p0_n.src0_addr = ecc_acc_dst_q;
                uop_p0_n.src1_addr = ecc_dst_q;
                uop_p0_n.dst_addr  = ecc_acc_dst_q;
                uop_p0_n.chunk_idx = 2'd3;
                st_n=S_UOP_P1_RD0;
            end else if (ecc_sqr_repeat_q == 7'd0) begin
                res_n={56'b0, ecc_dst_q, STATUS_OK};
                st_n=S_ECC_WRITE_DRAIN;
            end else begin
                st_n=S_ECC_WRITE_DRAIN;
            end
        end

        S_ECC_INV_INIT: begin
            ecc_inv_step_n='0;
            ecc_job_phase_n=ECC_PHASE_INV_COPY_INIT;
            ecc_dst_n=ecc_job_dst_q;
            vrf_req.ra=ecc_job_src_q;
            st_n=S_ECC_INV_COPY_WAIT;
        end

        S_ECC_INV_COPY_WAIT: begin
            st_n=S_ECC_INV_COPY_WAIT2;
        end

        S_ECC_INV_COPY_WAIT2: begin
            st_n=S_ECC_INV_COPY_WRITE;
        end

        S_ECC_INV_COPY_WRITE: begin
            vrf_req.wa=ecc_dst_q;
            vrf_req.wd=vrf_rd;
            if (ecc_job_phase_q == ECC_PHASE_PMUL_COPY) begin
                ecc_job_phase_n=ECC_PHASE_NONE;
                st_n=S_ECC_PMUL_STEP_NEXT;
            end else if (ecc_job_phase_q == ECC_PHASE_INV_COPY_TMP) begin
                ecc_job_phase_n=ECC_PHASE_NONE;
                st_n=S_ECC_INV_ISSUE_SQR;
            end else begin
                ecc_job_phase_n=ECC_PHASE_NONE;
                st_n=S_ECC_INV_STEP;
            end
        end

        S_ECC_INV_STEP: begin
            if (ecc_inv_step_needs_tmp(ecc_inv_step_q)) begin
                ecc_job_phase_n=ECC_PHASE_INV_COPY_TMP;
                ecc_dst_n=ecc_job_dst_q + 6'd2;
                vrf_req.ra=ecc_job_dst_q;
                st_n=S_ECC_INV_COPY_WAIT;
            end else begin
                st_n=S_ECC_INV_ISSUE_SQR;
            end
        end

        S_ECC_INV_ISSUE_SQR: begin
            hperm_spread_n=1'b1;
            hperm_dst_base_n=ecc_job_dst_q;
            ecc_dst_n=ecc_job_dst_q;
            ecc_src_a_n=ecc_job_dst_q;
            ecc_autoreduce_n=1'b1;
            ecc_mac_n=1'b0;
            ecc_sqr_repeat_n=ecc_inv_step_sqr_repeat(ecc_inv_step_q);
            ecc_job_phase_n=ECC_PHASE_INV_SQR;
            vrf_req.ra=ecc_job_dst_q;
            st_n=S_RD_WAIT;
        end

        S_ECC_INV_AFTER_SQR: begin
            ecc_job_phase_n=ECC_PHASE_NONE;
            if (!ecc_inv_step_has_mul(ecc_inv_step_q)) begin
                st_n=S_ECC_JOB_DONE;
            end else begin
                ecc_dst_n=ecc_job_dst_q;
                ecc_acc_dst_n='0;
                ecc_src_a_n=ecc_job_dst_q;
                ecc_src_b_n=ecc_inv_step_mul_src_is_orig(ecc_inv_step_q) ? ecc_job_src_q
                                                                          : (ecc_job_dst_q + 6'd2);
                ecc_autoreduce_n=1'b1;
                ecc_mac_n=1'b0;
                ecc_sqr_repeat_n='0;
                ecc_job_phase_n=ECC_PHASE_INV_MUL;
                vrf_req.ra=ecc_job_dst_q;
                st_n=S_ECC_LOAD_A_WAIT;
            end
        end

        S_ECC_INV_AFTER_MUL: begin
            ecc_job_phase_n=ECC_PHASE_NONE;
            ecc_inv_step_n=ecc_inv_step_q + 4'd1;
            st_n=S_ECC_INV_STEP;
        end

        S_ECC_PMUL_INIT: begin
            ecc_pmul_subop_n=ECC_PMUL_SUB_INIT;
            ecc_pmul_step_n='0;
            st_n=S_ECC_PMUL_STEP;
        end

        S_ECC_PMUL_CONST_WRITE: begin
            vrf_req.wa=ecc_dst_q;
            vrf_req.wd='0;
            if (ecc_pmul_const_one_from_dst)
                vrf_req.wd[0]=64'd1;
            st_n=S_ECC_PMUL_STEP_NEXT;
        end

        S_ECC_PMUL_READ_SCALAR_WAIT: begin
            st_n=S_ECC_PMUL_READ_SCALAR_WAIT2;
        end

        S_ECC_PMUL_READ_SCALAR_WAIT2: begin
            st_n=S_ECC_PMUL_READ_SCALAR;
        end

        S_ECC_PMUL_READ_SCALAR: begin
            ecc_pmul_scalar_bit_n=ecc_scalar_bit_from_row(vrf_rd, ecc_pmul_bit_q);
            ecc_pmul_step_n='0;
            if (ecc_scalar_bit_from_row(vrf_rd, ecc_pmul_bit_q))
                ecc_pmul_r0_inf_n=1'b0;
            ecc_pmul_subop_n=ECC_PMUL_SUB_ADD;
            st_n=S_ECC_PMUL_STEP;
        end

        S_ECC_PMUL_STEP: begin
            unique case (ecc_pmul_subop_q)
            ECC_PMUL_SUB_INIT: begin
                unique case (ecc_pmul_step_q)
                6'd0: begin
                    ecc_job_phase_n=ECC_PHASE_PMUL_COPY;
                    ecc_dst_n=ECC_PMUL_R1X;
                    vrf_req.ra=ecc_pmul_point_q;
                    st_n=S_ECC_INV_COPY_WAIT;
                end
                6'd1: begin
                    ecc_dst_n=ECC_PMUL_R0X;
                    st_n=S_ECC_PMUL_CONST_WRITE;
                end
                6'd2: begin
                    ecc_dst_n=ECC_PMUL_R0Z;
                    st_n=S_ECC_PMUL_CONST_WRITE;
                end
                default: begin
                    ecc_dst_n=ECC_PMUL_R1Z;
                    st_n=S_ECC_PMUL_CONST_WRITE;
                end
                endcase
            end
            ECC_PMUL_SUB_ZERO_OUT: begin
                ecc_dst_n=(ecc_pmul_step_q == 6'd0) ? ecc_pmul_result_q : (ecc_pmul_result_q + 6'd1);
                st_n=S_ECC_PMUL_CONST_WRITE;
            end
            ECC_PMUL_SUB_AFFINE: begin
                unique case (ecc_pmul_step_q)
                6'd0: begin
                    ecc_dst_n=ECC_PMUL_T0; ecc_src_a_n=ECC_PMUL_R0Z; ecc_src_b_n=ECC_PMUL_R1Z;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_R0Z;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                6'd1: begin
                    ecc_dst_n=ECC_PMUL_T2; ecc_src_a_n=ECC_PMUL_T0; ecc_src_b_n=ecc_pmul_point_q;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_T0;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                6'd2: begin
                    ecc_job_src_n=ECC_PMUL_T2;
                    ecc_job_dst_n=ECC_PMUL_T3;
                    ecc_inv_step_n='0;
                    st_n=S_ECC_INV_INIT;
                end
                6'd3: begin
                    ecc_dst_n=ECC_PMUL_T1; ecc_src_a_n=ECC_PMUL_R1Z; ecc_src_b_n=ecc_pmul_point_q;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_R1Z;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                6'd4: begin
                    ecc_dst_n=ECC_PMUL_T1; ecc_src_a_n=ECC_PMUL_T1; ecc_src_b_n=ECC_PMUL_T3;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_T1;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                6'd5: begin
                    ecc_dst_n=ECC_PMUL_T4; ecc_src_a_n=ECC_PMUL_R0X; ecc_src_b_n=ECC_PMUL_T1;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_R0X;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                6'd6: begin
                    ecc_dst_n=ECC_PMUL_T1; ecc_src_a_n=ECC_PMUL_R0Z; ecc_src_b_n=ecc_pmul_point_q;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_R0Z;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                6'd7: begin
                    ecc_dst_n=ECC_PMUL_T1; ecc_src_a_n=ECC_PMUL_T1; ecc_src_b_n=ECC_PMUL_T3;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_T1;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                6'd8: begin
                    ecc_dst_n=ECC_PMUL_T6; ecc_src_a_n=ECC_PMUL_R1X; ecc_src_b_n=ECC_PMUL_T1;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_R1X;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                6'd9: begin
                    ecc_dst_n=ECC_PMUL_T1; ecc_src_a_n=ECC_PMUL_T0; ecc_src_b_n=ECC_PMUL_T3;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_T0;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                6'd10: begin
                    uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK;
                    uop_p0_n.src0_addr=ECC_PMUL_T4; uop_p0_n.src1_addr=ecc_pmul_point_q;
                    uop_p0_n.dst_addr=ECC_PMUL_T2; uop_p0_n.chunk_idx=2'd3;
                    ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0;
                end
                6'd11: begin
                    uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK;
                    uop_p0_n.src0_addr=ECC_PMUL_T6; uop_p0_n.src1_addr=ECC_PMUL_T4;
                    uop_p0_n.dst_addr=ECC_PMUL_T3; uop_p0_n.chunk_idx=2'd3;
                    ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0;
                end
                6'd12: begin
                    uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK;
                    uop_p0_n.src0_addr=ECC_PMUL_T3; uop_p0_n.src1_addr=ecc_pmul_point_q;
                    uop_p0_n.dst_addr=ECC_PMUL_T3; uop_p0_n.chunk_idx=2'd3;
                    ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0;
                end
                6'd13: begin
                    hperm_spread_n=1'b1;
                    hperm_dst_base_n=ECC_PMUL_T5;
                    ecc_dst_n=ECC_PMUL_T5; ecc_src_a_n=ECC_PMUL_T5;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_T4;
                    st_n=S_RD_WAIT;
                end
                6'd14: begin
                    ecc_dst_n=ECC_PMUL_T7; ecc_src_a_n=ECC_PMUL_T5; ecc_src_b_n=ECC_PMUL_T4;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_T5;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                6'd15: begin
                    ecc_dst_n=ECC_PMUL_T9;
                    st_n=S_ECC_PMUL_CONST_WRITE;
                end
                6'd16: begin
                    uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK;
                    uop_p0_n.src0_addr=ECC_PMUL_T7; uop_p0_n.src1_addr=ECC_PMUL_T9;
                    uop_p0_n.dst_addr=ECC_PMUL_T7; uop_p0_n.chunk_idx=2'd3;
                    ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0;
                end
                6'd17: begin
                    hperm_spread_n=1'b1;
                    hperm_dst_base_n=ECC_PMUL_T8;
                    ecc_dst_n=ECC_PMUL_T8; ecc_src_a_n=ECC_PMUL_T8;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_T2;
                    st_n=S_RD_WAIT;
                end
                6'd18: begin
                    ecc_dst_n=ECC_PMUL_T8; ecc_src_a_n=ECC_PMUL_T3; ecc_src_b_n=ECC_PMUL_T8;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_T3;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                6'd19: begin
                    uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK;
                    uop_p0_n.src0_addr=ECC_PMUL_T7; uop_p0_n.src1_addr=ECC_PMUL_T8;
                    uop_p0_n.dst_addr=ECC_PMUL_T7; uop_p0_n.chunk_idx=2'd3;
                    ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0;
                end
                6'd20: begin
                    hperm_spread_n=1'b1;
                    hperm_dst_base_n=ECC_PMUL_T8;
                    ecc_dst_n=ECC_PMUL_T8; ecc_src_a_n=ECC_PMUL_T8;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ecc_pmul_point_q + 6'd1;
                    st_n=S_RD_WAIT;
                end
                6'd21: begin
                    uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK;
                    uop_p0_n.src0_addr=ECC_PMUL_T7; uop_p0_n.src1_addr=ECC_PMUL_T8;
                    uop_p0_n.dst_addr=ECC_PMUL_T7; uop_p0_n.chunk_idx=2'd3;
                    ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0;
                end
                6'd22: begin
                    ecc_dst_n=ECC_PMUL_T8; ecc_src_a_n=ECC_PMUL_T4; ecc_src_b_n=ecc_pmul_point_q + 6'd1;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_T4;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                6'd23: begin
                    uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK;
                    uop_p0_n.src0_addr=ECC_PMUL_T7; uop_p0_n.src1_addr=ECC_PMUL_T8;
                    uop_p0_n.dst_addr=ECC_PMUL_T7; uop_p0_n.chunk_idx=2'd3;
                    ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0;
                end
                6'd24: begin
                    ecc_dst_n=ECC_PMUL_T8; ecc_src_a_n=ECC_PMUL_T7; ecc_src_b_n=ECC_PMUL_T1;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_T7;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                6'd25: begin
                    uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK;
                    uop_p0_n.src0_addr=ECC_PMUL_T8; uop_p0_n.src1_addr=ecc_pmul_point_q + 6'd1;
                    uop_p0_n.dst_addr=ecc_pmul_result_q + 6'd1; uop_p0_n.chunk_idx=2'd3;
                    ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0;
                end
                default: begin
                    ecc_job_phase_n=ECC_PHASE_PMUL_COPY;
                    ecc_dst_n=ecc_pmul_result_q;
                    vrf_req.ra=ECC_PMUL_T4;
                    st_n=S_ECC_INV_COPY_WAIT;
                end
                endcase
            end
            ECC_PMUL_SUB_DBL: begin
                unique case (ecc_pmul_step_q)
                6'd0: begin hperm_spread_n=1'b1; hperm_dst_base_n=ECC_PMUL_T0; ecc_dst_n=ECC_PMUL_T0; ecc_src_a_n=ECC_PMUL_T0; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_req.ra=ecc_pmul_dbl_x; st_n=S_RD_WAIT; end
                6'd1: begin hperm_spread_n=1'b1; hperm_dst_base_n=ECC_PMUL_T1; ecc_dst_n=ECC_PMUL_T1; ecc_src_a_n=ECC_PMUL_T1; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_req.ra=ECC_PMUL_T0; st_n=S_RD_WAIT; end
                6'd2: begin hperm_spread_n=1'b1; hperm_dst_base_n=ECC_PMUL_T4; ecc_dst_n=ECC_PMUL_T4; ecc_src_a_n=ECC_PMUL_T4; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_req.ra=ecc_pmul_dbl_z; st_n=S_RD_WAIT; end
                6'd3: begin hperm_spread_n=1'b1; hperm_dst_base_n=ECC_PMUL_T5; ecc_dst_n=ECC_PMUL_T5; ecc_src_a_n=ECC_PMUL_T5; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_req.ra=ECC_PMUL_T4; st_n=S_RD_WAIT; end
                6'd4: begin uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK; uop_p0_n.src0_addr=ECC_PMUL_T1; uop_p0_n.src1_addr=ECC_PMUL_T5; uop_p0_n.dst_addr=ecc_pmul_dbl_x; uop_p0_n.chunk_idx=2'd3; ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0; end
                default: begin hperm_spread_n=1'b1; hperm_dst_base_n=ecc_pmul_dbl_z; ecc_dst_n=ecc_pmul_dbl_z; ecc_src_a_n=ecc_pmul_dbl_z; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_req.ra=ECC_PMUL_T2; st_n=S_RD_WAIT; end
                endcase
            end
            ECC_PMUL_SUB_ADD: begin
                unique case (ecc_pmul_step_q)
                6'd0: begin ecc_dst_n=ECC_PMUL_T0; ecc_src_a_n=ECC_PMUL_R0X; ecc_src_b_n=ECC_PMUL_R1Z; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_req.ra=ECC_PMUL_R0X; st_n=S_ECC_LOAD_A_WAIT; end
                6'd1: begin ecc_dst_n=ECC_PMUL_T1; ecc_src_a_n=ECC_PMUL_R1X; ecc_src_b_n=ECC_PMUL_R0Z; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_req.ra=ECC_PMUL_R1X; st_n=S_ECC_LOAD_A_WAIT; end
                6'd2: begin uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK; uop_p0_n.src0_addr=ECC_PMUL_T0; uop_p0_n.src1_addr=ECC_PMUL_T1; uop_p0_n.dst_addr=ECC_PMUL_T4; uop_p0_n.chunk_idx=2'd3; ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0; end
                6'd3: begin hperm_spread_n=1'b1; hperm_dst_base_n=ECC_PMUL_T5; ecc_dst_n=ECC_PMUL_T5; ecc_src_a_n=ECC_PMUL_T5; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_req.ra=ECC_PMUL_T4; st_n=S_RD_WAIT; end
                6'd4: begin ecc_dst_n=ECC_PMUL_T2; ecc_src_a_n=ecc_pmul_scalar_bit_q ? ECC_PMUL_R1X : ECC_PMUL_R0X; ecc_src_b_n=ecc_pmul_scalar_bit_q ? ECC_PMUL_R1Z : ECC_PMUL_R0Z; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_req.ra=ecc_pmul_scalar_bit_q ? ECC_PMUL_R1X : ECC_PMUL_R0X; st_n=S_ECC_LOAD_A_WAIT; end
                6'd5: begin ecc_dst_n=ECC_PMUL_T6; ecc_src_a_n=ECC_PMUL_T0; ecc_src_b_n=ECC_PMUL_T1; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_req.ra=ECC_PMUL_T0; st_n=S_ECC_LOAD_A_WAIT; end
                6'd6: begin ecc_dst_n=ECC_PMUL_T7; ecc_src_a_n=ecc_pmul_point_q; ecc_src_b_n=ECC_PMUL_T5; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_req.ra=ecc_pmul_point_q; st_n=S_ECC_LOAD_A_WAIT; end
                6'd7: begin uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK; uop_p0_n.src0_addr=ECC_PMUL_T7; uop_p0_n.src1_addr=ECC_PMUL_T6; uop_p0_n.dst_addr=ecc_pmul_add_out_x; uop_p0_n.chunk_idx=2'd3; ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0; end
                default: begin ecc_job_phase_n=ECC_PHASE_PMUL_COPY; ecc_dst_n=ecc_pmul_add_out_z; vrf_req.ra=ECC_PMUL_T5; st_n=S_ECC_INV_COPY_WAIT; end
                endcase
            end
            default: begin
                st_n=S_ECC_PMUL_STEP_NEXT;
            end
            endcase
        end

        S_ECC_PMUL_STEP_NEXT: begin
            if (ecc_pmul_subop_last(ecc_pmul_subop_q, ecc_pmul_step_q)) begin
                ecc_pmul_step_n='0;
                unique case (ecc_pmul_subop_q)
                ECC_PMUL_SUB_INIT: begin
                    vrf_req.ra=ecc_job_src_q;
                    st_n=S_ECC_PMUL_READ_SCALAR_WAIT;
                end
                ECC_PMUL_SUB_ADD: begin
                    ecc_pmul_step_n='0;
                    ecc_pmul_subop_n=ECC_PMUL_SUB_DBL;
                    st_n=S_ECC_PMUL_STEP;
                end
                ECC_PMUL_SUB_DBL: begin
                    if (ecc_pmul_bit_q == 8'd0) begin
                        ecc_pmul_subop_n=ecc_pmul_r0_inf_n ? ECC_PMUL_SUB_ZERO_OUT : ECC_PMUL_SUB_AFFINE;
                        st_n=(ecc_job_bg_q && valid_i) ? S_IDLE : S_ECC_PMUL_STEP;
                    end else begin
                        ecc_pmul_bit_n=ecc_pmul_bit_q - 8'd1;
                        vrf_req.ra=ecc_job_src_q;
                        st_n=S_ECC_PMUL_READ_SCALAR_WAIT;
                    end
                end
                default: begin
                    ecc_job_active_n=1'b0;
                    ecc_job_done_n=1'b1;
                    ecc_job_bg_n=1'b0;
                    ecc_job_phase_n=ECC_PHASE_NONE;
                    if (ecc_job_bg_q) begin
                        st_n=S_IDLE;
                    end else begin
                        res_n={32'b0, ecc_job_cycle_status, 6'b0, ecc_pmul_result_q, 2'b10, STATUS_OK};
                        st_n=S_RESULT;
                    end
                end
                endcase
            end else begin
                ecc_pmul_step_n=ecc_pmul_step_q + 6'd1;
                st_n=S_ECC_PMUL_STEP;
            end
        end

        S_ECC_JOB_DONE: begin
            ecc_job_phase_n=ECC_PHASE_NONE;
            if (ecc_job_kind_q == ECC_JOB_PMUL) begin
                st_n=S_ECC_PMUL_STEP_NEXT;
            end else begin
                ecc_job_active_n=1'b0;
                ecc_job_done_n=1'b1;
                ecc_job_bg_n=1'b0;
                if (ecc_job_bg_q) begin
                    st_n=S_IDLE;
                end else begin
                    res_n={32'b0, ecc_job_cycle_status, 6'b0, ecc_job_dst_q, 2'b10, STATUS_OK};
                    st_n=S_RESULT;
                end
            end
        end

        S_CLR: begin
            vrf_req.wa=clr_base_q+clr_cnt_q;
            vrf_req.wd='0;
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
            hmatch_best_dist_n = 11'd0;
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
            end
            vrf_req.ra=uop_p0_q.src0_addr;
            st_n=S_UOP_P1_RD0_WAIT;
        end

        S_UOP_P1_RD0_WAIT: begin
            st_n=S_UOP_P1_RD0_WAIT2;
        end

        S_UOP_P1_RD0_WAIT2: begin
            vrf_req.ra=uop_p0_q.src1_addr;
            st_n=S_UOP_P1_RD1;
        end

        S_UOP_P1_RD1: begin
            uop_p2_n       = uop_p0_q;
            p2_is_pop_n    = (uop_p0_q.op_type == UOP_HSIM_CHUNK)
                           || (uop_p0_q.op_type == UOP_HMATCH_CHUNK);
            p2_is_hbind_n  = (uop_p0_q.op_type == UOP_HBIND_CHUNK);
            uop_p0_n.valid = 1'b0;
            if ((uop_p0_q.op_type == UOP_HPERM_CHUNK)
             || (uop_p0_q.op_type == UOP_HCNTADD_SUBGROUP)
             || (uop_p0_q.op_type == UOP_HBIND_CHUNK)
             || (uop_p0_q.op_type == UOP_HSIM_CHUNK)
             || (uop_p0_q.op_type == UOP_HMATCH_CHUNK))
            begin
                hdc_src0_n = vrf_rd;
                hdc_src0_we=1'b1;
            end
            else if (uop_p0_q.op_type == UOP_HCNTCLIP_READ) begin
                hdc_src0_n = '0;
                hdc_src0_we=1'b1;
            end
            vrf_req.ra=uop_p0_q.src1_addr;
            st_n=S_UOP_P1_RD1_WAIT;
        end

        S_UOP_P1_RD1_WAIT: begin
            p2_lane_compute_n = uop_p2_q.valid;
            st_n=S_UOP_P2_LANE;
        end

        S_UOP_P2_LANE: begin
            uop_p3_n           = uop_p2_q;
            uop_p2_n.valid     = 1'b0;
            p2_is_pop_n        = 1'b0;
            p2_is_hbind_n      = 1'b0;
`ifndef SYNTHESIS
            assert ($onehot0({
                    ((uop_p2_q.op_type == UOP_HSIM_CHUNK)
                  || (uop_p2_q.op_type == UOP_HMATCH_CHUNK)),
                    uop_p2_use_counter,
                    uop_p2_use_shift,
                    uop_p2_use_clip,
                    (uop_p2_q.op_type == UOP_HBIND_CHUNK)
                }))
                else $error("HDEC P2 invalid compute mode flags: op_type=%0d",
                            uop_p2_q.op_type);
`endif
            if (uop_p2_use_shift) begin
                vrf_req.ra = uop_p2_q.src1_addr;
                hperm_lane_slot_n = 2'd0;
                hperm_lane_phase_n = 1'b0;
                hperm_lane_clear = 1'b1;
                st_n = S_HPERM_LANE64;
            end else begin
                st_n=S_UOP_P3_GLOBAL;
            end
        end

        S_HPERM_LANE64: begin
            vrf_req.ra = uop_p3_q.src1_addr;
            lane_shift_bit = {uop_p3_q.perm_nibble, hperm_bit_low_q};
            hperm_word_sel = {1'b0, hperm_lane_base_q} + {1'b0, hperm_lane_slot_q};
            hperm_next_sel = hperm_word_sel + 3'd1;
            hperm_wide_word = {
                hperm_pick_word(hperm_next_sel, hdc_src0_q, vrf_rd),
                hperm_pick_word(hperm_word_sel,  hdc_src0_q, vrf_rd)
            };
            if (!hperm_lane_phase_q) begin
                hperm_stage_n = hperm_byte_window(hperm_wide_word, lane_shift_bit[5:3]);
                hperm_stage_we = 1'b1;
                hperm_lane_phase_n = 1'b1;
            end else begin
                hperm_lane_word = hperm_low_shift(hperm_stage_q, lane_shift_bit[2:0]);
                hperm_lane_we = 1'b1;
                hperm_lane_phase_n = 1'b0;
                if (hperm_lane_slot_q == 2'd3) begin
                    st_n = S_UOP_P3_GLOBAL;
                end else begin
                    hperm_lane_slot_n = hperm_lane_slot_q + 2'd1;
                end
            end
        end

        S_UOP_P3_GLOBAL: begin
            uop_p3_n.valid  = 1'b0;
            if (uop_p3_q.op_type == UOP_HBIND_CHUNK) begin
                vrf_req.wa = uop_p3_q.dst_addr;
                vrf_req.wd = vec_payload_q;
            end else if ((uop_p3_q.op_type == UOP_HCNTADD_SUBGROUP)
                      || (uop_p3_q.op_type == UOP_HPERM_CHUNK)) begin
                vrf_req.wa = uop_p3_q.dst_addr;
                vrf_req.wd = vec_payload_q;
            end
            unique case (uop_p3_q.op_type)
            UOP_HBIND_CHUNK, UOP_HPERM_CHUNK: begin
                if (uop_p3_q.chunk_idx == 2'd3) st_n = S_UOP_P4_RESP;
                else begin
                    uop_p0_n = uop_p3_q; uop_p0_n.valid = 1'b1;
                    uop_p0_n.chunk_idx = uop_p3_q.chunk_idx + 2'd1;
                    uop_p0_n.src0_addr = uop_p3_q.src0_addr + 6'd1;
                    uop_p0_n.src1_addr = uop_p3_q.src1_addr + 6'd1;
                    uop_p0_n.dst_addr  = uop_p3_q.dst_addr  + 6'd1;
                    st_n = S_UOP_P1_RD0;
                end
            end
            UOP_HSIM_CHUNK, UOP_HMATCH_CHUNK: begin
                st_n = S_UOP_P3_POP_CAPTURE;
            end
            UOP_HCNTADD_SUBGROUP: begin
                if (uop_p3_q.subgroup_idx < 2'd3) begin
                    vrf_req.ra=uop_p3_q.dst_addr + 6'd1;
                    // Advance uop to P2 directly (skip P1_RD0/P1_RD1)
                    uop_p2_n = uop_p3_q; uop_p2_n.valid = 1'b1;
                    p2_is_pop_n = 1'b0; p2_is_hbind_n = 1'b0;
                    uop_p2_n.subgroup_idx = uop_p3_q.subgroup_idx + 2'd1;
                    uop_p2_n.src1_addr = uop_p3_q.dst_addr + 6'd1;
                    uop_p2_n.dst_addr = uop_p3_q.dst_addr + 6'd1;
                    uop_p0_n.valid = 1'b0;
                    st_n = S_UOP_P3_VRF_WAIT;
                end else if (uop_p3_q.chunk_idx < 2'd3) begin
                    uop_p0_n = uop_p3_q; uop_p0_n.valid = 1'b1;
                    uop_p0_n.chunk_idx    = uop_p3_q.chunk_idx + 2'd1;
                    uop_p0_n.subgroup_idx = 2'd0;
                    uop_p0_n.src0_addr = uop_p3_q.src0_addr + 6'd1;
                    uop_p0_n.src1_addr = uop_p3_q.dst_addr + 6'd1;
                    uop_p0_n.dst_addr  = uop_p3_q.dst_addr + 6'd1;
                    st_n = S_UOP_P1_RD0;
                end else st_n = S_UOP_P4_RESP;
            end
            UOP_HCNTCLIP_READ: begin
            hcntclip_word_with_result = hdc_src0_q;
                hcntclip_word_with_result[0][{uop_p3_q.subgroup_idx,4'b0000} +: 16] = vec_payload_q[0][15:0];
                hcntclip_word_with_result[1][{uop_p3_q.subgroup_idx,4'b0000} +: 16] = vec_payload_q[1][15:0];
                hcntclip_word_with_result[2][{uop_p3_q.subgroup_idx,4'b0000} +: 16] = vec_payload_q[2][15:0];
                hcntclip_word_with_result[3][{uop_p3_q.subgroup_idx,4'b0000} +: 16] = vec_payload_q[3][15:0];
                hdc_src0_n = hcntclip_word_with_result;
                hdc_src0_we=1'b1;
                if (uop_p3_q.subgroup_idx < 2'd3) begin
                    vrf_req.ra=hcntclip_acc_base+{2'b00,uop_p3_q.chunk_idx,2'b00}+{4'b0,(uop_p3_q.subgroup_idx + 2'd1)};
                    uop_p2_n = uop_p3_q; uop_p2_n.valid = 1'b1;
                    p2_is_pop_n = 1'b0; p2_is_hbind_n = 1'b0;
                    uop_p2_n.subgroup_idx = uop_p3_q.subgroup_idx + 2'd1;
                    uop_p0_n.valid = 1'b0;
                    st_n = S_UOP_P3_VRF_WAIT;
                end else begin
                    // word complete; go to dedicated write state
                    st_n = S_UOP_CLIP_WRITE;
                end
            end
            default: st_n = S_UOP_P4_RESP;
            endcase
        end

        // ── HCNTCLIP writeback (dedicated state, avoids pipeline timing issues) ─
        S_UOP_P3_VRF_WAIT: begin
            st_n=S_UOP_P3_VRF_WAIT2;
        end

        S_UOP_P3_VRF_WAIT2: begin
            p2_lane_compute_n = uop_p2_q.valid;
            st_n=S_UOP_P2_LANE;
        end

        S_UOP_P3_POP_CAPTURE: begin
            group_dist_n = group_dist_sum;
            st_n=S_UOP_P3_ACCUM;
        end

        S_UOP_P3_ACCUM: begin
            hsim_total_n = hsim_total_step;
            if (uop_p3_q.chunk_idx == 2'd3) begin
                if (uop_p3_q.op_type == UOP_HMATCH_CHUNK) begin
                    hmatch_update_n = (hsim_total_step > hmatch_best_dist_q);
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
            vrf_req.wa=hcntclip_dst_base_q+hcntclip_chunk_q;
            vrf_req.wd = hdc_src0_q;
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
                st_n = S_UOP_P1_RD0;
            end
        end

        S_UOP_P4_RESP: begin
            res_n = '0;
            if (uop_p3_q.op_type == UOP_HSIM_CHUNK) begin
                res_n = {53'b0, hsim_total_q};
                st_n = S_RESULT;
            end else if (uop_p3_q.op_type == UOP_HMATCH_CHUNK) begin
                hmatch_update_n = 1'b0;
                if (hmatch_update_q) begin
                    hmatch_best_dist_n = hsim_total_q;
                    hmatch_best_idx_n  = uop_p3_q.class_idx;
                end
                if (hmatch_update_q)
                    res_n = {50'b0, uop_p3_q.class_idx, hsim_total_q};
                else
                    res_n = {50'b0, hmatch_best_idx_q, hmatch_best_dist_q};
                st_n = S_RESULT;
            end else if (ecc_mac_q) begin
                ecc_mac_n = 1'b0;
                res_n = {56'b0, ecc_acc_dst_q, STATUS_OK};
                st_n = S_RESULT;
            end else if (ecc_job_active_q && (ecc_job_phase_q == ECC_PHASE_PMUL_ADD)) begin
                ecc_job_phase_n=ECC_PHASE_NONE;
                st_n=S_ECC_PMUL_STEP_NEXT;
            end else st_n = S_RESULT;
        end

        S_RESULT: begin
            st_n=(ecc_job_bg_q && ecc_job_active_q) ? S_ECC_BG_DISPATCH : S_IDLE;
        end

        S_ECC_BG_DISPATCH: begin
            st_n=(ecc_job_kind_q == ECC_JOB_INV) ? S_ECC_INV_INIT : S_ECC_PMUL_STEP;
        end
        default: st_n=S_IDLE;
        endcase

        // ECC diagonal products use the shared payload register as the matrix
        // cut; group7 captures the old payload while preissuing the next group0.

        unique case (st_q)
        S_EXEC: begin
            if (op_q == HDEC_VWR64)
                vrf_we_direct = (4'b0001 << vaddr_bank_q);
        end
        S_ECC_SQR_WRITE, S_HSPREAD_LO_WRITE, S_HSPREAD_HI_WRITE,
        S_ECC_INV_COPY_WRITE, S_ECC_PMUL_CONST_WRITE,
        S_CLR, S_UOP_CLIP_WRITE: begin
            vrf_we_direct = '1;
        end
        S_ECC_REDUCE_WRITE: begin
            if (ECC_DEBUG_FIELD_OPS)
                vrf_we_direct = '1;
        end
        S_ECC_WRITE_PAIR: begin
            if (ecc_autoreduce_q || (ECC_DEBUG_FIELD_OPS && ecc_fold_word_q[0]))
                vrf_we_direct = '1;
        end
        S_UOP_P3_GLOBAL: begin
            if ((uop_p3_q.op_type == UOP_HBIND_CHUNK)
             || (uop_p3_q.op_type == UOP_HCNTADD_SUBGROUP)
             || (uop_p3_q.op_type == UOP_HPERM_CHUNK))
                vrf_we_direct = '1;
        end
        default: begin
        end
        endcase

        // V27: one normalized VRF request bundle. This keeps today's behavior
        // equivalent while giving the interleaving scheduler a single broker
        // point for future HDC foreground / ECC background arbitration.
        vrf_ra = vrf_req.ra;
        vrf_we = vrf_we_direct;
        vrf_wa = vrf_req.wa;
        vrf_wd = vrf_req.wd;
    end

    // ── Sequential ──────────────────────────────────────────────────────────
    always_ff @(posedge clk_i) begin
        if (ecc_product_we) begin
            ecc_product_pair[ecc_fold_word_q] <= ecc_product_pair_wdata;
        end
        ecc_product_pair_hold_q <= ecc_product_pair_rdata;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni)begin
            st_q<=S_IDLE;res_q<='0;op_q<=HDEC_VWR64;a_q<='0;
            vaddr_bank_q<='0;vaddr_idx_q<='0;clr_cnt_q<='0;clr_base_q<='0;
            hsim_src0_base_q<='0;hsim_src1_base_q<='0;hsim_total_q<='0;group_dist_q<='0;
            hmatch_last_idx_q<='0;hmatch_best_idx_q<='0;hmatch_class_slot_q<='0;hmatch_best_dist_q<='0;hmatch_update_q<=1'b0;
            hperm_dst_base_q<='0;hperm_bit_low_q<='0;hperm_spread_q<=1'b0;hperm_lane_base_q<='0;
            hperm_lane_slot_q<='0;hperm_lane_phase_q<=1'b0;hperm_stage_q<='0;
            hcntclip_dst_base_q<='0;hcntclip_acc_sel_q<='0;hcntclip_chunk_q<='0;
            vrf_ra_q<='0;
            uop_p0_q<='0;uop_p2_q<='0;uop_p3_q<='0;
            p2_is_pop_q<=1'b0;p2_is_hbind_q<=1'b0;
            hdc_src0_q<='0;
            p2_lane_compute_q<=1'b0;
            ecc_src_a_q<='0;ecc_src_b_q<='0;ecc_dst_q<='0;ecc_acc_dst_q<='0;
            ecc_leaf_a_q<='0;ecc_leaf_b_q<='0;ecc_leaf_prod_q<='0;ecc_leaf_path_q<='0;ecc_fold_word_q<='0;
            ecc_diag_group_q<='0;
            ecc_leaf_xor_a_q<='0;ecc_leaf_xor_b_q<='0;ecc_leaf128_prod_q<='0;ecc_kpd64_sub_q<='0;
            ecc_autoreduce_q<=1'b0;ecc_raw_product_q<=1'b0;ecc_mac_q<=1'b0;ecc_sqr_repeat_q<='0;
            ecc_job_kind_q<=ECC_JOB_NONE;ecc_job_phase_q<=ECC_PHASE_NONE;ecc_job_active_q<=1'b0;ecc_job_done_q<=1'b0;ecc_job_bg_q<=1'b0;ecc_job_cycle_q<='0;ecc_inv_step_q<='0;ecc_job_src_q<='0;ecc_job_dst_q<='0;
            ecc_pmul_subop_q<=ECC_PMUL_SUB_NONE;ecc_pmul_step_q<='0;ecc_pmul_bit_q<='0;ecc_pmul_scalar_bit_q<=1'b0;
            ecc_pmul_r0_inf_q<=1'b1;ecc_pmul_result_q<='0;ecc_pmul_point_q<='0;
        end
        else begin
            st_q<=st_n;res_q<=res_n;op_q<=op_n;a_q<=a_n;
            vaddr_bank_q<=vaddr_bank_n;vaddr_idx_q<=vaddr_idx_n;clr_cnt_q<=clr_cnt_n;clr_base_q<=clr_base_n;
            hsim_src0_base_q<=hsim_src0_base_n;hsim_src1_base_q<=hsim_src1_base_n;hsim_total_q<=hsim_total_n;group_dist_q<=group_dist_n;
            hmatch_last_idx_q<=hmatch_last_idx_n;hmatch_best_idx_q<=hmatch_best_idx_n;hmatch_class_slot_q<=hmatch_class_slot_n;hmatch_best_dist_q<=hmatch_best_dist_n;hmatch_update_q<=hmatch_update_n;
            hperm_dst_base_q<=hperm_dst_base_n;hperm_bit_low_q<=hperm_bit_low_n;hperm_spread_q<=hperm_spread_n;hperm_lane_base_q<=hperm_lane_base_n;
            hperm_lane_slot_q<=hperm_lane_slot_n;hperm_lane_phase_q<=hperm_lane_phase_n;
            if (hperm_stage_we) hperm_stage_q<=hperm_stage_n;
            hcntclip_dst_base_q<=hcntclip_dst_base_n;hcntclip_acc_sel_q<=hcntclip_acc_sel_n;hcntclip_chunk_q<=hcntclip_chunk_n;
            vrf_ra_q<=vrf_ra;
            uop_p0_q<=uop_p0_n;uop_p2_q<=uop_p2_n;uop_p3_q<=uop_p3_n;
            p2_is_pop_q<=p2_is_pop_n;p2_is_hbind_q<=p2_is_hbind_n;
            if (hdc_src0_acc_we) begin
                hdc_src0_q[0]<=xor0_field_packet[63:0];
                hdc_src0_q[1]<=xor0_field_packet[127:64];
                hdc_src0_q[2]<=xor0_field_packet[191:128];
                hdc_src0_q[3]<={23'b0, xor0_field_packet[232:192]};
            end else if (hdc_src0_we) begin
                hdc_src0_q<=hdc_src0_n;
            end
            p2_lane_compute_q<=p2_lane_compute_n;
            ecc_src_a_q<=ecc_src_a_n;ecc_src_b_q<=ecc_src_b_n;ecc_dst_q<=ecc_dst_n;ecc_acc_dst_q<=ecc_acc_dst_n;
            ecc_leaf_a_q<=ecc_leaf_a_n;ecc_leaf_b_q<=ecc_leaf_b_n;ecc_leaf_prod_q<=ecc_leaf_prod_n;ecc_leaf_path_q<=ecc_leaf_path_n;ecc_fold_word_q<=ecc_fold_word_n;
            ecc_diag_group_q<=ecc_diag_group_n;
            ecc_leaf_xor_a_q<=ecc_leaf_xor_a_n;ecc_leaf_xor_b_q<=ecc_leaf_xor_b_n;ecc_leaf128_prod_q<=ecc_leaf128_prod_n;ecc_kpd64_sub_q<=ecc_kpd64_sub_n;
            ecc_autoreduce_q<=ecc_autoreduce_n;ecc_raw_product_q<=ecc_raw_product_n;
            ecc_mac_q<=ecc_mac_n;ecc_sqr_repeat_q<=ecc_sqr_repeat_n;
            ecc_job_kind_q<=ecc_job_kind_n;ecc_job_phase_q<=ecc_job_phase_n;ecc_job_active_q<=ecc_job_active_n;ecc_job_done_q<=ecc_job_done_n;ecc_job_bg_q<=ecc_job_bg_n;ecc_job_cycle_q<=ecc_job_cycle_n;ecc_inv_step_q<=ecc_inv_step_n;ecc_job_src_q<=ecc_job_src_n;ecc_job_dst_q<=ecc_job_dst_n;
            ecc_pmul_subop_q<=ecc_pmul_subop_n;ecc_pmul_step_q<=ecc_pmul_step_n;ecc_pmul_bit_q<=ecc_pmul_bit_n;ecc_pmul_scalar_bit_q<=ecc_pmul_scalar_bit_n;
            ecc_pmul_r0_inf_q<=ecc_pmul_r0_inf_n;ecc_pmul_result_q<=ecc_pmul_result_n;ecc_pmul_point_q<=ecc_pmul_point_n;
        end
    end
endmodule
