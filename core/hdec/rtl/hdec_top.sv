// hdec_top.sv — HDCU Phase: VRF mgmt + HDC compute FSM
// HDCU instruction subset: VWR64, VRD64, HCLR, HCNTCLR, HCNTADD,
// HBIND, HPERM, HSIM, HCNTCLIP, HMATCH, VADDR.
// No bundle, no add/sub counter, no BMCA.
module hdec_top import hdec_pkg::*; import hdec_resource_pkg::*; #(
    parameter bit ECC_STATUS_CYCLE_COUNT = 1'b0,
    parameter bit ECC_DEBUG_FIELD_OPS    = 1'b0,
    parameter bit ECC_PMUL_RESIDUE_SEEDING = 1'b1,
    parameter bit ECC_PMUL_AFFINE_FACTORING = 1'b1,
    parameter bit ECC_INV_SQUARE_REDIRECT = 1'b1,
    parameter bit ECC_PMUL_DBL_FROBENIUS = 1'b1,
    parameter bit ECC_PMUL_ADD_Z_FORWARD = 1'b1,
    parameter bit VV31_SCHED_ENABLE = 1'b1,
    parameter bit VV33_FINE_INTERLEAVE = 1'b1,
    parameter bit VV33_PAIRED_HMATCH = 1'b1
) (
    input logic clk_i, rst_ni, valid_i, output logic ready_o,
    input hdec_op_t operator_i, input logic [63:0] operand_a_i, operand_b_i,
    output logic valid_o, output logic [63:0] result_o
);
    localparam bit ECC_PMUL_RESIDUE_SEED_ACTIVE =
        ECC_PMUL_RESIDUE_SEEDING && !ECC_DEBUG_FIELD_OPS;
    localparam bit ECC_PMUL_AFFINE_FACTOR_ACTIVE =
        ECC_PMUL_AFFINE_FACTORING && !ECC_DEBUG_FIELD_OPS;
    logic [VRF_IDX_W-1:0] vrf_ra, vrf_ra_q;
    logic [LANE_NUM-1:0][VRF_IDX_W-1:0] vrf_bank_ra;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] vrf_rd;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] vrf_rd_early;
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
    hdec_vrf_64x256 i_vrf(
        .clk_i,
        .bank_ra_addr_i(vrf_bank_ra),
        .bank_ra_data_o(vrf_rd),
        .bank_ra_early_o(vrf_rd_early),
        .bank_we_i(vrf_we),
        .row_wa_addr_i(vrf_wa),
        .bank_wdata_i(vrf_wd),
        .vrf_ready_o()
    );
    logic [VRF_BNK_W-1:0] vaddr_bank_q,vaddr_bank_n; logic [VRF_IDX_W-1:0] vaddr_idx_q,vaddr_idx_n;

    // ── State Machine ───────────────────────────────────────────────────────
    typedef enum logic [6:0] {
        S_IDLE, S_EXEC, S_VWR_WAIT, S_RD_WAIT, S_RD_CAPTURE, S_RESULT, S_CLR, S_CLR_DRAIN,
        S_HSIM_INIT, S_HMATCH_INIT, S_HPERM_LANE64,
        S_UOP_P1_RD0, S_UOP_P1_RD0_WAIT, S_UOP_P1_RD1, S_UOP_P1_RD1_WAIT,
        S_UOP_P2_LANE, S_UOP_P3_GLOBAL, S_UOP_P3_POP_CAPTURE, S_UOP_P3_VRF_WAIT, S_UOP_P3_ACCUM, S_UOP_P4_RESP,
        S_UOP_CLIP_WRITE,
        S_ECC_LOAD_A_WAIT, S_ECC_LOAD_A, S_ECC_LOAD_B_WAIT, S_ECC_LOAD_B,
        S_ECC_DIAG_ISSUE, S_ECC_DIAG_CAPTURE0, S_ECC_DIAG_CAPTURE1,
        S_ECC_DIAG_CAPTURE2, S_ECC_DIAG_FOLD_ISSUE,
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
    logic [3:0] hmatch_req_base;
    logic [3:0] hmatch_req_count_lo;
    logic [3:0] hmatch_req_max_count;
    logic       hmatch_req_invalid;

    // ── HPERM registers ─────────────────────────────────────────────────────
    logic [1:0] hperm_bit_low_q,hperm_bit_low_n;
    logic hperm_spread_q,hperm_spread_n;
    logic [1:0] hperm_lane_base_q,hperm_lane_base_n;

    // ── HCNTCLIP registers ──────────────────────────────────────────────────
    logic [VRF_IDX_W-1:0] hcntclip_dst_base_q,hcntclip_dst_base_n,hcntclip_acc_base;
    logic [VRF_IDX_W-1:0] hdc_cnt_base0, hdc_cnt_base1;
    logic interleave_active;
    logic hcntclip_acc_sel_q,hcntclip_acc_sel_n;
    logic [1:0] hcntclip_chunk_q,hcntclip_chunk_n;
    // hcntclip_acc_base selects the active counter bank; per-entry addresses are
    // formed locally in the uop stages.

    // ── UOP Pipeline Registers ──────────────────────────────────────────────
    // P0: decode + uop issue
    // P1: VRF read address / read wait (uop stays in P0 until the second read)
    // P2: VRF read data (vrf_rd) directly feeds Lane local compute
    // P2/P3 boundary: lane_*_q registers cut the critical combinational path
    hdec_uop_t uop_p0_q, uop_p0_n, uop_p3_q, uop_p3_n;

    // ── Lane compute wires ──────────────────────────────────────────────────
    logic                                hdc_pop_product_issue, hdc_pop_capture, hdc_xor_issue;
    logic                                uop_p0_use_counter, uop_p0_use_shift, uop_p0_use_clip;
    logic                                uop_p0_use_paired_sources;
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
    logic [31:0]          ecc_leaf_a_q, ecc_leaf_a_n;
    logic [31:0]          ecc_leaf_b_q, ecc_leaf_b_n;
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
    logic [127:0]         ecc_sub32_capture_accum_xor1;
    logic                 ecc_diag_product_issue;
    logic                 ecc_diag_fold_preissue;
    logic                 ecc_diag_leaf_preissue;
    logic                 ecc_diag_early_b_load;
    logic                 ecc_pmul_add_t1_prefetch;
    logic                 ecc_pmul_add_t2_prefetch;
    logic                 ecc_xor1_diag_mode;
    logic                 ecc_diag_sub_shadow_mode;
    logic                 ecc_kernel_token_fold_mode;
    logic                 ecc_kernel_token_acc_cycle;
    logic                 ecc_diag_next_leaf_a_capture;
    logic                 ecc_diag_next_leaf_b_capture;
    logic [31:0]          ecc_leaf_b_unreversed;
    logic [15:0]          ecc_bitmatrix_src_a;
    logic [15:0]          ecc_bitmatrix_src_b;
    logic [31:0]          ecc_bitmatrix_product;
    logic                                ecc_autoreduce_fast;
    logic [3:0]           ecc_leaf_path_q, ecc_leaf_path_n;
    logic [3:0]           ecc_next_leaf_path;
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
    typedef enum logic [2:0] {
        ECC_PHASE_NONE          = 3'd0,
        ECC_PHASE_INV_SQR       = 3'd1,
        ECC_PHASE_INV_MUL       = 3'd2,
        ECC_PHASE_INV_COPY_INIT = 3'd3,
        ECC_PHASE_INV_COPY_TMP  = 3'd4,
        ECC_PHASE_PMUL_FIELD    = 3'd5,
        ECC_PHASE_PMUL_ADD      = 3'd6,
        ECC_PHASE_PMUL_COPY     = 3'd7
    } ecc_job_phase_e;
    typedef enum logic [2:0] {
        ECC_PMUL_SUB_NONE       = 3'd0,
        ECC_PMUL_SUB_INIT       = 3'd1,
        ECC_PMUL_SUB_ADD        = 3'd2,
        ECC_PMUL_SUB_DBL        = 3'd3,
        ECC_PMUL_SUB_AFFINE     = 3'd4,
        ECC_PMUL_SUB_ZERO_OUT   = 3'd5
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
    ecc_pmul_subop_e ecc_pmul_subop_q, ecc_pmul_subop_n;
    logic [4:0]         ecc_pmul_step_q, ecc_pmul_step_n;
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
    logic                 ecc_pmul_add_step5_complete;
    logic                 ecc_pmul_add_continuation;
    logic                 affine_field_active;
    logic                 ecc_pmul_residue_seed_one;
    logic                 ecc_pmul_residue_seed_vrf;

    // A two-bit lifetime tag is sufficient for the fixed HSIM/HMATCH path:
    // the deferred ECC square read is issued after the second HDC source read,
    // then committed at the later popcount-capture state.  No wide operand or
    // result buffer is added.
    localparam logic [1:0] VV33_SQ_IDLE    = 2'd0;
    localparam logic [1:0] VV33_SQ_PENDING = 2'd1;
    localparam logic [1:0] VV33_SQ_ISSUED  = 2'd2;
    localparam logic [1:0] VV33_SQ_DONE    = 2'd3;
    logic [1:0]           vv33_sq_phase_q, vv33_sq_phase_n;
    logic                 vv33_sq_defer_fire;
    logic                 vv33_sq_read_fire;
    logic                 vv33_sq_write_fire;
    logic                 vv33_sq_commit_q, vv33_sq_commit_n;
    logic                 vv33_hdc_request_valid;
    logic                 vv33_hdc_square_overlap;

    // Paired-return HMATCH sidecar.  Only narrow traversal and score state is
    // retained.  The two 256-bit operands remain in the VRF raw/output return
    // stages and enter the existing bit matrix for one CAP2 cycle.
    logic                 vv33_pair_active_q, vv33_pair_active_n;
    logic                 vv33_pair_a_sent_q, vv33_pair_a_sent_n;
    logic                 vv33_pair_next_q, vv33_pair_next_n;
    logic                 vv33_pair_read_ready_q, vv33_pair_read_ready_n;
    logic                 vv33_pair_product_q, vv33_pair_product_n;
    logic                 vv33_pair_pop_q, vv33_pair_pop_n;
    logic                 vv33_pair_sum_q, vv33_pair_sum_n;
    logic                 vv33_pair_finish_q, vv33_pair_finish_n;
    logic                 vv33_pair_resp_q, vv33_pair_resp_n;
    logic [1:0]           vv33_pair_class_idx_q, vv33_pair_class_idx_n;
    logic [1:0]           vv33_pair_chunk_q, vv33_pair_chunk_n;
    logic [10:0]          vv33_pair_total_q, vv33_pair_total_n;
    logic [10:0]          vv33_pair_best_q, vv33_pair_best_n;
    logic [1:0]           vv33_pair_best_idx_q, vv33_pair_best_idx_n;
    logic                 vv33_pair_start;
    logic                 vv33_pair_product_fire;
    logic                 vv33_pair_pop_fire;
    logic                 vv33_pair_fold_launch;
    logic                 vv33_pair_has_next;
    logic [1:0]           vv33_pair_next_chunk;
    logic [1:0]           vv33_pair_next_class_idx;
    logic [5:0]           vv33_pair_src_a_addr;
    logic [5:0]           vv33_pair_src_b_addr;
    logic [5:0]           vv33_pair_next_src_a_addr;
    logic [5:0]           vv33_pair_next_src_b_addr;
    logic [10:0]          vv33_pair_score;
    logic                 vv33_hinfer_pair_launch;
    logic                 vv33_hinfer_active;
    logic                 vv33_hinfer_request;
    logic                 vv33_hinfer_invalid;
    logic                 vv33_hinfer_field_ready;
    logic                 vv33_hinfer_field_accept;
    logic                 vv33_hinfer_pending_q, vv33_hinfer_pending_n;
    logic [9:0]           vv33_hinfer_rot_q, vv33_hinfer_rot_n;
    logic                 vv33_hinfer_resume_step_q, vv33_hinfer_resume_step_n;
`ifndef SYNTHESIS
    // Stable observation alias retained for the VV33 full-inference monitor.
    // The fixed resident path accepts a paired search exactly when it launches
    // at the first compatible diagonal slot.
    logic                 vv33_pair_accept;
`endif

    // The interleaved inference macro uses a compile-time resident partition.
    // Fixing these bases removes a runtime wide address-selection cone while
    // ordinary programmable HPERM, HBIND, and HMATCH remain unchanged.
    localparam logic [5:0] VV33_HINFER_ROLE_BASE  = 6'd8;
    localparam logic [5:0] VV33_HINFER_QUERY_BASE = 6'd12;
    localparam logic [5:0] VV33_HINFER_PROTO_BASE = 6'd16;
    localparam logic [5:0] VV33_HINFER_INPUT_BASE = 6'd28;
    localparam logic [2:0] VV33_HINFER_LAST_CLASS = 3'd2;

    // ── Combinational helpers ───────────────────────────────────────────────
    // Capture the counter-bank epoch when HCNTCLR starts.  A background PMUL
    // may complete before the later HCNTADD/HCNTCLIP requests arrive, so the
    // live ECC-busy flag cannot safely select their bank.
    assign interleave_active = hcntclip_dst_base_q[5];
    assign hdc_cnt_base0 = interleave_active ? 6'd16 : 6'd32;
    assign hdc_cnt_base1 = interleave_active ? 6'd24 : 6'd48;
    assign hcntclip_acc_base = hcntclip_acc_sel_q ? hdc_cnt_base1 : hdc_cnt_base0;
    assign hmatch_req_base = a_q[7:4];
    assign hmatch_req_count_lo = a_q[11:8];
    assign hmatch_req_max_count = 4'd8 - hmatch_req_base;
    assign hmatch_req_invalid = (a_q[15:8] == 8'd0) || (|a_q[15:12])
                              || hmatch_req_base[3]
                              || (hmatch_req_count_lo > hmatch_req_max_count);
    assign vv33_hdc_request_valid = valid_i
                                  && (operator_i >= HDEC_HCLR)
                                  && (operator_i <= HDEC_HMATCH);
    assign vv33_hinfer_request = (operator_i == HDEC_HMATCH)
                               && operand_a_i[63];
    assign vv33_hinfer_active = vv33_hinfer_pending_q;
    assign vv33_hdc_square_overlap = (operator_i == HDEC_HBIND)
                                    || (operator_i == HDEC_HSIM)
                                    || ((operator_i == HDEC_HMATCH)
                                     && !operand_a_i[63]);
    assign vv33_hinfer_invalid = (|vv33_hinfer_rot_q[1:0])
                               || (ecc_job_active_q
                                && (ecc_job_kind_q != ECC_JOB_PMUL));
    // One narrow pending bit retains the encoded inference after the descriptor
    // is released. Its paired context is initialized only at the existing
    // first-diagonal entry, preserving a single write point for all pair state.
    assign vv33_hinfer_pair_launch = vv33_hinfer_pending_q
                                   && VV33_PAIRED_HMATCH
                                   && VV31_SCHED_ENABLE
                                   && ecc_diag_sub_shadow_mode
                                   && !vv33_pair_active_q
                                   && !vv33_pair_resp_q
                                   && (vv33_sq_phase_q == VV33_SQ_IDLE)
                                   && ecc_job_bg_q
                                   && ecc_job_active_q
                                   && (ecc_job_phase_q == ECC_PHASE_PMUL_FIELD)
                                   && (st_q == S_ECC_DIAG_ISSUE)
                                   && (ecc_leaf_path_q == 4'b00_00)
                                   && (ecc_kpd64_sub_q == 2'd0);
    // A completed field product has already committed its 233-bit residue to
    // the VRF.  At this point hdc_src0_q and the shared payload no longer carry
    // live field state, so a fused HDC job can borrow the complete shared path
    // without a 233-bit checkpoint or a second compute core.
    assign vv33_hinfer_field_ready = valid_i
                                   && vv33_hinfer_request
                                   && !ECC_DEBUG_FIELD_OPS
                                   && !(|operand_a_i[9:8])
                                   && VV33_FINE_INTERLEAVE
                                   && !vv33_hinfer_active
                                   && !vv33_pair_active_q
                                   && !vv33_pair_resp_q
                                   && ecc_job_bg_q
                                   && ecc_job_active_q
                                   && (ecc_job_kind_q == ECC_JOB_PMUL)
                                   && (ecc_job_phase_q == ECC_PHASE_PMUL_FIELD)
                                   && (((st_q == S_ECC_WRITE_PAIR)
                                     && ecc_autoreduce_q
                                     && !ecc_pmul_add_t1_prefetch
                                     && !ecc_pmul_residue_seed_one)
                                    || (st_q == S_ECC_WRITE_DRAIN));
    assign vv33_hinfer_field_accept = valid_i && vv33_hinfer_field_ready;
    assign vv33_pair_start = vv33_hinfer_pair_launch;
`ifndef SYNTHESIS
    assign vv33_pair_accept = vv33_hinfer_pair_launch;
`endif
    assign vv33_pair_product_fire = vv33_pair_active_q
                                  && vv33_pair_read_ready_q
                                  && (st_q == S_ECC_DIAG_CAPTURE2);
    assign vv33_pair_pop_fire = vv33_pair_active_q
                              && vv33_pair_product_q
                              && (st_q == S_ECC_DIAG_FOLD_ISSUE);
    assign vv33_pair_has_next = !((vv33_pair_class_idx_q == 2'd2)
                               && (vv33_pair_chunk_q == 2'd3));
    assign vv33_pair_next_chunk = (vv33_pair_chunk_q == 2'd3)
                                ? 2'd0 : (vv33_pair_chunk_q + 2'd1);
    assign vv33_pair_next_class_idx = (vv33_pair_chunk_q == 2'd3)
                                    ? (vv33_pair_class_idx_q + 2'd1)
                                    : vv33_pair_class_idx_q;
    assign vv33_pair_src_a_addr = {4'b0011, vv33_pair_chunk_q};
    assign vv33_pair_src_b_addr = {2'b01, vv33_pair_class_idx_q,
                                   vv33_pair_chunk_q};
    assign vv33_pair_next_src_a_addr = {4'b0011, vv33_pair_next_chunk};
    assign vv33_pair_next_src_b_addr = {2'b01, vv33_pair_next_class_idx,
                                        vv33_pair_next_chunk};
    assign vv33_pair_score = vv33_pair_total_q + {2'b00, group_dist_q};
    // Only folds that already launch a following CAP0 and do not consume the
    // VRF read port for next-leaf A are paired-read launch points.
    assign vv33_pair_fold_launch = vv33_pair_active_q
                                 && (st_q == S_ECC_DIAG_FOLD_ISSUE)
                                 && (((ecc_kpd64_sub_q == 2'd0)
                                   && ecc_diag_fold_preissue)
                                  || ((ecc_kpd64_sub_q == 2'd2)
                                   && ecc_diag_leaf_preissue))
                                 && ((vv33_pair_product_q && vv33_pair_has_next)
                                  || (!vv33_pair_product_q
                                   && !vv33_pair_pop_q
                                   && !vv33_pair_a_sent_q
                                   && !vv33_pair_read_ready_q));
    assign hsim_total_step = hsim_total_q + {2'b00, group_dist_q};
    assign hdc_pop_product_issue = (st_q == S_UOP_P1_RD1)
                                 && uop_p0_q.valid
                                 && uop_p0_use_paired_sources;
    assign hdc_pop_capture = (st_q == S_UOP_P3_GLOBAL)
                          && ((uop_p3_q.op_type == UOP_HSIM_CHUNK)
                           || (uop_p3_q.op_type == UOP_HMATCH_CHUNK));
    assign hdc_xor_issue = (st_q == S_UOP_P2_LANE) && uop_p0_q.valid
                         && (uop_p0_q.op_type == UOP_HBIND_CHUNK);
    assign uop_p0_use_counter = (uop_p0_q.op_type == UOP_HCNTADD_SUBGROUP);
    assign uop_p0_use_shift   = (uop_p0_q.op_type == UOP_HPERM_CHUNK);
    assign uop_p0_use_clip    = (uop_p0_q.op_type == UOP_HCNTCLIP_READ);
    assign uop_p0_use_paired_sources = (uop_p0_q.op_type == UOP_HSIM_CHUNK)
                                     || (uop_p0_q.op_type == UOP_HMATCH_CHUNK);
    assign ecc_next_leaf_path = ecc_kpd64_path_inc(ecc_leaf_path_q);
    // The legacy schedule captures next A at group2 completion and next B in
    // the following fold. VV31 preserves A's original capture point, but
    // returns B one cycle earlier after group2 has consumed the old operands.
    assign ecc_diag_next_leaf_a_capture = ecc_diag_sub_shadow_mode
                                        && (st_q == S_ECC_DIAG_CAPTURE2)
                                        && (ecc_kpd64_sub_q == 2'd2)
                                        && !ecc_leaf_last;
    assign ecc_diag_next_leaf_b_capture = ecc_diag_sub_shadow_mode
                                        && (ecc_kpd64_sub_q == 2'd2)
                                        && !ecc_leaf_last
                                        && ((!VV31_SCHED_ENABLE
                                             && (st_q == S_ECC_DIAG_FOLD_ISSUE))
                                         || (VV31_SCHED_ENABLE
                                             && (st_q == S_ECC_DIAG_CAPTURE1)));
    assign ecc_leaf_read_path = ((st_q == S_ECC_LEAF_FOLD)
                               || ecc_diag_next_leaf_a_capture
                               || ecc_diag_next_leaf_b_capture)
                               ? ecc_next_leaf_path[3:0] : ecc_leaf_path_q[3:0];
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
    assign ecc_pmul_add_step5_complete =
        !ECC_DEBUG_FIELD_OPS
        && ecc_job_active_q
        && (ecc_job_phase_q == ECC_PHASE_PMUL_FIELD)
        && (ecc_pmul_subop_q == ECC_PMUL_SUB_ADD)
        && (ecc_pmul_step_q == 5'd5);
    assign ecc_pmul_add_continuation =
        !ECC_DEBUG_FIELD_OPS
        && ecc_job_active_q
        && (ecc_job_phase_q == ECC_PHASE_PMUL_FIELD)
        && (ecc_pmul_subop_q == ECC_PMUL_SUB_ADD)
        && (ecc_pmul_step_q == 5'd7);
    // T0 and T1 have disjoint input dependencies.  While T0 uses the VRF write
    // port, start T1's first operand read on the independent read port and
    // enter the existing load pipeline without STEP_NEXT/PMUL_STEP bubbles.
    assign ecc_pmul_add_t1_prefetch =
        VV31_SCHED_ENABLE
        && !ECC_DEBUG_FIELD_OPS
        && (ecc_pmul_subop_q == ECC_PMUL_SUB_ADD)
        && (ecc_pmul_step_q == 5'd0);
    // Q(T4) only consumes T4, whereas the following T2 multiply consumes the
    // selected point-coordinate pair.  Use the two square-read wait slots for
    // those independent A/B reads, then enter the canonical leaf load path.
    assign ecc_pmul_add_t2_prefetch =
        VV31_SCHED_ENABLE
        && !ECC_DEBUG_FIELD_OPS
        && ecc_job_active_q
        && (ecc_job_phase_q == ECC_PHASE_PMUL_FIELD)
        && (ecc_pmul_subop_q == ECC_PMUL_SUB_ADD)
        && (ecc_pmul_step_q == 5'd3);
    assign affine_field_active =
        ECC_PMUL_RESIDUE_SEED_ACTIVE
        && ecc_job_active_q
        && (ecc_job_phase_q == ECC_PHASE_PMUL_FIELD)
        && (ecc_pmul_subop_q == ECC_PMUL_SUB_AFFINE);
    assign ecc_pmul_residue_seed_one =
        affine_field_active
        && (ecc_pmul_step_q == 5'd14);
    assign ecc_pmul_residue_seed_vrf =
        affine_field_active
        && (ecc_pmul_step_q == 5'd18);
    assign ecc_pmul_const_one_from_dst = (ecc_dst_q == ECC_PMUL_R0X)
                                      || (ecc_dst_q == ECC_PMUL_R1Z)
                                      || (ecc_dst_q == ECC_PMUL_T9);
    assign ecc_autoreduce_fast = ecc_autoreduce_q && !ECC_DEBUG_FIELD_OPS;
    assign ecc_kernel_token_fold_mode = !ECC_DEBUG_FIELD_OPS;
    assign ecc_diag_sub_shadow_mode = ecc_autoreduce_fast;
    assign ecc_kernel_token_acc_cycle =
        ecc_kernel_token_fold_mode
        && ecc_autoreduce_q
        && (((st_q == S_ECC_DIAG_CAPTURE1)
             || (st_q == S_ECC_DIAG_CAPTURE2))
            || (st_q == S_ECC_DIAG_FOLD_ISSUE));
    // The fourteen diagonal equations occupy middle-XOR nodes, leaving the
    // native leaf low-XOR nodes live during group2.  Sub0 and sub1 can hand
    // their next operands to the existing leaf registers before group3, where
    // the otherwise-idle shared AND preissues the next group0 matrix.
    assign ecc_diag_fold_preissue =
        (st_q == S_ECC_DIAG_FOLD_ISSUE)
        && ecc_diag_sub_shadow_mode
        && (ecc_kpd64_sub_q < 2'd2);
    // At the final sub-product fold, both next-leaf operands have already
    // replaced dead current-leaf register values. XOR0 folds the current
    // token, leaving the shared bit matrix free to launch next group0.
    assign ecc_diag_leaf_preissue =
        VV31_SCHED_ENABLE
        && (st_q == S_ECC_DIAG_FOLD_ISSUE)
        && ecc_diag_sub_shadow_mode
        && (ecc_kpd64_sub_q == 2'd2)
        && !ecc_leaf_last;
    // The PMUL residue-seed read is the only autoreduced multiply that still
    // needs the LOAD_A_WAIT read slot. All other field multiplies can move B
    // into that slot and have both first-leaf operands registered by LOAD_B.
    assign ecc_diag_early_b_load =
        VV31_SCHED_ENABLE
        && ecc_autoreduce_fast
        && !ecc_mac_q
        && !ecc_pmul_residue_seed_vrf;
    assign ecc_diag_product_issue =
        (st_q == S_ECC_DIAG_ISSUE)
        || (st_q == S_ECC_DIAG_CAPTURE0)
        || (st_q == S_ECC_DIAG_CAPTURE1)
        || ecc_diag_fold_preissue
        || ecc_diag_leaf_preissue;
    assign ecc_xor1_diag_mode = (st_q == S_ECC_DIAG_CAPTURE0)
                              || (st_q == S_ECC_DIAG_CAPTURE1)
                              || (st_q == S_ECC_DIAG_CAPTURE2);
    assign ecc_leaf_b_unreversed = ecc_bitrev32_top(ecc_leaf_b_q);

    always_comb begin
        // ISSUE and FOLD launch group0.  CAP0 and CAP1 overlap the next two
        // fixed matrix groups without a group register or incrementer.
        ecc_bitmatrix_src_a = ecc_leaf_a_q[15:0];
        ecc_bitmatrix_src_b = ecc_leaf_b_unreversed[15:0];
        unique case (st_q)
            S_ECC_DIAG_CAPTURE0: begin
                ecc_bitmatrix_src_a = ecc_leaf_a_q[31:16];
                ecc_bitmatrix_src_b = ecc_leaf_b_unreversed[31:16];
            end
            S_ECC_DIAG_CAPTURE1: begin
                ecc_bitmatrix_src_a = ecc_leaf_a_q[15:0] ^ ecc_leaf_a_q[31:16];
                ecc_bitmatrix_src_b = ecc_leaf_b_unreversed[15:0]
                                    ^ ecc_leaf_b_unreversed[31:16];
            end
            default: begin
            end
        endcase
    end

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
                                                 input logic [4:0] step);
        unique case (subop)
            ECC_PMUL_SUB_INIT:       ecc_pmul_subop_last = (step == 5'd3);
            ECC_PMUL_SUB_ADD: begin
                ecc_pmul_subop_last = ECC_PMUL_ADD_Z_FORWARD
                                    ? (step == 5'd7) : (step == 5'd8);
            end
            ECC_PMUL_SUB_DBL: begin
                ecc_pmul_subop_last = ECC_PMUL_DBL_FROBENIUS
                                    ? (step == 5'd2) : (step == 5'd5);
            end
            ECC_PMUL_SUB_AFFINE:     ecc_pmul_subop_last = (step == 5'd26);
            ECC_PMUL_SUB_ZERO_OUT:   ecc_pmul_subop_last = (step == 5'd1);
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

    function automatic logic [3:0] ecc_leaf_bank_mask(input logic [3:0] path);
        begin
            unique case (path)
                4'b00_00: ecc_leaf_bank_mask = 4'b0001;
                4'b00_01: ecc_leaf_bank_mask = 4'b0011;
                4'b00_10: ecc_leaf_bank_mask = 4'b0010;
                4'b01_00: ecc_leaf_bank_mask = 4'b0101;
                4'b01_01: ecc_leaf_bank_mask = 4'b1111;
                4'b01_10: ecc_leaf_bank_mask = 4'b1010;
                4'b10_00: ecc_leaf_bank_mask = 4'b0100;
                4'b10_01: ecc_leaf_bank_mask = 4'b1100;
                4'b10_10: ecc_leaf_bank_mask = 4'b1000;
                default:  ecc_leaf_bank_mask = 4'b1111;
            endcase
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
        logic outer_zero;
        logic outer_two;
        logic outer_valid;
        logic inner_zero;
        logic inner_two;
        logic inner_valid;
        logic [6:0] shifted_template;
        begin
            outer_zero  = (path[3:2] == 2'd0);
            outer_two   = (path[3:2] == 2'd2);
            outer_valid = (path[3:2] != 2'd3);
            inner_zero  = (path[1:0] == 2'd0);
            inner_two   = (path[1:0] == 2'd2);
            inner_valid = (path[1:0] != 2'd3);

            // The four canonical templates F, 5, 3 and 1 are placed by
            // offsets {outer!=0, inner!=0}.  These seven equations are the
            // static expansion of that template-and-offset relation, avoiding
            // a variable shifter while keeping invalid path encodings at zero.
            shifted_template[0] = outer_zero  && inner_zero;
            shifted_template[1] = outer_zero  && inner_valid;
            shifted_template[2] = (inner_zero && outer_valid)
                                || (outer_zero && inner_two);
            shifted_template[3] = outer_valid && inner_valid;
            shifted_template[4] = (inner_two  && outer_valid)
                                || (outer_two  && inner_zero);
            shifted_template[5] = outer_two   && inner_valid;
            shifted_template[6] = outer_two   && inner_two;

            ecc_kpd64_leaf_offset_mask = shifted_template;
        end
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

    function automatic logic [63:0] ecc_diag16_karatsuba_token(
        input logic [2:0]  kernel_idx,
        input logic [31:0] kernel_product
    );
        logic [63:0] middle_shift;
        begin
            middle_shift = {16'b0, kernel_product, 16'b0};
            unique case (kernel_idx)
                3'd0: ecc_diag16_karatsuba_token = {32'b0, kernel_product}
                                                       ^ middle_shift;
                3'd1: ecc_diag16_karatsuba_token = {kernel_product, 32'b0}
                                                       ^ middle_shift;
                default: ecc_diag16_karatsuba_token = middle_shift;
            endcase
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

    function automatic logic [127:0] ecc_kpd64_sub32_delta(
        input logic [1:0]   sub_idx,
        input logic [63:0]  sub_product
    );
        logic [31:0] sub_lo;
        logic [31:0] sub_hi;
        begin
            sub_lo = sub_product[31:0];
            sub_hi = sub_product[63:32];
            unique case (sub_idx)
                2'd0: ecc_kpd64_sub32_delta = {32'b0, sub_hi, sub_hi ^ sub_lo, sub_lo};
                2'd1: ecc_kpd64_sub32_delta = {sub_hi, sub_hi ^ sub_lo, sub_lo, 32'b0};
                2'd2: ecc_kpd64_sub32_delta = {32'b0, sub_hi, sub_lo, 32'b0};
                default: ecc_kpd64_sub32_delta = '0;
            endcase
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

    function automatic logic [LANE_NUM-1:0][LANE_WIDTH-1:0] ecc_kpd64_leaf_reduce_packet_halves(
        input logic [6:0]  mask,
        input logic [63:0] leaf_lo,
        input logic [63:0] leaf_hi
    );
        logic [7:0]                                mask_ext;
        logic [7:0][63:0]                         global_word;
        logic [LANE_NUM-1:0][LANE_WIDTH-1:0] packet;
        begin
            mask_ext = {1'b0, mask};
            for (int unsigned word_idx = 0; word_idx < 8; word_idx++) begin
                global_word[word_idx] = '0;
                if (mask_ext[word_idx])
                    global_word[word_idx] ^= leaf_lo;
                if ((word_idx != 0) && mask_ext[word_idx - 1])
                    global_word[word_idx] ^= leaf_hi;
            end

            packet[0] = global_word[0]
                      ^ {41'b0, global_word[3][63:41]}
                      ^ {global_word[4][40:0], 23'b0}
                      ^ {global_word[7][7:0], global_word[6][63:8]}
                      ^ {18'b0, global_word[7][63:18]};
            packet[1] = global_word[1]
                      ^ {31'b0, global_word[3][63:41], 10'b0}
                      ^ {global_word[5][40:0], global_word[4][63:41]}
                      ^ {global_word[4][30:0], 33'b0}
                      ^ {global_word[6][61:8], global_word[7][17:8]};
            packet[2] = global_word[2]
                      ^ {41'b0, global_word[5][63:41]}
                      ^ {global_word[5][30:0], global_word[4][63:31]}
                      ^ {global_word[6][40:0], 23'b0}
                      ^ {global_word[7][61:0], global_word[6][63:62]};
            packet[3] = {23'b0, global_word[3][40:0]}
                      ^ {31'b0, global_word[5][63:31]}
                      ^ {23'b0, ({global_word[7][17:0],
                                  global_word[6][63:41]}
                               ^ {global_word[6][7:0], 33'b0}
                               ^ {39'b0, global_word[7][63:62]})};
            ecc_kpd64_leaf_reduce_packet_halves = packet;
        end
    endfunction

    function automatic logic [LANE_NUM-1:0][LANE_WIDTH-1:0] ecc_kpd64_leaf_reduce_packet(
        input logic [6:0]   mask,
        input logic [127:0] leaf_product
    );
        begin
            ecc_kpd64_leaf_reduce_packet = ecc_kpd64_leaf_reduce_packet_halves(
                mask, leaf_product[63:0], leaf_product[127:64]
            );
        end
    endfunction

    function automatic logic [LANE_NUM-1:0][LANE_WIDTH-1:0] ecc_kpd64_subproduct_reduce_packet(
        input logic [6:0]  mask,
        input logic [1:0]  sub_idx,
        input logic [63:0] sub_product
    );
        logic [31:0] sub_lo;
        logic [31:0] sub_hi;
        logic [63:0] leaf_lo;
        logic [63:0] leaf_hi;
        begin
            sub_lo = sub_product[31:0];
            sub_hi = sub_product[63:32];
            leaf_lo = '0;
            leaf_hi = '0;
            unique case (sub_idx)
                2'd0: begin
                    leaf_lo = {sub_hi ^ sub_lo, sub_lo};
                    leaf_hi = {32'b0, sub_hi};
                end
                2'd1: begin
                    leaf_lo = {sub_lo, 32'b0};
                    leaf_hi = {sub_hi, sub_hi ^ sub_lo};
                end
                2'd2: begin
                    leaf_lo = {sub_lo, 32'b0};
                    leaf_hi = {32'b0, sub_hi};
                end
                default: begin
                end
            endcase
            ecc_kpd64_subproduct_reduce_packet =
                ecc_kpd64_leaf_reduce_packet_halves(mask, leaf_lo, leaf_hi);
        end
    endfunction

    function automatic logic [LANE_NUM-1:0][LANE_WIDTH-1:0] ecc_kpd64_diagonal_onehot_reduce_packet(
        input logic [6:0]  mask,
        input logic [1:0]  sub_idx,
        input logic        group0_en,
        input logic        group1_en,
        input logic [30:0] diagonal
    );
        logic [31:0] diagonal32;
        logic [63:0] group_product;
        begin
            diagonal32 = {1'b0, diagonal};
            group_product = {16'b0, diagonal32, 16'b0};
            if (group0_en)
                group_product ^= {32'b0, diagonal32};
            if (group1_en)
                group_product ^= {diagonal32, 32'b0};
            ecc_kpd64_diagonal_onehot_reduce_packet =
                ecc_kpd64_subproduct_reduce_packet(
                    mask, sub_idx, group_product
                );
        end
    endfunction

    function automatic logic [LANE_NUM-1:0][LANE_WIDTH-1:0] ecc_kpd64_diagonal_reduce_packet(
        input logic [6:0]  mask,
        input logic [1:0]  sub_idx,
        input logic [1:0]  group_idx,
        input logic [30:0] diagonal
    );
        begin
            ecc_kpd64_diagonal_reduce_packet =
                ecc_kpd64_diagonal_onehot_reduce_packet(
                    mask,
                    sub_idx,
                    group_idx == 2'd0,
                    group_idx == 2'd1,
                    diagonal
                );
        end
    endfunction

    // synthesis translate_off
    function automatic logic [15:0] ecc_diag16_operand_ref(
        input logic [31:0] word,
        input logic [2:0]  kernel_idx
    );
        unique case (kernel_idx)
            3'd0: ecc_diag16_operand_ref = word[15:0];
            3'd1: ecc_diag16_operand_ref = word[31:16];
            default: ecc_diag16_operand_ref = word[15:0] ^ word[31:16];
        endcase
    endfunction

    function automatic logic [31:0] ecc_clmul16_ref(
        input logic [15:0] operand_a,
        input logic [15:0] operand_b
    );
        logic [31:0] product;
        begin
            product = '0;
            for (int bit_idx = 0; bit_idx < 16; bit_idx++) begin
                if (operand_b[bit_idx])
                    product ^= ({16'b0, operand_a} << bit_idx);
            end
            ecc_clmul16_ref = product;
        end
    endfunction

    logic [2:0] ecc_diag_assert_group;
    always_comb begin
        unique case (st_q)
            S_ECC_DIAG_CAPTURE1: ecc_diag_assert_group = 3'd1;
            S_ECC_DIAG_CAPTURE2: ecc_diag_assert_group = 3'd2;
            default:             ecc_diag_assert_group = 3'd0;
        endcase
    end

    always_ff @(posedge clk_i) begin
        if (rst_ni && ((st_q == S_ECC_DIAG_CAPTURE0)
                    || (st_q == S_ECC_DIAG_CAPTURE1)
                    || (st_q == S_ECC_DIAG_CAPTURE2))
            && !(VV31_SCHED_ENABLE && ecc_diag_next_leaf_a_capture)) begin
            if (ecc_bitmatrix_product !== ecc_clmul16_ref(
                    ecc_diag16_operand_ref(ecc_leaf_a_q, ecc_diag_assert_group),
                    ecc_diag16_operand_ref(ecc_leaf_b_unreversed,
                                           ecc_diag_assert_group))) begin
                $error("VV23 shared matrix kernel mismatch sub=%0d kernel=%0d got=%h",
                       ecc_kpd64_sub_q, ecc_diag_assert_group,
                       ecc_bitmatrix_product);
            end
        end
        if (rst_ni && (st_q == S_ECC_DIAG_FOLD_ISSUE)) begin
            if (ecc_diag_product_issue
                !== (ecc_diag_fold_preissue || ecc_diag_leaf_preissue))
                $error("VV25 fold preissue enable mismatch");
            if (ecc_diag_fold_preissue
                && ((ecc_bitmatrix_src_a !== ecc_leaf_a_q[15:0])
                    || (ecc_bitmatrix_src_b !== ecc_leaf_b_unreversed[15:0])))
                $error("VV25 fold did not preissue group0");
            if (ecc_diag_leaf_preissue
                && ((ecc_bitmatrix_src_a !== ecc_leaf_a_q[15:0])
                    || (ecc_bitmatrix_src_b !== ecc_leaf_b_unreversed[15:0])))
                $error("VV31 next-leaf registered preissue mismatch");
            if ((ecc_diag_fold_preissue || ecc_diag_leaf_preissue)
                && (st_n != S_ECC_DIAG_CAPTURE0))
                $error("VV25 fold preissue did not advance to capture");
            if (ecc_leaf_a_lowxor_xor1 !== (ecc_leaf_a_q ^ ecc_leaf_xor_a_q))
                $error("VV25 XOR1 changed VV22 leaf-A lowxor behavior");
            if (ecc_leaf_b_lowxor_xor1 !== (ecc_leaf_b_q ^ ecc_leaf_xor_b_q))
                $error("VV25 XOR1 changed VV22 leaf-B lowxor behavior");
            if (!ecc_kernel_token_fold_mode
                && (ecc_sub32_capture_accum_xor1 !== ecc_kpd64_sub32_accum(
                        ecc_leaf128_prod_q, ecc_kpd64_sub_q, ecc_leaf_prod_q))) begin
                $error("VV25 XOR1 changed VV22 sub32 fold behavior sub=%0d",
                        ecc_kpd64_sub_q);
            end
        end
    end
    // synthesis translate_on

    assign ecc_direct_reduce_word = ECC_DEBUG_FIELD_OPS
        ? ecc_kpd64_leaf_reduce_packet(
              ecc_leaf64_offset_mask, ecc_leaf128_prod_q
          )
        : ecc_kpd64_diagonal_onehot_reduce_packet(
              ecc_leaf64_offset_mask,
              ecc_kpd64_sub_q,
              st_q == S_ECC_DIAG_CAPTURE1,
              st_q == S_ECC_DIAG_CAPTURE2,
              ecc_leaf_prod_q[30:0]
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
        .payload_product_i(hdc_pop_product_issue || ecc_diag_product_issue
                         || vv33_pair_product_fire),
        .payload_pop_i(hdc_pop_capture || vv33_pair_pop_fire),
        .payload_bitband_i(ecc_diag_product_issue),
        .payload_cnt_i((st_q == S_UOP_P2_LANE) && uop_p0_q.valid && uop_p0_use_counter),
        .payload_clip_i((st_q == S_UOP_P2_LANE) && uop_p0_q.valid && uop_p0_use_clip),
        .hperm_we_i(hperm_lane_we),
        // During the overlapped HPERM phase slot_q names the window being
        // prepared, while the registered previous window retires to slot-1.
        .hperm_slot_i(hperm_lane_slot_q - 2'd1),
        .hperm_word_i(hperm_lane_word),
        .bool_src_a_i(hdc_src0_q),
        .bool_src_b_i(vrf_rd),
        .hdc_pair_src_a_i(vrf_rd),
        .hdc_pair_src_b_i(vrf_rd_early),
        .bitmatrix_src_a_i(ecc_bitmatrix_src_a),
        .bitmatrix_src_b_i(ecc_bitmatrix_src_b),
        .xor1_diag_mode_i(ecc_xor1_diag_mode),
        .xor1_legacy_acc_i(ecc_leaf128_prod_q),
        .xor1_legacy_sub_product_i(ecc_leaf_prod_q),
        .xor1_legacy_sub_idx_i(ecc_kpd64_sub_q),
        .xor1_legacy_leaf_a_i(ecc_leaf_a_q),
        .xor1_legacy_leaf_xor_a_i(ecc_leaf_xor_a_q),
        .xor1_legacy_leaf_b_i(ecc_leaf_b_q),
        .xor1_legacy_leaf_xor_b_i(ecc_leaf_xor_b_q),
        .xor0_contribution_packet_i(xor0_contribution_packet),
        .payload_q_o(vec_payload_q),
        .payload_pop_q_o(vec_popcount_q),
        .xor0_field_packet_o(xor0_field_packet),
        .bitmatrix_product_o(ecc_bitmatrix_product),
        .xor1_legacy_accum_o(ecc_sub32_capture_accum_xor1),
        .xor1_legacy_lowxor_a_o(ecc_leaf_a_lowxor_xor1),
        .xor1_legacy_lowxor_b_o(ecc_leaf_b_lowxor_xor1),
        .cnt_hv_word_i(hdc_src0_q),
        .cnt_old_counter_i(vrf_rd),
        .cnt_subgroup_i(uop_p0_q.subgroup_idx),
        .clip_counter_i(vrf_rd)
    );

    assign group_dist_sum = {3'b000, vec_popcount_q[0][0]} + {3'b000, vec_popcount_q[0][1]}
                          + {3'b000, vec_popcount_q[1][0]} + {3'b000, vec_popcount_q[1][1]}
                          + {3'b000, vec_popcount_q[2][0]} + {3'b000, vec_popcount_q[2][1]}
                          + {3'b000, vec_popcount_q[3][0]} + {3'b000, vec_popcount_q[3][1]};

    // ── Main FSM ────────────────────────────────────────────────────────────
    always_comb begin
        st_n=st_q;
        ready_o=((st_q==S_IDLE) && !vv33_pair_active_q
              && !vv33_hinfer_active) || vv33_hinfer_field_ready;
        valid_o=(st_q==S_RESULT) || vv33_pair_resp_q;
        result_o=res_q;
        res_n=res_q; op_n=op_q; a_n=a_q; vaddr_bank_n=vaddr_bank_q; vaddr_idx_n=vaddr_idx_q;
        clr_cnt_n=clr_cnt_q; clr_base_n=clr_base_q;
        hsim_src0_base_n=hsim_src0_base_q; hsim_src1_base_n=hsim_src1_base_q; hsim_total_n=hsim_total_q;
        group_dist_n=group_dist_q;
        hmatch_last_idx_n=hmatch_last_idx_q; hmatch_best_idx_n=hmatch_best_idx_q; hmatch_class_slot_n=hmatch_class_slot_q; hmatch_best_dist_n=hmatch_best_dist_q;
        hperm_bit_low_n=hperm_bit_low_q; hperm_spread_n=hperm_spread_q; hperm_lane_base_n=hperm_lane_base_q;
        hcntclip_dst_base_n=hcntclip_dst_base_q; hcntclip_acc_sel_n=hcntclip_acc_sel_q; hcntclip_chunk_n=hcntclip_chunk_q;
        uop_p0_n=uop_p0_q; uop_p3_n=uop_p3_q;
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
        // P2 lane issue is derived from the active state and P0 uop. P3
        // consumes the resulting one-cycle payload; later values are don't-care.
        ecc_src_a_n=ecc_src_a_q; ecc_src_b_n=ecc_src_b_q; ecc_dst_n=ecc_dst_q; ecc_acc_dst_n=ecc_acc_dst_q;
        ecc_leaf_a_n=ecc_leaf_a_q; ecc_leaf_b_n=ecc_leaf_b_q;
        ecc_leaf_prod_n=ecc_leaf_prod_q;
        ecc_leaf_xor_a_n=ecc_leaf_xor_a_q; ecc_leaf_xor_b_n=ecc_leaf_xor_b_q;
        ecc_leaf128_prod_n=ecc_leaf128_prod_q; ecc_kpd64_sub_n=ecc_kpd64_sub_q;
        ecc_leaf_path_n=ecc_leaf_path_q;
        ecc_fold_word_n=ecc_fold_word_q;
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
        vv33_sq_phase_n=vv33_sq_phase_q;
        vv33_sq_defer_fire=1'b0;
        vv33_sq_read_fire=1'b0;
        vv33_sq_write_fire=1'b0;
        vv33_sq_commit_n=vv33_sq_commit_q;
        vv33_pair_active_n=vv33_pair_active_q;
        vv33_pair_a_sent_n=vv33_pair_a_sent_q;
        vv33_pair_next_n=vv33_pair_next_q;
        vv33_pair_read_ready_n=vv33_pair_read_ready_q;
        vv33_pair_product_n=vv33_pair_product_q;
        vv33_pair_pop_n=vv33_pair_pop_q;
        vv33_pair_sum_n=vv33_pair_sum_q;
        vv33_pair_finish_n=vv33_pair_finish_q;
        vv33_pair_resp_n=1'b0;
        vv33_pair_class_idx_n=vv33_pair_class_idx_q;
        vv33_pair_chunk_n=vv33_pair_chunk_q;
        vv33_pair_total_n=vv33_pair_total_q;
        vv33_pair_best_n=vv33_pair_best_q;
        vv33_pair_best_idx_n=vv33_pair_best_idx_q;
        vv33_hinfer_pending_n=vv33_hinfer_pending_q;
        vv33_hinfer_rot_n=vv33_hinfer_rot_q;
        vv33_hinfer_resume_step_n=vv33_hinfer_resume_step_q;
        lane_shift_bit='0;
        vrf_req.ra='0; vrf_req.wa='x; vrf_req.wd='x;
        // The deferred square token is created only for the two compatible
        // foreground phases below.  Its lifecycle invariant is checked in
        // simulation, so the legacy write-enable cone remains narrow.
        vrf_we_direct={LANE_NUM{vv33_sq_commit_q}};
        // A registered one-cycle commit removes the foreground state decode
        // from the legacy BRAM write-enable cone.

        case(st_q)
        S_IDLE: begin
            if(valid_i&&ready_o)begin
                op_n=operator_i;a_n=operand_a_i;
                if (vv33_hinfer_request) begin
                    vv33_hinfer_pending_n=1'b1;
                    vv33_hinfer_rot_n=operand_a_i[17:8];
                    a_n[63]=1'b0;
                end
                st_n=S_EXEC;
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
                        ecc_dst_n   = a_q[32] ? a_q[23:18] : a_q[17:12];
                        ecc_acc_dst_n = a_q[23:18];
                        ecc_src_a_n = a_q[11:6];
                        ecc_src_b_n = a_q[5:0];
                        ecc_autoreduce_n = a_q[31] | a_q[32];
                        ecc_raw_product_n = ~(a_q[31] | a_q[32]);
                        ecc_mac_n = a_q[32];
                        ecc_sqr_repeat_n='0;
                        vrf_req.ra=a_q[32] ? a_q[23:18] : a_q[11:6];
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
                hcntclip_dst_base_n[5]=ecc_job_bg_q;
                clr_base_n=a_q[0] ? (ecc_job_bg_q ? 6'd24 : 6'd48)
                                  : (ecc_job_bg_q ? 6'd16 : 6'd32);
                clr_cnt_n=4'd0;st_n=S_CLR;
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
                if (vv33_hinfer_active) begin
                    if (vv33_hinfer_invalid) begin
                        vv33_hinfer_pending_n=1'b0;
                        res_n={62'b0,STATUS_ERROR};st_n=S_RESULT;
                    end else begin
                        // The resident role, query, input, and three prototype
                        // bases are fixed. Bits [17:8] carry the runtime HPERM
                        // rotation used by this inference instance.
                        hperm_bit_low_n=vv33_hinfer_rot_q[1:0];
                        hperm_spread_n=1'b0;
                        hperm_lane_base_n=vv33_hinfer_rot_q[7:6];
                        uop_p0_n.valid       = 1'b1;
                        // The macro reuses the ordinary HPERM uop encoding;
                        // op_q plus bit63 retain its lifecycle without a new
                        // payload mode or a separate macro FSM.
                        uop_p0_n.op_type     = UOP_HPERM_CHUNK;
                        uop_p0_n.chunk_idx   = 2'd0;
                        uop_p0_n.src0_addr   = VV33_HINFER_ROLE_BASE
                                             + {4'b0,vv33_hinfer_rot_q[9:8]};
                        uop_p0_n.src1_addr   = VV33_HINFER_ROLE_BASE
                                             + {4'b0,vv33_hinfer_rot_q[9:8] + 2'd1};
                        uop_p0_n.dst_addr    = VV33_HINFER_QUERY_BASE;
                        uop_p0_n.perm_nibble = vv33_hinfer_rot_q[5:2];
                        // Reuse an existing uop bit that is inactive for
                        // HPERM/HBIND as the macro-chain tag. No new state bit
                        // or wide address comparator is required.
                        uop_p0_n.is_last_class = 1'b1;
                        st_n=S_UOP_P1_RD0;
                    end
                end else begin
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
            end

            HDEC_HCNTCLIP: begin
                hcntclip_dst_base_n={hcntclip_dst_base_q[5],a_q[2:0],2'b00};
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
                        hperm_spread_n=1'b1;
                        ecc_dst_n=a_q[5:0];
                        ecc_acc_dst_n=a_q[17:12];
                        ecc_autoreduce_n=a_q[19] | a_q[20];
                        ecc_mac_n=a_q[20];
                        ecc_sqr_repeat_n=(a_q[19] | a_q[20]) ? {3'b0, a_q[27:24]} : 7'd0;
                        vrf_req.ra=a_q[11:6];
                        st_n=S_RD_WAIT;
                    end
                end else if ((|a_q[9:8])
                          || (a_q[3:0] == a_q[7:4])) begin
                    res_n={62'b0,STATUS_ERROR};st_n=S_RESULT;
                end
                else begin
                    hperm_bit_low_n=a_q[9:8];
                    hperm_spread_n=1'b0;
                    hperm_lane_base_n=a_q[15:14];
                    uop_p0_n.valid       = 1'b1;
                    uop_p0_n.op_type     = UOP_HPERM_CHUNK;
                    uop_p0_n.chunk_idx   = 2'd0;
                    // The high four bits select the source HV.  The low two
                    // bits select a row inside that HV and therefore wrap
                    // naturally modulo four.
                    uop_p0_n.src0_addr   = {a_q[7:4], a_q[17:16]};
                    uop_p0_n.src1_addr   = {
                        a_q[7:4],
                        a_q[17:16] + 2'd1
                    };
                    uop_p0_n.dst_addr    = {a_q[3:0],2'b00};
                    uop_p0_n.perm_nibble = a_q[13:10];
                    st_n=S_UOP_P1_RD0;
                end
            end

            default: begin res_n={62'b0,STATUS_NOT_IMPLEMENTED};st_n=S_RESULT;end
        endcase end

        S_VWR_WAIT: begin res_n='0;st_n=S_RESULT;end

        S_RD_WAIT: begin
            if (ecc_pmul_add_t2_prefetch)
                vrf_req.ra=ecc_pmul_dbl_x;
            st_n=S_RD_WAIT2;
        end

        S_RD_WAIT2: begin
            if (ecc_pmul_add_t2_prefetch)
                vrf_req.ra=ecc_pmul_dbl_z;
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
            vrf_req.wa=ecc_dst_q;
            vrf_req.wd=ecc_square_reduce_word;
            hperm_spread_n=1'b0;
            ecc_autoreduce_n=1'b0;
            if (ecc_pmul_add_t2_prefetch) begin
                ecc_pmul_step_n=5'd4;
                ecc_dst_n=ECC_PMUL_T2;
                ecc_src_a_n=ecc_pmul_dbl_x;
                ecc_src_b_n=ecc_pmul_dbl_z;
                ecc_autoreduce_n=1'b1;
                ecc_mac_n=1'b0;
                ecc_sqr_repeat_n='0;
                ecc_leaf_path_n='0;
                hdc_src0_n='0;
                hdc_src0_we=1'b1;
                st_n=S_ECC_LOAD_A;
            end else if (ecc_mac_q && (ecc_sqr_repeat_q == 7'd0)) begin
                uop_p0_n='0;
                uop_p0_n.valid     = 1'b1;
                uop_p0_n.op_type   = UOP_HBIND_CHUNK;
                uop_p0_n.src0_addr = ecc_acc_dst_q;
                uop_p0_n.src1_addr = ecc_dst_q;
                uop_p0_n.dst_addr  = ecc_acc_dst_q;
                uop_p0_n.chunk_idx = 2'd3;
                st_n=S_UOP_P1_RD0;
            end else begin
                st_n=S_ECC_WRITE_DRAIN;
            end
        end

        S_HSPREAD_LO_WRITE: begin
            vrf_req.wa=ecc_dst_q;
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
            vrf_req.wa=ecc_dst_q + 6'd1;
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
                if (ecc_pmul_residue_seed_one) begin
                    hdc_src0_n = '0;
                    hdc_src0_n[0][0] = 1'b1;
                    hdc_src0_we=1'b1;
                end else if (ecc_pmul_residue_seed_vrf) begin
                    vrf_req.ra=ecc_src_a_q;
                end else if (ecc_pmul_add_continuation) begin
                    vrf_req.ra=ecc_src_a_q;
                end else if (ecc_mac_q) begin
                    vrf_req.ra=ecc_src_a_q;
                end else begin
                    hdc_src0_n = '0;
                    hdc_src0_we=1'b1;
                end
            end
            if (ecc_diag_early_b_load)
                vrf_req.ra=ecc_src_b_q;
            st_n=S_ECC_LOAD_A_WAIT2;
        end

        S_ECC_LOAD_A_WAIT2: begin
            if (!ecc_diag_early_b_load)
                vrf_req.ra=ecc_src_b_q;
            st_n=S_ECC_LOAD_A;
        end

        S_ECC_LOAD_A: begin
            if (ecc_mac_q || ecc_pmul_residue_seed_vrf) begin
                hdc_src0_n = vrf_rd;
                hdc_src0_n[3][63:41] = '0;
                hdc_src0_we=1'b1;
            end else begin
                ecc_leaf_a_n = ecc_leaf_lowxor_rd[31:0];
                ecc_leaf_xor_a_n = ecc_leaf_lowxor_rd[63:32];
                if (!ecc_diag_early_b_load)
                    vrf_req.ra=ecc_src_b_q;
            end
            st_n=S_ECC_LOAD_B_WAIT;
        end

        S_ECC_LOAD_B_WAIT: begin
            if (ecc_mac_q || ecc_pmul_residue_seed_vrf) begin
                ecc_leaf_a_n = ecc_leaf_lowxor_rd[31:0];
                ecc_leaf_xor_a_n = ecc_leaf_lowxor_rd[63:32];
                st_n=S_ECC_LOAD_B;
            end else if (ecc_diag_early_b_load) begin
                ecc_leaf_b_n =
                    ecc_bitrev32_top(ecc_leaf_lowxor_rd[31:0]);
                ecc_leaf_xor_b_n =
                    ecc_bitrev32_top(ecc_leaf_lowxor_rd[63:32]);
                ecc_leaf128_prod_n = '0;
                ecc_kpd64_sub_n = 2'd0;
                ecc_leaf_prod_n = '0;
                ecc_leaf_path_n = '0;
                ecc_fold_word_n = 2'd0;
                st_n=S_ECC_DIAG_ISSUE;
            end else begin
                st_n=S_ECC_LOAD_B;
            end
        end

        S_ECC_LOAD_B: begin
            ecc_leaf_b_n =
                ecc_bitrev32_top(ecc_leaf_lowxor_rd[31:0]);
            ecc_leaf_xor_b_n =
                ecc_bitrev32_top(ecc_leaf_lowxor_rd[63:32]);
            ecc_leaf128_prod_n = '0;
            ecc_kpd64_sub_n = 2'd0;
            ecc_leaf_prod_n = '0;
            ecc_leaf_path_n = '0;
            ecc_fold_word_n = 2'd0;
            st_n=S_ECC_DIAG_ISSUE;
        end

        S_ECC_DIAG_ISSUE: begin
            // Start the first 16x16 kernel and prefetch the next 64-bit leaf
            // while the third 32x32 sub-product is in flight.
            if (!VV31_SCHED_ENABLE
                && ecc_diag_sub_shadow_mode && !ecc_leaf_last
                && (ecc_kpd64_sub_q == 2'd2)) begin
                vrf_req.ra=ecc_src_a_q;
            end
            if (vv33_pair_start) begin
                vv33_pair_active_n=1'b1;
                vv33_pair_a_sent_n=1'b1;
                vv33_pair_next_n=1'b0;
                vv33_pair_read_ready_n=1'b0;
                vv33_pair_product_n=1'b0;
                vv33_pair_pop_n=1'b0;
                vv33_pair_sum_n=1'b0;
                vv33_pair_finish_n=1'b0;
                vv33_pair_class_idx_n=2'd0;
                vv33_pair_chunk_n=2'd0;
                vv33_pair_total_n='0;
                vv33_pair_best_n='0;
                vv33_pair_best_idx_n='0;
                vrf_req.ra=VV33_HINFER_QUERY_BASE;
            end
            st_n=S_ECC_DIAG_CAPTURE0;
        end

        S_ECC_DIAG_FOLD_ISSUE: begin
            if (ecc_kernel_token_acc_cycle) begin
                hdc_src0_acc_we=1'b1;
            end
            // XOR1 is in its original VV22 fold mode, while the same shared
            // AND may preissue the next group0 matrix through the operands
            // handed off at the preceding group2 capture.
            if (!ecc_kernel_token_fold_mode)
                ecc_leaf128_prod_n = ecc_sub32_capture_accum_xor1;
            else
                ecc_leaf128_prod_n = '0;
            ecc_leaf_prod_n = '0;
            unique case (ecc_kpd64_sub_q)
                2'd0: begin
                    ecc_kpd64_sub_n = 2'd1;
                    st_n=ecc_diag_fold_preissue
                       ? S_ECC_DIAG_CAPTURE0 : S_ECC_DIAG_ISSUE;
                end
                2'd1: begin
                    ecc_kpd64_sub_n = 2'd2;
                    // Keep A on its original path. The preceding CAP2 issues B,
                    // so the two operands return in sub2 CAP1 and CAP2.
                    if (ecc_diag_fold_preissue && !ecc_leaf_last)
                        vrf_req.ra=ecc_src_a_q;
                    st_n=ecc_diag_fold_preissue
                       ? S_ECC_DIAG_CAPTURE0 : S_ECC_DIAG_ISSUE;
                end
                default: begin
                    if (ecc_diag_sub_shadow_mode) begin
                        if (!ecc_leaf_last) begin
                            if (ecc_diag_next_leaf_b_capture) begin
                                ecc_leaf_b_n =
                                    ecc_bitrev32_top(ecc_leaf_lowxor_rd[31:0]);
                                ecc_leaf_xor_b_n =
                                    ecc_bitrev32_top(ecc_leaf_lowxor_rd[63:32]);
                            end
                            ecc_leaf_path_n = ecc_next_leaf_path;
                            ecc_kpd64_sub_n = 2'd0;
                            ecc_fold_word_n = 2'd0;
                            st_n=ecc_diag_leaf_preissue
                               ? S_ECC_DIAG_CAPTURE0 : S_ECC_DIAG_ISSUE;
                        end else begin
                            ecc_kpd64_sub_n = 2'd3;
                            ecc_fold_word_n = 2'd0;
                            if (ecc_pmul_add_step5_complete) begin
                                // The last step-5 contribution is captured
                                // into hdc_src0_q at this edge.  Continue with
                                // the second product without a T6 VRF roundtrip.
                                ecc_pmul_step_n=5'd7;
                                ecc_dst_n=ecc_pmul_add_out_x;
                                ecc_src_a_n=ecc_pmul_point_q;
                                ecc_src_b_n=ECC_PMUL_ADD_Z_FORWARD
                                          ? ecc_pmul_add_out_z : ECC_PMUL_T5;
                                ecc_autoreduce_n=1'b1;
                                ecc_mac_n=1'b0;
                                ecc_sqr_repeat_n='0;
                                ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                                vrf_req.ra=ecc_pmul_point_q;
                                st_n=S_ECC_LOAD_A_WAIT;
                            end else begin
                                st_n=S_ECC_WRITE_PAIR;
                            end
                        end
                    end else begin
                        ecc_kpd64_sub_n = 2'd3;
                        ecc_fold_word_n = 2'd0;
                        if (!ecc_leaf_last)
                            vrf_req.ra=ecc_src_a_q;
                        st_n=S_ECC_LEAF_FOLD;
                    end
                end
            endcase
            if (vv33_pair_pop_fire) begin
                vv33_pair_product_n=1'b0;
                vv33_pair_pop_n=1'b1;
            end
            if (vv33_pair_fold_launch) begin
                if (vv33_pair_product_q) begin
                    vrf_req.ra=vv33_pair_next_src_a_addr;
                    vv33_pair_next_n=1'b1;
                end else begin
                    vrf_req.ra=vv33_pair_src_a_addr;
                    vv33_pair_next_n=1'b0;
                end
                vv33_pair_a_sent_n=1'b1;
            end
        end

        S_ECC_DIAG_CAPTURE0: begin
            if (ECC_DEBUG_FIELD_OPS) begin
                ecc_leaf_prod_n = ecc_leaf_prod_q
                                ^ ecc_diag16_karatsuba_token(
                                      3'd0, ecc_bitmatrix_product
                                  );
            end else begin
                ecc_leaf_prod_n = {33'b0, ecc_bitmatrix_product[30:0]};
            end
            if (!VV31_SCHED_ENABLE
                && ecc_diag_sub_shadow_mode && !ecc_leaf_last
                && (ecc_kpd64_sub_q == 2'd2)) begin
                vrf_req.ra=ecc_src_b_q;
            end
            if (vv33_pair_a_sent_q) begin
                vrf_req.ra=vv33_pair_next_q
                           ? vv33_pair_next_src_b_addr
                           : vv33_pair_src_b_addr;
                vv33_pair_a_sent_n=1'b0;
                vv33_pair_next_n=1'b0;
                vv33_pair_read_ready_n=1'b1;
            end
            if (vv33_pair_pop_q) begin
                vv33_pair_pop_n=1'b0;
                group_dist_n=group_dist_sum;
                vv33_pair_sum_n=1'b1;
            end
            st_n=S_ECC_DIAG_CAPTURE1;
        end

        S_ECC_DIAG_CAPTURE1: begin
            if (ecc_kernel_token_acc_cycle)
                hdc_src0_acc_we=1'b1;
            if (ECC_DEBUG_FIELD_OPS) begin
                ecc_leaf_prod_n = ecc_leaf_prod_q
                                ^ ecc_diag16_karatsuba_token(
                                      3'd1, ecc_bitmatrix_product
                                  );
            end else begin
                ecc_leaf_prod_n = {33'b0, ecc_bitmatrix_product[30:0]};
            end
            if (VV31_SCHED_ENABLE && ecc_diag_next_leaf_b_capture) begin
                // CAP1 launches current group2 before this edge, so the
                // returning next-leaf B can occupy its normal register pair.
                ecc_leaf_b_n =
                    ecc_bitrev32_top(ecc_leaf_lowxor_rd[31:0]);
                ecc_leaf_xor_b_n =
                    ecc_bitrev32_top(ecc_leaf_lowxor_rd[63:32]);
            end
            if (vv33_pair_sum_q) begin
                vv33_pair_sum_n=1'b0;
                if (vv33_pair_chunk_q == 2'd3) begin
                    if (vv33_pair_score > vv33_pair_best_q) begin
                        vv33_pair_best_n=vv33_pair_score;
                        vv33_pair_best_idx_n=vv33_pair_class_idx_q;
                    end
                    if (vv33_pair_class_idx_q == 2'd2) begin
                        // Commit the winning score first.  Response packing is
                        // deferred one cycle so the score add/compare chain
                        // never terminates directly at the broad res_q mux.
                        vv33_pair_finish_n=1'b1;
                        vv33_pair_read_ready_n=1'b0;
                        vv33_pair_product_n=1'b0;
                        vv33_pair_total_n='0;
                    end else begin
                        vv33_pair_total_n='0;
                        vv33_pair_chunk_n=2'd0;
                        vv33_pair_class_idx_n=vv33_pair_class_idx_q+2'd1;
                    end
                end else begin
                    vv33_pair_total_n=vv33_pair_score;
                    vv33_pair_chunk_n=vv33_pair_chunk_q+2'd1;
                end
            end
            st_n=S_ECC_DIAG_CAPTURE2;
        end

        S_ECC_DIAG_CAPTURE2: begin
            if (ecc_kernel_token_acc_cycle)
                hdc_src0_acc_we=1'b1;
            if (ECC_DEBUG_FIELD_OPS) begin
                ecc_leaf_prod_n = ecc_leaf_prod_q
                                ^ ecc_diag16_karatsuba_token(
                                      3'd2, ecc_bitmatrix_product
                                  );
            end else begin
                ecc_leaf_prod_n = {33'b0, ecc_bitmatrix_product[30:0]};
            end

            // Start the two consecutive next-leaf reads at sub1 completion.
            if (VV31_SCHED_ENABLE && ecc_diag_sub_shadow_mode
                && (ecc_kpd64_sub_q == 2'd1) && !ecc_leaf_last) begin
                vrf_req.ra=ecc_src_b_q;
            end
            unique case (ecc_kpd64_sub_q)
                2'd0: begin
                    ecc_leaf_a_n = ecc_leaf_a_lowxor_xor1;
                    ecc_leaf_b_n = ecc_leaf_b_lowxor_xor1;
                end
                2'd1: begin
                    ecc_leaf_a_n = ecc_leaf_xor_a_q;
                    ecc_leaf_b_n = ecc_leaf_xor_b_q;
                end
                default: begin
                    if (ecc_diag_next_leaf_a_capture) begin
                        ecc_leaf_a_n = ecc_leaf_lowxor_rd[31:0];
                        ecc_leaf_xor_a_n = ecc_leaf_lowxor_rd[63:32];
                    end
                end
            endcase
            if (vv33_pair_product_fire) begin
                vv33_pair_read_ready_n=1'b0;
                vv33_pair_product_n=1'b1;
            end
            if (vv33_pair_finish_q) begin
                res_n={51'b0, vv33_pair_best_idx_q, vv33_pair_best_q};
                vv33_pair_resp_n=1'b1;
                vv33_pair_finish_n=1'b0;
                vv33_pair_active_n=1'b0;
                if (vv33_hinfer_active)
                    vv33_hinfer_pending_n=1'b0;
            end
            st_n=S_ECC_DIAG_FOLD_ISSUE;
        end

        S_ECC_LEAF_FOLD: begin
            ecc_product_we = ECC_DEBUG_FIELD_OPS && ecc_raw_product_q;
            if (ecc_diag_sub_shadow_mode) begin
                hdc_src0_acc_we=1'b1;
                if (ecc_leaf_last) begin
                    ecc_fold_word_n = 2'd0;
                    st_n=S_ECC_WRITE_PAIR;
                end else begin
                    ecc_leaf_b_n = ecc_bitrev32_top(ecc_leaf_lowxor_rd[31:0]);
                    ecc_leaf_xor_b_n = ecc_bitrev32_top(ecc_leaf_lowxor_rd[63:32]);
                    ecc_fold_word_n = 2'd0;
                    ecc_leaf_path_n = ecc_next_leaf_path;
                    ecc_leaf128_prod_n = '0;
                    ecc_kpd64_sub_n = 2'd0;
                    st_n=S_ECC_DIAG_ISSUE;
                end
            end else if (ecc_autoreduce_fast) begin
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
                if (ecc_mac_q)
                    ecc_mac_n=1'b0;
                if (vv33_hinfer_field_accept) begin
                    // The write above commits the complete field result.  This
                    // is the highest-frequency safe boundary in PMUL: all wide
                    // residue state is now architectural, while the original
                    // continuation is the narrow STEP_NEXT transition.
                    op_n=HDEC_HMATCH;
                    vv33_hinfer_pending_n=1'b1;
                    vv33_hinfer_rot_n=operand_a_i[17:8];
                    if (ecc_sqr_repeat_q != 7'd0) begin
                        // Keep one square live across the query encoder.  The
                        // HPERM phase leaves it pending; the existing HBIND
                        // read/compute/write lifecycle then issues and commits
                        // the square without a second wide result path.
                        vv33_sq_phase_n=VV33_SQ_PENDING;
                        ecc_sqr_repeat_n=ecc_sqr_repeat_q-7'd1;
                        vv33_hinfer_resume_step_n=1'b0;
                    end else begin
                        ecc_job_phase_n=ECC_PHASE_NONE;
                        vv33_hinfer_resume_step_n=1'b1;
                    end
                    st_n=S_EXEC;
                end else if (ecc_sqr_repeat_q == 7'd0) begin
                    res_n={56'b0, ecc_dst_q, STATUS_OK};
                    if (ecc_job_active_q && (ecc_job_phase_q == ECC_PHASE_INV_SQR)) begin
                        st_n=S_ECC_INV_AFTER_SQR;
                    end else if (ecc_job_active_q && (ecc_job_phase_q == ECC_PHASE_INV_MUL)) begin
                        st_n=S_ECC_INV_AFTER_MUL;
                    end else if (ecc_job_active_q && (ecc_job_phase_q == ECC_PHASE_PMUL_FIELD)) begin
                        if (ecc_pmul_add_t1_prefetch) begin
                            ecc_pmul_step_n=5'd1;
                            ecc_dst_n=ECC_PMUL_T1;
                            ecc_src_a_n=ECC_PMUL_R1X;
                            ecc_src_b_n=ECC_PMUL_R0Z;
                            ecc_autoreduce_n=1'b1;
                            ecc_mac_n=1'b0;
                            ecc_sqr_repeat_n='0;
                            vrf_req.ra=ECC_PMUL_R1X;
                            st_n=S_ECC_LOAD_A_WAIT;
                        end else if (ecc_pmul_residue_seed_one) begin
                            ecc_job_phase_n=ECC_PHASE_NONE;
                            ecc_pmul_step_n=5'd17;
                            st_n=S_ECC_PMUL_STEP;
                        end else begin
                            ecc_job_phase_n=ECC_PHASE_NONE;
                            st_n=S_ECC_PMUL_STEP_NEXT;
                        end
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
            if (vv33_hinfer_field_accept) begin
                // The field result is architectural at this boundary.  Retire
                // the PMUL microstep now, keep only a one-bit continuation, and
                // execute the fused inference through the normal HDC decode.
                op_n=HDEC_HMATCH;
                vv33_hinfer_pending_n=1'b1;
                vv33_hinfer_rot_n=operand_a_i[17:8];
                if (ecc_sqr_repeat_q != 7'd0) begin
                    vv33_sq_phase_n=VV33_SQ_PENDING;
                    ecc_sqr_repeat_n=ecc_sqr_repeat_q-7'd1;
                    vv33_hinfer_resume_step_n=1'b0;
                end else begin
                    ecc_job_phase_n=ECC_PHASE_NONE;
                    vv33_hinfer_resume_step_n=1'b1;
                end
                st_n=S_EXEC;
            end else if (ECC_DEBUG_FIELD_OPS && ecc_autoreduce_q) begin
                vrf_req.ra=ecc_src_a_q;
                st_n=S_ECC_REDUCE_LOAD_LO_WAIT;
            end else if (ecc_sqr_repeat_q != 7'd0) begin
                if (VV33_FINE_INTERLEAVE
                 && ecc_job_bg_q
                 && vv33_hdc_request_valid
                 && !vv33_hinfer_active
                 && !vv33_pair_active_q
                 && ((ecc_job_phase_q == ECC_PHASE_PMUL_FIELD)
                  || (ecc_job_phase_q == ECC_PHASE_INV_SQR))) begin
                    // A dual-source Boolean operation carries one square
                    // through its own VRF/compute lifecycle.  Other HDC
                    // instructions use the same safe boundary but leave the
                    // square pending for normal replay after they retire.
                    vv33_sq_phase_n=vv33_hdc_square_overlap
                                      ? VV33_SQ_PENDING : VV33_SQ_DONE;
                    vv33_sq_defer_fire=1'b1;
                    if (vv33_hdc_square_overlap)
                        ecc_sqr_repeat_n=ecc_sqr_repeat_q - 7'd1;
                    hperm_spread_n=1'b0;
                    ecc_autoreduce_n=1'b0;
                    st_n=S_IDLE;
                end else begin
                    hperm_spread_n=1'b1;
                    ecc_src_a_n=ecc_dst_q;
                    ecc_autoreduce_n=1'b1;
                    ecc_sqr_repeat_n=ecc_sqr_repeat_q - 7'd1;
                    vrf_req.ra=ecc_dst_q;
                    st_n=S_RD_WAIT;
                end
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
            if (ecc_inv_step_needs_tmp(ecc_inv_step_q)
                && !ECC_INV_SQUARE_REDIRECT) begin
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
            ecc_dst_n=(ECC_INV_SQUARE_REDIRECT
                       && ecc_inv_step_has_mul(ecc_inv_step_q))
                     ? (ecc_job_dst_q + 6'd2) : ecc_job_dst_q;
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
                if (ECC_INV_SQUARE_REDIRECT
                    && ecc_inv_step_has_mul(ecc_inv_step_q)) begin
                    ecc_src_a_n=ecc_job_dst_q + 6'd2;
                    ecc_src_b_n=ecc_inv_step_mul_src_is_orig(ecc_inv_step_q)
                              ? ecc_job_src_q : ecc_job_dst_q;
                end else begin
                    ecc_src_a_n=ecc_job_dst_q;
                    ecc_src_b_n=ecc_inv_step_mul_src_is_orig(ecc_inv_step_q)
                              ? ecc_job_src_q : (ecc_job_dst_q + 6'd2);
                end
                ecc_autoreduce_n=1'b1;
                ecc_mac_n=1'b0;
                ecc_sqr_repeat_n='0;
                ecc_job_phase_n=ECC_PHASE_INV_MUL;
                vrf_req.ra=(ECC_INV_SQUARE_REDIRECT
                            && ecc_inv_step_has_mul(ecc_inv_step_q))
                          ? (ecc_job_dst_q + 6'd2) : ecc_job_dst_q;
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
                5'd0: begin
                    ecc_job_phase_n=ECC_PHASE_PMUL_COPY;
                    ecc_dst_n=ECC_PMUL_R1X;
                    vrf_req.ra=ecc_pmul_point_q;
                    st_n=S_ECC_INV_COPY_WAIT;
                end
                5'd1: begin
                    ecc_dst_n=ECC_PMUL_R0X;
                    st_n=S_ECC_PMUL_CONST_WRITE;
                end
                5'd2: begin
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
                ecc_dst_n=(ecc_pmul_step_q == 5'd0) ? ecc_pmul_result_q : (ecc_pmul_result_q + 6'd1);
                st_n=S_ECC_PMUL_CONST_WRITE;
            end
            ECC_PMUL_SUB_AFFINE: begin
                unique case (ecc_pmul_step_q)
                5'd0: begin
                    ecc_dst_n=ECC_PMUL_T0; ecc_src_a_n=ECC_PMUL_R0Z; ecc_src_b_n=ECC_PMUL_R1Z;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_R0Z;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                5'd1: begin
                    ecc_dst_n=ECC_PMUL_T2; ecc_src_a_n=ECC_PMUL_T0; ecc_src_b_n=ecc_pmul_point_q;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_T0;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                5'd2: begin
                    ecc_job_src_n=ECC_PMUL_T2;
                    ecc_job_dst_n=ECC_PMUL_T3;
                    ecc_inv_step_n='0;
                    st_n=S_ECC_INV_INIT;
                end
                5'd3: begin
                    ecc_dst_n=ECC_PMUL_AFFINE_FACTOR_ACTIVE ? ECC_PMUL_T5 : ECC_PMUL_T1;
                    ecc_src_a_n=ECC_PMUL_AFFINE_FACTOR_ACTIVE ? ecc_pmul_point_q : ECC_PMUL_R1Z;
                    ecc_src_b_n=ECC_PMUL_AFFINE_FACTOR_ACTIVE ? ECC_PMUL_T3 : ecc_pmul_point_q;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_AFFINE_FACTOR_ACTIVE ? ecc_pmul_point_q : ECC_PMUL_R1Z;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                5'd4: begin
                    ecc_dst_n=ECC_PMUL_T1;
                    ecc_src_a_n=ECC_PMUL_AFFINE_FACTOR_ACTIVE ? ECC_PMUL_R1Z : ECC_PMUL_T1;
                    ecc_src_b_n=ECC_PMUL_AFFINE_FACTOR_ACTIVE ? ECC_PMUL_T5 : ECC_PMUL_T3;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_AFFINE_FACTOR_ACTIVE ? ECC_PMUL_R1Z : ECC_PMUL_T1;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                5'd5: begin
                    ecc_dst_n=ECC_PMUL_T4; ecc_src_a_n=ECC_PMUL_R0X; ecc_src_b_n=ECC_PMUL_T1;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_R0X;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                5'd6: begin
                    ecc_dst_n=ECC_PMUL_T1; ecc_src_a_n=ECC_PMUL_R0Z;
                    ecc_src_b_n=ECC_PMUL_AFFINE_FACTOR_ACTIVE ? ECC_PMUL_T5 : ecc_pmul_point_q;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_R0Z;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                5'd7: begin
                    if (ECC_PMUL_AFFINE_FACTOR_ACTIVE) begin
                        st_n=S_ECC_PMUL_STEP_NEXT;
                    end else begin
                        ecc_dst_n=ECC_PMUL_T1; ecc_src_a_n=ECC_PMUL_T1; ecc_src_b_n=ECC_PMUL_T3;
                        ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                        ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                        vrf_req.ra=ECC_PMUL_T1;
                        st_n=S_ECC_LOAD_A_WAIT;
                    end
                end
                5'd8: begin
                    ecc_dst_n=ECC_PMUL_T6; ecc_src_a_n=ECC_PMUL_R1X; ecc_src_b_n=ECC_PMUL_T1;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_R1X;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                5'd9: begin
                    ecc_dst_n=ECC_PMUL_T1; ecc_src_a_n=ECC_PMUL_T0; ecc_src_b_n=ECC_PMUL_T3;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_T0;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                5'd10: begin
                    uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK;
                    uop_p0_n.src0_addr=ECC_PMUL_T4; uop_p0_n.src1_addr=ecc_pmul_point_q;
                    uop_p0_n.dst_addr=ECC_PMUL_T2; uop_p0_n.chunk_idx=2'd3;
                    ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0;
                end
                5'd11: begin
                    uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK;
                    uop_p0_n.src0_addr=ECC_PMUL_T6;
                    uop_p0_n.src1_addr=ECC_PMUL_T4;
                    uop_p0_n.dst_addr=ECC_PMUL_T3; uop_p0_n.chunk_idx=2'd3;
                    ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0;
                end
                5'd12: begin
                    uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK;
                    uop_p0_n.src0_addr=ECC_PMUL_T3; uop_p0_n.src1_addr=ecc_pmul_point_q;
                    uop_p0_n.dst_addr=ECC_PMUL_T3; uop_p0_n.chunk_idx=2'd3;
                    ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0;
                end
                5'd13: begin
                    hperm_spread_n=1'b1;
                    ecc_dst_n=ECC_PMUL_T5; ecc_src_a_n=ECC_PMUL_T5;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_T4;
                    st_n=S_RD_WAIT;
                end
                5'd14: begin
                    ecc_dst_n=ECC_PMUL_T7; ecc_src_a_n=ECC_PMUL_T5; ecc_src_b_n=ECC_PMUL_T4;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_T5;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                5'd15: begin
                    if (ECC_PMUL_RESIDUE_SEED_ACTIVE) begin
                        st_n=S_ECC_PMUL_STEP_NEXT;
                    end else begin
                        ecc_dst_n=ECC_PMUL_T9;
                        st_n=S_ECC_PMUL_CONST_WRITE;
                    end
                end
                5'd16: begin
                    if (ECC_PMUL_RESIDUE_SEED_ACTIVE) begin
                        st_n=S_ECC_PMUL_STEP_NEXT;
                    end else begin
                        uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK;
                        uop_p0_n.src0_addr=ECC_PMUL_T7; uop_p0_n.src1_addr=ECC_PMUL_T9;
                        uop_p0_n.dst_addr=ECC_PMUL_T7; uop_p0_n.chunk_idx=2'd3;
                        ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0;
                    end
                end
                5'd17: begin
                    hperm_spread_n=1'b1;
                    ecc_dst_n=ECC_PMUL_T8; ecc_src_a_n=ECC_PMUL_T8;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_T2;
                    st_n=S_RD_WAIT;
                end
                5'd18: begin
                    ecc_dst_n=ECC_PMUL_RESIDUE_SEED_ACTIVE ? ECC_PMUL_T7 : ECC_PMUL_T8;
                    ecc_src_a_n=ECC_PMUL_T3; ecc_src_b_n=ECC_PMUL_T8;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_RESIDUE_SEED_ACTIVE ? ECC_PMUL_T7 : ECC_PMUL_T3;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                5'd19: begin
                    if (ECC_PMUL_RESIDUE_SEED_ACTIVE) begin
                        st_n=S_ECC_PMUL_STEP_NEXT;
                    end else begin
                        uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK;
                        uop_p0_n.src0_addr=ECC_PMUL_T7; uop_p0_n.src1_addr=ECC_PMUL_T8;
                        uop_p0_n.dst_addr=ECC_PMUL_T7; uop_p0_n.chunk_idx=2'd3;
                        ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0;
                    end
                end
                5'd20: begin
                    hperm_spread_n=1'b1;
                    ecc_dst_n=ECC_PMUL_T8; ecc_src_a_n=ECC_PMUL_T8;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ecc_pmul_point_q + 6'd1;
                    st_n=S_RD_WAIT;
                end
                5'd21: begin
                    uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK;
                    uop_p0_n.src0_addr=ECC_PMUL_T7; uop_p0_n.src1_addr=ECC_PMUL_T8;
                    uop_p0_n.dst_addr=ECC_PMUL_T7; uop_p0_n.chunk_idx=2'd3;
                    ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0;
                end
                5'd22: begin
                    ecc_dst_n=ECC_PMUL_T8;
                    ecc_src_a_n=ECC_PMUL_T4; ecc_src_b_n=ecc_pmul_point_q + 6'd1;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_T4;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                5'd23: begin
                    uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK;
                    uop_p0_n.src0_addr=ECC_PMUL_T7; uop_p0_n.src1_addr=ECC_PMUL_T8;
                    uop_p0_n.dst_addr=ECC_PMUL_T7; uop_p0_n.chunk_idx=2'd3;
                    ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0;
                end
                5'd24: begin
                    ecc_dst_n=ECC_PMUL_T8; ecc_src_a_n=ECC_PMUL_T7; ecc_src_b_n=ECC_PMUL_T1;
                    ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                    ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                    vrf_req.ra=ECC_PMUL_T7;
                    st_n=S_ECC_LOAD_A_WAIT;
                end
                5'd25: begin
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
                5'd0: begin
                    if (ECC_PMUL_DBL_FROBENIUS) begin
                        uop_p0_n='0; uop_p0_n.valid=1'b1;
                        uop_p0_n.op_type=UOP_HBIND_CHUNK;
                        uop_p0_n.src0_addr=ecc_pmul_dbl_x;
                        uop_p0_n.src1_addr=ecc_pmul_dbl_z;
                        uop_p0_n.dst_addr=ecc_pmul_dbl_x;
                        uop_p0_n.chunk_idx=2'd3;
                        ecc_job_phase_n=ECC_PHASE_PMUL_ADD;
                        st_n=S_UOP_P1_RD0;
                    end else begin
                        hperm_spread_n=1'b1;
                        ecc_dst_n=ECC_PMUL_T0; ecc_src_a_n=ECC_PMUL_T0;
                        ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                        ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                        vrf_req.ra=ecc_pmul_dbl_x; st_n=S_RD_WAIT;
                    end
                end
                5'd1: begin
                    if (ECC_PMUL_DBL_FROBENIUS) begin
                        hperm_spread_n=1'b1;
                        ecc_dst_n=ecc_pmul_dbl_x;
                        ecc_src_a_n=ecc_pmul_dbl_x;
                        ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0;
                        ecc_sqr_repeat_n=7'd1;
                        ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                        vrf_req.ra=ecc_pmul_dbl_x;
                        st_n=S_RD_WAIT;
                    end else begin
                        hperm_spread_n=1'b1;
                        ecc_dst_n=ECC_PMUL_T1; ecc_src_a_n=ECC_PMUL_T1;
                        ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                        ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                        vrf_req.ra=ECC_PMUL_T0; st_n=S_RD_WAIT;
                    end
                end
                5'd2: begin
                    if (ECC_PMUL_DBL_FROBENIUS) begin
                        hperm_spread_n=1'b1;
                        ecc_dst_n=ecc_pmul_dbl_z;
                        ecc_src_a_n=ecc_pmul_dbl_z;
                        ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0;
                        ecc_sqr_repeat_n='0;
                        ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                        vrf_req.ra=ECC_PMUL_T2;
                        st_n=S_RD_WAIT;
                    end else begin
                        hperm_spread_n=1'b1;
                        ecc_dst_n=ECC_PMUL_T4; ecc_src_a_n=ECC_PMUL_T4;
                        ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                        ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                        vrf_req.ra=ecc_pmul_dbl_z; st_n=S_RD_WAIT;
                    end
                end
                5'd3: begin
                    if (ECC_PMUL_DBL_FROBENIUS) begin
                        st_n=S_ECC_PMUL_STEP_NEXT;
                    end else begin
                        hperm_spread_n=1'b1;
                        ecc_dst_n=ECC_PMUL_T5; ecc_src_a_n=ECC_PMUL_T5;
                        ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0;
                        ecc_job_phase_n=ECC_PHASE_PMUL_FIELD;
                        vrf_req.ra=ECC_PMUL_T4; st_n=S_RD_WAIT;
                    end
                end
                5'd4: begin
                    if (ECC_PMUL_DBL_FROBENIUS) begin
                        st_n=S_ECC_PMUL_STEP_NEXT;
                    end else begin
                        uop_p0_n='0; uop_p0_n.valid=1'b1;
                        uop_p0_n.op_type=UOP_HBIND_CHUNK;
                        uop_p0_n.src0_addr=ECC_PMUL_T1;
                        uop_p0_n.src1_addr=ECC_PMUL_T5;
                        uop_p0_n.dst_addr=ecc_pmul_dbl_x;
                        uop_p0_n.chunk_idx=2'd3;
                        ecc_job_phase_n=ECC_PHASE_PMUL_ADD;
                        st_n=S_UOP_P1_RD0;
                    end
                end
                default: begin hperm_spread_n=1'b1; ecc_dst_n=ecc_pmul_dbl_z; ecc_src_a_n=ecc_pmul_dbl_z; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_req.ra=ECC_PMUL_T2; st_n=S_RD_WAIT; end
                endcase
            end
            ECC_PMUL_SUB_ADD: begin
                unique case (ecc_pmul_step_q)
                5'd0: begin ecc_dst_n=ECC_PMUL_T0; ecc_src_a_n=ECC_PMUL_R0X; ecc_src_b_n=ECC_PMUL_R1Z; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_req.ra=ECC_PMUL_R0X; st_n=S_ECC_LOAD_A_WAIT; end
                5'd1: begin ecc_dst_n=ECC_PMUL_T1; ecc_src_a_n=ECC_PMUL_R1X; ecc_src_b_n=ECC_PMUL_R0Z; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_req.ra=ECC_PMUL_R1X; st_n=S_ECC_LOAD_A_WAIT; end
                5'd2: begin uop_p0_n='0; uop_p0_n.valid=1'b1; uop_p0_n.op_type=UOP_HBIND_CHUNK; uop_p0_n.src0_addr=ECC_PMUL_T0; uop_p0_n.src1_addr=ECC_PMUL_T1; uop_p0_n.dst_addr=ECC_PMUL_T4; uop_p0_n.chunk_idx=2'd3; ecc_job_phase_n=ECC_PHASE_PMUL_ADD; st_n=S_UOP_P1_RD0; end
                5'd3: begin hperm_spread_n=1'b1; ecc_dst_n=ECC_PMUL_ADD_Z_FORWARD ? ecc_pmul_add_out_z : ECC_PMUL_T5; ecc_src_a_n=ECC_PMUL_ADD_Z_FORWARD ? ecc_pmul_add_out_z : ECC_PMUL_T5; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_req.ra=ECC_PMUL_T4; st_n=S_RD_WAIT; end
                5'd4: begin ecc_dst_n=ECC_PMUL_T2; ecc_src_a_n=ecc_pmul_scalar_bit_q ? ECC_PMUL_R1X : ECC_PMUL_R0X; ecc_src_b_n=ecc_pmul_scalar_bit_q ? ECC_PMUL_R1Z : ECC_PMUL_R0Z; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_req.ra=ecc_pmul_scalar_bit_q ? ECC_PMUL_R1X : ECC_PMUL_R0X; st_n=S_ECC_LOAD_A_WAIT; end
                5'd5: begin ecc_dst_n=ECC_PMUL_T6; ecc_src_a_n=ECC_PMUL_T0; ecc_src_b_n=ECC_PMUL_T1; ecc_autoreduce_n=1'b1; ecc_mac_n=1'b0; ecc_sqr_repeat_n='0; ecc_job_phase_n=ECC_PHASE_PMUL_FIELD; vrf_req.ra=ECC_PMUL_T0; st_n=S_ECC_LOAD_A_WAIT; end
                5'd6: begin st_n=S_ECC_PMUL_STEP_NEXT; end
                5'd7: begin st_n=S_ECC_PMUL_STEP_NEXT; end
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
                    ecc_pmul_subop_n=ECC_PMUL_SUB_DBL;
                    st_n=S_ECC_PMUL_STEP;
                end
                ECC_PMUL_SUB_DBL: begin
                    if (ecc_pmul_bit_q == 8'd0) begin
                        ecc_pmul_subop_n=ecc_pmul_r0_inf_n ? ECC_PMUL_SUB_ZERO_OUT : ECC_PMUL_SUB_AFFINE;
                        st_n=(ecc_job_bg_q && valid_i
                           && !vv33_hinfer_active && !vv33_pair_active_q)
                           ? S_IDLE : S_ECC_PMUL_STEP;
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
                    if (ecc_job_bg_q && vv33_hinfer_active) begin
                        // No compatible diagonal lifecycle remains. Complete
                        // the retained resident query on the ordinary shared
                        // HMATCH path before returning the macro response.
                        vv33_pair_active_n=1'b0;
                        vv33_hinfer_pending_n=1'b0;
                        a_n[63]=1'b0;
                        hsim_src0_base_n=VV33_HINFER_QUERY_BASE;
                        hsim_src1_base_n=VV33_HINFER_PROTO_BASE;
                        hmatch_class_slot_n=VV33_HINFER_PROTO_BASE[5:2];
                        hmatch_last_idx_n=VV33_HINFER_LAST_CLASS;
                        st_n=S_HMATCH_INIT;
                    end else if (ecc_job_bg_q) begin
                        st_n=S_IDLE;
                    end else begin
                        res_n={32'b0, ecc_job_cycle_status, 6'b0, ecc_pmul_result_q, 2'b10, STATUS_OK};
                        st_n=S_RESULT;
                    end
                end
                endcase
            end else begin
                ecc_pmul_step_n=ecc_pmul_step_q + 5'd1;
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
            if (VV33_FINE_INTERLEAVE && vv33_sq_commit_q) begin
                vrf_req.wa=ecc_dst_q;
                vrf_req.wd=ecc_square_reduce_word;
                vv33_sq_write_fire=1'b1;
                vv33_sq_commit_n=1'b0;
                if ((ecc_sqr_repeat_q != 7'd0)
                 && (uop_p0_q.op_type == UOP_HBIND_CHUNK)) begin
                    // The next HBIND chunk already needs another VRF read
                    // sequence.  Carry one more square through that existing
                    // lifecycle instead of returning to the ECC square FSM.
                    vv33_sq_phase_n=VV33_SQ_PENDING;
                    ecc_sqr_repeat_n=ecc_sqr_repeat_q - 7'd1;
                end else begin
                    vv33_sq_phase_n=VV33_SQ_DONE;
                end
            end
            vrf_req.ra=uop_p0_q.src0_addr;
            st_n=S_UOP_P1_RD0_WAIT;
        end

        S_UOP_P1_RD0_WAIT: begin
            // HPERM's second row is known when the first row is issued.
            // Launch it one cycle earlier so the registered VRF output is
            // ready when the HPERM payload enters P2.
            if ((uop_p0_q.op_type == UOP_HPERM_CHUNK)
             || uop_p0_use_paired_sources)
                vrf_req.ra=uop_p0_q.src1_addr;
            st_n=S_UOP_P1_RD0_WAIT2;
        end

        S_UOP_P1_RD0_WAIT2: begin
            vrf_req.ra=uop_p0_q.src1_addr;
            st_n=S_UOP_P1_RD1;
        end

        S_UOP_P1_RD1: begin
            if (uop_p0_use_paired_sources) begin
                // The registered public return holds source A while the raw
                // early return holds source B.  Launch the shared matrix now;
                // P3 captures its count on the following cycle.
                uop_p3_n=uop_p0_q;
                uop_p0_n.valid=1'b0;
                st_n=S_UOP_P3_GLOBAL;
            end else if ((uop_p0_q.op_type == UOP_HPERM_CHUNK)
             || (uop_p0_q.op_type == UOP_HCNTADD_SUBGROUP)
             || (uop_p0_q.op_type == UOP_HBIND_CHUNK)
             )
            begin
                hdc_src0_n = vrf_rd;
                hdc_src0_we=1'b1;
                vrf_req.ra=uop_p0_q.src1_addr;
                if (uop_p0_q.op_type == UOP_HPERM_CHUNK)
                    st_n=S_UOP_P2_LANE;
                else
                    st_n=S_UOP_P1_RD1_WAIT;
            end else if (uop_p0_q.op_type == UOP_HCNTCLIP_READ) begin
                hdc_src0_n = '0;
                hdc_src0_we=1'b1;
                vrf_req.ra=uop_p0_q.src1_addr;
                st_n=S_UOP_P1_RD1_WAIT;
            end else begin
                st_n=S_UOP_P1_RD1_WAIT;
            end
        end

        S_UOP_P1_RD1_WAIT: begin
            if (VV33_FINE_INTERLEAVE
             && (vv33_sq_phase_q == VV33_SQ_PENDING)) begin
                vrf_req.ra=ecc_dst_q;
                vv33_sq_phase_n=VV33_SQ_ISSUED;
                vv33_sq_read_fire=1'b1;
            end
            st_n=S_UOP_P2_LANE;
        end

        S_UOP_P2_LANE: begin
            uop_p3_n           = uop_p0_q;
            uop_p0_n.valid     = 1'b0;
`ifndef SYNTHESIS
            assert ($onehot0({
                    ((uop_p0_q.op_type == UOP_HSIM_CHUNK)
                  || (uop_p0_q.op_type == UOP_HMATCH_CHUNK)),
                    uop_p0_use_counter,
                    uop_p0_use_shift,
                    uop_p0_use_clip,
                    (uop_p0_q.op_type == UOP_HBIND_CHUNK)
                }))
                else $error("HDEC P2 invalid compute mode flags: op_type=%0d",
                            uop_p0_q.op_type);
`endif
            if (uop_p0_use_shift) begin
                vrf_req.ra = uop_p0_q.src1_addr;
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
            // Keep one physical byte-window cone.  slot_q always names the
            // window prepared in this cycle; once primed, the previous stage
            // retires concurrently to slot_q-1.  The wrapped slot zero is the
            // final drain cycle.
            hperm_word_sel = {1'b0, hperm_lane_base_q}
                           + {1'b0, hperm_lane_slot_q};
            hperm_next_sel = hperm_word_sel + 3'd1;
            hperm_wide_word = {
                hperm_pick_word(hperm_next_sel, hdc_src0_q, vrf_rd),
                hperm_pick_word(hperm_word_sel,  hdc_src0_q, vrf_rd)
            };
            hperm_stage_n = hperm_byte_window(
                hperm_wide_word, lane_shift_bit[5:3]);
            hperm_stage_we = 1'b1;
            if (!hperm_lane_phase_q) begin
                hperm_lane_phase_n = 1'b1;
                hperm_lane_slot_n = hperm_lane_slot_q + 2'd1;
            end else begin
                hperm_lane_word = hperm_low_shift(hperm_stage_q, lane_shift_bit[2:0]);
                hperm_lane_we = 1'b1;
                if (hperm_lane_slot_q == 2'd0) begin
                    hperm_lane_phase_n = 1'b0;
                    st_n = S_UOP_P3_GLOBAL;
                end else begin
                    hperm_lane_slot_n = hperm_lane_slot_q + 2'd1;
                end
            end
        end

        S_UOP_P3_GLOBAL: begin
            uop_p3_n.valid  = 1'b0;
            if (VV33_FINE_INTERLEAVE
             && (vv33_sq_phase_q == VV33_SQ_ISSUED))
                vv33_sq_commit_n=1'b1;
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
                if (uop_p3_q.chunk_idx == 2'd3) begin
                    if ((uop_p3_q.op_type == UOP_HBIND_CHUNK)
                      && uop_p3_q.is_last_class
                      && vv33_hinfer_active) begin
                        // The encoded query is now architectural in the VRF.
                        // Keep the external macro request alive, then resume
                        // the PMUL from its narrow continuation while the
                        // matching work waits for a compatible diagonal slot.
                        if (ecc_job_bg_q && ecc_job_active_q) begin
                            // A single pending bit retains the completed query.
                            // Clearing the descriptor here prevents the macro
                            // lifetime from entering the shared payload cone.
                            vv33_hinfer_pending_n=1'b1;
                            a_n[63]=1'b0;
                            if (vv33_hinfer_resume_step_q) begin
                                vv33_hinfer_resume_step_n=1'b0;
                                st_n=S_ECC_PMUL_STEP_NEXT;
                            end else if (vv33_sq_phase_q == VV33_SQ_ISSUED) begin
                                // The final HBIND chunk has just consumed the
                                // square result.  Use the existing response
                                // slot only as a conflict-free square commit;
                                // the external inference response remains
                                // owned by the later paired HMATCH.
                                st_n=S_UOP_P4_RESP;
                            end else if (vv33_sq_phase_q == VV33_SQ_DONE) begin
                                vv33_sq_phase_n=VV33_SQ_IDLE;
                                if (ecc_sqr_repeat_q != 7'd0) begin
                                    hperm_spread_n=1'b1;
                                    ecc_src_a_n=ecc_dst_q;
                                    ecc_autoreduce_n=1'b1;
                                    ecc_sqr_repeat_n=ecc_sqr_repeat_q-7'd1;
                                    vrf_req.ra=ecc_dst_q;
                                    st_n=S_RD_WAIT;
                                end else if (ecc_job_phase_q == ECC_PHASE_INV_SQR) begin
                                    st_n=S_ECC_INV_AFTER_SQR;
                                end else begin
                                    ecc_job_phase_n=ECC_PHASE_NONE;
                                    st_n=S_ECC_PMUL_STEP_NEXT;
                                end
                            end else begin
                                st_n=S_ECC_BG_DISPATCH;
                            end
                        end else begin
                            vv33_hinfer_pending_n=1'b0;
                            a_n[63]=1'b0;
                            hsim_src0_base_n=VV33_HINFER_QUERY_BASE;
                            hsim_src1_base_n=VV33_HINFER_PROTO_BASE;
                            hmatch_class_slot_n=VV33_HINFER_PROTO_BASE[5:2];
                            hmatch_last_idx_n=VV33_HINFER_LAST_CLASS;
                            st_n=S_HMATCH_INIT;
                        end
                    end else if ((uop_p3_q.op_type == UOP_HPERM_CHUNK)
                              && uop_p3_q.is_last_class
                              && vv33_hinfer_active) begin
                        // The role permutation has reached the resident query
                        // slot.  Continue the same external macro request by
                        // launching the existing four-chunk HBIND pipeline.
                        uop_p0_n='0;
                        uop_p0_n.valid=1'b1;
                        uop_p0_n.op_type=UOP_HBIND_CHUNK;
                        uop_p0_n.src0_addr=VV33_HINFER_QUERY_BASE;
                        uop_p0_n.src1_addr=VV33_HINFER_INPUT_BASE;
                        uop_p0_n.dst_addr=VV33_HINFER_QUERY_BASE;
                        uop_p0_n.chunk_idx=2'd0;
                        uop_p0_n.is_last_class=1'b1;
                        st_n=S_UOP_P1_RD0;
                    end else begin
                        st_n = S_UOP_P4_RESP;
                    end
                end
                else begin
                    uop_p0_n = uop_p3_q; uop_p0_n.valid = 1'b1;
                    uop_p0_n.chunk_idx = uop_p3_q.chunk_idx + 2'd1;
                    if (uop_p3_q.op_type == UOP_HPERM_CHUNK) begin
                        // HPERM keeps both reads inside the source HV while
                        // advancing its wrapped two-row window.
                        uop_p0_n.src0_addr[1:0] =
                            uop_p3_q.src0_addr[1:0] + 2'd1;
                        uop_p0_n.src1_addr[1:0] =
                            uop_p3_q.src0_addr[1:0] + 2'd2;
                    end else begin
                        // HBIND advances the two independent source streams.
                        uop_p0_n.src0_addr =
                            uop_p3_q.src0_addr + 6'd1;
                        uop_p0_n.src1_addr =
                            uop_p3_q.src1_addr + 6'd1;
                    end
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
                    // Advance the retained P0 uop directly to the next P2
                    // subgroup, skipping the full P1 two-source read sequence.
                    uop_p0_n = uop_p3_q; uop_p0_n.valid = 1'b1;
                    uop_p0_n.subgroup_idx = uop_p3_q.subgroup_idx + 2'd1;
                    uop_p0_n.src1_addr = uop_p3_q.dst_addr + 6'd1;
                    uop_p0_n.dst_addr = uop_p3_q.dst_addr + 6'd1;
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
                for (int lid = 0; lid < LANE_NUM; lid++) begin
                    hdc_src0_n[lid] = {
                        vec_payload_q[lid][15:0],
                        hdc_src0_q[lid][63:16]
                    };
                end
                hdc_src0_we=1'b1;
                if (uop_p3_q.subgroup_idx < 2'd3) begin
                    vrf_req.ra=hcntclip_acc_base+{2'b00,uop_p3_q.chunk_idx,2'b00}+{4'b0,(uop_p3_q.subgroup_idx + 2'd1)};
                    uop_p0_n = uop_p3_q; uop_p0_n.valid = 1'b1;
                    uop_p0_n.subgroup_idx = uop_p3_q.subgroup_idx + 2'd1;
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
            st_n=S_UOP_P2_LANE;
        end

        S_UOP_P3_POP_CAPTURE: begin
            if (VV33_FINE_INTERLEAVE && vv33_sq_commit_q) begin
                vrf_req.wa=ecc_dst_q;
                vrf_req.wd=ecc_square_reduce_word;
                vv33_sq_write_fire=1'b1;
                vv33_sq_commit_n=1'b0;
                if ((ecc_sqr_repeat_q != 7'd0)
                 && ((uop_p3_q.chunk_idx != 2'd3)
                  || ((uop_p3_q.op_type == UOP_HMATCH_CHUNK)
                   && !uop_p3_q.is_last_class))) begin
                    // Similarity and matching naturally revisit the same
                    // four-chunk pipeline.  Re-arm the narrow square token
                    // while another chunk remains, without adding a new data
                    // path or square-result register.
                    vv33_sq_phase_n=VV33_SQ_PENDING;
                    ecc_sqr_repeat_n=ecc_sqr_repeat_q - 7'd1;
                end else begin
                    vv33_sq_phase_n=VV33_SQ_DONE;
                end
            end
            group_dist_n = group_dist_sum;
            st_n=S_UOP_P3_ACCUM;
        end

        S_UOP_P3_ACCUM: begin
            hsim_total_n = hsim_total_step;
            if (uop_p3_q.chunk_idx == 2'd3) begin
                if (uop_p3_q.op_type == UOP_HMATCH_CHUNK) begin
                    if (hsim_total_step > hmatch_best_dist_q) begin
                        hmatch_best_dist_n = hsim_total_step;
                        hmatch_best_idx_n  = uop_p3_q.class_idx;
                    end
                    if (uop_p3_q.is_last_class) begin
                        st_n = S_UOP_P4_RESP;
                    end else begin
                        hsim_total_n = '0;
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
            vrf_req.wa={1'b0,hcntclip_dst_base_q[4:0]}+hcntclip_chunk_q;
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
            if (VV33_FINE_INTERLEAVE && vv33_sq_commit_q) begin
                // HBIND writes its final vector chunk in P3.  P4 is the first
                // conflict-free slot in which the accompanying ECC square can
                // commit through the existing 1R1W VRF interface.
                vrf_req.wa=ecc_dst_q;
                vrf_req.wd=ecc_square_reduce_word;
                vv33_sq_phase_n=VV33_SQ_DONE;
                vv33_sq_write_fire=1'b1;
                vv33_sq_commit_n=1'b0;
            end
            res_n = '0;
            if (vv33_hinfer_active
             && (uop_p3_q.op_type == UOP_HBIND_CHUNK)
             && uop_p3_q.is_last_class
             && vv33_sq_commit_q) begin
                // Finish the square lifecycle without exposing an early HDC
                // response.  Any remaining serial squares return to the
                // original ECC path before PMUL advances.
                vv33_sq_phase_n=VV33_SQ_IDLE;
                if (ecc_sqr_repeat_q != 7'd0) begin
                    hperm_spread_n=1'b1;
                    ecc_src_a_n=ecc_dst_q;
                    ecc_autoreduce_n=1'b1;
                    ecc_sqr_repeat_n=ecc_sqr_repeat_q-7'd1;
                    vrf_req.ra=ecc_dst_q;
                    st_n=S_RD_WAIT;
                end else begin
                    ecc_job_phase_n=ECC_PHASE_NONE;
                    st_n=S_ECC_PMUL_STEP_NEXT;
                end
            end else if (uop_p3_q.op_type == UOP_HSIM_CHUNK) begin
                res_n = {53'b0, hsim_total_q};
                st_n = S_RESULT;
            end else if (uop_p3_q.op_type == UOP_HMATCH_CHUNK) begin
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
            if (VV33_FINE_INTERLEAVE
             && ecc_job_bg_q
             && ecc_job_active_q
             && (vv33_sq_phase_q == VV33_SQ_DONE)) begin
                vv33_sq_phase_n=VV33_SQ_IDLE;
                if (ecc_sqr_repeat_q != 7'd0) begin
                    // Resume the deterministic square chain.  This path is
                    // shared by a completed overlapped square and a parked
                    // non-overlap HDC instruction.
                    hperm_spread_n=1'b1;
                    ecc_src_a_n=ecc_dst_q;
                    ecc_autoreduce_n=1'b1;
                    ecc_sqr_repeat_n=ecc_sqr_repeat_q - 7'd1;
                    vrf_req.ra=ecc_dst_q;
                    st_n=S_RD_WAIT;
                end else if (ecc_job_phase_q == ECC_PHASE_INV_SQR) begin
                    st_n=S_ECC_INV_AFTER_SQR;
                end else begin
                    ecc_job_phase_n=ECC_PHASE_NONE;
                    st_n=S_ECC_PMUL_STEP_NEXT;
                end
            end else if (VV33_FINE_INTERLEAVE
                      && ecc_job_bg_q
                      && ecc_job_active_q
                      && (vv33_sq_phase_q != VV33_SQ_IDLE)) begin
                // Invalid HMATCH parameters take this exact-square replay.
                vv33_sq_phase_n=VV33_SQ_IDLE;
                hperm_spread_n=1'b1;
                ecc_src_a_n=ecc_dst_q;
                ecc_autoreduce_n=1'b1;
                vrf_req.ra=ecc_dst_q;
                st_n=S_RD_WAIT;
            end else begin
                st_n=(ecc_job_bg_q && ecc_job_active_q)
                   ? S_ECC_BG_DISPATCH : S_IDLE;
            end
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
        for (int unsigned bid = 0; bid < LANE_NUM; bid++)
            vrf_bank_ra[bid] = vrf_ra_q;
        vrf_we = vrf_we_direct;
        vrf_wa = vrf_req.wa;
        vrf_wd = vrf_req.wd;
    end

`ifndef SYNTHESIS
    // VV31 simulation-only resource events. These probes never participate in
    // arbitration; they give matched baseline and candidate runs stable names.
    localparam logic [2:0] VV31_VRF_OWNER_NONE = 3'd0;
    localparam logic [2:0] VV31_VRF_OWNER_HDC  = 3'd1;
    localparam logic [2:0] VV31_VRF_OWNER_ECC  = 3'd2;

    logic       vv31_evt_hdc_matrix;
    logic       vv31_evt_ecc_matrix;
    logic       vv31_evt_hdc_xor0;
    logic       vv31_evt_ecc_xor0;
    logic       vv31_evt_ecc_square;
    logic       vv31_evt_ecc_vrf_prefetch;
    logic       vv31_evt_ecc_entry_b_prefetch;
    logic       vv31_evt_ecc_leaf_operand_prefetch;
    logic       vv31_evt_ecc_leaf_preissue;
    logic       vv31_evt_ecc_t1_prefetch;
    logic       vv31_evt_ecc_t2_prefetch_a;
    logic       vv31_evt_ecc_t2_prefetch_b;
    logic       vv31_evt_hdc_vrf_read;
    logic       vv31_evt_ecc_control_progress;
    logic       vv31_evt_vrf_write;
    logic [2:0] vv31_evt_vrf_read_owner;
    logic [2:0] vv31_evt_vrf_write_owner;

    always_comb begin
        vv31_evt_hdc_matrix = hdc_pop_product_issue
                           || vv33_pair_product_fire;
        vv31_evt_ecc_matrix = ecc_diag_product_issue;
        vv31_evt_hdc_xor0   = hdc_xor_issue;
        vv31_evt_ecc_xor0   = hdc_src0_acc_we;
        vv31_evt_ecc_square = (st_q == S_ECC_SQR_WRITE);

        // Named evidence events for the accepted ECC-only schedule.  They are
        // observation points only and are removed from synthesis.
        vv31_evt_ecc_entry_b_prefetch =
            (st_q == S_ECC_LOAD_A_WAIT) && ecc_diag_early_b_load;
        vv31_evt_ecc_leaf_operand_prefetch =
            (VV31_SCHED_ENABLE
             && ecc_diag_sub_shadow_mode
             && !ecc_leaf_last
             && (((st_q == S_ECC_DIAG_CAPTURE2)
                  && (ecc_kpd64_sub_q == 2'd1))
                 || ((st_q == S_ECC_DIAG_FOLD_ISSUE)
                  && (ecc_kpd64_sub_q == 2'd1))));
        vv31_evt_ecc_leaf_preissue = ecc_diag_leaf_preissue;
        vv31_evt_ecc_t1_prefetch =
            (st_q == S_ECC_WRITE_PAIR) && ecc_pmul_add_t1_prefetch;
        vv31_evt_ecc_t2_prefetch_a =
            (st_q == S_RD_WAIT) && ecc_pmul_add_t2_prefetch;
        vv31_evt_ecc_t2_prefetch_b =
            (st_q == S_RD_WAIT2) && ecc_pmul_add_t2_prefetch;
        vv31_evt_ecc_vrf_prefetch =
            vv31_evt_ecc_entry_b_prefetch
          || vv31_evt_ecc_leaf_operand_prefetch
          || vv31_evt_ecc_t1_prefetch
          || vv31_evt_ecc_t2_prefetch_a
          || vv31_evt_ecc_t2_prefetch_b;

        vv31_evt_hdc_vrf_read = 1'b0;
        unique case (st_q)
        S_UOP_P1_RD0,
        S_UOP_P1_RD0_WAIT2,
        S_UOP_P1_RD1,
        S_HPERM_LANE64:
            vv31_evt_hdc_vrf_read =
                !(ecc_job_active_q
               && (ecc_job_phase_q == ECC_PHASE_PMUL_ADD));
        S_UOP_P1_RD0_WAIT:
            vv31_evt_hdc_vrf_read =
                (uop_p0_q.op_type == UOP_HPERM_CHUNK)
             && !(ecc_job_active_q
               && (ecc_job_phase_q == ECC_PHASE_PMUL_ADD));
        S_UOP_P2_LANE:
            vv31_evt_hdc_vrf_read = uop_p0_use_shift;
        S_UOP_P3_GLOBAL:
            vv31_evt_hdc_vrf_read =
                (uop_p3_q.op_type == UOP_HCNTADD_SUBGROUP)
             || (uop_p3_q.op_type == UOP_HCNTCLIP_READ);
        S_EXEC:
            vv31_evt_hdc_vrf_read = (op_q == HDEC_VRD64);
        default:
            vv31_evt_hdc_vrf_read = 1'b0;
        endcase

        vv31_evt_vrf_read_owner = VV31_VRF_OWNER_NONE;
        if (vv31_evt_hdc_vrf_read)
            vv31_evt_vrf_read_owner = VV31_VRF_OWNER_HDC;
        else if (vv31_evt_ecc_vrf_prefetch
              || (ecc_job_active_q
              && ((st_q inside {S_ECC_LOAD_A_WAIT,
                                 S_ECC_LOAD_A_WAIT2,
                                 S_ECC_LOAD_A,
                                S_ECC_LOAD_B_WAIT,
                                S_ECC_DIAG_FOLD_ISSUE,
                                S_ECC_DIAG_CAPTURE0,
                                S_ECC_LEAF_FOLD,
                                S_ECC_INV_COPY_WAIT,
                                S_ECC_INV_COPY_WAIT2,
                                S_ECC_INV_STEP,
                                S_ECC_PMUL_INIT,
                                S_ECC_PMUL_READ_SCALAR_WAIT,
                                 S_ECC_PMUL_STEP})
               || (ecc_job_phase_q == ECC_PHASE_PMUL_ADD))))
            vv31_evt_vrf_read_owner = VV31_VRF_OWNER_ECC;

        vv31_evt_vrf_write = |vrf_we_direct;
        vv31_evt_vrf_write_owner = VV31_VRF_OWNER_NONE;
        if (vv31_evt_vrf_write) begin
            if ((st_q inside {S_ECC_SQR_WRITE,
                              S_ECC_INV_COPY_WRITE,
                              S_ECC_PMUL_CONST_WRITE,
                              S_ECC_WRITE_PAIR})
             || (ecc_job_active_q
              && (ecc_job_phase_q == ECC_PHASE_PMUL_ADD)))
                vv31_evt_vrf_write_owner = VV31_VRF_OWNER_ECC;
            else
                vv31_evt_vrf_write_owner = VV31_VRF_OWNER_HDC;
        end

        vv31_evt_ecc_control_progress =
            ecc_job_active_q
         && (st_n != st_q)
         && !vv31_evt_ecc_matrix
         && !vv31_evt_ecc_xor0
         && !vv31_evt_ecc_square
         && (vv31_evt_vrf_read_owner == VV31_VRF_OWNER_NONE)
         && (vv31_evt_vrf_write_owner == VV31_VRF_OWNER_NONE);
    end

    // The low-area deferred-square implementation intentionally does not add
    // a global write-address selector.  Prove that its token can be consumed
    // only by the two foreground phases that provide the compatible 1R1W slot.
    always_ff @(posedge clk_i) begin
        if (rst_ni && vv33_pair_active_q) begin
            assert (VV31_SCHED_ENABLE)
                else $error("VV33 paired search active without scheduler support");
            assert (ecc_job_bg_q && ecc_job_active_q
                    && (ecc_job_kind_q == ECC_JOB_PMUL))
                else $error("VV33 paired search escaped the background PMUL lifetime");
            assert (vv33_pair_class_idx_q <= 2'd2)
                else $error("VV33 paired search escaped the reserved HDC VRF partition");
        end
        if (rst_ni && (vv33_pair_product_fire || vv33_pair_pop_fire
                    || vv33_pair_fold_launch)) begin
            assert (ecc_diag_sub_shadow_mode
                    && (ecc_job_phase_q == ECC_PHASE_PMUL_FIELD))
                else $error("VV33 paired data event escaped a compatible diagonal lifecycle");
        end
        if (rst_ni && VV33_FINE_INTERLEAVE && vv33_sq_commit_q) begin
            assert (st_q inside {S_UOP_P1_RD0,
                                 S_UOP_P3_POP_CAPTURE,
                                 S_UOP_P4_RESP})
                else $error("VV33 deferred square escaped compatible phase: st=%0d", st_q);
            assert (!$isunknown({vrf_req.wa, vrf_req.wd, vrf_we_direct}))
                else $error("VV33 deferred square attempted an unknown VRF write");
        end
    end
`endif

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
            hmatch_last_idx_q<='0;hmatch_best_idx_q<='0;hmatch_class_slot_q<='0;hmatch_best_dist_q<='0;
            hperm_bit_low_q<='0;hperm_spread_q<=1'b0;hperm_lane_base_q<='0;
            hperm_lane_slot_q<='0;hperm_lane_phase_q<=1'b0;hperm_stage_q<='0;
            hcntclip_dst_base_q<='0;hcntclip_acc_sel_q<='0;hcntclip_chunk_q<='0;
            vrf_ra_q<='0;
            uop_p0_q<='0;uop_p3_q<='0;
            hdc_src0_q<='0;
            ecc_src_a_q<='0;ecc_src_b_q<='0;ecc_dst_q<='0;ecc_acc_dst_q<='0;
            ecc_leaf_a_q<='0;ecc_leaf_b_q<='0;ecc_leaf_prod_q<='0;ecc_leaf_path_q<='0;ecc_fold_word_q<='0;
            ecc_leaf_xor_a_q<='0;ecc_leaf_xor_b_q<='0;ecc_leaf128_prod_q<='0;ecc_kpd64_sub_q<='0;
            ecc_autoreduce_q<=1'b0;ecc_raw_product_q<=1'b0;ecc_mac_q<=1'b0;ecc_sqr_repeat_q<='0;
            ecc_job_kind_q<=ECC_JOB_NONE;ecc_job_phase_q<=ECC_PHASE_NONE;ecc_job_active_q<=1'b0;ecc_job_done_q<=1'b0;ecc_job_bg_q<=1'b0;ecc_job_cycle_q<='0;ecc_inv_step_q<='0;ecc_job_src_q<='0;ecc_job_dst_q<='0;
            ecc_pmul_subop_q<=ECC_PMUL_SUB_NONE;ecc_pmul_step_q<='0;ecc_pmul_bit_q<='0;ecc_pmul_scalar_bit_q<=1'b0;
            ecc_pmul_r0_inf_q<=1'b1;ecc_pmul_result_q<='0;ecc_pmul_point_q<='0;
            vv33_sq_phase_q<=VV33_SQ_IDLE;
            vv33_sq_commit_q<=1'b0;
            vv33_pair_active_q<=1'b0;vv33_pair_a_sent_q<=1'b0;
            vv33_pair_next_q<=1'b0;vv33_pair_read_ready_q<=1'b0;
            vv33_pair_product_q<=1'b0;vv33_pair_pop_q<=1'b0;
            vv33_pair_sum_q<=1'b0;
            vv33_pair_finish_q<=1'b0;
            vv33_pair_resp_q<=1'b0;
            vv33_pair_class_idx_q<='0;
            vv33_pair_chunk_q<='0;vv33_pair_total_q<='0;
            vv33_pair_best_q<='0;vv33_pair_best_idx_q<='0;
            vv33_hinfer_pending_q<=1'b0;
            vv33_hinfer_rot_q<='0;
            vv33_hinfer_resume_step_q<=1'b0;
        end
        else begin
            st_q<=st_n;res_q<=res_n;op_q<=op_n;a_q<=a_n;
            vaddr_bank_q<=vaddr_bank_n;vaddr_idx_q<=vaddr_idx_n;clr_cnt_q<=clr_cnt_n;clr_base_q<=clr_base_n;
            hsim_src0_base_q<=hsim_src0_base_n;hsim_src1_base_q<=hsim_src1_base_n;hsim_total_q<=hsim_total_n;group_dist_q<=group_dist_n;
            hmatch_last_idx_q<=hmatch_last_idx_n;hmatch_best_idx_q<=hmatch_best_idx_n;hmatch_class_slot_q<=hmatch_class_slot_n;hmatch_best_dist_q<=hmatch_best_dist_n;
            hperm_bit_low_q<=hperm_bit_low_n;hperm_spread_q<=hperm_spread_n;hperm_lane_base_q<=hperm_lane_base_n;
            hperm_lane_slot_q<=hperm_lane_slot_n;hperm_lane_phase_q<=hperm_lane_phase_n;
            if (hperm_stage_we) hperm_stage_q<=hperm_stage_n;
            hcntclip_dst_base_q<=hcntclip_dst_base_n;hcntclip_acc_sel_q<=hcntclip_acc_sel_n;hcntclip_chunk_q<=hcntclip_chunk_n;
            vrf_ra_q<=vrf_ra;
            uop_p0_q<=uop_p0_n;uop_p3_q<=uop_p3_n;
            if (hdc_src0_acc_we) begin
                hdc_src0_q[0]<=xor0_field_packet[63:0];
                hdc_src0_q[1]<=xor0_field_packet[127:64];
                hdc_src0_q[2]<=xor0_field_packet[191:128];
                hdc_src0_q[3]<={23'b0, xor0_field_packet[232:192]};
            end else if (hdc_src0_we) begin
                hdc_src0_q<=hdc_src0_n;
            end
            ecc_src_a_q<=ecc_src_a_n;ecc_src_b_q<=ecc_src_b_n;ecc_dst_q<=ecc_dst_n;ecc_acc_dst_q<=ecc_acc_dst_n;
            ecc_leaf_a_q<=ecc_leaf_a_n;ecc_leaf_b_q<=ecc_leaf_b_n;
            ecc_leaf_prod_q<=ecc_leaf_prod_n;ecc_leaf_path_q<=ecc_leaf_path_n;ecc_fold_word_q<=ecc_fold_word_n;
            ecc_leaf_xor_a_q<=ecc_leaf_xor_a_n;ecc_leaf_xor_b_q<=ecc_leaf_xor_b_n;
            ecc_leaf128_prod_q<=ecc_leaf128_prod_n;ecc_kpd64_sub_q<=ecc_kpd64_sub_n;
            ecc_autoreduce_q<=ecc_autoreduce_n;ecc_raw_product_q<=ecc_raw_product_n;
            ecc_mac_q<=ecc_mac_n;ecc_sqr_repeat_q<=ecc_sqr_repeat_n;
            ecc_job_kind_q<=ecc_job_kind_n;ecc_job_phase_q<=ecc_job_phase_n;ecc_job_active_q<=ecc_job_active_n;ecc_job_done_q<=ecc_job_done_n;ecc_job_bg_q<=ecc_job_bg_n;ecc_job_cycle_q<=ecc_job_cycle_n;ecc_inv_step_q<=ecc_inv_step_n;ecc_job_src_q<=ecc_job_src_n;ecc_job_dst_q<=ecc_job_dst_n;
            ecc_pmul_subop_q<=ecc_pmul_subop_n;ecc_pmul_step_q<=ecc_pmul_step_n;ecc_pmul_bit_q<=ecc_pmul_bit_n;ecc_pmul_scalar_bit_q<=ecc_pmul_scalar_bit_n;
            ecc_pmul_r0_inf_q<=ecc_pmul_r0_inf_n;ecc_pmul_result_q<=ecc_pmul_result_n;ecc_pmul_point_q<=ecc_pmul_point_n;
            vv33_sq_phase_q<=vv33_sq_phase_n;
            vv33_sq_commit_q<=vv33_sq_commit_n;
            vv33_pair_active_q<=vv33_pair_active_n;
            vv33_pair_a_sent_q<=vv33_pair_a_sent_n;
            vv33_pair_next_q<=vv33_pair_next_n;
            vv33_pair_read_ready_q<=vv33_pair_read_ready_n;
            vv33_pair_product_q<=vv33_pair_product_n;
            vv33_pair_pop_q<=vv33_pair_pop_n;
            vv33_pair_sum_q<=vv33_pair_sum_n;
            vv33_pair_finish_q<=vv33_pair_finish_n;
            vv33_pair_resp_q<=vv33_pair_resp_n;
            vv33_pair_class_idx_q<=vv33_pair_class_idx_n;
            vv33_pair_chunk_q<=vv33_pair_chunk_n;
            vv33_pair_total_q<=vv33_pair_total_n;
            vv33_pair_best_q<=vv33_pair_best_n;
            vv33_pair_best_idx_q<=vv33_pair_best_idx_n;
            vv33_hinfer_pending_q<=vv33_hinfer_pending_n;
            vv33_hinfer_rot_q<=vv33_hinfer_rot_n;
            vv33_hinfer_resume_step_q<=vv33_hinfer_resume_step_n;
        end
    end

endmodule
