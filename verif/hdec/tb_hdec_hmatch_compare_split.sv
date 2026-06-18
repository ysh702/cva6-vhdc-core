module tb_hdec_hmatch_compare_split;
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

    function automatic logic [63:0] hmatch_result(input logic [7:0] idx,
                                                   input logic [10:0] distance);
        hmatch_result = {45'd0, idx, distance};
    endfunction

    task automatic issue(input hdec_op_t op,
                         input logic [63:0] a,
                         output logic [63:0] result,
                         output int cycles);
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
            forever begin
                @(posedge clk_i);
                #1;
                cycles++;
                if (valid_o) begin
                    result = result_o;
                    break;
                end
                if (cycles > 2000)
                    $fatal(1, "Timeout waiting for op %0d", op);
            end
        end
    endtask

    task automatic write_vrf64(input logic [1:0] bank,
                               input logic [5:0] idx,
                               input logic [63:0] data);
        logic [63:0] ignored;
        int cycles;
        begin
            issue(HDEC_VADDR, {56'd0, bank, idx}, ignored, cycles);
            issue(HDEC_VWR64, data, ignored, cycles);
        end
    endtask

    task automatic write_entry(input logic [5:0] idx,
                               input logic [63:0] b0,
                               input logic [63:0] b1,
                               input logic [63:0] b2,
                               input logic [63:0] b3);
        begin
            write_vrf64(2'd0, idx, b0);
            write_vrf64(2'd1, idx, b1);
            write_vrf64(2'd2, idx, b2);
            write_vrf64(2'd3, idx, b3);
        end
    endtask

    task automatic fill_slot(input logic [3:0] slot, input logic [63:0] value);
        logic [5:0] base;
        begin
            base = {slot, 2'b00};
            write_entry(base + 6'd0, value, value, value, value);
            write_entry(base + 6'd1, value, value, value, value);
            write_entry(base + 6'd2, value, value, value, value);
            write_entry(base + 6'd3, value, value, value, value);
        end
    endtask

    task automatic write_distinct_query(input logic [3:0] slot);
        logic [5:0] base;
        begin
            base = {slot, 2'b00};
            write_entry(base + 6'd0,
                        64'h0123_4567_89ab_cdef, 64'h1111_2222_3333_4444,
                        64'h5555_aaaa_5555_aaaa, 64'hffff_0000_ffff_0000);
            write_entry(base + 6'd1,
                        64'h1357_9bdf_2468_ace0, 64'h0f0f_f0f0_0f0f_f0f0,
                        64'h3333_cccc_3333_cccc, 64'haaaa_5555_aaaa_5555);
            write_entry(base + 6'd2,
                        64'h0000_ffff_0000_ffff, 64'h1234_5678_9abc_def0,
                        64'hfedc_ba98_7654_3210, 64'hc3c3_3c3c_c3c3_3c3c);
            write_entry(base + 6'd3,
                        64'hdead_beef_cafe_0123, 64'h789a_bcde_f012_3456,
                        64'h55aa_55aa_aa55_aa55, 64'h8000_0000_0000_0001);
        end
    endtask

    task automatic copy_distinct_query_to_slot(input logic [3:0] slot);
        begin
            write_distinct_query(slot);
        end
    endtask

    localparam logic [16:0] HMATCH_OVERLAP_MODE = 17'h1_0000;

    task automatic run_hmatch(input logic [16:0] param,
                               output logic [63:0] result,
                               output int cycles);
        begin
            issue(HDEC_HMATCH, {47'd0, param}, result, cycles);
            $display("HMATCH param=0x%05h cycles=%0d result=0x%016h",
                     param, cycles, result);
        end
    endtask

    task automatic check_result(input string name,
                                input logic [63:0] got,
                                input logic [63:0] exp);
        begin
            if (got !== exp)
                $fatal(1, "FAIL %s got=0x%016h expected=0x%016h",
                       name, got, exp);
            $display("PASS %-34s result=0x%016h", name, got);
        end
    endtask

    initial begin
        logic [63:0] result;
        int cycles;

        valid_i = 1'b0;
        operator_i = HDEC_VWR64;
        operand_a_i = '0;
        operand_b_i = '0;
        rst_ni = 1'b0;
        repeat (8) @(posedge clk_i);
        rst_ni = 1'b1;

        repeat (300) @(posedge clk_i);

        fill_slot(4'd0, 64'h0000_0000_0000_0000);
        fill_slot(4'd1, 64'hffff_ffff_ffff_ffff);
        run_hmatch(16'h0110, result, cycles);
        check_result("single class max distance", result, hmatch_result(8'd0, 11'd1024));

        write_distinct_query(4'd0);
        fill_slot(4'd1, 64'hffff_ffff_ffff_ffff);
        copy_distinct_query_to_slot(4'd2);
        run_hmatch(16'h0210, result, cycles);
        check_result("second class exact match", result, hmatch_result(8'd1, 11'd0));

        fill_slot(4'd0, 64'h0000_0000_0000_0000);
        fill_slot(4'd4, 64'h0000_0000_0000_0000);
        fill_slot(4'd5, 64'h0000_0000_0000_0000);
        run_hmatch(16'h0240, result, cycles);
        check_result("tie keeps first class", result, hmatch_result(8'd0, 11'd0));

        run_hmatch(16'h0010, result, cycles);
        check_result("illegal num_classes zero", result, 64'd2);

        fill_slot(4'd0, 64'hffff_ffff_ffff_ffff);
        fill_slot(4'd1, 64'h0000_0000_0000_0000);
        fill_slot(4'd2, 64'hf0f0_f0f0_f0f0_f0f0);
        run_hmatch(HMATCH_OVERLAP_MODE | 17'h0_0210, result, cycles);
        check_result("overlap picks larger score", result, hmatch_result(8'd1, 11'd512));

        fill_slot(4'd0, 64'hf0f0_f0f0_f0f0_f0f0);
        fill_slot(4'd4, 64'hf0f0_f0f0_f0f0_f0f0);
        fill_slot(4'd5, 64'hf0f0_f0f0_f0f0_f0f0);
        run_hmatch(HMATCH_OVERLAP_MODE | 17'h0_0240, result, cycles);
        check_result("overlap tie keeps first", result, hmatch_result(8'd0, 11'd512));

        $display("All HDEC HMATCH compare-split xsim tests passed.");
        $finish;
    end
endmodule
