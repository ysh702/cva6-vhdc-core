// hdec_top.sv — Phase1: VRF mgmt + transitional hbind control
// TRANSITIONAL: hbind FSM lives in hdec_top.  Will migrate to hdec_hdc_engine
// + scheduler + tag routing when hsim/hperm/badd are added.
module hdec_top import hdec_pkg::*; import hdec_resource_pkg::*; (
    input logic clk_i, rst_ni, valid_i, output logic ready_o,
    input hdec_op_t operator_i, input logic [63:0] operand_a_i, operand_b_i,
    output logic valid_o, output logic [63:0] result_o
);
    logic [LANE_NUM-1:0][VRF_IDX_W-1:0] vrf_ra; logic [LANE_NUM-1:0][LANE_WIDTH-1:0] vrf_rd;
    logic [LANE_NUM-1:0] vrf_we; logic [LANE_NUM-1:0][VRF_IDX_W-1:0] vrf_wa; logic [LANE_NUM-1:0][LANE_WIDTH-1:0] vrf_wd;
    hdec_vrf_64x256 i_vrf(.clk_i,.rst_ni,.bank_ra_addr_i(vrf_ra),.bank_ra_data_o(vrf_rd),.bank_we_i(vrf_we),.bank_wa_addr_i(vrf_wa),.bank_wdata_i(vrf_wd),.vrf_ready_o());
    logic [VRF_BNK_W-1:0] vaddr_bank_q,vaddr_bank_n; logic [VRF_IDX_W-1:0] vaddr_idx_q,vaddr_idx_n;
    typedef enum logic [5:0] { S_IDLE, S_EXEC, S_RD_WAIT, S_RESULT, S_CLR, S_HBIND_RD0, S_HBIND_RD1, S_HBIND_XOR_WR, S_HSIM_CLEAR, S_HSIM_RD0, S_HSIM_RD1, S_HSIM_LOAD, S_HSIM_COMPRESS, S_HSIM_ACCUM, S_HPERM_RD_A, S_HPERM_RD_B, S_HPERM_SHIFT_WR, S_BADD_RD_HV, S_BADD_RD_ACC, S_BADD_ACCUM_WR, S_HBUNDLE3_CLEAR, S_HBUNDLE3_RD_HV0, S_HBUNDLE3_LOAD_ROW0, S_HBUNDLE3_RD_HV1, S_HBUNDLE3_LOAD_ROW1, S_HBUNDLE3_RD_HV2, S_HBUNDLE3_LOAD_ROW2, S_HBUNDLE3_RD_HV3, S_HBUNDLE3_LOAD_ROW3, S_HBUNDLE3_COMPRESS, S_HBUNDLE3_LATCH, S_HBUNDLE3_UPDATE_SUB0, S_HBUNDLE3_UPDATE_SUB1, S_HBUNDLE3_UPDATE_SUB2, S_HBUNDLE3_UPDATE_SUB3 } st_t; st_t st_q,st_n;
    logic [63:0] res_q,res_n; hdec_op_t op_q,op_n; logic [63:0] a_q,a_n,b_q,b_n; logic [VRF_BNK_W-1:0] bk_q,bk_n;
    logic [3:0] clr_cnt_q,clr_cnt_n; logic [VRF_IDX_W-1:0] clr_base_q,clr_base_n;
    // hbind registers
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] src0_q,src0_n;
    logic [1:0] chunk_cnt_q,chunk_cnt_n;
    logic [VRF_IDX_W-1:0] hb_dst_base_q,hb_dst_base_n, hb_src0_base_q,hb_src0_base_n, hb_src1_base_q,hb_src1_base_n;
    logic [VRF_IDX_W-1:0] hsim_src0_base_q,hsim_src0_base_n, hsim_src1_base_q,hsim_src1_base_n;
    logic [10:0] hsim_total_q,hsim_total_n;
    logic [10:0] hsim_group_distance;
    logic [1:0] hsim_row_q,hsim_row_n;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] hperm_a_q,hperm_a_n;
    logic [VRF_IDX_W-1:0] hperm_dst_base_q,hperm_dst_base_n, hperm_src_base_q,hperm_src_base_n;
    logic [3:0] hperm_word_off_q,hperm_word_off_n, hperm_nibble_q,hperm_nibble_n;
    logic [1:0] hperm_lane_base_q,hperm_lane_base_n;
    logic [4:0] hperm_word0;
    logic [1:0] hperm_next_chunk;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] badd_hv_q,badd_hv_n;
    logic [2:0] badd_hv_slot_q,badd_hv_slot_n;
    logic [1:0] badd_chunk_q,badd_chunk_n, badd_subgroup_q,badd_subgroup_n;
    logic badd_acc_sel_q,badd_acc_sel_n;
    logic [VRF_IDX_W-1:0] badd_hv_entry,badd_acc_entry,badd_acc_base,badd_next_acc_entry;
    logic [2:0] hbundle_base_q,hbundle_base_n;
    logic hbundle_acc_sel_q,hbundle_acc_sel_n;
    logic hbundle_is4_q,hbundle_is4_n;
    logic [1:0] hbundle_chunk_q,hbundle_chunk_n;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] hbundle_lo_q,hbundle_lo_n,hbundle_hi_a_q,hbundle_hi_a_n,hbundle_hi_b_q,hbundle_hi_b_n;
    logic [VRF_IDX_W-1:0] hbundle_hv0_entry,hbundle_hv1_entry,hbundle_hv2_entry,hbundle_hv3_entry;
    logic [VRF_IDX_W-1:0] hbundle_acc_base,hbundle_acc_entry0,hbundle_acc_entry1,hbundle_acc_entry2,hbundle_acc_entry3;
    // Lane bool wires
    logic [LANE_NUM-1:0]                lane_bool_valid;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] lane_bool_result;
    logic                                lane_bmca_row_clear;
    logic                                lane_bmca_row_load_valid;
    logic [1:0]                          lane_bmca_row_load_sel;
    logic                                lane_bmca_row_use_direct;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] lane_bmca_row_direct;
    logic                                lane_bmca_compress_valid;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] lane_bmca_lo,lane_bmca_hi_a,lane_bmca_hi_b;
    logic [LANE_NUM-1:0][8:0]            lane_bmca_count;
    logic [LANE_NUM-1:0]                 lane_bmca_count_valid;
    logic [LANE_NUM-1:0]                 lane_bundle_valid;
    logic [LANE_NUM-1:0][15:0]           lane_bundle_lo_bits,lane_bundle_hi_a_bits,lane_bundle_hi_b_bits;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] lane_bundle_counter_result;
    logic [LANE_NUM-1:0]                  lane_shift_valid;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] lane_shift_a,lane_shift_b,lane_shift_result;
    logic [3:0]                           lane_shift_nibble;
    logic [LANE_NUM-1:0]                  lane_addsub_valid;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] lane_addsub_result;
    logic [LANE_NUM-1:0][15:0]            lane_addsub_hv_bits;
    assign hsim_group_distance = {2'b0,lane_bmca_count[0]} + {2'b0,lane_bmca_count[1]} + {2'b0,lane_bmca_count[2]} + {2'b0,lane_bmca_count[3]};
    assign hperm_word0 = {1'b0,chunk_cnt_q,2'b00} + {1'b0,hperm_word_off_q};
    // Intentional 2-bit add: hperm source chunk B wraps modulo 4.
    assign hperm_next_chunk = hperm_word0[3:2] + 2'd1;
    // Must match bclr accumulator base mapping: acc0=32, acc1=48.
    assign badd_acc_base = badd_acc_sel_q ? 6'd48 : 6'd32;
    assign badd_hv_entry = {1'b0, badd_hv_slot_q, 2'b00} + {4'b0, badd_chunk_q};
    assign badd_acc_entry = badd_acc_base + {2'b00, badd_chunk_q, 2'b00} + {4'b0, badd_subgroup_q};
    assign badd_next_acc_entry = badd_acc_base + {2'b00, badd_chunk_q, 2'b00} + {4'b0, (badd_subgroup_q + 2'd1)};
    assign hbundle_hv0_entry = {1'b0, hbundle_base_q, 2'b00} + {4'b0, hbundle_chunk_q};
    assign hbundle_hv1_entry = {1'b0, (hbundle_base_q + 3'd1), 2'b00} + {4'b0, hbundle_chunk_q};
    assign hbundle_hv2_entry = {1'b0, (hbundle_base_q + 3'd2), 2'b00} + {4'b0, hbundle_chunk_q};
    assign hbundle_hv3_entry = {1'b0, (hbundle_base_q + 3'd3), 2'b00} + {4'b0, hbundle_chunk_q};
    assign hbundle_acc_base = hbundle_acc_sel_q ? 6'd48 : 6'd32;
    assign hbundle_acc_entry0 = hbundle_acc_base + {2'b00, hbundle_chunk_q, 2'b00};
    assign hbundle_acc_entry1 = hbundle_acc_entry0 + 6'd1;
    assign hbundle_acc_entry2 = hbundle_acc_entry0 + 6'd2;
    assign hbundle_acc_entry3 = hbundle_acc_entry0 + 6'd3;
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
    // 4× Lane instances (transitional: VRF managed by top, Lane does bool compute only)
    for (genvar lid = 0; lid < LANE_NUM; lid++) begin : gen_lane
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
            .bool_valid_i(lane_bool_valid[lid]),
            .bool_src_a_i(src0_q[lid]),
            .bool_src_b_i(vrf_rd[lid]),
            .bool_result_o(lane_bool_result[lid]),
            .bmca_row_clear_i(lane_bmca_row_clear),
            .bmca_row_load_valid_i(lane_bmca_row_load_valid),
            .bmca_row_load_sel_i(lane_bmca_row_load_sel),
            .bmca_row_use_direct_i(lane_bmca_row_use_direct),
            .bmca_row_direct_i(lane_bmca_row_direct[lid]),
            .bmca_compress_valid_i(lane_bmca_compress_valid),
            .bmca_lo_o(lane_bmca_lo[lid]),
            .bmca_hi_a_o(lane_bmca_hi_a[lid]),
            .bmca_hi_b_o(lane_bmca_hi_b[lid]),
            .bmca_count_o(lane_bmca_count[lid]),
            .bmca_count_valid_o(lane_bmca_count_valid[lid]),
            .bundle_valid_i(lane_bundle_valid[lid]),
            .bundle_old_counter_i(vrf_rd[lid]),
            .bundle_lo_bits_i(lane_bundle_lo_bits[lid]),
            .bundle_hi_a_bits_i(lane_bundle_hi_a_bits[lid]),
            .bundle_hi_b_bits_i(lane_bundle_hi_b_bits[lid]),
            .bundle_counter_result_o(lane_bundle_counter_result[lid]),
            .shift_valid_i(lane_shift_valid[lid]),
            .shift_src_a_i(lane_shift_a[lid]),
            .shift_src_b_i(lane_shift_b[lid]),
            .shift_nibble_i(lane_shift_nibble),
            .shift_result_o(lane_shift_result[lid]),
            .addsub_valid_i(lane_addsub_valid[lid]),
            .addsub_old_counter_i(vrf_rd[lid]),
            .addsub_hv_bits_i(lane_addsub_hv_bits[lid]),
            .addsub_result_o(lane_addsub_result[lid])
        );
    end
    always_comb begin
        st_n=st_q; ready_o=(st_q==S_IDLE); valid_o=(st_q==S_RESULT); result_o=res_q;
        res_n=res_q; op_n=op_q; a_n=a_q; b_n=b_q; bk_n=bk_q; vaddr_bank_n=vaddr_bank_q; vaddr_idx_n=vaddr_idx_q;
        clr_cnt_n=clr_cnt_q; clr_base_n=clr_base_q;
        src0_n=src0_q; chunk_cnt_n=chunk_cnt_q;
        hb_dst_base_n=hb_dst_base_q; hb_src0_base_n=hb_src0_base_q; hb_src1_base_n=hb_src1_base_q;
        hsim_src0_base_n=hsim_src0_base_q; hsim_src1_base_n=hsim_src1_base_q; hsim_total_n=hsim_total_q; hsim_row_n=hsim_row_q;
        hperm_a_n=hperm_a_q; hperm_dst_base_n=hperm_dst_base_q; hperm_src_base_n=hperm_src_base_q;
        hperm_word_off_n=hperm_word_off_q; hperm_nibble_n=hperm_nibble_q; hperm_lane_base_n=hperm_lane_base_q;
        badd_hv_n=badd_hv_q; badd_hv_slot_n=badd_hv_slot_q; badd_chunk_n=badd_chunk_q; badd_subgroup_n=badd_subgroup_q; badd_acc_sel_n=badd_acc_sel_q;
        hbundle_base_n=hbundle_base_q; hbundle_acc_sel_n=hbundle_acc_sel_q; hbundle_is4_n=hbundle_is4_q; hbundle_chunk_n=hbundle_chunk_q; hbundle_lo_n=hbundle_lo_q; hbundle_hi_a_n=hbundle_hi_a_q; hbundle_hi_b_n=hbundle_hi_b_q;
        lane_bool_valid='0;
        lane_bmca_row_clear=1'b0; lane_bmca_row_load_valid=1'b0; lane_bmca_row_load_sel=hsim_row_q; lane_bmca_row_use_direct=1'b0; lane_bmca_row_direct=vrf_rd; lane_bmca_compress_valid=1'b0;
        lane_bundle_valid='0; lane_bundle_lo_bits='0; lane_bundle_hi_a_bits='0; lane_bundle_hi_b_bits='0;
        lane_shift_valid='0;
        lane_shift_a='0; lane_shift_b='0; lane_shift_nibble=hperm_nibble_q;
        lane_addsub_valid='0; lane_addsub_hv_bits='0;
        vrf_ra='0; vrf_we='0; vrf_wa='0; vrf_wd='0;
        case(st_q)
        S_IDLE: if(valid_i&&ready_o)begin op_n=operator_i;a_n=operand_a_i;b_n=operand_b_i;st_n=S_EXEC;end
        S_EXEC: unique case(op_q)
            HDEC_VADDR: begin vaddr_bank_n=a_q[7:6];vaddr_idx_n=a_q[5:0];res_n='0;st_n=S_RESULT;end
            HDEC_VWR64: begin vrf_we[vaddr_bank_q]=1'b1;vrf_wa[vaddr_bank_q]=vaddr_idx_q;vrf_wd[vaddr_bank_q]=a_q;res_n='0;st_n=S_RESULT;end
            HDEC_VRD64: begin vrf_ra[vaddr_bank_q]=vaddr_idx_q;bk_n=vaddr_bank_q;st_n=S_RD_WAIT;end
            HDEC_HCLR: begin clr_base_n={a_q[3:0],2'b00};clr_cnt_n=4'd0;st_n=S_CLR;end
            HDEC_BCLR: begin clr_base_n=a_q[0]?6'd48:6'd32;clr_cnt_n=4'd0;st_n=S_CLR;end
            HDEC_BADD: begin
                if(a_q[3])begin res_n={62'b0,STATUS_ERROR};st_n=S_RESULT;end
                else begin
                    badd_hv_slot_n=a_q[2:0];
                    badd_acc_sel_n=a_q[4];
                    badd_chunk_n=2'd0;
                    badd_subgroup_n=2'd0;
                    st_n=S_BADD_RD_HV;
                end
            end
            HDEC_HBIND: begin
                hb_dst_base_n ={a_q[3:0], 2'b00};
                hb_src0_base_n={a_q[7:4], 2'b00};
                hb_src1_base_n={a_q[11:8],2'b00};
                chunk_cnt_n=2'd0; st_n=S_HBIND_RD0;
            end
            HDEC_HSIM: begin
                hsim_src0_base_n={a_q[3:0],2'b00};
                hsim_src1_base_n={a_q[7:4],2'b00};
                hsim_total_n='0; chunk_cnt_n=2'd0; hsim_row_n=2'd0; st_n=S_HSIM_CLEAR;
            end
            HDEC_HBUNDLE3: begin
                if(a_q[2:0] > 3'd5)begin
                    res_n={62'b0,STATUS_ERROR};st_n=S_RESULT;
                end else begin
                    hbundle_base_n=a_q[2:0];
                    hbundle_acc_sel_n=a_q[3];
                    hbundle_is4_n=1'b0;
                    hbundle_chunk_n=2'd0;
                    st_n=S_HBUNDLE3_CLEAR;
                end
            end
            HDEC_HBUNDLE4: begin
                if(a_q[2:0] > 3'd4)begin
                    res_n={62'b0,STATUS_ERROR};st_n=S_RESULT;
                end else begin
                    hbundle_base_n=a_q[2:0];
                    hbundle_acc_sel_n=a_q[3];
                    hbundle_is4_n=1'b1;
                    hbundle_chunk_n=2'd0;
                    st_n=S_HBUNDLE3_CLEAR;
                end
            end
            HDEC_HPERM: begin
                if((a_q[9:8] != 2'b00) || (a_q[3:0] == a_q[7:4]))begin res_n={62'b0,STATUS_ERROR};st_n=S_RESULT;end
                else begin
                    hperm_dst_base_n={a_q[3:0],2'b00};
                    hperm_src_base_n={a_q[7:4],2'b00};
                    hperm_word_off_n=a_q[17:14];
                    hperm_nibble_n=a_q[13:10];
                    chunk_cnt_n=2'd0; st_n=S_HPERM_RD_A;
                end
            end
            default: begin res_n={62'b0,STATUS_NOT_IMPLEMENTED};st_n=S_RESULT;end
        endcase
        S_RD_WAIT: begin res_n=vrf_rd[bk_q];st_n=S_RESULT;end
        S_CLR: begin
            vrf_we='1;
            vrf_wa[0]=clr_base_q+clr_cnt_q; vrf_wa[1]=clr_base_q+clr_cnt_q;
            vrf_wa[2]=clr_base_q+clr_cnt_q; vrf_wa[3]=clr_base_q+clr_cnt_q;
            vrf_wd='0;
            if((op_q==HDEC_HCLR&&clr_cnt_q==4'd3)||(op_q==HDEC_BCLR&&clr_cnt_q==4'd15))begin res_n='0;st_n=S_RESULT;end
            else clr_cnt_n=clr_cnt_q+4'd1;
        end
        S_HBIND_RD0: begin
            vrf_ra[0]=hb_src0_base_q+chunk_cnt_q; vrf_ra[1]=hb_src0_base_q+chunk_cnt_q;
            vrf_ra[2]=hb_src0_base_q+chunk_cnt_q; vrf_ra[3]=hb_src0_base_q+chunk_cnt_q;
            st_n=S_HBIND_RD1;
        end
        S_HBIND_RD1: begin
            src0_n=vrf_rd;
            vrf_ra[0]=hb_src1_base_q+chunk_cnt_q; vrf_ra[1]=hb_src1_base_q+chunk_cnt_q;
            vrf_ra[2]=hb_src1_base_q+chunk_cnt_q; vrf_ra[3]=hb_src1_base_q+chunk_cnt_q;
            st_n=S_HBIND_XOR_WR;
        end
        S_HBIND_XOR_WR: begin
            lane_bool_valid='1;
            vrf_we='1;
            vrf_wa[0]=hb_dst_base_q+chunk_cnt_q; vrf_wa[1]=hb_dst_base_q+chunk_cnt_q;
            vrf_wa[2]=hb_dst_base_q+chunk_cnt_q; vrf_wa[3]=hb_dst_base_q+chunk_cnt_q;
            vrf_wd=lane_bool_result;
            if(chunk_cnt_q==2'd3)begin res_n='0;st_n=S_RESULT;end
            else begin chunk_cnt_n=chunk_cnt_q+2'd1;st_n=S_HBIND_RD0;end
        end
        S_HSIM_CLEAR: begin
            lane_bmca_row_clear=1'b1;
            hsim_row_n=2'd0;
            st_n=S_HSIM_RD0;
        end
        S_HSIM_RD0: begin
            vrf_ra[0]=hsim_src0_base_q+chunk_cnt_q; vrf_ra[1]=hsim_src0_base_q+chunk_cnt_q;
            vrf_ra[2]=hsim_src0_base_q+chunk_cnt_q; vrf_ra[3]=hsim_src0_base_q+chunk_cnt_q;
            st_n=S_HSIM_RD1;
        end
        S_HSIM_RD1: begin
            src0_n=vrf_rd;
            vrf_ra[0]=hsim_src1_base_q+chunk_cnt_q; vrf_ra[1]=hsim_src1_base_q+chunk_cnt_q;
            vrf_ra[2]=hsim_src1_base_q+chunk_cnt_q; vrf_ra[3]=hsim_src1_base_q+chunk_cnt_q;
            st_n=S_HSIM_LOAD;
        end
        S_HSIM_LOAD: begin
            lane_bool_valid='1;
            lane_bmca_row_load_valid=1'b1;
            lane_bmca_row_load_sel=hsim_row_q;
            if((chunk_cnt_q==2'd3)||(hsim_row_q==2'd3))begin
                st_n=S_HSIM_COMPRESS;
            end else begin
                chunk_cnt_n=chunk_cnt_q+2'd1;
                hsim_row_n=hsim_row_q+2'd1;
                st_n=S_HSIM_RD0;
            end
        end
        S_HSIM_COMPRESS: begin
            lane_bmca_compress_valid=1'b1;
            st_n=S_HSIM_ACCUM;
        end
        S_HSIM_ACCUM: begin
            if(&lane_bmca_count_valid)begin
                if(chunk_cnt_q==2'd3)begin res_n={53'b0,(hsim_total_q+{1'b0,hsim_group_distance})};st_n=S_RESULT;end
                else begin hsim_total_n=hsim_total_q+{1'b0,hsim_group_distance};chunk_cnt_n=chunk_cnt_q+2'd1;st_n=S_HSIM_CLEAR;end
            end
        end
        S_HBUNDLE3_CLEAR: begin
            lane_bmca_row_clear=1'b1;
            st_n=S_HBUNDLE3_RD_HV0;
        end
        S_HBUNDLE3_RD_HV0: begin
            vrf_ra[0]=hbundle_hv0_entry; vrf_ra[1]=hbundle_hv0_entry;
            vrf_ra[2]=hbundle_hv0_entry; vrf_ra[3]=hbundle_hv0_entry;
            st_n=S_HBUNDLE3_LOAD_ROW0;
        end
        S_HBUNDLE3_LOAD_ROW0: begin
            lane_bmca_row_use_direct=1'b1;
            lane_bmca_row_load_valid=1'b1;
            lane_bmca_row_load_sel=2'd0;
            st_n=S_HBUNDLE3_RD_HV1;
        end
        S_HBUNDLE3_RD_HV1: begin
            vrf_ra[0]=hbundle_hv1_entry; vrf_ra[1]=hbundle_hv1_entry;
            vrf_ra[2]=hbundle_hv1_entry; vrf_ra[3]=hbundle_hv1_entry;
            st_n=S_HBUNDLE3_LOAD_ROW1;
        end
        S_HBUNDLE3_LOAD_ROW1: begin
            lane_bmca_row_use_direct=1'b1;
            lane_bmca_row_load_valid=1'b1;
            lane_bmca_row_load_sel=2'd1;
            st_n=S_HBUNDLE3_RD_HV2;
        end
        S_HBUNDLE3_RD_HV2: begin
            vrf_ra[0]=hbundle_hv2_entry; vrf_ra[1]=hbundle_hv2_entry;
            vrf_ra[2]=hbundle_hv2_entry; vrf_ra[3]=hbundle_hv2_entry;
            st_n=S_HBUNDLE3_LOAD_ROW2;
        end
        S_HBUNDLE3_LOAD_ROW2: begin
            lane_bmca_row_use_direct=1'b1;
            lane_bmca_row_load_valid=1'b1;
            lane_bmca_row_load_sel=2'd2;
            st_n=hbundle_is4_q ? S_HBUNDLE3_RD_HV3 : S_HBUNDLE3_COMPRESS;
        end
        S_HBUNDLE3_RD_HV3: begin
            vrf_ra[0]=hbundle_hv3_entry; vrf_ra[1]=hbundle_hv3_entry;
            vrf_ra[2]=hbundle_hv3_entry; vrf_ra[3]=hbundle_hv3_entry;
            st_n=S_HBUNDLE3_LOAD_ROW3;
        end
        S_HBUNDLE3_LOAD_ROW3: begin
            lane_bmca_row_use_direct=1'b1;
            lane_bmca_row_load_valid=1'b1;
            lane_bmca_row_load_sel=2'd3;
            st_n=S_HBUNDLE3_COMPRESS;
        end
        S_HBUNDLE3_COMPRESS: begin
            lane_bmca_compress_valid=1'b1;
            st_n=S_HBUNDLE3_LATCH;
        end
        S_HBUNDLE3_LATCH: begin
            if(&lane_bmca_count_valid)begin
                hbundle_lo_n=lane_bmca_lo;
                hbundle_hi_a_n=lane_bmca_hi_a;
                hbundle_hi_b_n=lane_bmca_hi_b;
                vrf_ra[0]=hbundle_acc_entry0; vrf_ra[1]=hbundle_acc_entry0;
                vrf_ra[2]=hbundle_acc_entry0; vrf_ra[3]=hbundle_acc_entry0;
                st_n=S_HBUNDLE3_UPDATE_SUB0;
            end
        end
        S_HBUNDLE3_UPDATE_SUB0: begin
            lane_bundle_valid='1;
            lane_bundle_lo_bits[0]=hbundle_lo_q[0][15:0]; lane_bundle_lo_bits[1]=hbundle_lo_q[1][15:0]; lane_bundle_lo_bits[2]=hbundle_lo_q[2][15:0]; lane_bundle_lo_bits[3]=hbundle_lo_q[3][15:0];
            lane_bundle_hi_a_bits[0]=hbundle_hi_a_q[0][15:0]; lane_bundle_hi_a_bits[1]=hbundle_hi_a_q[1][15:0]; lane_bundle_hi_a_bits[2]=hbundle_hi_a_q[2][15:0]; lane_bundle_hi_a_bits[3]=hbundle_hi_a_q[3][15:0];
            lane_bundle_hi_b_bits[0]=hbundle_hi_b_q[0][15:0]; lane_bundle_hi_b_bits[1]=hbundle_hi_b_q[1][15:0]; lane_bundle_hi_b_bits[2]=hbundle_hi_b_q[2][15:0]; lane_bundle_hi_b_bits[3]=hbundle_hi_b_q[3][15:0];
            vrf_we='1;
            vrf_wa[0]=hbundle_acc_entry0; vrf_wa[1]=hbundle_acc_entry0; vrf_wa[2]=hbundle_acc_entry0; vrf_wa[3]=hbundle_acc_entry0;
            vrf_wd=lane_bundle_counter_result;
            vrf_ra[0]=hbundle_acc_entry1; vrf_ra[1]=hbundle_acc_entry1; vrf_ra[2]=hbundle_acc_entry1; vrf_ra[3]=hbundle_acc_entry1;
            st_n=S_HBUNDLE3_UPDATE_SUB1;
        end
        S_HBUNDLE3_UPDATE_SUB1: begin
            lane_bundle_valid='1;
            lane_bundle_lo_bits[0]=hbundle_lo_q[0][31:16]; lane_bundle_lo_bits[1]=hbundle_lo_q[1][31:16]; lane_bundle_lo_bits[2]=hbundle_lo_q[2][31:16]; lane_bundle_lo_bits[3]=hbundle_lo_q[3][31:16];
            lane_bundle_hi_a_bits[0]=hbundle_hi_a_q[0][31:16]; lane_bundle_hi_a_bits[1]=hbundle_hi_a_q[1][31:16]; lane_bundle_hi_a_bits[2]=hbundle_hi_a_q[2][31:16]; lane_bundle_hi_a_bits[3]=hbundle_hi_a_q[3][31:16];
            lane_bundle_hi_b_bits[0]=hbundle_hi_b_q[0][31:16]; lane_bundle_hi_b_bits[1]=hbundle_hi_b_q[1][31:16]; lane_bundle_hi_b_bits[2]=hbundle_hi_b_q[2][31:16]; lane_bundle_hi_b_bits[3]=hbundle_hi_b_q[3][31:16];
            vrf_we='1;
            vrf_wa[0]=hbundle_acc_entry1; vrf_wa[1]=hbundle_acc_entry1; vrf_wa[2]=hbundle_acc_entry1; vrf_wa[3]=hbundle_acc_entry1;
            vrf_wd=lane_bundle_counter_result;
            vrf_ra[0]=hbundle_acc_entry2; vrf_ra[1]=hbundle_acc_entry2; vrf_ra[2]=hbundle_acc_entry2; vrf_ra[3]=hbundle_acc_entry2;
            st_n=S_HBUNDLE3_UPDATE_SUB2;
        end
        S_HBUNDLE3_UPDATE_SUB2: begin
            lane_bundle_valid='1;
            lane_bundle_lo_bits[0]=hbundle_lo_q[0][47:32]; lane_bundle_lo_bits[1]=hbundle_lo_q[1][47:32]; lane_bundle_lo_bits[2]=hbundle_lo_q[2][47:32]; lane_bundle_lo_bits[3]=hbundle_lo_q[3][47:32];
            lane_bundle_hi_a_bits[0]=hbundle_hi_a_q[0][47:32]; lane_bundle_hi_a_bits[1]=hbundle_hi_a_q[1][47:32]; lane_bundle_hi_a_bits[2]=hbundle_hi_a_q[2][47:32]; lane_bundle_hi_a_bits[3]=hbundle_hi_a_q[3][47:32];
            lane_bundle_hi_b_bits[0]=hbundle_hi_b_q[0][47:32]; lane_bundle_hi_b_bits[1]=hbundle_hi_b_q[1][47:32]; lane_bundle_hi_b_bits[2]=hbundle_hi_b_q[2][47:32]; lane_bundle_hi_b_bits[3]=hbundle_hi_b_q[3][47:32];
            vrf_we='1;
            vrf_wa[0]=hbundle_acc_entry2; vrf_wa[1]=hbundle_acc_entry2; vrf_wa[2]=hbundle_acc_entry2; vrf_wa[3]=hbundle_acc_entry2;
            vrf_wd=lane_bundle_counter_result;
            vrf_ra[0]=hbundle_acc_entry3; vrf_ra[1]=hbundle_acc_entry3; vrf_ra[2]=hbundle_acc_entry3; vrf_ra[3]=hbundle_acc_entry3;
            st_n=S_HBUNDLE3_UPDATE_SUB3;
        end
        S_HBUNDLE3_UPDATE_SUB3: begin
            lane_bundle_valid='1;
            lane_bundle_lo_bits[0]=hbundle_lo_q[0][63:48]; lane_bundle_lo_bits[1]=hbundle_lo_q[1][63:48]; lane_bundle_lo_bits[2]=hbundle_lo_q[2][63:48]; lane_bundle_lo_bits[3]=hbundle_lo_q[3][63:48];
            lane_bundle_hi_a_bits[0]=hbundle_hi_a_q[0][63:48]; lane_bundle_hi_a_bits[1]=hbundle_hi_a_q[1][63:48]; lane_bundle_hi_a_bits[2]=hbundle_hi_a_q[2][63:48]; lane_bundle_hi_a_bits[3]=hbundle_hi_a_q[3][63:48];
            lane_bundle_hi_b_bits[0]=hbundle_hi_b_q[0][63:48]; lane_bundle_hi_b_bits[1]=hbundle_hi_b_q[1][63:48]; lane_bundle_hi_b_bits[2]=hbundle_hi_b_q[2][63:48]; lane_bundle_hi_b_bits[3]=hbundle_hi_b_q[3][63:48];
            vrf_we='1;
            vrf_wa[0]=hbundle_acc_entry3; vrf_wa[1]=hbundle_acc_entry3; vrf_wa[2]=hbundle_acc_entry3; vrf_wa[3]=hbundle_acc_entry3;
            vrf_wd=lane_bundle_counter_result;
            if(hbundle_chunk_q==2'd3)begin res_n='0;st_n=S_RESULT;end
            else begin hbundle_chunk_n=hbundle_chunk_q+2'd1;st_n=S_HBUNDLE3_CLEAR;end
        end
        S_HPERM_RD_A: begin
            vrf_ra[0]=hperm_src_base_q+hperm_word0[3:2]; vrf_ra[1]=hperm_src_base_q+hperm_word0[3:2];
            vrf_ra[2]=hperm_src_base_q+hperm_word0[3:2]; vrf_ra[3]=hperm_src_base_q+hperm_word0[3:2];
            hperm_lane_base_n=hperm_word0[1:0];
            st_n=S_HPERM_RD_B;
        end
        S_HPERM_RD_B: begin
            hperm_a_n=vrf_rd;
            vrf_ra[0]=hperm_src_base_q+hperm_next_chunk; vrf_ra[1]=hperm_src_base_q+hperm_next_chunk;
            vrf_ra[2]=hperm_src_base_q+hperm_next_chunk; vrf_ra[3]=hperm_src_base_q+hperm_next_chunk;
            st_n=S_HPERM_SHIFT_WR;
        end
        S_HPERM_SHIFT_WR: begin
            lane_shift_valid='1;
            lane_shift_nibble=hperm_nibble_q;
            lane_shift_a[0]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd0,hperm_a_q,vrf_rd);
            lane_shift_a[1]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd1,hperm_a_q,vrf_rd);
            lane_shift_a[2]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd2,hperm_a_q,vrf_rd);
            lane_shift_a[3]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd3,hperm_a_q,vrf_rd);
            lane_shift_b[0]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd1,hperm_a_q,vrf_rd);
            lane_shift_b[1]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd2,hperm_a_q,vrf_rd);
            lane_shift_b[2]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd3,hperm_a_q,vrf_rd);
            lane_shift_b[3]=hperm_pick_word({1'b0,hperm_lane_base_q}+3'd4,hperm_a_q,vrf_rd);
            vrf_we='1;
            vrf_wa[0]=hperm_dst_base_q+chunk_cnt_q; vrf_wa[1]=hperm_dst_base_q+chunk_cnt_q;
            vrf_wa[2]=hperm_dst_base_q+chunk_cnt_q; vrf_wa[3]=hperm_dst_base_q+chunk_cnt_q;
            vrf_wd=lane_shift_result;
            if(chunk_cnt_q==2'd3)begin res_n='0;st_n=S_RESULT;end
            else begin chunk_cnt_n=chunk_cnt_q+2'd1;st_n=S_HPERM_RD_A;end
        end
        S_BADD_RD_HV: begin
            vrf_ra[0]=badd_hv_entry; vrf_ra[1]=badd_hv_entry;
            vrf_ra[2]=badd_hv_entry; vrf_ra[3]=badd_hv_entry;
            st_n=S_BADD_RD_ACC;
        end
        S_BADD_RD_ACC: begin
            badd_hv_n=vrf_rd;
            vrf_ra[0]=badd_acc_entry; vrf_ra[1]=badd_acc_entry;
            vrf_ra[2]=badd_acc_entry; vrf_ra[3]=badd_acc_entry;
            st_n=S_BADD_ACCUM_WR;
        end
        S_BADD_ACCUM_WR: begin
            lane_addsub_valid='1;
            lane_addsub_hv_bits[0]=badd_hv_q[0][{badd_subgroup_q,4'b0000} +: 16];
            lane_addsub_hv_bits[1]=badd_hv_q[1][{badd_subgroup_q,4'b0000} +: 16];
            lane_addsub_hv_bits[2]=badd_hv_q[2][{badd_subgroup_q,4'b0000} +: 16];
            lane_addsub_hv_bits[3]=badd_hv_q[3][{badd_subgroup_q,4'b0000} +: 16];
            vrf_we='1;
            vrf_wa[0]=badd_acc_entry; vrf_wa[1]=badd_acc_entry;
            vrf_wa[2]=badd_acc_entry; vrf_wa[3]=badd_acc_entry;
            vrf_wd=lane_addsub_result;
            if(badd_subgroup_q==2'd3)begin
                badd_subgroup_n=2'd0;
                if(badd_chunk_q==2'd3)begin res_n='0;st_n=S_RESULT;end
                else begin badd_chunk_n=badd_chunk_q+2'd1;st_n=S_BADD_RD_HV;end
            end else begin
                vrf_ra[0]=badd_next_acc_entry; vrf_ra[1]=badd_next_acc_entry;
                vrf_ra[2]=badd_next_acc_entry; vrf_ra[3]=badd_next_acc_entry;
                badd_subgroup_n=badd_subgroup_q+2'd1;
                st_n=S_BADD_ACCUM_WR;
            end
        end
        S_RESULT: st_n=S_IDLE;
        default: st_n=S_IDLE;
        endcase
    end
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if(!rst_ni)begin st_q<=S_IDLE;res_q<='0;op_q<=HDEC_VWR64;a_q<='0;b_q<='0;bk_q<='0;vaddr_bank_q<='0;vaddr_idx_q<='0;clr_cnt_q<='0;clr_base_q<='0;src0_q<='0;chunk_cnt_q<='0;hb_dst_base_q<='0;hb_src0_base_q<='0;hb_src1_base_q<='0;hsim_src0_base_q<='0;hsim_src1_base_q<='0;hsim_total_q<='0;hsim_row_q<='0;hperm_a_q<='0;hperm_dst_base_q<='0;hperm_src_base_q<='0;hperm_word_off_q<='0;hperm_nibble_q<='0;hperm_lane_base_q<='0;badd_hv_q<='0;badd_hv_slot_q<='0;badd_chunk_q<='0;badd_subgroup_q<='0;badd_acc_sel_q<='0;hbundle_base_q<='0;hbundle_acc_sel_q<='0;hbundle_is4_q<='0;hbundle_chunk_q<='0;hbundle_lo_q<='0;hbundle_hi_a_q<='0;hbundle_hi_b_q<='0;end
        else begin st_q<=st_n;res_q<=res_n;op_q<=op_n;a_q<=a_n;b_q<=b_n;bk_q<=bk_n;vaddr_bank_q<=vaddr_bank_n;vaddr_idx_q<=vaddr_idx_n;clr_cnt_q<=clr_cnt_n;clr_base_q<=clr_base_n;src0_q<=src0_n;chunk_cnt_q<=chunk_cnt_n;hb_dst_base_q<=hb_dst_base_n;hb_src0_base_q<=hb_src0_base_n;hb_src1_base_q<=hb_src1_base_n;hsim_src0_base_q<=hsim_src0_base_n;hsim_src1_base_q<=hsim_src1_base_n;hsim_total_q<=hsim_total_n;hsim_row_q<=hsim_row_n;hperm_a_q<=hperm_a_n;hperm_dst_base_q<=hperm_dst_base_n;hperm_src_base_q<=hperm_src_base_n;hperm_word_off_q<=hperm_word_off_n;hperm_nibble_q<=hperm_nibble_n;hperm_lane_base_q<=hperm_lane_base_n;badd_hv_q<=badd_hv_n;badd_hv_slot_q<=badd_hv_slot_n;badd_chunk_q<=badd_chunk_n;badd_subgroup_q<=badd_subgroup_n;badd_acc_sel_q<=badd_acc_sel_n;hbundle_base_q<=hbundle_base_n;hbundle_acc_sel_q<=hbundle_acc_sel_n;hbundle_is4_q<=hbundle_is4_n;hbundle_chunk_q<=hbundle_chunk_n;hbundle_lo_q<=hbundle_lo_n;hbundle_hi_a_q<=hbundle_hi_a_n;hbundle_hi_b_q<=hbundle_hi_b_n;end
    end
endmodule
