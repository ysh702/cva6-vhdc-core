module tb_hdec_ecc_pmul_wall_v27;
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
    int unsigned error_count;

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

    task automatic issue(input hdec_op_t op,
                         input logic [63:0] a,
                         output logic [63:0] result);
        int unsigned cycles;
        begin
            issue_count(op, a, result, cycles);
        end
    endtask

    task automatic issue_count(input hdec_op_t op,
                               input logic [63:0] a,
                               output logic [63:0] result,
                               output int unsigned cycles);
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
        logic [255:0] expected_x_3g;
        logic [255:0] expected_y_3g;
        int unsigned pmul_wall_cycles;

        error_count = 0;
        valid_i     = 1'b0;
        operator_i  = HDEC_VWR64;
        operand_a_i = '0;
        operand_b_i = '0;
        rst_ni      = 1'b0;

        repeat (8) @(posedge clk_i);
        rst_ni = 1'b1;
        repeat (20) @(posedge clk_i);

        gx = 256'h0000017232ba853a7e731af129f22ff4149563a419c26bf50a4c9d6eefad6126;
        gy = 256'h000001db537dece819b7f70f555a67c427a8cd9bf18aeb9b56e0c11056fae6a3;
        scalar = 256'd3;
        expected_x_3g = 256'h0000004656e0aabbe341407715ca4a7fac287b41baa1f789c29bfa27e53a7a46;
        expected_y_3g = 256'h000000f79a7245fba513df787a64c618e97ebcc078638ebaaa562e9862bc00ce;

        write_row(6'd0, gx);
        write_row(6'd1, gy);
        write_row(6'd2, scalar);

        issue_count(HDEC_ECC_STATUS, ecc_pmul_operand(6'd4, 6'd0, 6'd2),
                    status, pmul_wall_cycles);
        if (status[1:0] !== STATUS_OK) begin
            error_count++;
            $error("PMUL returned bad status 0x%016h", status);
        end
        $display("PMUL_BLOCKING_WALL_CYCLES=%0d", pmul_wall_cycles);
        $display("PMUL_BLOCKING_STATUS_LOW16=%0d", status[31:16]);

        check_row("PMUL_WALL_3G_X", 6'd4, expected_x_3g);
        check_row("PMUL_WALL_3G_Y", 6'd5, expected_y_3g);

        if (error_count == 0)
            $display("[HDEC_ECC_PMUL_WALL_V27] PASS");
        else
            $fatal(1, "[HDEC_ECC_PMUL_WALL_V27] FAIL errors=%0d", error_count);
        $finish;
    end
endmodule
