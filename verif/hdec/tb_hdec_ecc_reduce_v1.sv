module tb_hdec_ecc_reduce_v1;
    import hdec_pkg::*;

    logic clk_i;
    logic rst_ni;
    logic valid_i;
    logic ready_o;
    hdec_op_t operator_i;
    logic [63:0] operand_a_i;
    logic [63:0] operand_b_i;
    logic valid_o;
    logic [63:0] result_o;

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

    function automatic logic [63:0] ecc_reduce_operand(
        input logic [5:0] dst_idx,
        input logic [5:0] src_idx
    );
        begin
            ecc_reduce_operand = {46'd0, dst_idx, 6'd0, src_idx};
        end
    endfunction

    function automatic logic [63:0] ecc_mul_operand(
        input logic [5:0] dst_idx,
        input logic [5:0] src_a_idx,
        input logic [5:0] src_b_idx
    );
        begin
            ecc_mul_operand = {46'd0, dst_idx, src_a_idx, src_b_idx};
        end
    endfunction

    function automatic logic [63:0] ecc_gfmul_operand(
        input logic [5:0] dst_idx,
        input logic [5:0] src_a_idx,
        input logic [5:0] src_b_idx
    );
        begin
            ecc_gfmul_operand = ecc_mul_operand(dst_idx, src_a_idx, src_b_idx) | (64'h1 << 31);
        end
    endfunction

    function automatic logic [63:0] ecc_gfmac_operand(
        input logic [5:0] acc_dst_idx,
        input logic [5:0] tmp_idx,
        input logic [5:0] src_a_idx,
        input logic [5:0] src_b_idx
    );
        begin
            ecc_gfmac_operand = ecc_mul_operand(tmp_idx, src_a_idx, src_b_idx)
                              | ({58'd0, acc_dst_idx} << 18)
                              | (64'h1 << 32);
        end
    endfunction

    function automatic logic [63:0] hspread_operand(
        input logic [5:0] dst_idx,
        input logic [5:0] src_idx
    );
        begin
            hspread_operand = {45'd0, 1'b1, 6'd0, src_idx, dst_idx};
        end
    endfunction

    function automatic logic [63:0] hspread_reduce_operand(
        input logic [5:0] dst_idx,
        input logic [5:0] src_idx
    );
        begin
            hspread_reduce_operand = {44'd0, 1'b1, 1'b1, 6'd0, src_idx, dst_idx};
        end
    endfunction

    function automatic logic [63:0] hspread_mac_operand(
        input logic [5:0] acc_dst_idx,
        input logic [5:0] tmp_idx,
        input logic [5:0] src_idx
    );
        begin
            hspread_mac_operand = hspread_operand(tmp_idx, src_idx)
                                | ({58'd0, acc_dst_idx} << 12)
                                | (64'h1 << 20);
        end
    endfunction

    function automatic logic [255:0] slow_reduce233(input logic [511:0] product);
        logic [511:0] work;
        begin
            work = product;
            for (int bit_idx = 511; bit_idx >= 233; bit_idx--) begin
                if (work[bit_idx]) begin
                    work[bit_idx] = 1'b0;
                    work[bit_idx - 233] = work[bit_idx - 233] ^ 1'b1;
                    work[bit_idx - 159] = work[bit_idx - 159] ^ 1'b1;
                end
            end
            slow_reduce233 = '0;
            slow_reduce233[232:0] = work[232:0];
        end
    endfunction

    function automatic logic [511:0] slow_mul_raw233(
        input logic [255:0] a,
        input logic [255:0] b
    );
        logic [511:0] product;
        begin
            product = '0;
            for (int ai = 0; ai < 233; ai++) begin
                if (a[ai]) begin
                    for (int bi = 0; bi < 233; bi++) begin
                        if (b[bi])
                            product[ai + bi] = product[ai + bi] ^ 1'b1;
                    end
                end
            end
            slow_mul_raw233 = product;
        end
    endfunction

    function automatic logic [511:0] slow_square_raw233(input logic [255:0] a);
        logic [511:0] product;
        begin
            product = '0;
            for (int bit_idx = 0; bit_idx < 233; bit_idx++) begin
                if (a[bit_idx])
                    product[bit_idx << 1] = 1'b1;
            end
            slow_square_raw233 = product;
        end
    endfunction

    task automatic issue(input hdec_op_t op,
                         input logic [63:0] a,
                         output logic [63:0] result);
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
            seen = 1'b0;
            for (int cycles = 0; cycles < 2000 && !seen; cycles++) begin
                @(posedge clk_i);
                #1;
                if (valid_o) begin
                    result = result_o;
                    seen = 1'b1;
                end
            end
            if (!seen)
                $fatal(1, "Timeout waiting for op %0d", op);
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

    task automatic write_product(input logic [5:0] base_idx,
                                 input logic [511:0] product);
        begin
            write_row(base_idx, product[255:0]);
            write_row(base_idx + 6'd1, product[511:256]);
        end
    endtask

    task automatic run_reduce(input logic [5:0] dst_idx,
                              input logic [5:0] src_idx,
                              output logic [63:0] status);
        begin
            issue(HDEC_ECC_REDUCE, ecc_reduce_operand(dst_idx, src_idx), status);
        end
    endtask

    task automatic check_row(input string label,
                             input logic [5:0] idx,
                             input logic [255:0] expected);
        logic [255:0] got;
        begin
            read_row(idx, got);
            if (got !== expected) begin
                $error("%s got=0x%064h expected=0x%064h", label, got, expected);
                $fatal(1);
            end
        end
    endtask

    initial begin
        logic [63:0] status;
        logic [511:0] product;
        logic [255:0] a_field;
        logic [255:0] b_field;
        logic [255:0] acc_field;
        logic [255:0] expected;

        valid_i = 1'b0;
        operator_i = HDEC_VWR64;
        operand_a_i = '0;
        operand_b_i = '0;
        rst_ni = 1'b0;
        repeat (8) @(posedge clk_i);
        rst_ni = 1'b1;
        repeat (120) @(posedge clk_i);

        product = '0;
        product[233] = 1'b1;
        product[511] = 1'b1;
        product[300] = 1'b1;
        product[17] = 1'b1;
        write_product(6'd20, product);
        run_reduce(6'd22, 6'd20, status);
        if (status[1:0] !== STATUS_OK)
            $fatal(1, "direct REDUCE returned bad status 0x%016h", status);
        check_row("direct REDUCE", 6'd22, slow_reduce233(product));

        a_field = 256'h00000000000000000000000000000123456789abcdef0fedcba9876543210;
        b_field = 256'h0000000000000000000000000000000fedcba98765432100123456789abcdef;
        a_field[255:233] = '0;
        b_field[255:233] = '0;
        write_row(6'd24, a_field);
        write_row(6'd25, b_field);
        issue(HDEC_ECC_MUL, ecc_mul_operand(6'd26, 6'd24, 6'd25), status);
        if (status[1:0] !== STATUS_OK)
            $fatal(1, "ECC_MUL returned bad status 0x%016h", status);
        run_reduce(6'd28, 6'd26, status);
        if (status[1:0] !== STATUS_OK)
            $fatal(1, "MUL->REDUCE returned bad status 0x%016h", status);
        expected = slow_reduce233(slow_mul_raw233(a_field, b_field));
        check_row("MUL->REDUCE", 6'd28, expected);

        issue(HDEC_HPERM, hspread_operand(6'd34, 6'd24), status);
        if (status[1:0] !== STATUS_OK)
            $fatal(1, "HSPREAD returned bad status 0x%016h", status);
        run_reduce(6'd36, 6'd34, status);
        if (status[1:0] !== STATUS_OK)
            $fatal(1, "SQR->REDUCE returned bad status 0x%016h", status);
        expected = slow_reduce233(slow_square_raw233(a_field));
        check_row("SQR->REDUCE", 6'd36, expected);

        issue(HDEC_ECC_MUL, ecc_gfmul_operand(6'd30, 6'd24, 6'd25), status);
        if (status[1:0] !== STATUS_OK)
            $fatal(1, "auto GF_MUL returned bad status 0x%016h", status);
        expected = slow_reduce233(slow_mul_raw233(a_field, b_field));
        check_row("auto GF_MUL", 6'd30, expected);

        issue(HDEC_HPERM, hspread_reduce_operand(6'd38, 6'd24), status);
        if (status[1:0] !== STATUS_OK)
            $fatal(1, "auto GF_SQR returned bad status 0x%016h", status);
        expected = slow_reduce233(slow_square_raw233(a_field));
        check_row("auto GF_SQR", 6'd38, expected);

        acc_field = 256'h0000000000000000000000000000000123456789abcdef0011223344556677;
        acc_field[255:233] = '0;
        write_row(6'd42, acc_field);
        issue(HDEC_ECC_MUL, ecc_gfmac_operand(6'd42, 6'd40, 6'd24, 6'd25), status);
        if (status[1:0] !== STATUS_OK)
            $fatal(1, "auto GF_MAC returned bad status 0x%016h", status);
        expected = acc_field ^ slow_reduce233(slow_mul_raw233(a_field, b_field));
        check_row("auto GF_MAC", 6'd42, expected);

        acc_field = 256'h0000000000000000000000000000000abcdef0123456789ffeeddccbbaa9988;
        acc_field[255:233] = '0;
        write_row(6'd46, acc_field);
        issue(HDEC_HPERM, hspread_mac_operand(6'd46, 6'd44, 6'd24), status);
        if (status[1:0] !== STATUS_OK)
            $fatal(1, "auto GF_SQRMAC returned bad status 0x%016h", status);
        expected = acc_field ^ slow_reduce233(slow_square_raw233(a_field));
        check_row("auto GF_SQRMAC", 6'd46, expected);

        run_reduce(6'd29, 6'd63, status);
        if (status[1:0] !== STATUS_ERROR)
            $fatal(1, "REDUCE src=63 should fail, got 0x%016h", status);

        $display("[HDEC_ECC_REDUCE_V1] PASS");
        $finish;
    end
endmodule
