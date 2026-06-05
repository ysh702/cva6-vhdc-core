// hdec_top.sv — HDCU Phase: VRF mgmt + HDC compute FSM
// HDCU instruction subset: VWR64, VRD64, HCLR, HCNTCLR, HCNTADD,
// HBIND, HPERM, HSIM, HCNTCLIP, HMATCH, VADDR.
// No bundle, no add/sub counter, no BMCA.
module hdec_top import hdec_pkg::*; import hdec_resource_pkg::*; (
    input logic clk_i, rst_ni, valid_i, output logic ready_o,
    input hdec_op_t operator_i, input logic [63:0] operand_a_i, operand_b_i,
    output logic valid_o, output logic [63:0] result_o
);
    logic [LANE_NUM-1:0][VRF_IDX_W-1:0] vrf_ra; logic [LANE_NUM-1:0][LANE_WIDTH-1:0] vrf_rd;
    logic [LANE_NUM-1:0] vrf_we; logic [LANE_NUM-1:0][VRF_IDX_W-1:0] vrf_wa; logic [LANE_NUM-1:0][LANE_WIDTH-1:0] vrf_wd;
    hdec_vrf_64x256 i_vrf(.clk_i,.rst_ni,.bank_ra_addr_i(vrf_ra),.bank_ra_data_o(vrf_rd),.bank_we_i(vrf_we),.bank_wa_addr_i(vrf_wa),.bank_wdata_i(vrf_wd),.vrf_ready_o());
    logic [VRF_BNK_W-1:0] vaddr_bank_q,vaddr_bank_n; logic [VRF_IDX_W-1:0] vaddr_idx_q,vaddr_idx_n;

    // ── State Machine ───────────────────────────────────────────────────────
    typedef enum logic [4:0] {
        S_IDLE, S_EXEC, S_RD_WAIT, S_RESULT, S_CLR,
        S_UOP_P1_RD0, S_UOP_P1_RD1, S_UOP_P2_LANE, S_UOP_P3_GLOBAL, S_UOP_P4_RESP,
        S_UOP_CLIP_WRITE
    } st_t;
    st_t st_q, st_n;

    logic [63:0] res_q,res_n; hdec_op_t op_q,op_n; logic [63:0] a_q,a_n,b_q,b_n; logic [VRF_BNK_W-1:0] bk_q,bk_n;
    logic [3:0] clr_cnt_q,clr_cnt_n; logic [VRF_IDX_W-1:0] clr_base_q,clr_base_n;

    // ── HBIND registers ─────────────────────────────────────────────────────
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] src0_q,src0_n;
    logic [1:0] chunk_cnt_q,chunk_cnt_n;
    logic [VRF_IDX_W-1:0] hb_dst_base_q,hb_dst_base_n, hb_src0_base_q,hb_src0_base_n, hb_src1_base_q,hb_src1_base_n;

    // ── HSIM / HMATCH registers ─────────────────────────────────────────────
    logic [VRF_IDX_W-1:0] hsim_src0_base_q,hsim_src0_base_n, hsim_src1_base_q,hsim_src1_base_n;
    logic [10:0] hsim_total_q,hsim_total_n;
    logic [7:0] hmatch_num_q,hmatch_num_n,hmatch_best_idx_q,hmatch_best_idx_n;
    logic [3:0] hmatch_class_slot_q,hmatch_class_slot_n;
    logic [10:0] hmatch_best_dist_q,hmatch_best_dist_n;

    // ── HPERM registers ─────────────────────────────────────────────────────
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] hperm_a_q,hperm_a_n;
    logic [VRF_IDX_W-1:0] hperm_dst_base_q,hperm_dst_base_n, hperm_src_base_q,hperm_src_base_n;
    logic [3:0] hperm_word_off_q,hperm_word_off_n;
    logic [1:0] hperm_lane_base_q,hperm_lane_base_n;
    logic [4:0] hperm_word0;
    logic [1:0] hperm_next_chunk;

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
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] local_vec64_result;
    logic [LANE_NUM-1:0][6:0]            local_pop7_result;
    logic [LANE_NUM-1:0][15:0]           local_clip16_result;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] lane_shift_a,lane_shift_b;

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
    logic [LANE_NUM-1:0][6:0]            lane_popcnt_q, lane_popcnt_n;
    logic [LANE_NUM-1:0][15:0]           lane_clip_q, lane_clip_n;

    // ── Scalar Response Registers (P4) ──────────────────────────────────────
    logic [63:0] scalar_response_q, scalar_response_n;
    logic        response_valid_q, response_valid_n;
    hdec_op_t    p4_arch_op_q, p4_arch_op_n;  // saved arch_op for P4 response pack
    logic [10:0] group_dist;

    // ── Combinational helpers ───────────────────────────────────────────────
    assign hperm_word0 = {1'b0,chunk_cnt_q,2'b00} + {1'b0,hperm_word_off_q};
    assign hperm_next_chunk = hperm_word0[3:2] + 2'd1;
    assign hcntadd_acc_base = hcntadd_acc_sel_q ? 6'd48 : 6'd32;
    assign hcntclip_acc_base = hcntclip_acc_sel_q ? 6'd48 : 6'd32;

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

    // ── 4× Lane instances ───────────────────────────────────────────────────
    for (genvar lid = 0; lid < LANE_NUM; lid++) begin : gen_lane
        hdec_lane_p2_local #(.LANE_ID(lid)) i_lane_p2_local (
            .clk_i, .rst_ni,
            .lane_ctrl_i(uop_p2_q.lane_ctrl),
            .bool_src_a_i(src0_q[lid]),
            .bool_src_b_i(vrf_rd[lid]),
            .cnt_hv_word_i(hcntadd_hv_q[lid]),
            .cnt_old_counter_i(vrf_rd[lid]),
            .shift_src_a_i(lane_shift_a[lid]),
            .shift_src_b_i(lane_shift_b[lid]),
            .clip_counter_i(vrf_rd[lid]),
            .vec64_result_o(local_vec64_result[lid]),
            .pop7_result_o(local_pop7_result[lid]),
            .clip16_result_o(local_clip16_result[lid])
        );
    end

    // ── Main FSM ────────────────────────────────────────────────────────────
    always_comb begin
        st_n=st_q; ready_o=(st_q==S_IDLE); valid_o=(st_q==S_RESULT); result_o=response_valid_q?scalar_response_q:res_q;
        res_n=res_q; op_n=op_q; a_n=a_q; b_n=b_q; bk_n=bk_q; vaddr_bank_n=vaddr_bank_q; vaddr_idx_n=vaddr_idx_q;
        clr_cnt_n=clr_cnt_q; clr_base_n=clr_base_q;
        src0_n=src0_q; chunk_cnt_n=chunk_cnt_q;
        hb_dst_base_n=hb_dst_base_q; hb_src0_base_n=hb_src0_base_q; hb_src1_base_n=hb_src1_base_q;
        hsim_src0_base_n=hsim_src0_base_q; hsim_src1_base_n=hsim_src1_base_q; hsim_total_n=hsim_total_q;
        hmatch_num_n=hmatch_num_q; hmatch_best_idx_n=hmatch_best_idx_q; hmatch_class_slot_n=hmatch_class_slot_q; hmatch_best_dist_n=hmatch_best_dist_q;
        hperm_a_n=hperm_a_q; hperm_dst_base_n=hperm_dst_base_q; hperm_src_base_n=hperm_src_base_q;
        hperm_word_off_n=hperm_word_off_q; hperm_lane_base_n=hperm_lane_base_q;
        hcntadd_hv_n=hcntadd_hv_q; hcntadd_hv_slot_n=hcntadd_hv_slot_q; hcntadd_chunk_n=hcntadd_chunk_q; hcntadd_subgroup_n=hcntadd_subgroup_q; hcntadd_acc_sel_n=hcntadd_acc_sel_q;
        hcntclip_dst_base_n=hcntclip_dst_base_q; hcntclip_acc_sel_n=hcntclip_acc_sel_q; hcntclip_threshold_n=hcntclip_threshold_q; hcntclip_chunk_n=hcntclip_chunk_q; hcntclip_subgroup_n=hcntclip_subgroup_q; hcntclip_word_n=hcntclip_word_q; hcntclip_word_with_result=hcntclip_word_q;
        uop_p0_n=uop_p0_q; uop_p1_n=uop_p1_q; uop_p2_n=uop_p2_q; uop_p3_n=uop_p3_q;
        lane_result_n=lane_result_q; lane_popcnt_n=lane_popcnt_q; lane_clip_n=lane_clip_q;
        scalar_response_n=scalar_response_q; response_valid_n=response_valid_q; p4_arch_op_n=p4_arch_op_q;
        group_dist='0;
        lane_shift_a='0; lane_shift_b='0;
        vrf_ra='0; vrf_we='0; vrf_wa='0; vrf_wd='0;

        case(st_q)
        S_IDLE: if(valid_i&&ready_o)begin op_n=operator_i;a_n=operand_a_i;b_n=operand_b_i;st_n=S_EXEC;end

        S_EXEC: begin uop_p0_n='0; unique case(op_q)
            HDEC_VADDR: begin vaddr_bank_n=a_q[7:6];vaddr_idx_n=a_q[5:0];res_n='0;st_n=S_RESULT;end
            HDEC_VWR64: begin vrf_we[vaddr_bank_q]=1'b1;vrf_wa[vaddr_bank_q]=vaddr_idx_q;vrf_wd[vaddr_bank_q]=a_q;res_n='0;st_n=S_RESULT;end
            HDEC_VRD64: begin vrf_ra[vaddr_bank_q]=vaddr_idx_q;bk_n=vaddr_bank_q;st_n=S_RD_WAIT;end

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
                    uop_p0_n.arch_op     = HDEC_HCNTADD;
                    uop_p0_n.chunk_idx   = 2'd0;
                    uop_p0_n.subgroup_idx= 2'd0;
                    uop_p0_n.src0_addr   = {1'b0, a_q[2:0], 2'b00};
                    uop_p0_n.src1_addr   = a_q[4] ? 6'd48 : 6'd32;
                    uop_p0_n.lane_ctrl.valid        = 1'b1;
                    uop_p0_n.lane_ctrl.op           = HDEC_LANE_CNTADD;
                    uop_p0_n.lane_ctrl.capture_kind = HDEC_CAPTURE_VEC64;
                    uop_p0_n.lane_ctrl.subgroup     = 2'd0;
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
                uop_p0_n.arch_op      = HDEC_HBIND;
                uop_p0_n.src0_addr    = hb_src0_base_n;
                uop_p0_n.src1_addr    = hb_src1_base_n;
                uop_p0_n.dst_addr     = hb_dst_base_n;
                uop_p0_n.src0_base    = hb_src0_base_n;
                uop_p0_n.src1_base    = hb_src1_base_n;
                uop_p0_n.dst_base     = hb_dst_base_n;
                uop_p0_n.chunk_idx    = 2'd0;
                uop_p0_n.lane_ctrl.valid        = 1'b1;
                uop_p0_n.lane_ctrl.op           = HDEC_LANE_XOR;
                uop_p0_n.lane_ctrl.capture_kind = HDEC_CAPTURE_VEC64;
                st_n=S_UOP_P1_RD0;
            end

            HDEC_HSIM: begin
                hsim_src0_base_n={a_q[3:0],2'b00};
                hsim_src1_base_n={a_q[7:4],2'b00};
                hsim_total_n='0;
                uop_p0_n.valid        = 1'b1;
                uop_p0_n.op_type      = UOP_HSIM_CHUNK;
                uop_p0_n.arch_op      = HDEC_HSIM;
                uop_p0_n.src0_addr    = hsim_src0_base_n;
                uop_p0_n.src1_addr    = hsim_src1_base_n;
                uop_p0_n.src0_base    = hsim_src0_base_n;
                uop_p0_n.src1_base    = hsim_src1_base_n;
                uop_p0_n.chunk_idx    = 2'd0;
                uop_p0_n.lane_ctrl.valid        = 1'b1;
                uop_p0_n.lane_ctrl.op           = HDEC_LANE_POPCOUNT_DIFF;
                uop_p0_n.lane_ctrl.capture_kind = HDEC_CAPTURE_POP7;
                st_n=S_UOP_P1_RD0;
            end

            HDEC_HMATCH: begin
                if((a_q[15:8] == 8'd0) || (({5'b0,a_q[7:4]} + {1'b0,a_q[15:8]} - 9'd1) > 9'd7))begin
                    res_n={62'b0,STATUS_ERROR};st_n=S_RESULT;
                end else begin
                    hsim_src0_base_n={a_q[3:0],2'b00};
                    hsim_src1_base_n={a_q[7:4],2'b00};
                    hmatch_class_slot_n=a_q[7:4];
                    hmatch_num_n=a_q[15:8];
                    hmatch_best_idx_n=8'd0;
                    hmatch_best_dist_n=11'd1025;
                    hsim_total_n='0;
                    uop_p0_n.valid        = 1'b1;
                    uop_p0_n.op_type      = UOP_HMATCH_CHUNK;
                    uop_p0_n.arch_op      = HDEC_HMATCH;
                    uop_p0_n.src0_addr    = hsim_src0_base_n;
                    uop_p0_n.src1_addr    = hsim_src1_base_n;
                    uop_p0_n.src0_base    = hsim_src0_base_n;
                    uop_p0_n.src1_base    = hsim_src1_base_n;
                    uop_p0_n.chunk_idx    = 2'd0;
                    uop_p0_n.class_idx    = 8'd0;
                    uop_p0_n.class_count  = hmatch_num_n;
                    uop_p0_n.lane_ctrl.valid        = 1'b1;
                    uop_p0_n.lane_ctrl.op           = HDEC_LANE_POPCOUNT_DIFF;
                    uop_p0_n.lane_ctrl.capture_kind = HDEC_CAPTURE_POP7;
                    uop_p0_n.is_last_class = (hmatch_num_n == 8'd1);
                    st_n=S_UOP_P1_RD0;
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
                uop_p0_n.arch_op     = HDEC_HCNTCLIP;
                uop_p0_n.chunk_idx   = 2'd0;
                uop_p0_n.subgroup_idx= 2'd0;
                uop_p0_n.src0_addr   = (a_q[3] ? 6'd48 : 6'd32);
                uop_p0_n.dst_base    = hcntclip_dst_base_n;
                uop_p0_n.lane_ctrl.valid        = 1'b1;
                uop_p0_n.lane_ctrl.op           = HDEC_LANE_CLIP;
                uop_p0_n.lane_ctrl.capture_kind = HDEC_CAPTURE_CLIP16;
                uop_p0_n.lane_ctrl.subgroup     = 2'd0;
                uop_p0_n.lane_ctrl.threshold    = hcntclip_threshold_n;
                st_n=S_UOP_P1_RD0;
            end

            HDEC_HPERM: begin
                if((a_q[9:8] != 2'b00) || (a_q[3:0] == a_q[7:4]))begin res_n={62'b0,STATUS_ERROR};st_n=S_RESULT;end
                else begin
                    hperm_dst_base_n={a_q[3:0],2'b00};
                    hperm_src_base_n={a_q[7:4],2'b00};
                    hperm_word_off_n=a_q[17:14];
                    chunk_cnt_n=2'd0;
                    uop_p0_n.valid       = 1'b1;
                    uop_p0_n.op_type     = UOP_HPERM_CHUNK;
                    uop_p0_n.arch_op     = HDEC_HPERM;
                    uop_p0_n.chunk_idx   = 2'd0;
                    uop_p0_n.src0_base   = hperm_src_base_n;
                    uop_p0_n.dst_base    = hperm_dst_base_n;
                    uop_p0_n.lane_ctrl.valid        = 1'b1;
                    uop_p0_n.lane_ctrl.op           = HDEC_LANE_SHIFT;
                    uop_p0_n.lane_ctrl.capture_kind = HDEC_CAPTURE_VEC64;
                    uop_p0_n.lane_ctrl.perm         = a_q[13:10];
                    st_n=S_UOP_P1_RD0;
                end
            end

            default: begin res_n={62'b0,STATUS_NOT_IMPLEMENTED};st_n=S_RESULT;end
        endcase end

        S_RD_WAIT: begin res_n=vrf_rd[bk_q];st_n=S_RESULT;end

        // ── S_CLR: shared by HCLR (4 entries) and HCNTCLR (16 entries) ──────
        S_CLR: begin
            vrf_we='1;
            vrf_wa[0]=clr_base_q+clr_cnt_q; vrf_wa[1]=clr_base_q+clr_cnt_q;
            vrf_wa[2]=clr_base_q+clr_cnt_q; vrf_wa[3]=clr_base_q+clr_cnt_q;
            vrf_wd='0;
            if((op_q==HDEC_HCLR&&clr_cnt_q==4'd3)||(op_q==HDEC_HCNTCLR&&clr_cnt_q==4'd15))begin res_n='0;st_n=S_RESULT;end
            else clr_cnt_n=clr_cnt_q+4'd1;
        end

        // ── UOP Pipeline ─────────────────────────────────────────────────────
        S_UOP_P1_RD0: begin
            uop_p1_n       = uop_p0_q;
            uop_p0_n.valid = 1'b0;
            if (uop_p0_q.op_type == UOP_HPERM_CHUNK) begin
                chunk_cnt_n = uop_p0_q.chunk_idx;
                hperm_lane_base_n = hperm_word0[1:0];
                vrf_ra[0]=hperm_src_base_q+hperm_word0[3:2]; vrf_ra[1]=hperm_src_base_q+hperm_word0[3:2];
                vrf_ra[2]=hperm_src_base_q+hperm_word0[3:2]; vrf_ra[3]=hperm_src_base_q+hperm_word0[3:2];
            end else begin
                vrf_ra[0]=uop_p0_q.src0_addr; vrf_ra[1]=uop_p0_q.src0_addr;
                vrf_ra[2]=uop_p0_q.src0_addr; vrf_ra[3]=uop_p0_q.src0_addr;
            end
            st_n=S_UOP_P1_RD1;
        end

        S_UOP_P1_RD1: begin
            uop_p2_n       = uop_p1_q;
            uop_p1_n.valid = 1'b0;
            if (uop_p1_q.op_type == UOP_HPERM_CHUNK) begin
                hperm_a_n = vrf_rd;
                vrf_ra[0]=hperm_src_base_q+hperm_next_chunk; vrf_ra[1]=hperm_src_base_q+hperm_next_chunk;
                vrf_ra[2]=hperm_src_base_q+hperm_next_chunk; vrf_ra[3]=hperm_src_base_q+hperm_next_chunk;
            end else begin
                src0_n = vrf_rd;
                if (uop_p1_q.op_type == UOP_HCNTADD_SUBGROUP) hcntadd_hv_n = vrf_rd;
                if (uop_p1_q.op_type != UOP_HCNTCLIP_READ) begin
                    vrf_ra[0]=uop_p1_q.src1_addr; vrf_ra[1]=uop_p1_q.src1_addr;
                    vrf_ra[2]=uop_p1_q.src1_addr; vrf_ra[3]=uop_p1_q.src1_addr;
                end else begin
                    vrf_ra[0]=uop_p1_q.src0_addr; vrf_ra[1]=uop_p1_q.src0_addr;
                    vrf_ra[2]=uop_p1_q.src0_addr; vrf_ra[3]=uop_p1_q.src0_addr;
                end
            end
            st_n=S_UOP_P2_LANE;
        end

        S_UOP_P2_LANE: begin
            uop_p3_n           = uop_p2_q;
            uop_p2_n.valid     = 1'b0;
`ifndef SYNTHESIS
            assert (!uop_p2_q.lane_ctrl.valid ||
                    ((uop_p2_q.lane_ctrl.op != HDEC_LANE_NOP) &&
                     (uop_p2_q.lane_ctrl.capture_kind != HDEC_CAPTURE_NONE)))
                else $error("HDEC P2 invalid lane control: op_type=%0d",
                            uop_p2_q.op_type);
`endif
            if (uop_p2_q.lane_ctrl.op == HDEC_LANE_SHIFT) begin
                lane_shift_a[0]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd0,hperm_a_q,vrf_rd);
                lane_shift_a[1]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd1,hperm_a_q,vrf_rd);
                lane_shift_a[2]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd2,hperm_a_q,vrf_rd);
                lane_shift_a[3]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd3,hperm_a_q,vrf_rd);
                lane_shift_b[0]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd1,hperm_a_q,vrf_rd);
                lane_shift_b[1]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd2,hperm_a_q,vrf_rd);
                lane_shift_b[2]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd3,hperm_a_q,vrf_rd);
                lane_shift_b[3]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd4,hperm_a_q,vrf_rd);
            end
            if (uop_p2_q.valid) begin
                unique case (uop_p2_q.lane_ctrl.capture_kind)
                    HDEC_CAPTURE_VEC64: lane_result_n = local_vec64_result;
                    HDEC_CAPTURE_POP7: begin
                        lane_popcnt_n[0] = local_pop7_result[0];
                        lane_popcnt_n[1] = local_pop7_result[1];
                        lane_popcnt_n[2] = local_pop7_result[2];
                        lane_popcnt_n[3] = local_pop7_result[3];
                    end
                    HDEC_CAPTURE_CLIP16: begin
                        lane_clip_n[0] = local_clip16_result[0];
                        lane_clip_n[1] = local_clip16_result[1];
                        lane_clip_n[2] = local_clip16_result[2];
                        lane_clip_n[3] = local_clip16_result[3];
                    end
                    default: ;
                endcase
            end
            st_n=S_UOP_P3_GLOBAL;
        end

        S_UOP_P3_GLOBAL: begin
            uop_p3_n.valid  = 1'b0;
            p4_arch_op_n    = uop_p3_q.arch_op;
            unique case (uop_p3_q.op_type)
            UOP_HBIND_CHUNK: begin
                vrf_we = '1;
                vrf_wa[0]=uop_p3_q.dst_addr; vrf_wa[1]=uop_p3_q.dst_addr;
                vrf_wa[2]=uop_p3_q.dst_addr; vrf_wa[3]=uop_p3_q.dst_addr;
                vrf_wd = lane_result_q;
                if (uop_p3_q.chunk_idx == 2'd3) st_n = S_UOP_P4_RESP;
                else begin
                    uop_p0_n = uop_p3_q; uop_p0_n.valid = 1'b1;
                    uop_p0_n.chunk_idx = uop_p3_q.chunk_idx + 2'd1;
                    uop_p0_n.src0_addr = uop_p3_q.src0_base + (uop_p3_q.chunk_idx + 2'd1);
                    uop_p0_n.src1_addr = uop_p3_q.src1_base + (uop_p3_q.chunk_idx + 2'd1);
                    uop_p0_n.dst_addr  = uop_p3_q.dst_base  + (uop_p3_q.chunk_idx + 2'd1);
                    st_n = S_UOP_P1_RD0;
                end
            end
            UOP_HSIM_CHUNK, UOP_HMATCH_CHUNK: begin
                group_dist = {4'b0, lane_popcnt_q[0]} + {4'b0, lane_popcnt_q[1]}
                           + {4'b0, lane_popcnt_q[2]} + {4'b0, lane_popcnt_q[3]};
                hsim_total_n = hsim_total_q + {1'b0, group_dist};
                if (uop_p3_q.chunk_idx == 2'd3) begin
                    if (uop_p3_q.op_type == UOP_HMATCH_CHUNK) begin
                        if (hsim_total_n < hmatch_best_dist_q) begin
                            hmatch_best_dist_n = hsim_total_n;
                            hmatch_best_idx_n  = uop_p3_q.class_idx;
                        end
                        if (uop_p3_q.is_last_class) begin
                            st_n = S_UOP_P4_RESP;
                        end else begin
                            hsim_total_n        = '0;
                            hmatch_class_slot_n  = hmatch_class_slot_q + 4'd1;
                            uop_p0_n = uop_p3_q; uop_p0_n.valid = 1'b1;
                            uop_p0_n.chunk_idx   = 2'd0;
                            uop_p0_n.class_idx   = uop_p3_q.class_idx + 8'd1;
                            uop_p0_n.is_last_class = (uop_p3_q.class_idx + 8'd1 == uop_p3_q.class_count - 8'd1);
                            uop_p0_n.src1_addr   = {hmatch_class_slot_n, 2'b00};
                            uop_p0_n.src1_base   = {hmatch_class_slot_n, 2'b00};
                            st_n = S_UOP_P1_RD0;
                        end
                    end else st_n = S_UOP_P4_RESP;
                end else begin
                    uop_p0_n = uop_p3_q; uop_p0_n.valid = 1'b1;
                    uop_p0_n.chunk_idx = uop_p3_q.chunk_idx + 2'd1;
                    uop_p0_n.src0_addr = uop_p3_q.src0_base + (uop_p3_q.chunk_idx + 2'd1);
                    uop_p0_n.src1_addr = uop_p3_q.src1_base + (uop_p3_q.chunk_idx + 2'd1);
                    if (uop_p3_q.op_type == UOP_HMATCH_CHUNK) uop_p0_n.is_last_class = uop_p3_q.is_last_class;
                    st_n = S_UOP_P1_RD0;
                end
            end
            UOP_HCNTADD_SUBGROUP: begin
                vrf_we = '1;
                vrf_wa[0]=hcntadd_acc_base+{2'b00,uop_p3_q.chunk_idx,2'b00}+{4'b0,uop_p3_q.subgroup_idx};
                vrf_wa[1]=vrf_wa[0]; vrf_wa[2]=vrf_wa[0]; vrf_wa[3]=vrf_wa[0];
                vrf_wd = lane_result_q;
                if (uop_p3_q.subgroup_idx < 2'd3) begin
                    hcntadd_subgroup_n = uop_p3_q.subgroup_idx + 2'd1;
                    vrf_ra[0]=hcntadd_acc_base+{2'b00,uop_p3_q.chunk_idx,2'b00}+{4'b0,hcntadd_subgroup_n};
                    vrf_ra[1]=vrf_ra[0]; vrf_ra[2]=vrf_ra[0]; vrf_ra[3]=vrf_ra[0];
                    // Advance uop to P2 directly (skip P1_RD0/P1_RD1)
                    uop_p2_n = uop_p3_q; uop_p2_n.valid = 1'b1;
                    uop_p2_n.subgroup_idx = hcntadd_subgroup_n;
                    uop_p2_n.lane_ctrl.subgroup = hcntadd_subgroup_n;
                    uop_p1_n.valid = 1'b0; uop_p0_n.valid = 1'b0;
                    st_n = S_UOP_P2_LANE;
                end else if (uop_p3_q.chunk_idx < 2'd3) begin
                    hcntadd_subgroup_n = 2'd0;
                    hcntadd_chunk_n    = uop_p3_q.chunk_idx + 2'd1;
                    uop_p0_n = uop_p3_q; uop_p0_n.valid = 1'b1;
                    uop_p0_n.chunk_idx    = hcntadd_chunk_n;
                    uop_p0_n.subgroup_idx = 2'd0;
                    uop_p0_n.lane_ctrl.subgroup = 2'd0;
                    uop_p0_n.src0_addr = {1'b0,hcntadd_hv_slot_q,2'b00}+{4'b0,hcntadd_chunk_n};
                    uop_p0_n.src1_addr = hcntadd_acc_base+{2'b00,hcntadd_chunk_n,2'b00};
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
                    uop_p2_n.lane_ctrl.subgroup = hcntclip_subgroup_n;
                    uop_p2_n.lane_ctrl.threshold = hcntclip_threshold_q;
                    uop_p1_n.valid = 1'b0; uop_p0_n.valid = 1'b0;
                    st_n = S_UOP_P2_LANE;
                end else begin
                    // word complete; go to dedicated write state
                    hcntclip_subgroup_n = 2'd0;
                    st_n = S_UOP_CLIP_WRITE;
                end
            end
            UOP_HPERM_CHUNK: begin
                vrf_we = '1;
                vrf_wa[0]=hperm_dst_base_q+uop_p3_q.chunk_idx; vrf_wa[1]=hperm_dst_base_q+uop_p3_q.chunk_idx;
                vrf_wa[2]=hperm_dst_base_q+uop_p3_q.chunk_idx; vrf_wa[3]=hperm_dst_base_q+uop_p3_q.chunk_idx;
                vrf_wd = lane_result_q;
                if (uop_p3_q.chunk_idx == 2'd3) st_n = S_UOP_P4_RESP;
                else begin
                    chunk_cnt_n = uop_p3_q.chunk_idx + 2'd1;
                    uop_p0_n = uop_p3_q; uop_p0_n.valid = 1'b1;
                    uop_p0_n.chunk_idx = chunk_cnt_n;
                    st_n = S_UOP_P1_RD0;
                end
            end
            default: st_n = S_UOP_P4_RESP;
            endcase
        end

        // ── HCNTCLIP writeback (dedicated state, avoids pipeline timing issues) ─
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
                uop_p0_n.arch_op = HDEC_HCNTCLIP;
                uop_p0_n.chunk_idx = hcntclip_chunk_n;
                uop_p0_n.subgroup_idx = 2'd0;
                uop_p0_n.src0_addr = hcntclip_acc_base+{2'b00,hcntclip_chunk_n,2'b00};
                uop_p0_n.lane_ctrl.valid        = 1'b1;
                uop_p0_n.lane_ctrl.op           = HDEC_LANE_CLIP;
                uop_p0_n.lane_ctrl.capture_kind = HDEC_CAPTURE_CLIP16;
                uop_p0_n.lane_ctrl.subgroup     = 2'd0;
                uop_p0_n.lane_ctrl.threshold    = hcntclip_threshold_q;
                st_n = S_UOP_P1_RD0;
            end
        end

        S_UOP_P4_RESP: begin
            scalar_response_n = '0;
            response_valid_n  = 1'b1;
            if (p4_arch_op_q == HDEC_HSIM)
                scalar_response_n = {53'b0, hsim_total_q};
            else if (p4_arch_op_q == HDEC_HMATCH)
                scalar_response_n = {45'b0, hmatch_best_idx_q, hmatch_best_dist_q};
            st_n = S_RESULT;
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
            src0_q<='0;chunk_cnt_q<='0;
            hb_dst_base_q<='0;hb_src0_base_q<='0;hb_src1_base_q<='0;
            hsim_src0_base_q<='0;hsim_src1_base_q<='0;hsim_total_q<='0;
            hmatch_num_q<='0;hmatch_best_idx_q<='0;hmatch_class_slot_q<='0;hmatch_best_dist_q<='0;
            hperm_a_q<='0;hperm_dst_base_q<='0;hperm_src_base_q<='0;hperm_word_off_q<='0;hperm_lane_base_q<='0;
            hcntadd_hv_q<='0;hcntadd_hv_slot_q<='0;hcntadd_chunk_q<='0;hcntadd_subgroup_q<='0;hcntadd_acc_sel_q<='0;
            hcntclip_dst_base_q<='0;hcntclip_acc_sel_q<='0;hcntclip_threshold_q<='0;hcntclip_chunk_q<='0;hcntclip_subgroup_q<='0;hcntclip_word_q<='0;
            uop_p0_q<='0;uop_p1_q<='0;uop_p2_q<='0;uop_p3_q<='0;
            lane_result_q<='0;lane_popcnt_q<='0;lane_clip_q<='0;
            scalar_response_q<='0;response_valid_q<='0;p4_arch_op_q<=HDEC_VWR64;
        end
        else begin
            st_q<=st_n;res_q<=res_n;op_q<=op_n;a_q<=a_n;b_q<=b_n;bk_q<=bk_n;
            vaddr_bank_q<=vaddr_bank_n;vaddr_idx_q<=vaddr_idx_n;clr_cnt_q<=clr_cnt_n;clr_base_q<=clr_base_n;
            src0_q<=src0_n;chunk_cnt_q<=chunk_cnt_n;
            hb_dst_base_q<=hb_dst_base_n;hb_src0_base_q<=hb_src0_base_n;hb_src1_base_q<=hb_src1_base_n;
            hsim_src0_base_q<=hsim_src0_base_n;hsim_src1_base_q<=hsim_src1_base_n;hsim_total_q<=hsim_total_n;
            hmatch_num_q<=hmatch_num_n;hmatch_best_idx_q<=hmatch_best_idx_n;hmatch_class_slot_q<=hmatch_class_slot_n;hmatch_best_dist_q<=hmatch_best_dist_n;
            hperm_a_q<=hperm_a_n;hperm_dst_base_q<=hperm_dst_base_n;hperm_src_base_q<=hperm_src_base_n;hperm_word_off_q<=hperm_word_off_n;hperm_lane_base_q<=hperm_lane_base_n;
            hcntadd_hv_q<=hcntadd_hv_n;hcntadd_hv_slot_q<=hcntadd_hv_slot_n;hcntadd_chunk_q<=hcntadd_chunk_n;hcntadd_subgroup_q<=hcntadd_subgroup_n;hcntadd_acc_sel_q<=hcntadd_acc_sel_n;
            hcntclip_dst_base_q<=hcntclip_dst_base_n;hcntclip_acc_sel_q<=hcntclip_acc_sel_n;hcntclip_threshold_q<=hcntclip_threshold_n;hcntclip_chunk_q<=hcntclip_chunk_n;hcntclip_subgroup_q<=hcntclip_subgroup_n;hcntclip_word_q<=hcntclip_word_n;
            uop_p0_q<=uop_p0_n;uop_p1_q<=uop_p1_n;uop_p2_q<=uop_p2_n;uop_p3_q<=uop_p3_n;
            lane_result_q<=lane_result_n;lane_popcnt_q<=lane_popcnt_n;lane_clip_q<=lane_clip_n;
            scalar_response_q<=scalar_response_n;response_valid_q<=response_valid_n;p4_arch_op_q<=p4_arch_op_n;
        end
    end
endmodule
