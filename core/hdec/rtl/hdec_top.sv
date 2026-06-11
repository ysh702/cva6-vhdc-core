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
    hdec_vrf_64x256 i_vrf(.clk_i,.bank_ra_addr_i(vrf_ra_q),.bank_ra_data_o(vrf_rd),.bank_we_i(vrf_we_q),.bank_wa_addr_i(vrf_wa_q),.bank_wdata_i(vrf_wd_q),.vrf_ready_o());
    logic [VRF_BNK_W-1:0] vaddr_bank_q,vaddr_bank_n; logic [VRF_IDX_W-1:0] vaddr_idx_q,vaddr_idx_n;

    // ── State Machine ───────────────────────────────────────────────────────
    typedef enum logic [6:0] {
        S_IDLE, S_EXEC, S_VWR_WAIT, S_RD_WAIT, S_RD_CAPTURE, S_RESULT, S_CLR, S_CLR_DRAIN,
        S_HSIM_INIT, S_HMATCH_INIT,
        S_UOP_P1_RD0, S_UOP_P1_RD0_WAIT, S_UOP_P1_RD1, S_UOP_P1_RD1_WAIT,
        S_UOP_P2_LANE, S_UOP_P3_GLOBAL, S_UOP_P3_POP_CAPTURE, S_UOP_P3_VRF_WAIT, S_UOP_P3_ACCUM, S_UOP_P4_RESP,
        S_UOP_CLIP_WRITE,
        S_ECC_LOAD_A_WAIT, S_ECC_LOAD_A, S_ECC_LOAD_B_WAIT, S_ECC_LOAD_B,
        S_ECC_DIAG_ISSUE, S_ECC_DIAG_WAIT, S_ECC_DIAG_ACCUM,
        S_ECC_LEAF_FOLD,
        S_ECC_WRITE_PAIR, S_ECC_WRITE_DRAIN,
        S_ECC_REDUCE_LOAD_LO_WAIT, S_ECC_REDUCE_LOAD_LO, S_ECC_REDUCE_LOAD_HI_WAIT, S_ECC_REDUCE_WRITE,
        S_ECC_INV_INIT, S_ECC_INV_COPY_WAIT, S_ECC_INV_COPY_WRITE, S_ECC_INV_STEP, S_ECC_INV_ISSUE_SQR,
        S_ECC_INV_AFTER_SQR, S_ECC_INV_AFTER_MUL,
        S_ECC_PMUL_INIT, S_ECC_PMUL_CONST_WRITE, S_ECC_PMUL_READ_SCALAR_WAIT, S_ECC_PMUL_READ_SCALAR,
        S_ECC_PMUL_START_ADD, S_ECC_PMUL_START_DBL, S_ECC_PMUL_STEP, S_ECC_PMUL_STEP_NEXT,
        S_ECC_JOB_DONE,
        S_HSPREAD_LO_WRITE, S_HSPREAD_HI_WRITE
    } st_t;
    st_t st_q, st_n;

    logic [63:0] res_q,res_n; hdec_op_t op_q,op_n; logic [63:0] a_q,a_n; logic [VRF_BNK_W-1:0] bk_q,bk_n;
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
    logic [VRF_IDX_W-1:0] hperm_dst_base_q,hperm_dst_base_n, hperm_src_base_q,hperm_src_base_n;
    logic [3:0] hperm_word_off_q,hperm_word_off_n, hperm_nibble_q,hperm_nibble_n;
    logic [1:0] hperm_bit_low_q,hperm_bit_low_n;
    logic hperm_spread_q,hperm_spread_n;
    logic [1:0] hperm_lane_base_q,hperm_lane_base_n;

    // ── HCNTADD registers ───────────────────────────────────────────────────
    logic [2:0] hcntadd_hv_slot_q,hcntadd_hv_slot_n;
    logic [1:0] hcntadd_subgroup_q,hcntadd_subgroup_n;
    logic hcntadd_acc_sel_q,hcntadd_acc_sel_n;
    logic [VRF_IDX_W-1:0] hcntadd_acc_base;

    // ── HCNTCLIP registers ──────────────────────────────────────────────────
    logic [VRF_IDX_W-1:0] hcntclip_dst_base_q,hcntclip_dst_base_n,hcntclip_acc_base;
    logic hcntclip_acc_sel_q,hcntclip_acc_sel_n;
    logic [3:0] hcntclip_threshold_q,hcntclip_threshold_n;
    logic [1:0] hcntclip_chunk_q,hcntclip_chunk_n,hcntclip_subgroup_q,hcntclip_subgroup_n;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] hcntclip_word_with_result;
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
    logic                                p2_lane_compute_q, p2_lane_compute_n;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] hdc_src0_q, hdc_src0_n;
    logic [LANE_NUM-1:0]                 lane_xor_only_valid;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] lane_bool_result;
    logic [LANE_NUM-1:0]                 lane_cnt_valid;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] lane_cnt_new_counter;
    logic [LANE_NUM-1:0]                 lane_shift_valid;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] lane_shift_a,lane_shift_b,lane_shift_result;
    logic [5:0]                          lane_shift_bit;
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
    hdec_op_t    p4_arch_op_q, p4_arch_op_n;
    logic [10:0] group_dist_q, group_dist_n, group_dist_sum;
    logic signed [11:0] hmatch_budget_step;
    logic        hmatch_budget_step_nonnegative;

    // ── ECC V1 diagonal multiply shadow state ───────────────────────────────
    logic [VRF_IDX_W-1:0] ecc_src_a_q, ecc_src_a_n;
    logic [VRF_IDX_W-1:0] ecc_src_b_q, ecc_src_b_n;
    logic [VRF_IDX_W-1:0] ecc_dst_q,   ecc_dst_n;
    logic [VRF_IDX_W-1:0] ecc_acc_dst_q, ecc_acc_dst_n;
    logic [31:0]          ecc_leaf_a_q,  ecc_leaf_a_n;
    logic [31:0]          ecc_leaf_b_q,  ecc_leaf_b_n;
    logic [63:0]          ecc_leaf_prod_q, ecc_leaf_prod_n;
    logic [2:0]           ecc_diag_slot_q, ecc_diag_slot_n;
    logic [1:0]           ecc_fold_word_q, ecc_fold_word_n;
    logic                 ecc_pipe0_valid_q, ecc_pipe0_valid_n;
    logic                 ecc_pipe1_valid_q, ecc_pipe1_valid_n;
    logic [2:0]           ecc_pipe0_diag_slot_q, ecc_pipe0_diag_slot_n;
    logic [2:0]           ecc_pipe1_diag_slot_q, ecc_pipe1_diag_slot_n;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] ecc_partial_vec;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] pop_src_a;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] pop_src_b;
    logic [7:0]           ecc_diag8_parity;
    logic [5:0]           ecc_leaf_path_q, ecc_leaf_path_n;
    logic [5:0]           ecc_next_leaf_path;
    logic [14:0]          ecc_leaf_offset_mask;
    (* ram_style = "distributed" *) logic [127:0] ecc_product_pair [0:3];
    logic                 ecc_product_we;
    logic [127:0]         ecc_product_pair_rdata;
    logic [127:0]         ecc_product_pair_wdata;
    logic [63:0]          ecc_product_even_contrib;
    logic [63:0]          ecc_product_odd_contrib;
    logic [VRF_IDX_W-1:0] ecc_product_wb_addr;
    logic [255:0]         ecc_reduce_result;
    logic                 ecc_autoreduce_q, ecc_autoreduce_n;
    logic                 ecc_mac_q, ecc_mac_n;
    logic [6:0]           ecc_sqr_repeat_q, ecc_sqr_repeat_n;
    logic                 ecc_leaf_first;
    logic                 ecc_leaf_last;
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
        ECC_PMUL_CTRL_INIT   = 3'd0,
        ECC_PMUL_CTRL_ADD    = 3'd1,
        ECC_PMUL_CTRL_DBL    = 3'd2,
        ECC_PMUL_CTRL_FINAL  = 3'd3
    } ecc_pmul_ctrl_e;
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
    logic [15:0]        ecc_job_cycle_q, ecc_job_cycle_n;
    logic [3:0]         ecc_inv_step_q, ecc_inv_step_n;
    logic [VRF_IDX_W-1:0] ecc_job_src_q, ecc_job_src_n;
    logic [VRF_IDX_W-1:0] ecc_job_dst_q, ecc_job_dst_n;
    logic [VRF_IDX_W-1:0] ecc_job_copy_dst_q, ecc_job_copy_dst_n;
    ecc_pmul_ctrl_e     ecc_pmul_ctrl_q, ecc_pmul_ctrl_n;
    ecc_pmul_subop_e    ecc_pmul_subop_q, ecc_pmul_subop_n;
    logic [5:0]         ecc_pmul_step_q, ecc_pmul_step_n;
    logic [7:0]         ecc_pmul_bit_q, ecc_pmul_bit_n;
    logic               ecc_pmul_scalar_bit_q, ecc_pmul_scalar_bit_n;
    logic               ecc_pmul_r0_inf_q, ecc_pmul_r0_inf_n;
    logic               ecc_pmul_out_sel_q, ecc_pmul_out_sel_n;
    logic               ecc_pmul_const_one_q, ecc_pmul_const_one_n;
    logic [VRF_IDX_W-1:0] ecc_pmul_result_q, ecc_pmul_result_n;
    logic [VRF_IDX_W-1:0] ecc_pmul_point_q, ecc_pmul_point_n;
    logic [VRF_IDX_W-1:0] ecc_pmul_x1_q, ecc_pmul_x1_n;
    logic [VRF_IDX_W-1:0] ecc_pmul_z1_q, ecc_pmul_z1_n;
    logic [VRF_IDX_W-1:0] ecc_pmul_x2_q, ecc_pmul_x2_n;
    logic [VRF_IDX_W-1:0] ecc_pmul_z2_q, ecc_pmul_z2_n;
    logic [VRF_IDX_W-1:0] ecc_pmul_out_x_q, ecc_pmul_out_x_n;
    logic [VRF_IDX_W-1:0] ecc_pmul_out_z_q, ecc_pmul_out_z_n;
    logic                pop_d_mux;
    logic                xor_d_mux;
    logic                ecc_issue_pop;

    // ── Combinational helpers ───────────────────────────────────────────────
    assign hcntadd_acc_base = hcntadd_acc_sel_q ? 6'd48 : 6'd32;
    assign hcntclip_acc_base = hcntclip_acc_sel_q ? 6'd48 : 6'd32;
    assign hmatch_budget_step = hmatch_budget_q - $signed({1'b0, group_dist_q});
    assign hmatch_budget_step_nonnegative = !hmatch_budget_step[11];
    assign hdc_pop_issue = p2_lane_compute_q && uop_p2_q.valid
                         && ((uop_p2_q.op_type == UOP_HSIM_CHUNK)
                          || (uop_p2_q.op_type == UOP_HMATCH_CHUNK));
    assign hdc_xor_issue = p2_lane_compute_q && uop_p2_q.valid
                         && ((uop_p2_q.op_type == UOP_HBIND_CHUNK)
                          || (uop_p2_q.op_type == UOP_HSIM_CHUNK)
                          || (uop_p2_q.op_type == UOP_HMATCH_CHUNK));
    assign ecc_issue_pop = (st_q == S_ECC_DIAG_ISSUE);
    assign pop_d_mux     = hdc_pop_issue || ecc_issue_pop;
    assign xor_d_mux     = hdc_xor_issue || ecc_issue_pop;
    assign ecc_next_leaf_path = ecc_kpd32_path_inc(ecc_leaf_path_q);
    assign ecc_leaf_first = (ecc_leaf_path_q == 6'b00_00_00);
    assign ecc_leaf_last  = (ecc_leaf_path_q == 6'b10_10_10);
    assign ecc_leaf_offset_mask = ecc_kpd32_leaf_offset_mask(ecc_leaf_path_q);
    assign ecc_product_pair_rdata = ecc_product_pair[ecc_fold_word_q];
    assign ecc_product_even_contrib = ecc_kpd32_fold_word_contrib(ecc_leaf_offset_mask, {ecc_fold_word_q, 1'b0}, ecc_leaf_prod_q);
    assign ecc_product_odd_contrib  = ecc_kpd32_fold_word_contrib(ecc_leaf_offset_mask, {ecc_fold_word_q, 1'b1}, ecc_leaf_prod_q);
    assign ecc_product_pair_wdata = (ecc_leaf_first ? '0 : ecc_product_pair_rdata)
                                  ^ {ecc_product_odd_contrib, ecc_product_even_contrib};
    assign ecc_product_wb_addr = ecc_dst_q + {5'b0, ecc_fold_word_q[1]};
    assign ecc_reduce_result = ecc_reduce233({vrf_rd[3], vrf_rd[2], vrf_rd[1], vrf_rd[0],
                                              hdc_src0_q[3], hdc_src0_q[2], hdc_src0_q[1], hdc_src0_q[0]});
    assign ecc_diag8_parity = {lane_popcnt_part_q[3][1][0], lane_popcnt_part_q[3][0][0],
                              lane_popcnt_part_q[2][1][0], lane_popcnt_part_q[2][0][0],
                              lane_popcnt_part_q[1][1][0], lane_popcnt_part_q[1][0][0],
                              lane_popcnt_part_q[0][1][0], lane_popcnt_part_q[0][0][0]};
    assign ecc_partial_vec[0] = {ecc_diag32_partial(ecc_leaf_a_q, ecc_leaf_b_q, {1'b0, ecc_diag_slot_q, 3'b000} + 7'd1),
                                 ecc_diag32_partial(ecc_leaf_a_q, ecc_leaf_b_q, {1'b0, ecc_diag_slot_q, 3'b000} + 7'd0)};
    assign ecc_partial_vec[1] = {ecc_diag32_partial(ecc_leaf_a_q, ecc_leaf_b_q, {1'b0, ecc_diag_slot_q, 3'b000} + 7'd3),
                                 ecc_diag32_partial(ecc_leaf_a_q, ecc_leaf_b_q, {1'b0, ecc_diag_slot_q, 3'b000} + 7'd2)};
    assign ecc_partial_vec[2] = {ecc_diag32_partial(ecc_leaf_a_q, ecc_leaf_b_q, {1'b0, ecc_diag_slot_q, 3'b000} + 7'd5),
                                 ecc_diag32_partial(ecc_leaf_a_q, ecc_leaf_b_q, {1'b0, ecc_diag_slot_q, 3'b000} + 7'd4)};
    assign ecc_partial_vec[3] = {ecc_diag32_partial(ecc_leaf_a_q, ecc_leaf_b_q, {1'b0, ecc_diag_slot_q, 3'b000} + 7'd7),
                                 ecc_diag32_partial(ecc_leaf_a_q, ecc_leaf_b_q, {1'b0, ecc_diag_slot_q, 3'b000} + 7'd6)};

    function automatic hdec_op_t p4_arch_from_uop(input hdec_uop_type_e op_type);
        unique case (op_type)
            UOP_HSIM_CHUNK:       p4_arch_from_uop = HDEC_HSIM;
            UOP_HMATCH_CHUNK:     p4_arch_from_uop = HDEC_HMATCH;
            UOP_HCNTCLIP_READ:    p4_arch_from_uop = HDEC_HCNTCLIP;
            default:              p4_arch_from_uop = HDEC_VWR64;
        endcase
    endfunction

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
            ECC_PMUL_SUB_ADD:        ecc_pmul_subop_last = (step == 6'd9);
            ECC_PMUL_SUB_DBL:        ecc_pmul_subop_last = (step == 6'd5);
            ECC_PMUL_SUB_AFFINE:     ecc_pmul_subop_last = (step == 6'd23);
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

    function automatic logic [255:0] ecc_reduce233(
        input logic [511:0] product
    );
        logic [352:0] stage1;
        logic [119:0] stage2_hi;
        begin
            stage1 = '0;
            // GF(2^233), f(x)=x^233+x^74+1:
            // every coefficient at x^(233+j) folds to x^j and x^(74+j).
            stage1[232:0] = product[232:0];
            stage1[278:0] = stage1[278:0] ^ product[511:233];
            stage1[352:74] = stage1[352:74] ^ product[511:233];

            stage2_hi = stage1[352:233];
            ecc_reduce233 = '0;
            ecc_reduce233[232:0] = stage1[232:0];
            ecc_reduce233[119:0] = ecc_reduce233[119:0] ^ stage2_hi;
            ecc_reduce233[193:74] = ecc_reduce233[193:74] ^ stage2_hi;
        end
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

    function automatic logic [5:0] ecc_kpd32_path_inc(input logic [5:0] path);
        logic [1:0] d2, d1, d0;
        begin
            d2 = path[5:4];
            d1 = path[3:2];
            d0 = path[1:0];
            if (d0 != 2'd2) begin
                d0 = d0 + 2'd1;
            end else begin
                d0 = 2'd0;
                if (d1 != 2'd2) begin
                    d1 = d1 + 2'd1;
                end else begin
                    d1 = 2'd0;
                    d2 = d2 + 2'd1;
                end
            end
            ecc_kpd32_path_inc = {d2, d1, d0};
        end
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
        input logic [5:0]   path
    );
        logic [31:0] s0_0, s0_1, s0_2, s0_3;
        logic [31:0] s1_0, s1_1;
        begin
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

    function automatic logic [14:0] ecc_kpd32_leaf_offset_mask(input logic [5:0] path);
        unique case (path)
            6'b00_00_00: ecc_kpd32_leaf_offset_mask = 15'h00ff;
            6'b00_00_01: ecc_kpd32_leaf_offset_mask = 15'h00aa;
            6'b00_00_10: ecc_kpd32_leaf_offset_mask = 15'h01fe;
            6'b00_01_00: ecc_kpd32_leaf_offset_mask = 15'h00cc;
            6'b00_01_01: ecc_kpd32_leaf_offset_mask = 15'h0088;
            6'b00_01_10: ecc_kpd32_leaf_offset_mask = 15'h0198;
            6'b00_10_00: ecc_kpd32_leaf_offset_mask = 15'h03fc;
            6'b00_10_01: ecc_kpd32_leaf_offset_mask = 15'h02a8;
            6'b00_10_10: ecc_kpd32_leaf_offset_mask = 15'h07f8;
            6'b01_00_00: ecc_kpd32_leaf_offset_mask = 15'h00f0;
            6'b01_00_01: ecc_kpd32_leaf_offset_mask = 15'h00a0;
            6'b01_00_10: ecc_kpd32_leaf_offset_mask = 15'h01e0;
            6'b01_01_00: ecc_kpd32_leaf_offset_mask = 15'h00c0;
            6'b01_01_01: ecc_kpd32_leaf_offset_mask = 15'h0080;
            6'b01_01_10: ecc_kpd32_leaf_offset_mask = 15'h0180;
            6'b01_10_00: ecc_kpd32_leaf_offset_mask = 15'h03c0;
            6'b01_10_01: ecc_kpd32_leaf_offset_mask = 15'h0280;
            6'b01_10_10: ecc_kpd32_leaf_offset_mask = 15'h0780;
            6'b10_00_00: ecc_kpd32_leaf_offset_mask = 15'h0ff0;
            6'b10_00_01: ecc_kpd32_leaf_offset_mask = 15'h0aa0;
            6'b10_00_10: ecc_kpd32_leaf_offset_mask = 15'h1fe0;
            6'b10_01_00: ecc_kpd32_leaf_offset_mask = 15'h0cc0;
            6'b10_01_01: ecc_kpd32_leaf_offset_mask = 15'h0880;
            6'b10_01_10: ecc_kpd32_leaf_offset_mask = 15'h1980;
            6'b10_10_00: ecc_kpd32_leaf_offset_mask = 15'h3fc0;
            6'b10_10_01: ecc_kpd32_leaf_offset_mask = 15'h2a80;
            6'b10_10_10: ecc_kpd32_leaf_offset_mask = 15'h7f80;
            default:      ecc_kpd32_leaf_offset_mask = '0;
        endcase
    endfunction

    function automatic logic [63:0] ecc_kpd32_fold_word_contrib(
        input logic [14:0] mask,
        input logic [2:0]  word_idx,
        input logic [63:0] leaf_product
    );
        logic [3:0] slot;
        logic [63:0] contrib;
        begin
            slot = {word_idx, 1'b0};
            contrib = '0;
            if (mask[slot])
                contrib ^= leaf_product;
            if ((slot != 4'd0) && mask[slot - 4'd1])
                contrib ^= {32'b0, leaf_product[63:32]};
            if ((slot != 4'd14) && mask[slot + 4'd1])
                contrib ^= {leaf_product[31:0], 32'b0};
            ecc_kpd32_fold_word_contrib = contrib;
        end
    endfunction

    function automatic logic [511:0] ecc_kpd32_fold_leaf_word_pair(
        input logic [511:0] product,
        input logic [14:0]  mask,
        input logic [1:0]   pair_idx,
        input logic [63:0]  leaf_product
    );
        logic [511:0] updated;
        logic [2:0]   word0, word1;
        logic [63:0]  contrib0, contrib1;
        begin
            updated = product;
            word0 = {pair_idx, 1'b0};
            word1 = {pair_idx, 1'b1};
            contrib0 = ecc_kpd32_fold_word_contrib(mask, word0, leaf_product);
            contrib1 = ecc_kpd32_fold_word_contrib(mask, word1, leaf_product);
            unique case (pair_idx)
                2'd0: begin
                    updated[63:0]    = product[63:0]    ^ contrib0;
                    updated[127:64]  = product[127:64]  ^ contrib1;
                end
                2'd1: begin
                    updated[191:128] = product[191:128] ^ contrib0;
                    updated[255:192] = product[255:192] ^ contrib1;
                end
                2'd2: begin
                    updated[319:256] = product[319:256] ^ contrib0;
                    updated[383:320] = product[383:320] ^ contrib1;
                end
                2'd3: begin
                    updated[447:384] = product[447:384] ^ contrib0;
                    updated[511:448] = product[511:448] ^ contrib1;
                end
                default: updated = product;
            endcase
            ecc_kpd32_fold_leaf_word_pair = updated;
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
            .cnt_hv_word_i(hdc_src0_q[lid]),
            .cnt_old_counter_i(vrf_rd[lid]),
            .cnt_subgroup_i(hcntadd_subgroup_q),
            .cnt_new_counter_o(lane_cnt_new_counter[lid]),
            .shift_valid_i(lane_shift_valid[lid]),
            .shift_src_a_i(lane_shift_a[lid]),
            .shift_src_b_i(lane_shift_b[lid]),
            .shift_bit_i(lane_shift_bit),
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
        st_n=st_q; ready_o=(st_q==S_IDLE); valid_o=(st_q==S_RESULT); result_o=res_q;
        res_n='0; op_n=op_q; a_n=a_q; bk_n=bk_q; vaddr_bank_n=vaddr_bank_q; vaddr_idx_n=vaddr_idx_q;
        clr_cnt_n=clr_cnt_q; clr_base_n=clr_base_q;
        chunk_cnt_n=chunk_cnt_q;
        hb_dst_base_n=hb_dst_base_q; hb_src0_base_n=hb_src0_base_q; hb_src1_base_n=hb_src1_base_q;
        hsim_src0_base_n=hsim_src0_base_q; hsim_src1_base_n=hsim_src1_base_q; hsim_total_n=hsim_total_q;
        group_dist_n=group_dist_q;
        hmatch_last_idx_n=hmatch_last_idx_q; hmatch_best_idx_n=hmatch_best_idx_q; hmatch_class_slot_n=hmatch_class_slot_q; hmatch_best_dist_n=hmatch_best_dist_q;
        hmatch_budget_n=hmatch_budget_q; hmatch_update_n=hmatch_update_q;
        hperm_dst_base_n=hperm_dst_base_q; hperm_src_base_n=hperm_src_base_q;
        hperm_word_off_n=hperm_word_off_q; hperm_nibble_n=hperm_nibble_q; hperm_bit_low_n=hperm_bit_low_q; hperm_spread_n=hperm_spread_q; hperm_lane_base_n=hperm_lane_base_q;
        hcntadd_hv_slot_n=hcntadd_hv_slot_q; hcntadd_subgroup_n=hcntadd_subgroup_q; hcntadd_acc_sel_n=hcntadd_acc_sel_q;
        hcntclip_dst_base_n=hcntclip_dst_base_q; hcntclip_acc_sel_n=hcntclip_acc_sel_q; hcntclip_threshold_n=hcntclip_threshold_q; hcntclip_chunk_n=hcntclip_chunk_q; hcntclip_subgroup_n=hcntclip_subgroup_q; hcntclip_word_with_result=hdc_src0_q;
        uop_p0_n=uop_p0_q; uop_p1_n=uop_p1_q; uop_p2_n=uop_p2_q; uop_p3_n=uop_p3_q;
        hdc_src0_n=hdc_src0_q;
        lane_result_n=lane_result_q; lane_clip_n=lane_clip_q;
        p2_lane_compute_n=1'b0;
        p4_arch_op_n=p4_arch_op_q;
        ecc_src_a_n=ecc_src_a_q; ecc_src_b_n=ecc_src_b_q; ecc_dst_n=ecc_dst_q; ecc_acc_dst_n=ecc_acc_dst_q;
        ecc_leaf_a_n=ecc_leaf_a_q; ecc_leaf_b_n=ecc_leaf_b_q; ecc_leaf_prod_n=ecc_leaf_prod_q;
        ecc_diag_slot_n=ecc_diag_slot_q;
        ecc_leaf_path_n=ecc_leaf_path_q;
        ecc_fold_word_n=ecc_fold_word_q;
        ecc_product_we=1'b0;
        ecc_autoreduce_n=ecc_autoreduce_q; ecc_mac_n=ecc_mac_q; ecc_sqr_repeat_n=ecc_sqr_repeat_q;
        ecc_job_kind_n=ecc_job_kind_q; ecc_job_phase_n=ecc_job_phase_q;
        ecc_job_active_n=ecc_job_active_q; ecc_job_done_n=ecc_job_done_q;
        ecc_job_cycle_n=ecc_job_cycle_q + (ecc_job_active_q ? 16'd1 : 16'd0);
        ecc_inv_step_n=ecc_inv_step_q; ecc_job_src_n=ecc_job_src_q; ecc_job_dst_n=ecc_job_dst_q;
        ecc_job_copy_dst_n=ecc_job_copy_dst_q;
        ecc_pmul_ctrl_n=ecc_pmul_ctrl_q; ecc_pmul_subop_n=ecc_pmul_subop_q;
        ecc_pmul_step_n=ecc_pmul_step_q; ecc_pmul_bit_n=ecc_pmul_bit_q;
        ecc_pmul_scalar_bit_n=ecc_pmul_scalar_bit_q;
        ecc_pmul_r0_inf_n=ecc_pmul_r0_inf_q;
        ecc_pmul_out_sel_n=ecc_pmul_out_sel_q;
        ecc_pmul_const_one_n=ecc_pmul_const_one_q; ecc_pmul_result_n=ecc_pmul_result_q; ecc_pmul_point_n=ecc_pmul_point_q;
        ecc_pmul_x1_n=ecc_pmul_x1_q; ecc_pmul_z1_n=ecc_pmul_z1_q;
        ecc_pmul_x2_n=ecc_pmul_x2_q; ecc_pmul_z2_n=ecc_pmul_z2_q;
        ecc_pmul_out_x_n=ecc_pmul_out_x_q; ecc_pmul_out_z_n=ecc_pmul_out_z_q;
        ecc_pipe0_valid_n=1'b0; ecc_pipe0_diag_slot_n=ecc_pipe0_diag_slot_q;
        ecc_pipe1_valid_n=ecc_pipe0_valid_q; ecc_pipe1_diag_slot_n=ecc_pipe0_diag_slot_q;
        lane_cnt_valid='0;
        lane_shift_valid='0;
        lane_shift_a='0; lane_shift_b='0; lane_shift_bit={hperm_nibble_q, hperm_bit_low_q};
        lane_clip_valid='0;
        vrf_ra='0; vrf_we='0; vrf_wa='0; vrf_wd='0;

        if (p2_lane_compute_q && uop_p2_q.valid) begin
            if (uop_p2_q.use_counter)
                lane_cnt_valid = '1;
            if (uop_p2_q.use_shift) begin
                lane_shift_valid = '1;
                lane_shift_bit = {uop_p2_q.perm_nibble, hperm_bit_low_q};
                lane_shift_a[0]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd0,hdc_src0_q,vrf_rd);
                lane_shift_a[1]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd1,hdc_src0_q,vrf_rd);
                lane_shift_a[2]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd2,hdc_src0_q,vrf_rd);
                lane_shift_a[3]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd3,hdc_src0_q,vrf_rd);
                lane_shift_b[0]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd1,hdc_src0_q,vrf_rd);
                lane_shift_b[1]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd2,hdc_src0_q,vrf_rd);
                lane_shift_b[2]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd3,hdc_src0_q,vrf_rd);
                lane_shift_b[3]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd4,hdc_src0_q,vrf_rd);
            end
            if (uop_p2_q.use_clip)
                lane_clip_valid = '1;

            if (uop_p2_q.use_counter)
                lane_result_n = lane_cnt_new_counter;
            else if (uop_p2_q.use_shift)
                lane_result_n = lane_shift_result;
            else if (uop_p2_q.use_clip) begin
                lane_clip_n[0] = lane_clip_bits[0];
                lane_clip_n[1] = lane_clip_bits[1];
                lane_clip_n[2] = lane_clip_bits[2];
                lane_clip_n[3] = lane_clip_bits[3];
            end
        end

        case(st_q)
        S_IDLE: if(valid_i&&ready_o)begin op_n=operator_i;a_n=operand_a_i;st_n=S_EXEC;end

        S_EXEC: begin uop_p0_n='0; unique case(op_q)
            HDEC_VADDR: begin vaddr_bank_n=a_q[7:6];vaddr_idx_n=a_q[5:0];res_n='0;st_n=S_RESULT;end
            HDEC_VWR64: begin vrf_we[vaddr_bank_q]=1'b1;vrf_wa[vaddr_bank_q]=vaddr_idx_q;vrf_wd[vaddr_bank_q]=a_q;res_n='0;st_n=S_VWR_WAIT;end
            HDEC_VRD64: begin vrf_ra[vaddr_bank_q]=vaddr_idx_q;bk_n=vaddr_bank_q;st_n=S_RD_WAIT;end

            HDEC_ECC_MUL: begin
                ecc_leaf_a_n  = '0;
                ecc_leaf_b_n  = '0;
                ecc_leaf_prod_n = '0;
                ecc_leaf_path_n = '0;
                ecc_diag_slot_n = '0;
                ecc_fold_word_n = '0;
                ecc_pipe0_valid_n = 1'b0;
                ecc_pipe1_valid_n = 1'b0;
                if ((a_q[17:12] == 6'd63)
                 || (a_q[32] && ((a_q[23:18] == a_q[17:12])
                               || (a_q[23:18] == (a_q[17:12] + 6'd1))))) begin
                    ecc_autoreduce_n=1'b0; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    res_n={62'b0,STATUS_ERROR};st_n=S_RESULT;
                end else begin
                    ecc_dst_n   = a_q[17:12];
                    ecc_acc_dst_n = a_q[23:18];
                    ecc_src_a_n = a_q[11:6];
                    ecc_src_b_n = a_q[5:0];
                    ecc_autoreduce_n = a_q[31] | a_q[32];
                    ecc_mac_n = a_q[32];
                    ecc_sqr_repeat_n='0;
                    vrf_ra[0]=a_q[11:6]; vrf_ra[1]=a_q[11:6];
                    vrf_ra[2]=a_q[11:6]; vrf_ra[3]=a_q[11:6];
                    st_n=S_ECC_LOAD_A_WAIT;
                end
            end

            HDEC_ECC_STATUS: begin
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
                        ecc_job_src_n=a_q[5:0];
                        ecc_job_dst_n=a_q[17:12];
                        ecc_inv_step_n='0;
                        ecc_dst_n=a_q[17:12];
                        st_n=S_ECC_INV_INIT;
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
                        ecc_job_src_n=a_q[5:0];
                        ecc_job_dst_n=a_q[17:12];
                        ecc_pmul_result_n=a_q[17:12];
                        ecc_pmul_point_n=a_q[11:6];
                        ecc_pmul_bit_n=8'd232;
                        ecc_pmul_scalar_bit_n=1'b0;
                        ecc_pmul_r0_inf_n=1'b1;
                        ecc_pmul_out_sel_n=1'b0;
                        ecc_pmul_ctrl_n=ECC_PMUL_CTRL_INIT;
                        ecc_pmul_subop_n=ECC_PMUL_SUB_INIT;
                        ecc_pmul_step_n='0;
                        st_n=S_ECC_PMUL_INIT;
                    end
                end else begin
                    res_n={32'b0, ecc_job_cycle_q, 6'b0, ecc_job_dst_q,
                           ecc_job_done_q, ecc_job_active_q, STATUS_OK};
                    if (ecc_job_kind_q == ECC_JOB_PMUL)
                        res_n={32'b0, ecc_job_cycle_q, 6'b0, ecc_pmul_result_q,
                               ecc_job_done_q, ecc_job_active_q, STATUS_OK};
                    st_n=S_RESULT;
                end
            end

            HDEC_ECC_ADD: begin
                uop_p0_n.valid        = 1'b1;
                uop_p0_n.op_type      = UOP_HBIND_CHUNK;
                uop_p0_n.src0_addr    = a_q[11:6];
                uop_p0_n.src1_addr    = a_q[5:0];
                uop_p0_n.dst_addr     = a_q[17:12];
                uop_p0_n.chunk_idx    = 2'd3;
                st_n=S_UOP_P1_RD0;
            end

            HDEC_ECC_ALIGN: begin
                hperm_dst_base_n       = a_q[17:12];
                hperm_src_base_n       = a_q[5:0];
                hperm_word_off_n       = 4'd0;
                hperm_nibble_n         = a_q[23:20];
                hperm_bit_low_n        = a_q[19:18];
                hperm_spread_n         = 1'b0;
                hperm_lane_base_n      = a_q[25:24];
                chunk_cnt_n            = 2'd3;
                uop_p0_n.valid         = 1'b1;
                uop_p0_n.op_type       = UOP_HPERM_CHUNK;
                uop_p0_n.chunk_idx     = 2'd3;
                uop_p0_n.src0_addr     = a_q[5:0];
                uop_p0_n.src1_addr     = a_q[11:6];
                uop_p0_n.dst_addr      = a_q[17:12];
                uop_p0_n.perm_nibble   = a_q[23:20];
                uop_p0_n.use_shift     = 1'b1;
                st_n=S_UOP_P1_RD0;
            end

            HDEC_ECC_REDUCE: begin
                ecc_autoreduce_n=1'b0; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                if (a_q[5:0] == 6'd63) begin
                    res_n={62'b0,STATUS_ERROR};st_n=S_RESULT;
                end else begin
                    ecc_dst_n = a_q[17:12];
                    ecc_src_a_n = a_q[5:0];
                    vrf_ra[0]=a_q[5:0]; vrf_ra[1]=a_q[5:0];
                    vrf_ra[2]=a_q[5:0]; vrf_ra[3]=a_q[5:0];
                    st_n=S_ECC_REDUCE_LOAD_LO_WAIT;
                end
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
                hdc_src0_n='0;
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
                if (a_q[18]) begin
                    if ((a_q[5:0] == 6'd63)
                     || (a_q[20] && ((a_q[17:12] == a_q[5:0])
                                   || (a_q[17:12] == (a_q[5:0] + 6'd1))))) begin
                        ecc_autoreduce_n=1'b0; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                        res_n={62'b0,STATUS_ERROR};st_n=S_RESULT;
                    end else begin
                        hperm_dst_base_n=a_q[5:0];
                        hperm_src_base_n=a_q[11:6];
                        hperm_spread_n=1'b1;
                        ecc_dst_n=a_q[5:0];
                        ecc_acc_dst_n=a_q[17:12];
                        ecc_autoreduce_n=a_q[19] | a_q[20];
                        ecc_mac_n=a_q[20];
                        ecc_sqr_repeat_n=(a_q[19] | a_q[20]) ? {3'b0, a_q[27:24]} : 7'd0;
                        vrf_ra[0]=a_q[11:6]; vrf_ra[1]=a_q[11:6];
                        vrf_ra[2]=a_q[11:6]; vrf_ra[3]=a_q[11:6];
                        st_n=S_RD_WAIT;
                    end
                end else if(a_q[3:0] == a_q[7:4])begin res_n={62'b0,STATUS_ERROR};st_n=S_RESULT;end
                else begin
                    hperm_dst_base_n={a_q[3:0],2'b00};
                    hperm_src_base_n={a_q[7:4],2'b00};
                    hperm_word_off_n=a_q[17:14];
                    hperm_nibble_n=a_q[13:10];
                    hperm_bit_low_n=a_q[9:8];
                    hperm_spread_n=1'b0;
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

        S_RD_WAIT: begin
            if (((op_q == HDEC_HPERM) && hperm_spread_q)
             || (ecc_job_active_q && (ecc_job_phase_q == ECC_PHASE_INV_SQR))
             || (ecc_job_active_q && hperm_spread_q && (ecc_job_phase_q == ECC_PHASE_PMUL_FIELD)))
                st_n=S_HSPREAD_LO_WRITE;
            else
                st_n=S_RD_CAPTURE;
        end

        S_RD_CAPTURE: begin res_n=vrf_rd[bk_q];st_n=S_RESULT;end

        S_HSPREAD_LO_WRITE: begin
            hdc_src0_n = vrf_rd;
            vrf_we = '1;
            vrf_wa[0]=hperm_dst_base_q; vrf_wa[1]=hperm_dst_base_q;
            vrf_wa[2]=hperm_dst_base_q; vrf_wa[3]=hperm_dst_base_q;
            vrf_wd[0]=hspread_half64(vrf_rd[0], 1'b0);
            vrf_wd[1]=hspread_half64(vrf_rd[0], 1'b1);
            vrf_wd[2]=hspread_half64(vrf_rd[1], 1'b0);
            vrf_wd[3]=hspread_half64(vrf_rd[1], 1'b1);
            st_n=S_HSPREAD_HI_WRITE;
        end

        S_HSPREAD_HI_WRITE: begin
            vrf_we = '1;
            vrf_wa[0]=hperm_dst_base_q + 6'd1; vrf_wa[1]=hperm_dst_base_q + 6'd1;
            vrf_wa[2]=hperm_dst_base_q + 6'd1; vrf_wa[3]=hperm_dst_base_q + 6'd1;
            vrf_wd[0]=hspread_half64(hdc_src0_q[2], 1'b0);
            vrf_wd[1]=hspread_half64(hdc_src0_q[2], 1'b1);
            vrf_wd[2]=hspread_half64(hdc_src0_q[3], 1'b0);
            vrf_wd[3]=hspread_half64(hdc_src0_q[3], 1'b1);
            hperm_spread_n=1'b0;
            res_n={62'b0,STATUS_OK};
            if (ecc_autoreduce_q) begin
                ecc_dst_n = hperm_dst_base_q;
                ecc_src_a_n = hperm_dst_base_q;
                st_n=S_ECC_WRITE_DRAIN;
            end else begin
                st_n=S_RESULT;
            end
        end

        // ── ECC V1 raw GF(2) diagonal multiply ─────────────────────────────
        S_ECC_LOAD_A_WAIT: begin
            st_n=S_ECC_LOAD_A;
        end

        S_ECC_LOAD_A: begin
            ecc_leaf_a_n = ecc_kpd32_leaf_word({vrf_rd[3], vrf_rd[2], vrf_rd[1], vrf_rd[0]}, ecc_leaf_path_q);
            vrf_ra[0]=ecc_src_b_q; vrf_ra[1]=ecc_src_b_q;
            vrf_ra[2]=ecc_src_b_q; vrf_ra[3]=ecc_src_b_q;
            st_n=S_ECC_LOAD_B_WAIT;
        end

        S_ECC_LOAD_B_WAIT: begin
            st_n=S_ECC_LOAD_B;
        end

        S_ECC_LOAD_B: begin
            ecc_leaf_b_n = ecc_kpd32_leaf_word({vrf_rd[3], vrf_rd[2], vrf_rd[1], vrf_rd[0]}, ecc_leaf_path_q);
            ecc_leaf_prod_n = '0;
            ecc_leaf_path_n = '0;
            ecc_diag_slot_n = 3'd0;
            ecc_fold_word_n = 2'd0;
            ecc_pipe0_valid_n = 1'b0;
            ecc_pipe1_valid_n = 1'b0;
            st_n=S_ECC_DIAG_ISSUE;
        end

        S_ECC_DIAG_ISSUE: begin
            if (ecc_pipe1_valid_q)
                ecc_leaf_prod_n = ecc_kpd32_leaf_store_pack(ecc_leaf_prod_q, {ecc_pipe1_diag_slot_q, 3'b000}, ecc_diag8_parity);
            ecc_pipe0_valid_n = 1'b1;
            ecc_pipe0_diag_slot_n = ecc_diag_slot_q;
            if (ecc_diag_slot_q == 3'd7) begin
                st_n=S_ECC_DIAG_WAIT;
            end else begin
                ecc_diag_slot_n = ecc_diag_slot_q + 3'd1;
                st_n=S_ECC_DIAG_ISSUE;
            end
        end

        S_ECC_DIAG_WAIT: begin
            if (ecc_pipe1_valid_q)
                ecc_leaf_prod_n = ecc_kpd32_leaf_store_pack(ecc_leaf_prod_q, {ecc_pipe1_diag_slot_q, 3'b000}, ecc_diag8_parity);
            st_n=S_ECC_DIAG_ACCUM;
        end

        S_ECC_DIAG_ACCUM: begin
            if (ecc_pipe1_valid_q)
                ecc_leaf_prod_n = ecc_kpd32_leaf_store_pack(ecc_leaf_prod_q, {ecc_pipe1_diag_slot_q, 3'b000}, ecc_diag8_parity);
            st_n=S_ECC_LEAF_FOLD;
        end

        S_ECC_LEAF_FOLD: begin
            ecc_product_we = 1'b1;
            if (!ecc_leaf_last) begin
                unique case (ecc_fold_word_q)
                    2'd0: begin
                        vrf_ra[0]=ecc_src_a_q; vrf_ra[1]=ecc_src_a_q;
                        vrf_ra[2]=ecc_src_a_q; vrf_ra[3]=ecc_src_a_q;
                    end
                    2'd1: begin
                        vrf_ra[0]=ecc_src_b_q; vrf_ra[1]=ecc_src_b_q;
                        vrf_ra[2]=ecc_src_b_q; vrf_ra[3]=ecc_src_b_q;
                    end
                    2'd2: begin
                        ecc_leaf_a_n = ecc_kpd32_leaf_word({vrf_rd[3], vrf_rd[2], vrf_rd[1], vrf_rd[0]}, ecc_next_leaf_path);
                    end
                    default: begin
                        ecc_leaf_b_n = ecc_kpd32_leaf_word({vrf_rd[3], vrf_rd[2], vrf_rd[1], vrf_rd[0]}, ecc_next_leaf_path);
                    end
                endcase
            end
            if (ecc_fold_word_q == 2'd3) begin
                ecc_fold_word_n = 2'd0;
                if (ecc_leaf_last) begin
                    st_n=S_ECC_WRITE_PAIR;
                end else begin
                    ecc_leaf_path_n = ecc_next_leaf_path;
                    ecc_leaf_prod_n = '0;
                    ecc_diag_slot_n = 3'd0;
                    st_n=S_ECC_DIAG_ISSUE;
                end
            end else begin
                ecc_fold_word_n = ecc_fold_word_q + 2'd1;
                st_n=S_ECC_LEAF_FOLD;
            end
        end

        S_ECC_WRITE_PAIR: begin
            unique case (ecc_fold_word_q[0])
                1'b0: begin
                    vrf_we[0]=1'b1;
                    vrf_wa[0]=ecc_product_wb_addr;
                    vrf_wd[0]=ecc_product_pair_rdata[63:0];
                    vrf_we[1]=1'b1;
                    vrf_wa[1]=ecc_product_wb_addr;
                    vrf_wd[1]=ecc_product_pair_rdata[127:64];
                end
                default: begin
                    vrf_we[2]=1'b1;
                    vrf_wa[2]=ecc_product_wb_addr;
                    vrf_wd[2]=ecc_product_pair_rdata[63:0];
                    vrf_we[3]=1'b1;
                    vrf_wa[3]=ecc_product_wb_addr;
                    vrf_wd[3]=ecc_product_pair_rdata[127:64];
                end
            endcase
            if (ecc_fold_word_q == 2'd3) begin
                res_n={56'b0, ecc_dst_q, STATUS_OK};
                if (ecc_autoreduce_q)
                    ecc_src_a_n = ecc_dst_q;
                st_n=S_ECC_WRITE_DRAIN;
            end else begin
                ecc_fold_word_n = ecc_fold_word_q + 2'd1;
                st_n=S_ECC_WRITE_PAIR;
            end
        end

        // ── S_CLR: shared by HCLR (4 entries) and HCNTCLR (16 entries) ──────
        S_ECC_WRITE_DRAIN: begin
            if (ecc_autoreduce_q) begin
                vrf_ra[0]=ecc_src_a_q; vrf_ra[1]=ecc_src_a_q;
                vrf_ra[2]=ecc_src_a_q; vrf_ra[3]=ecc_src_a_q;
                st_n=S_ECC_REDUCE_LOAD_LO_WAIT;
            end else if (ecc_sqr_repeat_q != 7'd0) begin
                hperm_dst_base_n=ecc_dst_q;
                hperm_src_base_n=ecc_dst_q;
                hperm_spread_n=1'b1;
                ecc_src_a_n=ecc_dst_q;
                ecc_autoreduce_n=1'b1;
                ecc_sqr_repeat_n=ecc_sqr_repeat_q - 7'd1;
                vrf_ra[0]=ecc_dst_q; vrf_ra[1]=ecc_dst_q;
                vrf_ra[2]=ecc_dst_q; vrf_ra[3]=ecc_dst_q;
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
            st_n=S_ECC_REDUCE_LOAD_LO;
        end

        S_ECC_REDUCE_LOAD_LO: begin
            hdc_src0_n = vrf_rd;
            vrf_ra[0]=ecc_src_a_q + 6'd1; vrf_ra[1]=ecc_src_a_q + 6'd1;
            vrf_ra[2]=ecc_src_a_q + 6'd1; vrf_ra[3]=ecc_src_a_q + 6'd1;
            st_n=S_ECC_REDUCE_LOAD_HI_WAIT;
        end

        S_ECC_REDUCE_LOAD_HI_WAIT: begin
            st_n=S_ECC_REDUCE_WRITE;
        end

        S_ECC_REDUCE_WRITE: begin
            vrf_we = '1;
            vrf_wa[0]=ecc_dst_q; vrf_wa[1]=ecc_dst_q;
            vrf_wa[2]=ecc_dst_q; vrf_wa[3]=ecc_dst_q;
            vrf_wd[0]=ecc_reduce_result[63:0];
            vrf_wd[1]=ecc_reduce_result[127:64];
            vrf_wd[2]=ecc_reduce_result[191:128];
            vrf_wd[3]=ecc_reduce_result[255:192];
            ecc_autoreduce_n=1'b0;
            if (ecc_mac_q && (ecc_sqr_repeat_q == 7'd0)) begin
                uop_p0_n='0;
                uop_p0_n.valid     = 1'b1;
                uop_p0_n.op_type   = UOP_HBIND_CHUNK;
                uop_p0_n.src0_addr = ecc_acc_dst_q;
                uop_p0_n.src1_addr = ecc_dst_q;
                uop_p0_n.dst_addr  = ecc_acc_dst_q;
                uop_p0_n.chunk_idx = 2'd3;
                p4_arch_op_n       = HDEC_ECC_MUL;
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
            ecc_job_copy_dst_n=ecc_job_dst_q;
            vrf_ra[0]=ecc_job_src_q; vrf_ra[1]=ecc_job_src_q;
            vrf_ra[2]=ecc_job_src_q; vrf_ra[3]=ecc_job_src_q;
            st_n=S_ECC_INV_COPY_WAIT;
        end

        S_ECC_INV_COPY_WAIT: begin
            st_n=S_ECC_INV_COPY_WRITE;
        end

        S_ECC_INV_COPY_WRITE: begin
            vrf_we='1;
            vrf_wa[0]=ecc_job_copy_dst_q; vrf_wa[1]=ecc_job_copy_dst_q;
            vrf_wa[2]=ecc_job_copy_dst_q; vrf_wa[3]=ecc_job_copy_dst_q;
            vrf_wd=vrf_rd;
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
                ecc_job_copy_dst_n=ecc_job_dst_q + 6'd2;
                vrf_ra[0]=ecc_job_dst_q; vrf_ra[1]=ecc_job_dst_q;
                vrf_ra[2]=ecc_job_dst_q; vrf_ra[3]=ecc_job_dst_q;
                st_n=S_ECC_INV_COPY_WAIT;
            end else begin
                st_n=S_ECC_INV_ISSUE_SQR;
            end
        end

        S_ECC_INV_ISSUE_SQR: begin
            hperm_dst_base_n=ecc_job_dst_q;
            hperm_src_base_n=ecc_job_dst_q;
            hperm_spread_n=1'b1;
            ecc_dst_n=ecc_job_dst_q;
            ecc_src_a_n=ecc_job_dst_q;
            ecc_autoreduce_n=1'b1;
            ecc_mac_n=1'b0;
            ecc_sqr_repeat_n=ecc_inv_step_sqr_repeat(ecc_inv_step_q);
            ecc_job_phase_n=ECC_PHASE_INV_SQR;
            vrf_ra[0]=ecc_job_dst_q; vrf_ra[1]=ecc_job_dst_q;
            vrf_ra[2]=ecc_job_dst_q; vrf_ra[3]=ecc_job_dst_q;
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
                ecc_leaf_a_n='0;
                ecc_leaf_b_n='0;
                ecc_leaf_prod_n='0;
                ecc_leaf_path_n='0;
                ecc_diag_slot_n='0;
                ecc_fold_word_n='0;
                ecc_autoreduce_n=1'b1;
                ecc_mac_n=1'b0;
                ecc_sqr_repeat_n='0;
                ecc_pipe0_valid_n=1'b0;
                ecc_pipe1_valid_n=1'b0;
                ecc_job_phase_n=ECC_PHASE_INV_MUL;
                vrf_ra[0]=ecc_job_dst_q; vrf_ra[1]=ecc_job_dst_q;
                vrf_ra[2]=ecc_job_dst_q; vrf_ra[3]=ecc_job_dst_q;
                st_n=S_ECC_LOAD_A_WAIT;
            end
        end

        S_ECC_INV_AFTER_MUL: begin
            ecc_job_phase_n=ECC_PHASE_NONE;
            ecc_inv_step_n=ecc_inv_step_q + 4'd1;
            st_n=S_ECC_INV_STEP;
        end

        S_ECC_PMUL_INIT: begin
            ecc_pmul_ctrl_n=ECC_PMUL_CTRL_INIT;
            ecc_pmul_subop_n=ECC_PMUL_SUB_INIT;
            ecc_pmul_step_n='0;
            st_n=S_ECC_PMUL_STEP;
        end

        S_ECC_PMUL_CONST_WRITE: begin
            vrf_we='1;
            vrf_wa[0]=ecc_job_copy_dst_q; vrf_wa[1]=ecc_job_copy_dst_q;
            vrf_wa[2]=ecc_job_copy_dst_q; vrf_wa[3]=ecc_job_copy_dst_q;
            vrf_wd='0;
            if (ecc_pmul_const_one_q)
                vrf_wd[0]=64'd1;
            st_n=S_ECC_PMUL_STEP_NEXT;
        end

        S_ECC_PMUL_READ_SCALAR_WAIT: begin
            st_n=S_ECC_PMUL_READ_SCALAR;
        end

        S_ECC_PMUL_READ_SCALAR: begin
            ecc_pmul_scalar_bit_n=ecc_scalar_bit_from_row(vrf_rd, ecc_pmul_bit_q);
            st_n=S_ECC_PMUL_START_ADD;
        end

        S_ECC_PMUL_START_ADD: begin
            ecc_pmul_ctrl_n=ECC_PMUL_CTRL_ADD;
            ecc_pmul_step_n='0;
            ecc_pmul_x1_n=ECC_PMUL_R0X; ecc_pmul_z1_n=ECC_PMUL_R0Z;
            ecc_pmul_x2_n=ECC_PMUL_R1X; ecc_pmul_z2_n=ECC_PMUL_R1Z;
            ecc_pmul_out_sel_n=ecc_pmul_scalar_bit_q ? 1'b0 : 1'b1;
            ecc_pmul_out_x_n=ecc_pmul_scalar_bit_q ? ECC_PMUL_R0X : ECC_PMUL_R1X;
            ecc_pmul_out_z_n=ecc_pmul_scalar_bit_q ? ECC_PMUL_R0Z : ECC_PMUL_R1Z;
            if (ecc_pmul_scalar_bit_q)
                ecc_pmul_r0_inf_n=1'b0;
            ecc_pmul_subop_n=ECC_PMUL_SUB_ADD;
            st_n=S_ECC_PMUL_STEP;
        end

        S_ECC_PMUL_START_DBL: begin
            ecc_pmul_ctrl_n=ECC_PMUL_CTRL_DBL;
            ecc_pmul_step_n='0;
            ecc_pmul_out_sel_n=ecc_pmul_scalar_bit_q;
            if (ecc_pmul_scalar_bit_q) begin
                ecc_pmul_x1_n=ECC_PMUL_R1X; ecc_pmul_z1_n=ECC_PMUL_R1Z;
                ecc_pmul_out_x_n=ECC_PMUL_R1X; ecc_pmul_out_z_n=ECC_PMUL_R1Z;
            end else begin
                ecc_pmul_x1_n=ECC_PMUL_R0X; ecc_pmul_z1_n=ECC_PMUL_R0Z;
                ecc_pmul_out_x_n=ECC_PMUL_R0X; ecc_pmul_out_z_n=ECC_PMUL_R0Z;
            end
            ecc_pmul_subop_n=ECC_PMUL_SUB_DBL;
            st_n=S_ECC_PMUL_STEP;
        end

        S_ECC_PMUL_STEP: begin
            unique case (ecc_pmul_subop_q)
            ECC_PMUL_SUB_INIT: begin
                unique case (ecc_pmul_step_q)
                6'd0: begin
                    ecc_job_phase_n=ECC_PHASE_PMUL_COPY;
                    ecc_job_copy_dst_n=ECC_PMUL_R1X;
                    vrf_ra[0]=ecc_pmul_point_q; vrf_ra[1]=ecc_pmul_point_q;
                    vrf_ra[2]=ecc_pmul_point_q; vrf_ra[3]=ecc_pmul_point_q;
                    st_n=S_ECC_INV_COPY_WAIT;
                end
                6'd1: begin
                    ecc_job_copy_dst_n=ECC_PMUL_R0X;
                    ecc_pmul_const_one_n=1'b1;
                    st_n=S_ECC_PMUL_CONST_WRITE;
                end
                6'd2: begin
                    ecc_job_copy_dst_n=ECC_PMUL_R0Z;
                    ecc_pmul_const_one_n=1'b0;
                    st_n=S_ECC_PMUL_CONST_WRITE;
                end
                default: begin
                    ecc_job_copy_dst_n=ECC_PMUL_R1Z;
                    ecc_pmul_const_one_n=1'b1;
                    st_n=S_ECC_PMUL_CONST_WRITE;
                end
                endcase
            end
            ECC_PMUL_SUB_ZERO_OUT: begin
                ecc_job_copy_dst_n=(ecc_pmul_step_q == 6'd0) ? ecc_pmul_result_q : (ecc_pmul_result_q + 6'd1);
                ecc_pmul_const_one_n=1'b0;
                st_n=S_ECC_PMUL_CONST_WRITE;
            end
            ECC_PMUL_SUB_AFFINE: begin
                unique case (ecc_pmul_step_q)
                6'd0: begin
                    ecc_job_src_n=ECC_PMUL_R0Z;
                    ecc_job_dst_n=ECC_PMUL_T0;
                    ecc_inv_step_n='0;
                    st_n=S_ECC_INV_INIT;
                end
                6'd1: begin
                    ecc_dst_n=ECC_PMUL_T4; ecc_src_a_n=ECC_PMUL_R0X; ecc_src_b_n=ECC_PMUL_T0;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_leaf_a_n='0; ecc_leaf_b_n='0; ecc_leaf_prod_n='0; ecc_leaf_path_n='0;
                    ecc_diag_slot_n='0; ecc_fold_word_n='0; ecc_pipe0_valid_n=1'b0; ecc_pipe1_valid_n=1'b0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_ra[0]=ECC_PMUL_R0X; vrf_ra[1]=ECC_PMUL_R0X; vrf_ra[2]=ECC_PMUL_R0X; vrf_ra[3]=ECC_PMUL_R0X;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                6'd2: begin
                    ecc_job_src_n=ECC_PMUL_R1Z;
                    ecc_job_dst_n=ECC_PMUL_T1;
                    ecc_inv_step_n='0;
                    st_n=S_ECC_INV_INIT;
                end
                6'd3: begin
                    ecc_dst_n=ECC_PMUL_T6; ecc_src_a_n=ECC_PMUL_R1X; ecc_src_b_n=ECC_PMUL_T1;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_leaf_a_n='0; ecc_leaf_b_n='0; ecc_leaf_prod_n='0; ecc_leaf_path_n='0;
                    ecc_diag_slot_n='0; ecc_fold_word_n='0; ecc_pipe0_valid_n=1'b0; ecc_pipe1_valid_n=1'b0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_ra[0]=ECC_PMUL_R1X; vrf_ra[1]=ECC_PMUL_R1X; vrf_ra[2]=ECC_PMUL_R1X; vrf_ra[3]=ECC_PMUL_R1X;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                6'd4: begin
                    uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK;
                    uop_p0_n.src0_addr=ECC_PMUL_T4; uop_p0_n.src1_addr=ecc_pmul_point_q;
                    uop_p0_n.dst_addr=ECC_PMUL_T2; uop_p0_n.chunk_idx=2'd3;
                    ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0;
                end
                6'd5: begin
                    uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK;
                    uop_p0_n.src0_addr=ECC_PMUL_T6; uop_p0_n.src1_addr=ECC_PMUL_T4;
                    uop_p0_n.dst_addr=ECC_PMUL_T3; uop_p0_n.chunk_idx=2'd3;
                    ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0;
                end
                6'd6: begin
                    uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK;
                    uop_p0_n.src0_addr=ECC_PMUL_T3; uop_p0_n.src1_addr=ecc_pmul_point_q;
                    uop_p0_n.dst_addr=ECC_PMUL_T3; uop_p0_n.chunk_idx=2'd3;
                    ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0;
                end
                6'd7: begin
                    hperm_dst_base_n=ECC_PMUL_T5; hperm_src_base_n=ECC_PMUL_T4; hperm_spread_n=1'b1;
                    ecc_dst_n=ECC_PMUL_T5; ecc_src_a_n=ECC_PMUL_T5;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_ra[0]=ECC_PMUL_T4; vrf_ra[1]=ECC_PMUL_T4; vrf_ra[2]=ECC_PMUL_T4; vrf_ra[3]=ECC_PMUL_T4;
                    st_n=S_RD_WAIT;
                end
                6'd8: begin
                    ecc_dst_n=ECC_PMUL_T7; ecc_src_a_n=ECC_PMUL_T5; ecc_src_b_n=ECC_PMUL_T4;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_leaf_a_n='0; ecc_leaf_b_n='0; ecc_leaf_prod_n='0; ecc_leaf_path_n='0;
                    ecc_diag_slot_n='0; ecc_fold_word_n='0; ecc_pipe0_valid_n=1'b0; ecc_pipe1_valid_n=1'b0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_ra[0]=ECC_PMUL_T5; vrf_ra[1]=ECC_PMUL_T5; vrf_ra[2]=ECC_PMUL_T5; vrf_ra[3]=ECC_PMUL_T5;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                6'd9: begin
                    ecc_job_copy_dst_n=ECC_PMUL_T9;
                    ecc_pmul_const_one_n=1'b1;
                    st_n=S_ECC_PMUL_CONST_WRITE;
                end
                6'd10: begin
                    uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK;
                    uop_p0_n.src0_addr=ECC_PMUL_T7; uop_p0_n.src1_addr=ECC_PMUL_T9;
                    uop_p0_n.dst_addr=ECC_PMUL_T7; uop_p0_n.chunk_idx=2'd3;
                    ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0;
                end
                6'd11: begin
                    hperm_dst_base_n=ECC_PMUL_T8; hperm_src_base_n=ECC_PMUL_T2; hperm_spread_n=1'b1;
                    ecc_dst_n=ECC_PMUL_T8; ecc_src_a_n=ECC_PMUL_T8;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_ra[0]=ECC_PMUL_T2; vrf_ra[1]=ECC_PMUL_T2; vrf_ra[2]=ECC_PMUL_T2; vrf_ra[3]=ECC_PMUL_T2;
                    st_n=S_RD_WAIT;
                end
                6'd12: begin
                    ecc_dst_n=ECC_PMUL_T8; ecc_src_a_n=ECC_PMUL_T3; ecc_src_b_n=ECC_PMUL_T8;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_leaf_a_n='0; ecc_leaf_b_n='0; ecc_leaf_prod_n='0; ecc_leaf_path_n='0;
                    ecc_diag_slot_n='0; ecc_fold_word_n='0; ecc_pipe0_valid_n=1'b0; ecc_pipe1_valid_n=1'b0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_ra[0]=ECC_PMUL_T3; vrf_ra[1]=ECC_PMUL_T3; vrf_ra[2]=ECC_PMUL_T3; vrf_ra[3]=ECC_PMUL_T3;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                6'd13: begin
                    uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK;
                    uop_p0_n.src0_addr=ECC_PMUL_T7; uop_p0_n.src1_addr=ECC_PMUL_T8;
                    uop_p0_n.dst_addr=ECC_PMUL_T7; uop_p0_n.chunk_idx=2'd3;
                    ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0;
                end
                6'd14: begin
                    hperm_dst_base_n=ECC_PMUL_T8; hperm_src_base_n=ecc_pmul_point_q + 6'd1; hperm_spread_n=1'b1;
                    ecc_dst_n=ECC_PMUL_T8; ecc_src_a_n=ECC_PMUL_T8;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_ra[0]=ecc_pmul_point_q + 6'd1; vrf_ra[1]=ecc_pmul_point_q + 6'd1;
                    vrf_ra[2]=ecc_pmul_point_q + 6'd1; vrf_ra[3]=ecc_pmul_point_q + 6'd1;
                    st_n=S_RD_WAIT;
                end
                6'd15: begin
                    uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK;
                    uop_p0_n.src0_addr=ECC_PMUL_T7; uop_p0_n.src1_addr=ECC_PMUL_T8;
                    uop_p0_n.dst_addr=ECC_PMUL_T7; uop_p0_n.chunk_idx=2'd3;
                    ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0;
                end
                6'd16: begin
                    ecc_dst_n=ECC_PMUL_T8; ecc_src_a_n=ECC_PMUL_T4; ecc_src_b_n=ecc_pmul_point_q + 6'd1;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_leaf_a_n='0; ecc_leaf_b_n='0; ecc_leaf_prod_n='0; ecc_leaf_path_n='0;
                    ecc_diag_slot_n='0; ecc_fold_word_n='0; ecc_pipe0_valid_n=1'b0; ecc_pipe1_valid_n=1'b0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_ra[0]=ECC_PMUL_T4; vrf_ra[1]=ECC_PMUL_T4; vrf_ra[2]=ECC_PMUL_T4; vrf_ra[3]=ECC_PMUL_T4;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                6'd17: begin
                    uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK;
                    uop_p0_n.src0_addr=ECC_PMUL_T7; uop_p0_n.src1_addr=ECC_PMUL_T8;
                    uop_p0_n.dst_addr=ECC_PMUL_T7; uop_p0_n.chunk_idx=2'd3;
                    ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0;
                end
                6'd18: begin
                    ecc_dst_n=ECC_PMUL_T8; ecc_src_a_n=ecc_pmul_point_q; ecc_src_b_n=ECC_PMUL_T2;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_leaf_a_n='0; ecc_leaf_b_n='0; ecc_leaf_prod_n='0; ecc_leaf_path_n='0;
                    ecc_diag_slot_n='0; ecc_fold_word_n='0; ecc_pipe0_valid_n=1'b0; ecc_pipe1_valid_n=1'b0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_ra[0]=ecc_pmul_point_q; vrf_ra[1]=ecc_pmul_point_q; vrf_ra[2]=ecc_pmul_point_q; vrf_ra[3]=ecc_pmul_point_q;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                6'd19: begin
                    ecc_job_src_n=ECC_PMUL_T8;
                    ecc_job_dst_n=ECC_PMUL_T5;
                    ecc_inv_step_n='0;
                    st_n=S_ECC_INV_INIT;
                end
                6'd20: begin
                    ecc_dst_n=ECC_PMUL_T8; ecc_src_a_n=ECC_PMUL_T7; ecc_src_b_n=ECC_PMUL_T5;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_leaf_a_n='0; ecc_leaf_b_n='0; ecc_leaf_prod_n='0; ecc_leaf_path_n='0;
                    ecc_diag_slot_n='0; ecc_fold_word_n='0; ecc_pipe0_valid_n=1'b0; ecc_pipe1_valid_n=1'b0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_ra[0]=ECC_PMUL_T7; vrf_ra[1]=ECC_PMUL_T7; vrf_ra[2]=ECC_PMUL_T7; vrf_ra[3]=ECC_PMUL_T7;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                6'd21: begin
                    ecc_dst_n=ECC_PMUL_T8; ecc_src_a_n=ECC_PMUL_T8; ecc_src_b_n=ECC_PMUL_T2;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_leaf_a_n='0; ecc_leaf_b_n='0; ecc_leaf_prod_n='0; ecc_leaf_path_n='0;
                    ecc_diag_slot_n='0; ecc_fold_word_n='0; ecc_pipe0_valid_n=1'b0; ecc_pipe1_valid_n=1'b0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_ra[0]=ECC_PMUL_T8; vrf_ra[1]=ECC_PMUL_T8; vrf_ra[2]=ECC_PMUL_T8; vrf_ra[3]=ECC_PMUL_T8;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                6'd22: begin
                    uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK;
                    uop_p0_n.src0_addr=ECC_PMUL_T8; uop_p0_n.src1_addr=ecc_pmul_point_q + 6'd1;
                    uop_p0_n.dst_addr=ecc_pmul_result_q + 6'd1; uop_p0_n.chunk_idx=2'd3;
                    ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0;
                end
                default: begin
                    ecc_job_phase_n=ECC_PHASE_PMUL_COPY;
                    ecc_job_copy_dst_n=ecc_pmul_result_q;
                    vrf_ra[0]=ECC_PMUL_T4; vrf_ra[1]=ECC_PMUL_T4; vrf_ra[2]=ECC_PMUL_T4; vrf_ra[3]=ECC_PMUL_T4;
                    st_n=S_ECC_INV_COPY_WAIT;
                end
                endcase
            end
            ECC_PMUL_SUB_DBL: begin
                unique case (ecc_pmul_step_q)
                6'd0: begin hperm_dst_base_n=ECC_PMUL_T0; hperm_src_base_n=ecc_pmul_x1_q; hperm_spread_n=1'b1; ecc_dst_n=ECC_PMUL_T0; ecc_src_a_n=ECC_PMUL_T0; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_ra[0]=ecc_pmul_x1_q; vrf_ra[1]=ecc_pmul_x1_q; vrf_ra[2]=ecc_pmul_x1_q; vrf_ra[3]=ecc_pmul_x1_q; st_n=S_RD_WAIT; end
                6'd1: begin hperm_dst_base_n=ECC_PMUL_T1; hperm_src_base_n=ECC_PMUL_T0; hperm_spread_n=1'b1; ecc_dst_n=ECC_PMUL_T1; ecc_src_a_n=ECC_PMUL_T1; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_ra[0]=ECC_PMUL_T0; vrf_ra[1]=ECC_PMUL_T0; vrf_ra[2]=ECC_PMUL_T0; vrf_ra[3]=ECC_PMUL_T0; st_n=S_RD_WAIT; end
                6'd2: begin hperm_dst_base_n=ECC_PMUL_T4; hperm_src_base_n=ecc_pmul_z1_q; hperm_spread_n=1'b1; ecc_dst_n=ECC_PMUL_T4; ecc_src_a_n=ECC_PMUL_T4; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_ra[0]=ecc_pmul_z1_q; vrf_ra[1]=ecc_pmul_z1_q; vrf_ra[2]=ecc_pmul_z1_q; vrf_ra[3]=ecc_pmul_z1_q; st_n=S_RD_WAIT; end
                6'd3: begin hperm_dst_base_n=ECC_PMUL_T5; hperm_src_base_n=ECC_PMUL_T4; hperm_spread_n=1'b1; ecc_dst_n=ECC_PMUL_T5; ecc_src_a_n=ECC_PMUL_T5; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_ra[0]=ECC_PMUL_T4; vrf_ra[1]=ECC_PMUL_T4; vrf_ra[2]=ECC_PMUL_T4; vrf_ra[3]=ECC_PMUL_T4; st_n=S_RD_WAIT; end
                6'd4: begin uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK; uop_p0_n.src0_addr=ECC_PMUL_T1; uop_p0_n.src1_addr=ECC_PMUL_T5; uop_p0_n.dst_addr=ecc_pmul_out_x_q; uop_p0_n.chunk_idx=2'd3; ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0; end
                default: begin hperm_dst_base_n=ecc_pmul_out_z_q; hperm_src_base_n=ecc_pmul_out_sel_q ? ECC_PMUL_T3 : ECC_PMUL_T2; hperm_spread_n=1'b1; ecc_dst_n=ecc_pmul_out_z_q; ecc_src_a_n=ecc_pmul_out_z_q; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_ra[0]=hperm_src_base_n; vrf_ra[1]=hperm_src_base_n; vrf_ra[2]=hperm_src_base_n; vrf_ra[3]=hperm_src_base_n; st_n=S_RD_WAIT; end
                endcase
            end
            ECC_PMUL_SUB_ADD: begin
                unique case (ecc_pmul_step_q)
                6'd0: begin ecc_dst_n=ECC_PMUL_T0; ecc_src_a_n=ecc_pmul_x1_q; ecc_src_b_n=ecc_pmul_z2_q; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_leaf_a_n='0; ecc_leaf_b_n='0; ecc_leaf_prod_n='0; ecc_leaf_path_n='0; ecc_diag_slot_n='0; ecc_fold_word_n='0; ecc_pipe0_valid_n=1'b0; ecc_pipe1_valid_n=1'b0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_ra[0]=ecc_pmul_x1_q; vrf_ra[1]=ecc_pmul_x1_q; vrf_ra[2]=ecc_pmul_x1_q; vrf_ra[3]=ecc_pmul_x1_q; st_n=S_ECC_LOAD_A_WAIT; end
                6'd1: begin ecc_dst_n=ECC_PMUL_T1; ecc_src_a_n=ecc_pmul_x2_q; ecc_src_b_n=ecc_pmul_z1_q; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_leaf_a_n='0; ecc_leaf_b_n='0; ecc_leaf_prod_n='0; ecc_leaf_path_n='0; ecc_diag_slot_n='0; ecc_fold_word_n='0; ecc_pipe0_valid_n=1'b0; ecc_pipe1_valid_n=1'b0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_ra[0]=ecc_pmul_x2_q; vrf_ra[1]=ecc_pmul_x2_q; vrf_ra[2]=ecc_pmul_x2_q; vrf_ra[3]=ecc_pmul_x2_q; st_n=S_ECC_LOAD_A_WAIT; end
                6'd2: begin uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK; uop_p0_n.src0_addr=ECC_PMUL_T0; uop_p0_n.src1_addr=ECC_PMUL_T1; uop_p0_n.dst_addr=ECC_PMUL_T4; uop_p0_n.chunk_idx=2'd3; ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0; end
                6'd3: begin hperm_dst_base_n=ECC_PMUL_T5; hperm_src_base_n=ECC_PMUL_T4; hperm_spread_n=1'b1; ecc_dst_n=ECC_PMUL_T5; ecc_src_a_n=ECC_PMUL_T5; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_ra[0]=ECC_PMUL_T4; vrf_ra[1]=ECC_PMUL_T4; vrf_ra[2]=ECC_PMUL_T4; vrf_ra[3]=ECC_PMUL_T4; st_n=S_RD_WAIT; end
                6'd4: begin ecc_dst_n=ECC_PMUL_T2; ecc_src_a_n=ecc_pmul_x1_q; ecc_src_b_n=ecc_pmul_z1_q; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_leaf_a_n='0; ecc_leaf_b_n='0; ecc_leaf_prod_n='0; ecc_leaf_path_n='0; ecc_diag_slot_n='0; ecc_fold_word_n='0; ecc_pipe0_valid_n=1'b0; ecc_pipe1_valid_n=1'b0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_ra[0]=ecc_pmul_x1_q; vrf_ra[1]=ecc_pmul_x1_q; vrf_ra[2]=ecc_pmul_x1_q; vrf_ra[3]=ecc_pmul_x1_q; st_n=S_ECC_LOAD_A_WAIT; end
                6'd5: begin ecc_dst_n=ECC_PMUL_T3; ecc_src_a_n=ecc_pmul_x2_q; ecc_src_b_n=ecc_pmul_z2_q; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_leaf_a_n='0; ecc_leaf_b_n='0; ecc_leaf_prod_n='0; ecc_leaf_path_n='0; ecc_diag_slot_n='0; ecc_fold_word_n='0; ecc_pipe0_valid_n=1'b0; ecc_pipe1_valid_n=1'b0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_ra[0]=ecc_pmul_x2_q; vrf_ra[1]=ecc_pmul_x2_q; vrf_ra[2]=ecc_pmul_x2_q; vrf_ra[3]=ecc_pmul_x2_q; st_n=S_ECC_LOAD_A_WAIT; end
                6'd6: begin ecc_dst_n=ECC_PMUL_T6; ecc_src_a_n=ECC_PMUL_T2; ecc_src_b_n=ECC_PMUL_T3; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_leaf_a_n='0; ecc_leaf_b_n='0; ecc_leaf_prod_n='0; ecc_leaf_path_n='0; ecc_diag_slot_n='0; ecc_fold_word_n='0; ecc_pipe0_valid_n=1'b0; ecc_pipe1_valid_n=1'b0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_ra[0]=ECC_PMUL_T2; vrf_ra[1]=ECC_PMUL_T2; vrf_ra[2]=ECC_PMUL_T2; vrf_ra[3]=ECC_PMUL_T2; st_n=S_ECC_LOAD_A_WAIT; end
                6'd7: begin ecc_dst_n=ECC_PMUL_T7; ecc_src_a_n=ecc_pmul_point_q; ecc_src_b_n=ECC_PMUL_T5; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_leaf_a_n='0; ecc_leaf_b_n='0; ecc_leaf_prod_n='0; ecc_leaf_path_n='0; ecc_diag_slot_n='0; ecc_fold_word_n='0; ecc_pipe0_valid_n=1'b0; ecc_pipe1_valid_n=1'b0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_ra[0]=ecc_pmul_point_q; vrf_ra[1]=ecc_pmul_point_q; vrf_ra[2]=ecc_pmul_point_q; vrf_ra[3]=ecc_pmul_point_q; st_n=S_ECC_LOAD_A_WAIT; end
                6'd8: begin uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK; uop_p0_n.src0_addr=ECC_PMUL_T7; uop_p0_n.src1_addr=ECC_PMUL_T6; uop_p0_n.dst_addr=ecc_pmul_out_x_q; uop_p0_n.chunk_idx=2'd3; ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0; end
                default: begin ecc_job_phase_n=ECC_PHASE_PMUL_COPY; ecc_job_copy_dst_n=ecc_pmul_out_z_q; vrf_ra[0]=ECC_PMUL_T5; vrf_ra[1]=ECC_PMUL_T5; vrf_ra[2]=ECC_PMUL_T5; vrf_ra[3]=ECC_PMUL_T5; st_n=S_ECC_INV_COPY_WAIT; end
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
                unique case (ecc_pmul_ctrl_q)
                ECC_PMUL_CTRL_INIT: begin
                    vrf_ra[0]=ecc_job_src_q; vrf_ra[1]=ecc_job_src_q;
                    vrf_ra[2]=ecc_job_src_q; vrf_ra[3]=ecc_job_src_q;
                    st_n=S_ECC_PMUL_READ_SCALAR_WAIT;
                end
                ECC_PMUL_CTRL_ADD: begin
                    st_n=S_ECC_PMUL_START_DBL;
                end
                ECC_PMUL_CTRL_DBL: begin
                    if (ecc_pmul_bit_q == 8'd0) begin
                        ecc_pmul_ctrl_n=ECC_PMUL_CTRL_FINAL;
                        ecc_pmul_subop_n=ecc_pmul_r0_inf_n ? ECC_PMUL_SUB_ZERO_OUT : ECC_PMUL_SUB_AFFINE;
                        st_n=S_ECC_PMUL_STEP;
                    end else begin
                        ecc_pmul_bit_n=ecc_pmul_bit_q - 8'd1;
                        vrf_ra[0]=ecc_job_src_q; vrf_ra[1]=ecc_job_src_q;
                        vrf_ra[2]=ecc_job_src_q; vrf_ra[3]=ecc_job_src_q;
                        st_n=S_ECC_PMUL_READ_SCALAR_WAIT;
                    end
                end
                default: begin
                    ecc_job_active_n=1'b0;
                    ecc_job_done_n=1'b1;
                    ecc_job_phase_n=ECC_PHASE_NONE;
                    res_n={32'b0, ecc_job_cycle_q, 6'b0, ecc_pmul_result_q, 2'b10, STATUS_OK};
                    st_n=S_RESULT;
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
                res_n={32'b0, ecc_job_cycle_q, 6'b0, ecc_job_dst_q, 2'b10, STATUS_OK};
                st_n=S_RESULT;
            end
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
            if ((uop_p1_q.op_type == UOP_HPERM_CHUNK)
             || (uop_p1_q.op_type == UOP_HCNTADD_SUBGROUP)
             || (uop_p1_q.op_type == UOP_HBIND_CHUNK)
             || (uop_p1_q.op_type == UOP_HSIM_CHUNK)
             || (uop_p1_q.op_type == UOP_HMATCH_CHUNK))
                hdc_src0_n = vrf_rd;
            vrf_ra[0]=uop_p1_q.src1_addr; vrf_ra[1]=uop_p1_q.src1_addr;
            vrf_ra[2]=uop_p1_q.src1_addr; vrf_ra[3]=uop_p1_q.src1_addr;
            st_n=S_UOP_P1_RD1_WAIT;
        end

        S_UOP_P1_RD1_WAIT: begin
            p2_lane_compute_n = uop_p2_q.valid;
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
            st_n=S_UOP_P3_GLOBAL;
        end

        S_UOP_P3_GLOBAL: begin
            uop_p3_n.valid  = 1'b0;
            p4_arch_op_n    = ecc_mac_q ? HDEC_ECC_MUL : p4_arch_from_uop(uop_p3_q.op_type);
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
                    uop_p0_n = uop_p3_q; uop_p0_n.valid = 1'b1;
                    uop_p0_n.chunk_idx    = uop_p3_q.chunk_idx + 2'd1;
                    uop_p0_n.subgroup_idx = 2'd0;
                    uop_p0_n.src0_addr = {1'b0,hcntadd_hv_slot_q,2'b00}+{4'b0,(uop_p3_q.chunk_idx + 2'd1)};
                    uop_p0_n.src1_addr = hcntadd_acc_base+{2'b00,(uop_p3_q.chunk_idx + 2'd1),2'b00};
                    uop_p0_n.dst_addr  = hcntadd_acc_base+{2'b00,(uop_p3_q.chunk_idx + 2'd1),2'b00};
                    st_n = S_UOP_P1_RD0;
                end else st_n = S_UOP_P4_RESP;
            end
            UOP_HCNTCLIP_READ: begin
            hcntclip_word_with_result = hdc_src0_q;
                hcntclip_word_with_result[0][{uop_p3_q.subgroup_idx,4'b0000} +: 16] = lane_clip_q[0];
                hcntclip_word_with_result[1][{uop_p3_q.subgroup_idx,4'b0000} +: 16] = lane_clip_q[1];
                hcntclip_word_with_result[2][{uop_p3_q.subgroup_idx,4'b0000} +: 16] = lane_clip_q[2];
                hcntclip_word_with_result[3][{uop_p3_q.subgroup_idx,4'b0000} +: 16] = lane_clip_q[3];
                hdc_src0_n = hcntclip_word_with_result;
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
            p2_lane_compute_n = uop_p2_q.valid;
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
            vrf_wd = hdc_src0_q;
            hdc_src0_n = '0;
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
            res_n = '0;
            if (p4_arch_op_q == HDEC_HSIM) begin
                res_n = {53'b0, hsim_total_q};
                st_n = S_RESULT;
            end else if (p4_arch_op_q == HDEC_HMATCH) begin
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
            end else if ((p4_arch_op_q == HDEC_ECC_MUL) && ecc_mac_q) begin
                ecc_mac_n = 1'b0;
                res_n = {56'b0, ecc_acc_dst_q, STATUS_OK};
                st_n = S_RESULT;
            end else if (ecc_job_active_q && (ecc_job_phase_q == ECC_PHASE_PMUL_ADD)) begin
                ecc_job_phase_n=ECC_PHASE_NONE;
                st_n=S_ECC_PMUL_STEP_NEXT;
            end else st_n = S_RESULT;
        end

        S_RESULT: begin st_n=S_IDLE;end
        default: st_n=S_IDLE;
        endcase
    end

    // ── Sequential ──────────────────────────────────────────────────────────
    always_ff @(posedge clk_i) begin
        if (ecc_product_we) begin
            ecc_product_pair[ecc_fold_word_q] <= ecc_product_pair_wdata;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni)begin
            st_q<=S_IDLE;res_q<='0;op_q<=HDEC_VWR64;a_q<='0;bk_q<='0;
            vaddr_bank_q<='0;vaddr_idx_q<='0;clr_cnt_q<='0;clr_base_q<='0;
            chunk_cnt_q<='0;
            hb_dst_base_q<='0;hb_src0_base_q<='0;hb_src1_base_q<='0;
            hsim_src0_base_q<='0;hsim_src1_base_q<='0;hsim_total_q<='0;group_dist_q<='0;
            hmatch_last_idx_q<='0;hmatch_best_idx_q<='0;hmatch_class_slot_q<='0;hmatch_best_dist_q<='0;hmatch_budget_q<='0;hmatch_update_q<=1'b0;
            hperm_dst_base_q<='0;hperm_src_base_q<='0;hperm_word_off_q<='0;hperm_nibble_q<='0;hperm_bit_low_q<='0;hperm_spread_q<=1'b0;hperm_lane_base_q<='0;
            hcntadd_hv_slot_q<='0;hcntadd_subgroup_q<='0;hcntadd_acc_sel_q<='0;
            hcntclip_dst_base_q<='0;hcntclip_acc_sel_q<='0;hcntclip_threshold_q<='0;hcntclip_chunk_q<='0;hcntclip_subgroup_q<='0;
            vrf_ra_q<='0;vrf_we_q<='0;vrf_wa_q<='0;vrf_wd_q<='0;
            uop_p0_q<='0;uop_p1_q<='0;uop_p2_q<='0;uop_p3_q<='0;
            hdc_src0_q<='0;
            lane_result_q<='0;lane_clip_q<='0;
            p2_lane_compute_q<=1'b0;
            p4_arch_op_q<=HDEC_VWR64;
            ecc_src_a_q<='0;ecc_src_b_q<='0;ecc_dst_q<='0;ecc_acc_dst_q<='0;
            ecc_leaf_a_q<='0;ecc_leaf_b_q<='0;ecc_leaf_prod_q<='0;ecc_leaf_path_q<='0;ecc_diag_slot_q<='0;ecc_fold_word_q<='0;
            ecc_autoreduce_q<=1'b0;ecc_mac_q<=1'b0;ecc_sqr_repeat_q<='0;
            ecc_job_kind_q<=ECC_JOB_NONE;ecc_job_phase_q<=ECC_PHASE_NONE;ecc_job_active_q<=1'b0;ecc_job_done_q<=1'b0;ecc_job_cycle_q<='0;ecc_inv_step_q<='0;ecc_job_src_q<='0;ecc_job_dst_q<='0;ecc_job_copy_dst_q<='0;
            ecc_pmul_ctrl_q<=ECC_PMUL_CTRL_INIT;ecc_pmul_subop_q<=ECC_PMUL_SUB_NONE;ecc_pmul_step_q<='0;ecc_pmul_bit_q<='0;ecc_pmul_scalar_bit_q<=1'b0;
            ecc_pmul_r0_inf_q<=1'b1;ecc_pmul_out_sel_q<=1'b0;ecc_pmul_const_one_q<=1'b0;ecc_pmul_result_q<='0;ecc_pmul_point_q<='0;
            ecc_pmul_x1_q<='0;ecc_pmul_z1_q<='0;ecc_pmul_x2_q<='0;ecc_pmul_z2_q<='0;ecc_pmul_out_x_q<='0;ecc_pmul_out_z_q<='0;
            ecc_pipe0_valid_q<=1'b0;ecc_pipe1_valid_q<=1'b0;ecc_pipe0_diag_slot_q<='0;ecc_pipe1_diag_slot_q<='0;
        end
        else begin
            st_q<=st_n;res_q<=res_n;op_q<=op_n;a_q<=a_n;bk_q<=bk_n;
            vaddr_bank_q<=vaddr_bank_n;vaddr_idx_q<=vaddr_idx_n;clr_cnt_q<=clr_cnt_n;clr_base_q<=clr_base_n;
            chunk_cnt_q<=chunk_cnt_n;
            hb_dst_base_q<=hb_dst_base_n;hb_src0_base_q<=hb_src0_base_n;hb_src1_base_q<=hb_src1_base_n;
            hsim_src0_base_q<=hsim_src0_base_n;hsim_src1_base_q<=hsim_src1_base_n;hsim_total_q<=hsim_total_n;group_dist_q<=group_dist_n;
            hmatch_last_idx_q<=hmatch_last_idx_n;hmatch_best_idx_q<=hmatch_best_idx_n;hmatch_class_slot_q<=hmatch_class_slot_n;hmatch_best_dist_q<=hmatch_best_dist_n;hmatch_budget_q<=hmatch_budget_n;hmatch_update_q<=hmatch_update_n;
            hperm_dst_base_q<=hperm_dst_base_n;hperm_src_base_q<=hperm_src_base_n;hperm_word_off_q<=hperm_word_off_n;hperm_nibble_q<=hperm_nibble_n;hperm_bit_low_q<=hperm_bit_low_n;hperm_spread_q<=hperm_spread_n;hperm_lane_base_q<=hperm_lane_base_n;
            hcntadd_hv_slot_q<=hcntadd_hv_slot_n;hcntadd_subgroup_q<=hcntadd_subgroup_n;hcntadd_acc_sel_q<=hcntadd_acc_sel_n;
            hcntclip_dst_base_q<=hcntclip_dst_base_n;hcntclip_acc_sel_q<=hcntclip_acc_sel_n;hcntclip_threshold_q<=hcntclip_threshold_n;hcntclip_chunk_q<=hcntclip_chunk_n;hcntclip_subgroup_q<=hcntclip_subgroup_n;
            vrf_ra_q<=vrf_ra;vrf_we_q<=vrf_we;vrf_wa_q<=vrf_wa;vrf_wd_q<=vrf_wd;
            uop_p0_q<=uop_p0_n;uop_p1_q<=uop_p1_n;uop_p2_q<=uop_p2_n;uop_p3_q<=uop_p3_n;
            hdc_src0_q<=hdc_src0_n;
            lane_result_q<=lane_result_n;lane_clip_q<=lane_clip_n;
            p2_lane_compute_q<=p2_lane_compute_n;
            p4_arch_op_q<=p4_arch_op_n;
            ecc_src_a_q<=ecc_src_a_n;ecc_src_b_q<=ecc_src_b_n;ecc_dst_q<=ecc_dst_n;ecc_acc_dst_q<=ecc_acc_dst_n;
            ecc_leaf_a_q<=ecc_leaf_a_n;ecc_leaf_b_q<=ecc_leaf_b_n;ecc_leaf_prod_q<=ecc_leaf_prod_n;ecc_leaf_path_q<=ecc_leaf_path_n;ecc_diag_slot_q<=ecc_diag_slot_n;ecc_fold_word_q<=ecc_fold_word_n;
            ecc_autoreduce_q<=ecc_autoreduce_n;ecc_mac_q<=ecc_mac_n;ecc_sqr_repeat_q<=ecc_sqr_repeat_n;
            ecc_job_kind_q<=ecc_job_kind_n;ecc_job_phase_q<=ecc_job_phase_n;ecc_job_active_q<=ecc_job_active_n;ecc_job_done_q<=ecc_job_done_n;ecc_job_cycle_q<=ecc_job_cycle_n;ecc_inv_step_q<=ecc_inv_step_n;ecc_job_src_q<=ecc_job_src_n;ecc_job_dst_q<=ecc_job_dst_n;ecc_job_copy_dst_q<=ecc_job_copy_dst_n;
            ecc_pmul_ctrl_q<=ecc_pmul_ctrl_n;ecc_pmul_subop_q<=ecc_pmul_subop_n;ecc_pmul_step_q<=ecc_pmul_step_n;ecc_pmul_bit_q<=ecc_pmul_bit_n;ecc_pmul_scalar_bit_q<=ecc_pmul_scalar_bit_n;
            ecc_pmul_r0_inf_q<=ecc_pmul_r0_inf_n;ecc_pmul_out_sel_q<=ecc_pmul_out_sel_n;ecc_pmul_const_one_q<=ecc_pmul_const_one_n;ecc_pmul_result_q<=ecc_pmul_result_n;ecc_pmul_point_q<=ecc_pmul_point_n;
            ecc_pmul_x1_q<=ecc_pmul_x1_n;ecc_pmul_z1_q<=ecc_pmul_z1_n;ecc_pmul_x2_q<=ecc_pmul_x2_n;ecc_pmul_z2_q<=ecc_pmul_z2_n;ecc_pmul_out_x_q<=ecc_pmul_out_x_n;ecc_pmul_out_z_q<=ecc_pmul_out_z_n;
            ecc_pipe0_valid_q<=ecc_pipe0_valid_n;ecc_pipe1_valid_q<=ecc_pipe1_valid_n;ecc_pipe0_diag_slot_q<=ecc_pipe0_diag_slot_n;ecc_pipe1_diag_slot_q<=ecc_pipe1_diag_slot_n;
        end
    end
endmodule
