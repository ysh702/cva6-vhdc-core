module tb_vv30_pmul_random_k #(
    parameter bit DUT_RESIDUE_SEEDING = 1'b1,
    parameter bit DUT_AFFINE_FACTORING = 1'b1,
    parameter bit DUT_INV_REDIRECT = 1'b1,
    parameter bit DUT_DBL_FROBENIUS = 1'b1,
    parameter bit DUT_ADD_Z_FORWARD = 1'b1
);
    import hdec_pkg::*;

    localparam int MAX_CASES = 64;
    localparam logic [255:0] K233_N =
        256'h0000008000000000000000000000000000069d5bb915bcd46efb1ad5f173abdf;

    logic clk_i;
    logic rst_ni;
    logic valid_i;
    logic ready_o;
    hdec_op_t operator_i;
    logic [63:0] operand_a_i;
    logic [63:0] operand_b_i;
    logic valid_o;
    logic [63:0] result_o;

    logic [255:0] point_x_inputs [0:MAX_CASES-1];
    logic [255:0] point_y_inputs [0:MAX_CASES-1];
    logic [255:0] scalar_inputs  [0:MAX_CASES-1];
    logic [255:0] expected_x     [0:MAX_CASES-1];
    logic [255:0] expected_y     [0:MAX_CASES-1];
    logic [255:0] master_seed_mem [0:0];
    logic [31:0]  scalar_count_mem [0:0];

    int unsigned error_count;

