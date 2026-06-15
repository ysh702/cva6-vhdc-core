module tb_hdec_ecc_pmul_profile_v27;
    import hdec_pkg::*;

    localparam int ST_RD_WAIT                 = 3;
    localparam int ST_UOP_P1_RD0              = 10;
    localparam int ST_ECC_LOAD_A_WAIT         = 21;
    localparam int ST_ECC_LOAD_A              = 22;
    localparam int ST_ECC_LOAD_B_WAIT         = 23;
    localparam int ST_ECC_LOAD_B              = 24;
    localparam int ST_ECC_DIAG_ISSUE          = 25;
    localparam int ST_ECC_DIAG_WAIT           = 26;
    localparam int ST_ECC_LEAF_FOLD           = 27;
    localparam int ST_ECC_WRITE_PAIR          = 28;
    localparam int ST_ECC_WRITE_DRAIN         = 29;
    localparam int ST_ECC_REDUCE_LOAD_LO_WAIT = 30;
    localparam int ST_ECC_REDUCE_LOAD_LO      = 31;
    localparam int ST_ECC_REDUCE_LOAD_HI_WAIT = 32;
    localparam int ST_ECC_REDUCE_WRITE        = 33;
    localparam int ST_ECC_INV_INIT            = 34;

    localparam int PH_INV_SQR                 = 1;
    localparam int PH_INV_MUL                 = 2;
    localparam int PH_PMUL_FIELD              = 5;
    localparam int PH_PMUL_ADD                = 6;
    localparam int PH_PMUL_COPY               = 7;

    localparam int SUB_INIT                   = 1;
    localparam int SUB_ADD                    = 3;
    localparam int SUB_DBL                    = 4;
    localparam int SUB_AFFINE                 = 5;
    localparam int SUB_ZERO_OUT               = 6;

    logic clk_i;
    logic rst_ni;
    logic valid_i;
    logic ready_o;
    hdec_op_t operator_i;
    logic [63:0] operand_a_i;
    logic [63:0] operand_b_i;
    logic valid_o;
    logic [63:0] result_o;
    int unsigned error_count;

    int unsigned prof_cycles;
    int unsigned phase_inv_sqr_cycles;
    int unsigned phase_inv_mul_cycles;
    int unsigned phase_pmul_field_cycles;
    int unsigned phase_pmul_add_cycles;
    int unsigned phase_pmul_copy_cycles;
    int unsigned sub_init_cycles;
    int unsigned sub_add_cycles;
    int unsigned sub_dbl_cycles;
    int unsigned sub_affine_cycles;
    int unsigned sub_zero_cycles;
    int unsigned gf_mul_start_count;
    int unsigned gf_mul_start_in_add;
    int unsigned gf_mul_start_in_affine;
    int unsigned gf_mul_start_in_inv_mul;
    int unsigned sqr_start_count;
    int unsigned sqr_start_in_dbl;
    int unsigned sqr_start_in_affine;
    int unsigned sqr_start_in_inv_sqr;
    int unsigned hbind_start_count;
    int unsigned hbind_start_in_add;
    int unsigned hbind_start_in_dbl;
    int unsigned hbind_start_in_affine;
    int unsigned inv_start_count;
    int unsigned st_ecc_load_cycles;
    int unsigned st_ecc_diag_cycles;
    int unsigned st_ecc_leaf_fold_cycles;
    int unsigned st_ecc_write_pair_cycles;
    int unsigned st_ecc_write_drain_cycles;
    int unsigned st_ecc_reduce_cycles;
    int unsigned st_hspread_cycles;
    int unsigned st_ecc_uop_cycles;

    hdec_top dut (
        .clk_i,
        .rst_ni,
        .valid_i,
        .ready_o,
        .operator_i,
        .operand_a_i,
        .operand_b_i,
        .valid_o,
        .result_o
    );

    initial clk_i = 1'b0;
    always #2.5 clk_i = ~clk_i;

    function automatic logic [63:0] ecc_pmul_operand(
        input logic [5:0] dst_idx,
        input logic [5:0] point_x_idx,
        input logic [5:0] scalar_idx
    );
        ecc_pmul_operand = (64'h1 << 30)
                         | ({58'd0, dst_idx} << 12)
                         | ({58'd0, point_x_idx} << 6)
                         | {58'd0, scalar_idx};
    endfunction

    task automatic clear_profile;
        begin
            prof_cycles = 0;
            phase_inv_sqr_cycles = 0;
            phase_inv_mul_cycles = 0;
            phase_pmul_field_cycles = 0;
            phase_pmul_add_cycles = 0;
            phase_pmul_copy_cycles = 0;
            sub_init_cycles = 0;
            sub_add_cycles = 0;
            sub_dbl_cycles = 0;
            sub_affine_cycles = 0;
            sub_zero_cycles = 0;
            gf_mul_start_count = 0;
            gf_mul_start_in_add = 0;
            gf_mul_start_in_affine = 0;
            gf_mul_start_in_inv_mul = 0;
            sqr_start_count = 0;
            sqr_start_in_dbl = 0;
            sqr_start_in_affine = 0;
            sqr_start_in_inv_sqr = 0;
            hbind_start_count = 0;
            hbind_start_in_add = 0;
            hbind_start_in_dbl = 0;
            hbind_start_in_affine = 0;
            inv_start_count = 0;
            st_ecc_load_cycles = 0;
            st_ecc_diag_cycles = 0;
            st_ecc_leaf_fold_cycles = 0;
            st_ecc_write_pair_cycles = 0;
            st_ecc_write_drain_cycles = 0;
            st_ecc_reduce_cycles = 0;
            st_hspread_cycles = 0;
            st_ecc_uop_cycles = 0;
        end
    endtask

    task automatic sample_profile;
        int st;
        int phase;
        int subop;
        begin
            st = int'(dut.st_q);
            phase = int'(dut.ecc_job_phase_q);
            subop = int'(dut.ecc_pmul_subop_q);
            prof_cycles++;

            unique case (phase)
                PH_INV_SQR:    phase_inv_sqr_cycles++;
                PH_INV_MUL:    phase_inv_mul_cycles++;
                PH_PMUL_FIELD: phase_pmul_field_cycles++;
                PH_PMUL_ADD:   phase_pmul_add_cycles++;
                PH_PMUL_COPY:  phase_pmul_copy_cycles++;
                default: begin end
            endcase

            unique case (subop)
                SUB_INIT:     sub_init_cycles++;
                SUB_ADD:      sub_add_cycles++;
                SUB_DBL:      sub_dbl_cycles++;
                SUB_AFFINE:   sub_affine_cycles++;
                SUB_ZERO_OUT: sub_zero_cycles++;
                default: begin end
            endcase

            if (st == ST_ECC_LOAD_A_WAIT) begin
                gf_mul_start_count++;
                if (subop == SUB_ADD)
                    gf_mul_start_in_add++;
                if (subop == SUB_AFFINE)
                    gf_mul_start_in_affine++;
                if (phase == PH_INV_MUL)
                    gf_mul_start_in_inv_mul++;
            end

            if ((st == ST_RD_WAIT) && dut.hperm_spread_q && dut.ecc_job_active_q) begin
                sqr_start_count++;
                if (subop == SUB_DBL)
                    sqr_start_in_dbl++;
                if (subop == SUB_AFFINE)
                    sqr_start_in_affine++;
                if (phase == PH_INV_SQR)
                    sqr_start_in_inv_sqr++;
            end

            if ((st == ST_UOP_P1_RD0) && dut.uop_p0_q.valid
                    && (dut.uop_p0_q.op_type == UOP_HBIND_CHUNK)
                    && dut.ecc_job_active_q) begin
                hbind_start_count++;
                if (subop == SUB_ADD)
                    hbind_start_in_add++;
                if (subop == SUB_DBL)
                    hbind_start_in_dbl++;
                if (subop == SUB_AFFINE)
                    hbind_start_in_affine++;
            end

            if (st == ST_ECC_INV_INIT)
                inv_start_count++;

            unique case (st)
                ST_ECC_LOAD_A_WAIT,
                ST_ECC_LOAD_A,
                ST_ECC_LOAD_B_WAIT,
                ST_ECC_LOAD_B:
                    st_ecc_load_cycles++;
                ST_ECC_DIAG_ISSUE,
                ST_ECC_DIAG_WAIT:
                    st_ecc_diag_cycles++;
                ST_ECC_LEAF_FOLD:
                    st_ecc_leaf_fold_cycles++;
                ST_ECC_WRITE_PAIR:
                    st_ecc_write_pair_cycles++;
                ST_ECC_WRITE_DRAIN:
                    st_ecc_write_drain_cycles++;
                ST_ECC_REDUCE_LOAD_LO_WAIT,
                ST_ECC_REDUCE_LOAD_LO,
                ST_ECC_REDUCE_LOAD_HI_WAIT,
                ST_ECC_REDUCE_WRITE:
                    st_ecc_reduce_cycles++;
                51, 52:
                    st_hspread_cycles++;
                ST_UOP_P1_RD0, 11, 12, 13, 14, 15, 16, 17, 18, 19:
                    if (dut.ecc_job_active_q)
                        st_ecc_uop_cycles++;
                default: begin end
            endcase
        end
    endtask

    task automatic issue(input hdec_op_t op,
                         input logic [63:0] a,
                         output logic [63:0] result);
        int unsigned cycles;
        begin
            issue_count(op, a, result, cycles, 1'b0);
        end
    endtask

    task automatic issue_count(input hdec_op_t op,
                               input logic [63:0] a,
                               output logic [63:0] result,
                               output int unsigned cycles,
                               input bit do_profile);
        bit seen;
        begin
            while (!ready_o) @(posedge clk_i);
            @(posedge clk_i);
            valid_i     <= 1'b1;
            operator_i  <= op;
            operand_a_i <= a;
            operand_b_i <= '0;
            @(posedge clk_i);
            valid_i     <= 1'b0;
            operator_i  <= HDEC_VWR64;
            operand_a_i <= '0;
            operand_b_i <= '0;

            result = 'x;
            cycles = 0;
            seen = 1'b0;
            for (int wait_cycles = 0; wait_cycles < 1000000 && !seen; wait_cycles++) begin
                @(posedge clk_i);
                cycles++;
                #1;
                if (do_profile)
                    sample_profile();
                if (valid_o) begin
                    result = result_o;
                    seen = 1'b1;
                end
            end
            if (!seen) begin
                error_count++;
                $fatal(1, "Timeout waiting for op %0d", op);
            end
        end
    endtask

    task automatic write_vrf64(input logic [1:0] bank,
                               input logic [5:0] idx,
                               input logic [63:0] data);
        logic [63:0] ignored;
        begin
            issue(HDEC_VADDR, {56'd0, bank, idx}, ignored);
            issue(HDEC_VWR64, data, ignored);
        end
    endtask

    task automatic read_vrf64(input logic [1:0] bank,
                              input logic [5:0] idx,
                              output logic [63:0] data);
        logic [63:0] ignored;
        begin
            issue(HDEC_VADDR, {56'd0, bank, idx}, ignored);
            issue(HDEC_VRD64, '0, data);
        end
    endtask

    task automatic write_row(input logic [5:0] idx,
                             input logic [255:0] value);
        begin
            write_vrf64(2'd0, idx, value[63:0]);
            write_vrf64(2'd1, idx, value[127:64]);
            write_vrf64(2'd2, idx, value[191:128]);
            write_vrf64(2'd3, idx, value[255:192]);
        end
    endtask

    task automatic read_row(input logic [5:0] idx,
                            output logic [255:0] value);
        begin
            read_vrf64(2'd0, idx, value[63:0]);
            read_vrf64(2'd1, idx, value[127:64]);
            read_vrf64(2'd2, idx, value[191:128]);
            read_vrf64(2'd3, idx, value[255:192]);
        end
    endtask

    task automatic check_row(input string label,
                             input logic [5:0] idx,
                             input logic [255:0] expected);
        logic [255:0] got;
        begin
            read_row(idx, got);
            if (got !== expected) begin
                error_count++;
                $error("%s mismatch got=0x%064h expected=0x%064h", label, got, expected);
            end
        end
    endtask

    initial begin
        logic [63:0] status;
        logic [255:0] gx;
        logic [255:0] gy;
        logic [255:0] scalar;
        logic [255:0] expected_x_rand;
        logic [255:0] expected_y_rand;
        int unsigned pmul_wall_cycles;

        error_count = 0;
        valid_i     = 1'b0;
        operator_i  = HDEC_VWR64;
        operand_a_i = '0;
        operand_b_i = '0;
        rst_ni      = 1'b0;
        clear_profile();

        repeat (8) @(posedge clk_i);
        rst_ni = 1'b1;
        repeat (20) @(posedge clk_i);

        gx = 256'h0000017232ba853a7e731af129f22ff4149563a419c26bf50a4c9d6eefad6126;
        gy = 256'h000001db537dece819b7f70f555a67c427a8cd9bf18aeb9b56e0c11056fae6a3;
        scalar = 256'h000001807641b930b5b5658e21062f9465931d9dfc2010db64170d358aa115a0;
        expected_x_rand = 256'h000000f43234b60b69a741092b0bae60cb7bdd1f4f41678ce500a24138589932;
        expected_y_rand = 256'h000000cd8f8a1c7e66f52b0e7dd4f01c9c9d9c9c74e42ec48eaebd9ffa719484;

        write_row(6'd0, gx);
        write_row(6'd1, gy);
        write_row(6'd2, scalar);

        issue_count(HDEC_ECC_STATUS, ecc_pmul_operand(6'd4, 6'd0, 6'd2),
                    status, pmul_wall_cycles, 1'b1);
        if (status[1:0] !== STATUS_OK) begin
            error_count++;
            $error("PMUL returned bad status 0x%016h", status);
        end

        $display("PMUL_PROFILE_WALL_CYCLES=%0d", pmul_wall_cycles);
        $display("PMUL_PROFILE_STATUS_LOW16=%0d", status[31:16]);
        $display("PMUL_PROFILE_SAMPLED_CYCLES=%0d", prof_cycles);
        $display("PMUL_PROFILE_PHASE_INV_SQR_CYCLES=%0d", phase_inv_sqr_cycles);
        $display("PMUL_PROFILE_PHASE_INV_MUL_CYCLES=%0d", phase_inv_mul_cycles);
        $display("PMUL_PROFILE_PHASE_PMUL_FIELD_CYCLES=%0d", phase_pmul_field_cycles);
        $display("PMUL_PROFILE_PHASE_PMUL_ADD_CYCLES=%0d", phase_pmul_add_cycles);
        $display("PMUL_PROFILE_PHASE_PMUL_COPY_CYCLES=%0d", phase_pmul_copy_cycles);
        $display("PMUL_PROFILE_SUB_INIT_CYCLES=%0d", sub_init_cycles);
        $display("PMUL_PROFILE_SUB_ADD_CYCLES=%0d", sub_add_cycles);
        $display("PMUL_PROFILE_SUB_DBL_CYCLES=%0d", sub_dbl_cycles);
        $display("PMUL_PROFILE_SUB_AFFINE_CYCLES=%0d", sub_affine_cycles);
        $display("PMUL_PROFILE_SUB_ZERO_CYCLES=%0d", sub_zero_cycles);
        $display("PMUL_PROFILE_GF_MUL_STARTS=%0d", gf_mul_start_count);
        $display("PMUL_PROFILE_GF_MUL_STARTS_ADD=%0d", gf_mul_start_in_add);
        $display("PMUL_PROFILE_GF_MUL_STARTS_AFFINE=%0d", gf_mul_start_in_affine);
        $display("PMUL_PROFILE_GF_MUL_STARTS_INV_MUL=%0d", gf_mul_start_in_inv_mul);
        $display("PMUL_PROFILE_SQR_STARTS=%0d", sqr_start_count);
        $display("PMUL_PROFILE_SQR_STARTS_DBL=%0d", sqr_start_in_dbl);
        $display("PMUL_PROFILE_SQR_STARTS_AFFINE=%0d", sqr_start_in_affine);
        $display("PMUL_PROFILE_SQR_STARTS_INV_SQR=%0d", sqr_start_in_inv_sqr);
        $display("PMUL_PROFILE_HBIND_STARTS=%0d", hbind_start_count);
        $display("PMUL_PROFILE_HBIND_STARTS_ADD=%0d", hbind_start_in_add);
        $display("PMUL_PROFILE_HBIND_STARTS_DBL=%0d", hbind_start_in_dbl);
        $display("PMUL_PROFILE_HBIND_STARTS_AFFINE=%0d", hbind_start_in_affine);
        $display("PMUL_PROFILE_INV_STARTS=%0d", inv_start_count);
        $display("PMUL_PROFILE_ST_ECC_LOAD_CYCLES=%0d", st_ecc_load_cycles);
        $display("PMUL_PROFILE_ST_ECC_DIAG_CYCLES=%0d", st_ecc_diag_cycles);
        $display("PMUL_PROFILE_ST_ECC_LEAF_FOLD_CYCLES=%0d", st_ecc_leaf_fold_cycles);
        $display("PMUL_PROFILE_ST_ECC_WRITE_PAIR_CYCLES=%0d", st_ecc_write_pair_cycles);
        $display("PMUL_PROFILE_ST_ECC_WRITE_DRAIN_CYCLES=%0d", st_ecc_write_drain_cycles);
        $display("PMUL_PROFILE_ST_ECC_REDUCE_CYCLES=%0d", st_ecc_reduce_cycles);
        $display("PMUL_PROFILE_ST_HSPREAD_CYCLES=%0d", st_hspread_cycles);
        $display("PMUL_PROFILE_ST_ECC_UOP_CYCLES=%0d", st_ecc_uop_cycles);

        check_row("PMUL_PROFILE_RAND_X", 6'd4, expected_x_rand);
        check_row("PMUL_PROFILE_RAND_Y", 6'd5, expected_y_rand);

        if (error_count == 0)
            $display("[HDEC_ECC_PMUL_PROFILE_V27] PASS");
        else
            $fatal(1, "[HDEC_ECC_PMUL_PROFILE_V27] FAIL errors=%0d", error_count);
        $finish;
    end
endmodule
