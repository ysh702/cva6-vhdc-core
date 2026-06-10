module tb_hdec_ecc_inv_v17;
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

    function automatic logic [63:0] ecc_inv_operand(
        input logic [5:0] dst_idx,
        input logic [5:0] src_idx
    );
        ecc_inv_operand = (64'h1 << 31) | ({58'd0, dst_idx} << 12) | {58'd0, src_idx};
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
            for (int cycles = 0; cycles < 140000 && !seen; cycles++) begin
                @(posedge clk_i);
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
        logic [255:0] a_field;
        logic [255:0] expected_inv;

        error_count = 0;
        valid_i     = 1'b0;
        operator_i  = HDEC_VWR64;
        operand_a_i = '0;
        operand_b_i = '0;
        rst_ni      = 1'b0;

        repeat (8) @(posedge clk_i);
        rst_ni = 1'b1;
        repeat (20) @(posedge clk_i);

        a_field = 256'h00000000000000000000000000000123456789abcdef0fedcba9876543210;
        a_field[255:233] = '0;
        expected_inv = 256'h000000cd19db029a4f01607e5b121223031381bf41f0aebb3ecfa6a9ff47ea51;

        write_row(6'd24, a_field);
        issue(HDEC_ECC_STATUS, ecc_inv_operand(6'd26, 6'd24), status);
        if (status[1:0] !== STATUS_OK) begin
            error_count++;
            $error("GF_INV returned bad status 0x%016h", status);
        end
        $display("GF_INV_CYCLES=%0d", status[31:16]);
        check_row("GF_INV", 6'd26, expected_inv);

        if (error_count == 0)
            $display("[HDEC_ECC_INV_V17] PASS");
        else
            $fatal(1, "[HDEC_ECC_INV_V17] FAIL errors=%0d", error_count);
        $finish;
    end
endmodule