`ifdef VV35_DUAL_DUT
    vv35_dual_accel_core_top dut (
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
`else
    hdec_top #(
        .ECC_PMUL_RESIDUE_SEEDING(DUT_RESIDUE_SEEDING),
        .ECC_PMUL_AFFINE_FACTORING(DUT_AFFINE_FACTORING),
        .ECC_INV_SQUARE_REDIRECT(DUT_INV_REDIRECT),
        .ECC_PMUL_DBL_FROBENIUS(DUT_DBL_FROBENIUS),
        .ECC_PMUL_ADD_Z_FORWARD(DUT_ADD_Z_FORWARD)
    ) dut (
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
`endif

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

    function automatic int unsigned hamming_weight256(
        input logic [255:0] value
    );
        int unsigned count;
        begin
            count = 0;
            for (int bit_index = 0; bit_index < 256; bit_index++)
                count += value[bit_index];
            return count;
        end
    endfunction

    task automatic issue_count(
        input hdec_op_t op,
        input logic [63:0] operand,
        output logic [63:0] result,
        output int unsigned cycles
    );
        bit seen;
        begin
            while (!ready_o)
                @(posedge clk_i);
            @(posedge clk_i);
            valid_i     <= 1'b1;
            operator_i  <= op;
            operand_a_i <= operand;
            operand_b_i <= '0;
            @(posedge clk_i);
            valid_i     <= 1'b0;
            operator_i  <= HDEC_VWR64;
            operand_a_i <= '0;
            operand_b_i <= '0;

            result = 'x;
            cycles = 0;
            seen = 1'b0;
            for (int wait_cycles = 0;
                 wait_cycles < 1000000 && !seen;
                 wait_cycles++) begin
                @(posedge clk_i);
                cycles++;
                #1;
                if (valid_o) begin
                    result = result_o;
                    seen = 1'b1;
                end
            end
            if (!seen)
                $fatal(1, "[VV30:pmul_random_k] timeout op=%0d", op);
            if ($isunknown(result)) begin
                error_count++;
                $error("[VV30:pmul_random_k] unknown response op=%0d", op);
            end
        end
    endtask

    task automatic issue(
        input hdec_op_t op,
        input logic [63:0] operand,
        output logic [63:0] result
    );
        int unsigned ignored_cycles;
        begin
            issue_count(op, operand, result, ignored_cycles);
        end
    endtask

    task automatic write_vrf64(
        input logic [1:0] bank,
        input logic [5:0] index,
        input logic [63:0] data
    );
        logic [63:0] ignored;
        begin
            issue(HDEC_VADDR, {56'd0, bank, index}, ignored);
            issue(HDEC_VWR64, data, ignored);
        end
    endtask

    task automatic read_vrf64(
        input logic [1:0] bank,
        input logic [5:0] index,
        output logic [63:0] data
    );
        logic [63:0] ignored;
        begin
            issue(HDEC_VADDR, {56'd0, bank, index}, ignored);
            issue(HDEC_VRD64, '0, data);
        end
    endtask

    task automatic write_row(
        input logic [5:0] index,
        input logic [255:0] value
    );
        begin
            write_vrf64(2'd0, index, value[63:0]);
            write_vrf64(2'd1, index, value[127:64]);
            write_vrf64(2'd2, index, value[191:128]);
            write_vrf64(2'd3, index, value[255:192]);
        end
    endtask

    task automatic read_row(
        input logic [5:0] index,
        output logic [255:0] value
    );
        begin
            read_vrf64(2'd0, index, value[63:0]);
            read_vrf64(2'd1, index, value[127:64]);
            read_vrf64(2'd2, index, value[191:128]);
            read_vrf64(2'd3, index, value[255:192]);
        end
    endtask

    initial begin
        logic [255:0] master_seed;
        int scalar_count;
        int unsigned reference_cycles;
        logic [63:0] status;
        logic [255:0] got_x;
        logic [255:0] got_y;

        error_count = 0;
        valid_i = 1'b0;
        operator_i = HDEC_VWR64;
        operand_a_i = '0;
        operand_b_i = '0;
        rst_ni = 1'b0;
        reference_cycles = 0;

        $readmemh("master_seed.mem", master_seed_mem);
        $readmemh("scalar_count.mem", scalar_count_mem);
        master_seed = master_seed_mem[0];
        scalar_count = scalar_count_mem[0];
        if ((scalar_count < 1) || (scalar_count > MAX_CASES))
            $fatal(1, "[VV30:pmul_random_k] invalid scalar_count=%0d",
                   scalar_count);

        $readmemh("pmul_point_x.mem", point_x_inputs, 0, scalar_count - 1);
        $readmemh("pmul_point_y.mem", point_y_inputs, 0, scalar_count - 1);
        $readmemh("pmul_scalars.mem", scalar_inputs, 0, scalar_count - 1);
        $readmemh("pmul_expected_x.mem", expected_x, 0, scalar_count - 1);
        $readmemh("pmul_expected_y.mem", expected_y, 0, scalar_count - 1);

        repeat (8) @(posedge clk_i);
        rst_ni = 1'b1;
        repeat (20) @(posedge clk_i);

        for (int test_index = 0; test_index < scalar_count; test_index++) begin
            int unsigned pmul_cycles;
            if ((scalar_inputs[test_index] == 0)
                || (scalar_inputs[test_index] >= K233_N)
                || (scalar_inputs[test_index][255:233] != 0)) begin
                error_count++;
                $error("[VV30:pmul_random_k] malformed random K case=%0d seed=%064h K=%064h",
                       test_index, master_seed, scalar_inputs[test_index]);
            end
            if ((test_index > 0)
                && (scalar_inputs[test_index] == scalar_inputs[test_index - 1])) begin
                error_count++;
                $error("[VV30:pmul_random_k] repeated adjacent K case=%0d seed=%064h K=%064h",
                       test_index, master_seed, scalar_inputs[test_index]);
            end
            if ((point_x_inputs[test_index][255:233] != 0)
                || (point_y_inputs[test_index][255:233] != 0)) begin
                error_count++;
                $error("[VV30:pmul_random_k] point padding is nonzero case=%0d seed=%064h",
                       test_index, master_seed);
            end
            write_row(6'd0, point_x_inputs[test_index]);
            write_row(6'd1, point_y_inputs[test_index]);
            write_row(6'd2, scalar_inputs[test_index]);
            write_row(6'd4, '0);
            write_row(6'd5, '0);

            issue_count(
                HDEC_ECC_STATUS,
                ecc_pmul_operand(6'd4, 6'd0, 6'd2),
                status,
                pmul_cycles
            );
            if (status[1:0] !== STATUS_OK) begin
                error_count++;
                $error("[VV30:pmul_random_k] bad status case=%0d seed=%064h K=%064h status=%016h",
                       test_index, master_seed, scalar_inputs[test_index], status);
            end

            read_row(6'd4, got_x);
            read_row(6'd5, got_y);
            if ((got_x !== expected_x[test_index])
                || (got_y !== expected_y[test_index])) begin
                error_count++;
                $error("[VV30:pmul_random_k] mismatch case=%0d seed=%064h K=%064h got=(%064h,%064h) expected=(%064h,%064h)",
                       test_index, master_seed, scalar_inputs[test_index],
                       got_x, got_y,
                       expected_x[test_index], expected_y[test_index]);
            end
            if ((got_x[255:233] != 0) || (got_y[255:233] != 0)) begin
                error_count++;
                $error("[VV30:pmul_random_k] result padding is nonzero case=%0d seed=%064h K=%064h",
                       test_index, master_seed, scalar_inputs[test_index]);
            end

            if (test_index == 0)
                reference_cycles = pmul_cycles;
            else if (pmul_cycles != reference_cycles) begin
                error_count++;
                $error("[VV30:pmul_random_k] scalar-dependent cycle count case=%0d seed=%064h K=%064h cycles=%0d expected=%0d",
                       test_index, master_seed, scalar_inputs[test_index],
                       pmul_cycles, reference_cycles);
            end
            $display("[VV30:PMUL_CYCLE] case=%0d K=%064h weight=%0d cycles=%0d",
                     test_index, scalar_inputs[test_index],
                     hamming_weight256(scalar_inputs[test_index]), pmul_cycles);
        end

        $display("[VV30:COVERAGE] test=pmul_random_k observed=%0d expected=%0d",
                 scalar_count, scalar_count);
        if (error_count == 0)
            $display("[VV30:pmul_random_k] PASS");
        else
            $fatal(1, "[VV30:pmul_random_k] FAIL errors=%0d seed=%064h",
                   error_count, master_seed);
        $finish;
    end
endmodule

module tb_vv30_pmul_graph_baseline;
    tb_vv30_pmul_random_k #(
        .DUT_DBL_FROBENIUS(1'b0),
        .DUT_ADD_Z_FORWARD(1'b0)
    ) test();
endmodule

module tb_vv30_pmul_graph_dbl_only;
    tb_vv30_pmul_random_k #(
        .DUT_DBL_FROBENIUS(1'b1),
        .DUT_ADD_Z_FORWARD(1'b0)
    ) test();
endmodule

module tb_vv30_pmul_graph_add_only;
    tb_vv30_pmul_random_k #(
        .DUT_DBL_FROBENIUS(1'b0),
        .DUT_ADD_Z_FORWARD(1'b1)
    ) test();
endmodule

module tb_vv30_pmul_method_base;
    tb_vv30_pmul_random_k #(
        .DUT_RESIDUE_SEEDING(1'b0),
        .DUT_AFFINE_FACTORING(1'b0),
        .DUT_INV_REDIRECT(1'b0),
        .DUT_DBL_FROBENIUS(1'b0),
        .DUT_ADD_Z_FORWARD(1'b0)
    ) test();
endmodule

module tb_vv30_pmul_method_seed;
    tb_vv30_pmul_random_k #(
        .DUT_RESIDUE_SEEDING(1'b1),
        .DUT_AFFINE_FACTORING(1'b0),
        .DUT_INV_REDIRECT(1'b0),
        .DUT_DBL_FROBENIUS(1'b0),
        .DUT_ADD_Z_FORWARD(1'b0)
    ) test();
endmodule

module tb_vv30_pmul_method_factor;
    tb_vv30_pmul_random_k #(
        .DUT_RESIDUE_SEEDING(1'b1),
        .DUT_AFFINE_FACTORING(1'b1),
        .DUT_INV_REDIRECT(1'b0),
        .DUT_DBL_FROBENIUS(1'b0),
        .DUT_ADD_Z_FORWARD(1'b0)
    ) test();
endmodule

module tb_vv30_pmul_method_inv;
    tb_vv30_pmul_random_k #(
        .DUT_RESIDUE_SEEDING(1'b1),
        .DUT_AFFINE_FACTORING(1'b1),
        .DUT_INV_REDIRECT(1'b1),
        .DUT_DBL_FROBENIUS(1'b0),
        .DUT_ADD_Z_FORWARD(1'b0)
    ) test();
endmodule
