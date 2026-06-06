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
    logic [3:0] hperm_word_off_q,hperm_word_off_n, hperm_nibble_q,hperm_nibble_n;
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
    // P2/P3 boundary: each lane slice owns its registered payload outputs
    hdec_uop_t uop_p0_q, uop_p0_n, uop_p1_q, uop_p1_n, uop_p2_q, uop_p2_n, uop_p3_q, uop_p3_n;

    // ── Per-lane P2 slices ──────────────────────────────────────────────────
    hdec_p2_lane_ctrl_t                   p2_lane_ctrl_d[LANE_NUM];
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] lane_shift_a, lane_shift_b;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] lane_vec64_q;
    logic [LANE_NUM-1:0][6:0]            lane_pop7_q;
    logic [LANE_NUM-1:0][15:0]           lane_clip16_q;

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

    // ── 4× lane-local P2 slices ─────────────────────────────────────────────
    for (genvar lid = 0; lid < LANE_NUM; lid++) begin : gen_lane
        hdec_p2_lane_slice #(.LANE_ID(lid)) i_p2_lane_slice (
            .clk_i,
            .rst_ni,
            .p2_lane_ctrl_d_i(p2_lane_ctrl_d[lid]),
            .bool_src_a_i(src0_q[lid]),
            .bool_src_b_i(vrf_rd[lid]),
            .cnt_hv_word_i(hcntadd_hv_q[lid]),
            .cnt_old_counter_i(vrf_rd[lid]),
            .shift_src_a_i(lane_shift_a[lid]),
            .shift_src_b_i(lane_shift_b[lid]),
            .clip_counter_i(vrf_rd[lid]),
            .lane_vec64_q_o(lane_vec64_q[lid]),
            .lane_pop7_q_o(lane_pop7_q[lid]),
            .lane_clip16_q_o(lane_clip16_q[lid])
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
        hperm_word_off_n=hperm_word_off_q; hperm_nibble_n=hperm_nibble_q; hperm_lane_base_n=hperm_lane_base_q;
        hcntadd_hv_n=hcntadd_hv_q; hcntadd_hv_slot_n=hcntadd_hv_slot_q; hcntadd_chunk_n=hcntadd_chunk_q; hcntadd_subgroup_n=hcntadd_subgroup_q; hcntadd_acc_sel_n=hcntadd_acc_sel_q;
        hcntclip_dst_base_n=hcntclip_dst_base_q; hcntclip_acc_sel_n=hcntclip_acc_sel_q; hcntclip_threshold_n=hcntclip_threshold_q; hcntclip_chunk_n=hcntclip_chunk_q; hcntclip_subgroup_n=hcntclip_subgroup_q; hcntclip_word_n=hcntclip_word_q; hcntclip_word_with_result=hcntclip_word_q;
        uop_p0_n=uop_p0_q; uop_p1_n=uop_p1_q; uop_p2_n=uop_p2_q; uop_p3_n=uop_p3_q;
        scalar_response_n=scalar_response_q; response_valid_n=response_valid_q; p4_arch_op_n=p4_arch_op_q;
        group_dist='0;
        for (int lid = 0; lid < LANE_NUM; lid++)
            p2_lane_ctrl_d[lid] = '0;
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
                st_n=S_UOP_P1_RD0;
            end

            HDEC_HPERM: begin
                if((a_q[9:8] != 2'b00) || (a_q[3:0] == a_q[7:4]))begin res_n={62'b0,STATUS_ERROR};st_n=S_RESULT;end
                else begin
                    hperm_dst_base_n={a_q[3:0],2'b00};
                    hperm_src_base_n={a_q[7:4],2'b00};
                    hperm_word_off_n=a_q[17:14];
                    hperm_nibble_n=a_q[13:10];
                    chunk_cnt_n=2'd0;
                    uop_p0_n.valid       = 1'b1;
                    uop_p0_n.op_type     = UOP_HPERM_CHUNK;
                    uop_p0_n.arch_op     = HDEC_HPERM;
                    uop_p0_n.chunk_idx   = 2'd0;
                    uop_p0_n.src0_base   = hperm_src_base_n;
                    uop_p0_n.dst_base    = hperm_dst_base_n;
                    uop_p0_n.perm_nibble = hperm_nibble_n;
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
            for (int lid = 0; lid < LANE_NUM; lid++) begin
                unique case (uop_p1_q.op_type)
                    UOP_HBIND_CHUNK: begin
                        p2_lane_ctrl_d[lid].do_xor_only = 1'b1;
                        p2_lane_ctrl_d[lid].capture_vec = 1'b1;
                    end
                    UOP_HSIM_CHUNK, UOP_HMATCH_CHUNK: begin
                        p2_lane_ctrl_d[lid].do_popcount_diff = 1'b1;
                        p2_lane_ctrl_d[lid].capture_pop = 1'b1;
                    end
                    UOP_HCNTADD_SUBGROUP: begin
                        p2_lane_ctrl_d[lid].do_counter = 1'b1;
                        p2_lane_ctrl_d[lid].capture_vec = 1'b1;
                        p2_lane_ctrl_d[lid].subgroup = uop_p1_q.subgroup_idx;
                    end
                    UOP_HCNTCLIP_READ: begin
                        p2_lane_ctrl_d[lid].do_clip = 1'b1;
                        p2_lane_ctrl_d[lid].capture_clip = 1'b1;
                        p2_lane_ctrl_d[lid].threshold = hcntclip_threshold_q;
                    end
                    UOP_HPERM_CHUNK: begin
                        p2_lane_ctrl_d[lid].do_shift = 1'b1;
                        p2_lane_ctrl_d[lid].capture_vec = 1'b1;
                        p2_lane_ctrl_d[lid].perm_nibble = uop_p1_q.perm_nibble;
                    end
                    default: p2_lane_ctrl_d[lid] = '0;
                endcase
            end
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
            lane_shift_a[0]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd0,hperm_a_q,vrf_rd);
            lane_shift_a[1]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd1,hperm_a_q,vrf_rd);
            lane_shift_a[2]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd2,hperm_a_q,vrf_rd);
            lane_shift_a[3]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd3,hperm_a_q,vrf_rd);
            lane_shift_b[0]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd1,hperm_a_q,vrf_rd);
            lane_shift_b[1]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd2,hperm_a_q,vrf_rd);
            lane_shift_b[2]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd3,hperm_a_q,vrf_rd);
            lane_shift_b[3]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd4,hperm_a_q,vrf_rd);
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
                vrf_wd = lane_vec64_q;
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
                group_dist = {4'b0, lane_pop7_q[0]} + {4'b0, lane_pop7_q[1]}
                           + {4'b0, lane_pop7_q[2]} + {4'b0, lane_pop7_q[3]};
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
                vrf_wd = lane_vec64_q;
                if (uop_p3_q.subgroup_idx < 2'd3) begin
                    hcntadd_subgroup_n = uop_p3_q.subgroup_idx + 2'd1;
                    vrf_ra[0]=hcntadd_acc_base+{2'b00,uop_p3_q.chunk_idx,2'b00}+{4'b0,hcntadd_subgroup_n};
                    vrf_ra[1]=vrf_ra[0]; vrf_ra[2]=vrf_ra[0]; vrf_ra[3]=vrf_ra[0];
                    // Advance uop to P2 directly (skip P1_RD0/P1_RD1)
                    uop_p2_n = uop_p3_q; uop_p2_n.valid = 1'b1;
                    uop_p2_n.subgroup_idx = hcntadd_subgroup_n;
                    for (int lid = 0; lid < LANE_NUM; lid++) begin
                        p2_lane_ctrl_d[lid].do_counter = 1'b1;
                        p2_lane_ctrl_d[lid].capture_vec = 1'b1;
                        p2_lane_ctrl_d[lid].subgroup = hcntadd_subgroup_n;
                    end
                    uop_p1_n.valid = 1'b0; uop_p0_n.valid = 1'b0;
                    st_n = S_UOP_P2_LANE;
                end else if (uop_p3_q.chunk_idx < 2'd3) begin
                    hcntadd_subgroup_n = 2'd0;
                    hcntadd_chunk_n    = uop_p3_q.chunk_idx + 2'd1;
                    uop_p0_n = uop_p3_q; uop_p0_n.valid = 1'b1;
                    uop_p0_n.chunk_idx    = hcntadd_chunk_n;
                    uop_p0_n.subgroup_idx = 2'd0;
                    uop_p0_n.src0_addr = {1'b0,hcntadd_hv_slot_q,2'b00}+{4'b0,hcntadd_chunk_n};
                    uop_p0_n.src1_addr = hcntadd_acc_base+{2'b00,hcntadd_chunk_n,2'b00};
                    st_n = S_UOP_P1_RD0;
                end else st_n = S_UOP_P4_RESP;
            end
            UOP_HCNTCLIP_READ: begin
                hcntclip_word_with_result = hcntclip_word_q;
                hcntclip_word_with_result[0][{uop_p3_q.subgroup_idx,4'b0000} +: 16] = lane_clip16_q[0];
                hcntclip_word_with_result[1][{uop_p3_q.subgroup_idx,4'b0000} +: 16] = lane_clip16_q[1];
                hcntclip_word_with_result[2][{uop_p3_q.subgroup_idx,4'b0000} +: 16] = lane_clip16_q[2];
                hcntclip_word_with_result[3][{uop_p3_q.subgroup_idx,4'b0000} +: 16] = lane_clip16_q[3];
                hcntclip_word_n = hcntclip_word_with_result;
                if (uop_p3_q.subgroup_idx < 2'd3) begin
                    hcntclip_subgroup_n = uop_p3_q.subgroup_idx + 2'd1;
                    vrf_ra[0]=hcntclip_acc_base+{2'b00,uop_p3_q.chunk_idx,2'b00}+{4'b0,hcntclip_subgroup_n};
                    vrf_ra[1]=vrf_ra[0]; vrf_ra[2]=vrf_ra[0]; vrf_ra[3]=vrf_ra[0];
                    uop_p2_n = uop_p3_q; uop_p2_n.valid = 1'b1;
                    uop_p2_n.subgroup_idx = hcntclip_subgroup_n;
                    for (int lid = 0; lid < LANE_NUM; lid++) begin
                        p2_lane_ctrl_d[lid].do_clip = 1'b1;
                        p2_lane_ctrl_d[lid].capture_clip = 1'b1;
                        p2_lane_ctrl_d[lid].threshold = hcntclip_threshold_q;
                    end
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
                vrf_wd = lane_vec64_q;
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
            hperm_a_q<='0;hperm_dst_base_q<='0;hperm_src_base_q<='0;hperm_word_off_q<='0;hperm_nibble_q<='0;hperm_lane_base_q<='0;
            hcntadd_hv_q<='0;hcntadd_hv_slot_q<='0;hcntadd_chunk_q<='0;hcntadd_subgroup_q<='0;hcntadd_acc_sel_q<='0;
            hcntclip_dst_base_q<='0;hcntclip_acc_sel_q<='0;hcntclip_threshold_q<='0;hcntclip_chunk_q<='0;hcntclip_subgroup_q<='0;hcntclip_word_q<='0;
            uop_p0_q<='0;uop_p1_q<='0;uop_p2_q<='0;uop_p3_q<='0;
            scalar_response_q<='0;response_valid_q<='0;p4_arch_op_q<=HDEC_VWR64;
        end
        else begin
            st_q<=st_n;res_q<=res_n;op_q<=op_n;a_q<=a_n;b_q<=b_n;bk_q<=bk_n;
            vaddr_bank_q<=vaddr_bank_n;vaddr_idx_q<=vaddr_idx_n;clr_cnt_q<=clr_cnt_n;clr_base_q<=clr_base_n;
            src0_q<=src0_n;chunk_cnt_q<=chunk_cnt_n;
            hb_dst_base_q<=hb_dst_base_n;hb_src0_base_q<=hb_src0_base_n;hb_src1_base_q<=hb_src1_base_n;
            hsim_src0_base_q<=hsim_src0_base_n;hsim_src1_base_q<=hsim_src1_base_n;hsim_total_q<=hsim_total_n;
            hmatch_num_q<=hmatch_num_n;hmatch_best_idx_q<=hmatch_best_idx_n;hmatch_class_slot_q<=hmatch_class_slot_n;hmatch_best_dist_q<=hmatch_best_dist_n;
            hperm_a_q<=hperm_a_n;hperm_dst_base_q<=hperm_dst_base_n;hperm_src_base_q<=hperm_src_base_n;hperm_word_off_q<=hperm_word_off_n;hperm_nibble_q<=hperm_nibble_n;hperm_lane_base_q<=hperm_lane_base_n;
            hcntadd_hv_q<=hcntadd_hv_n;hcntadd_hv_slot_q<=hcntadd_hv_slot_n;hcntadd_chunk_q<=hcntadd_chunk_n;hcntadd_subgroup_q<=hcntadd_subgroup_n;hcntadd_acc_sel_q<=hcntadd_acc_sel_n;
            hcntclip_dst_base_q<=hcntclip_dst_base_n;hcntclip_acc_sel_q<=hcntclip_acc_sel_n;hcntclip_threshold_q<=hcntclip_threshold_n;hcntclip_chunk_q<=hcntclip_chunk_n;hcntclip_subgroup_q<=hcntclip_subgroup_n;hcntclip_word_q<=hcntclip_word_n;
            uop_p0_q<=uop_p0_n;uop_p1_q<=uop_p1_n;uop_p2_q<=uop_p2_n;uop_p3_q<=uop_p3_n;
            scalar_response_q<=scalar_response_n;response_valid_q<=response_valid_n;p4_arch_op_q<=p4_arch_op_n;
        end
    end
endmodule
