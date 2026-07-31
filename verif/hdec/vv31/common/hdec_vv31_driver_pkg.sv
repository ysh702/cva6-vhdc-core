package hdec_vv31_driver_pkg;
    import hdec_pkg::*;

    typedef struct packed {
        logic [63:0] request_cycle;
        logic [63:0] accept_cycle;
        logic [63:0] response_cycle;
    } vv31_timing_t;

    function automatic logic [63:0] vv31_vaddr_operand(
        input logic [1:0] bank,
        input logic [5:0] row
    );
        vv31_vaddr_operand = {56'd0, bank, row};
    endfunction

    function automatic logic [63:0] vv31_hbind_operand(
        input logic [3:0] dst_slot,
        input logic [3:0] src0_slot,
        input logic [3:0] src1_slot
    );
        vv31_hbind_operand = {52'd0, src1_slot, src0_slot, dst_slot};
    endfunction

    function automatic logic [63:0] vv31_hsim_operand(
        input logic [3:0] src0_slot,
        input logic [3:0] src1_slot
    );
        vv31_hsim_operand = {56'd0, src1_slot, src0_slot};
    endfunction

    function automatic logic [63:0] vv31_hmatch_operand(
        input logic [3:0] query_slot,
        input logic [3:0] class_start_slot,
        input logic [7:0] class_count
    );
        vv31_hmatch_operand =
            {48'd0, class_count, class_start_slot, query_slot};
    endfunction

    function automatic logic [63:0] vv31_hperm_operand(
        input logic [3:0] dst_slot,
        input logic [3:0] src_slot,
        input logic [9:0] rotate
    );
        begin
            vv31_hperm_operand = '0;
            vv31_hperm_operand[3:0]   = dst_slot;
            vv31_hperm_operand[7:4]   = src_slot;
            vv31_hperm_operand[9:8]   = rotate[1:0];
            vv31_hperm_operand[13:10] = rotate[5:2];
            vv31_hperm_operand[15:14] = rotate[7:6];
            vv31_hperm_operand[17:16] = rotate[9:8];
        end
    endfunction

    function automatic logic [63:0] vv31_hcntclip_operand(
        input logic [2:0] dst_slot,
        input logic       acc_select,
        input logic [3:0] threshold
    );
        vv31_hcntclip_operand =
            {56'd0, threshold, acc_select, dst_slot};
    endfunction

    function automatic logic [63:0] vv31_ecc_pmul_operand(
        input logic       background,
        input logic [5:0] dst_row,
        input logic [5:0] point_x_row,
        input logic [5:0] scalar_row
    );
        begin
            vv31_ecc_pmul_operand = '0;
            vv31_ecc_pmul_operand[30]    = 1'b1;
            vv31_ecc_pmul_operand[29]    = background;
            vv31_ecc_pmul_operand[17:12] = dst_row;
            vv31_ecc_pmul_operand[11:6]  = point_x_row;
            vv31_ecc_pmul_operand[5:0]   = scalar_row;
        end
    endfunction

    function automatic bit vv31_is_hdc_compute(input hdec_op_t operation);
        case (operation)
            HDEC_HCLR,
            HDEC_HCNTCLR,
            HDEC_HCNTADD,
            HDEC_HBIND,
            HDEC_HPERM,
            HDEC_HSIM,
            HDEC_HCNTCLIP,
            HDEC_HMATCH: vv31_is_hdc_compute = 1'b1;
            default: vv31_is_hdc_compute = 1'b0;
        endcase
    endfunction

endpackage
