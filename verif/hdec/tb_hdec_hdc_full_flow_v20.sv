module tb_hdec_hdc_full_flow_v20;
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

    function automatic logic [63:0] pattern_word(input int word_idx);
        case (word_idx)
            0:  pattern_word = 64'h0123_4567_89ab_cdef;
            1:  pattern_word = 64'h1111_2222_3333_4444;
            2:  pattern_word = 64'h5555_aaaa_5555_aaaa;
            3:  pattern_word = 64'hffff_0000_ffff_0000;
            4:  pattern_word = 64'h1357_9bdf_2468_ace0;
            5:  pattern_word = 64'h0f0f_f0f0_0f0f_f0f0;
            6:  pattern_word = 64'h3333_cccc_3333_cccc;
            7:  pattern_word = 64'haaaa_5555_aaaa_5555;
            8:  pattern_word = 64'h0000_ffff_0000_ffff;
            9:  pattern_word = 64'h1234_5678_9abc_def0;
            10: pattern_word = 64'hfedc_ba98_7654_3210;
            11: pattern_word = 64'hc3c3_3c3c_c3c3_3c3c;
            12: pattern_word = 64'hdead_beef_cafe_0123;
            13: pattern_word = 64'h789a_bcde_f012_3456;
            14: pattern_word = 64'h55aa_55aa_aa55_aa55;
            default: pattern_word = 64'h8000_0000_0000_0001;
        endcase
    endfunction

    function automatic logic [63:0] hbind_operand(
        input logic [3:0] dst_slot,
        input logic [3:0] src0_slot,
        input logic [3:0] src1_slot
    );
        hbind_operand = {52'd0, src1_slot, src0_slot, dst_slot};
    endfunction

    function automatic logic [63:0] hsim_operand(
        input logic [3:0] src0_slot,
        input logic [3:0] src1_slot
    );
        hsim_operand = {56'd0, src1_slot, src0_slot};
    endfunction

    function automatic logic [63:0] hmatch_operand(
        input logic [3:0] query_slot,
        input logic [3:0] class_start_slot,
        input logic [7:0] num_classes
    );
        hmatch_operand = {48'd0, num_classes, class_start_slot, query_slot};
    endfunction

    function automatic logic [63:0] hperm_operand(
        input logic [3:0] dst_slot,
        input logic [3:0] src_slot,
        input logic [3:0] word_off,
        input logic [5:0] bit_shift
    );
        hperm_operand = {46'd0, word_off, bit_shift[5:2], bit_shift[1:0],
                         src_slot, dst_slot};
    endfunction

    function automatic logic [63:0] hcntclip_operand(
        input logic [2:0] dst_slot,
        input logic       acc_sel,
        input logic [3:0] threshold
    );
        hcntclip_operand = {56'd0, threshold, acc_sel, dst_slot};
    endfunction

    function automatic logic [63:0] hmatch_result(
        input logic [7:0] idx,
        input logic [10:0] distance
    );
        hmatch_result = {45'd0, idx, distance};
    endfunction

    function automatic logic [63:0] align_word(
        input int word_idx,
        input logic [5:0] sh
    );
        logic [63:0] a;
        logic [63:0] b;
        begin
            a = pattern_word(word_idx);
            b = pattern_word(word_idx + 1);
            if (sh == 6'd0)
                align_word = a;
            else
                align_word = (a >> sh) | (b << (7'd64 - {1'b0, sh}));
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
            for (int cycles = 0; cycles < 10000 && !seen; cycles++) begin
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

    task automatic check_status(input string label, input logic [63:0] status);
        begin
            if (status[1:0] !== STATUS_OK) begin
                error_count++;
                $error("%s returned bad status 0x%016h", label, status);
            end
        end
    endtask

    task automatic check_equal64(input string label,
                                 input logic [63:0] got,
                                 input logic [63:0] expected);
        begin
            if (got !== expected) begin
                error_count++;
                $error("%s mismatch got=0x%016h expected=0x%016h",
                       label, got, expected);
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

    task automatic write_hv_word(input logic [3:0] slot,
                                 input int word_idx,
                                 input logic [63:0] data);
        logic [5:0] entry_idx;
        logic [1:0] bank;
        begin
            entry_idx = {slot, 2'b00} + 6'(word_idx / 4);
            bank = 2'(word_idx % 4);
            write_vrf64(bank, entry_idx, data);
        end
    endtask

    task automatic read_hv_word(input logic [3:0] slot,
                                input int word_idx,
                                output logic [63:0] data);
        logic [5:0] entry_idx;
        logic [1:0] bank;
        begin
            entry_idx = {slot, 2'b00} + 6'(word_idx / 4);
            bank = 2'(word_idx % 4);
            read_vrf64(bank, entry_idx, data);
        end
    endtask

    task automatic write_pattern_slot(input logic [3:0] slot, input logic invert);
        begin
            for (int word_idx = 0; word_idx < 16; word_idx++)
                write_hv_word(slot, word_idx, invert ? ~pattern_word(word_idx)
                                                     :  pattern_word(word_idx));
        end
    endtask

    task automatic write_constant_slot(input logic [3:0] slot, input logic [63:0] value);
        begin
            for (int word_idx = 0; word_idx < 16; word_idx++)
                write_hv_word(slot, word_idx, value);
        end
    endtask

    task automatic check_constant_slot(input string label,
                                       input logic [3:0] slot,
                                       input logic [63:0] value);
        logic [63:0] got;
        begin
            for (int word_idx = 0; word_idx < 16; word_idx++) begin
                read_hv_word(slot, word_idx, got);
                check_equal64($sformatf("%s word%0d", label, word_idx), got, value);
            end
        end
    endtask

    task automatic check_hperm_first_entry(input logic [5:0] sh);
        logic [63:0] got;
        begin
            for (int bank = 0; bank < 4; bank++) begin
                read_vrf64(2'(bank), 6'd16, got);
                check_equal64($sformatf("HPERM bank%0d", bank), got,
                              align_word(bank, sh));
            end
        end
    endtask

    initial begin
        logic [63:0] status;
        logic [63:0] result;

        error_count = 0;
        valid_i     = 1'b0;
        operator_i  = HDEC_VWR64;
        operand_a_i = '0;
        operand_b_i = '0;
        rst_ni      = 1'b0;

        repeat (8) @(posedge clk_i);
        rst_ni = 1'b1;
        repeat (40) @(posedge clk_i);

        write_pattern_slot(4'd0, 1'b0);
        write_pattern_slot(4'd1, 1'b1);
        write_constant_slot(4'd2, 64'hdead_beef_cafe_babe);

        issue(HDEC_HSIM, hsim_operand(4'd0, 4'd0), result);
        check_equal64("HSIM identical", result, 64'd0);

        issue(HDEC_HSIM, hsim_operand(4'd0, 4'd1), result);
        check_equal64("HSIM complement", result, 64'd1024);

        issue(HDEC_HCLR, 64'd2, status);
        check_status("HCLR slot2", status);
        check_constant_slot("HCLR slot2 zero", 4'd2, 64'd0);

        issue(HDEC_HBIND, hbind_operand(4'd3, 4'd0, 4'd1), status);
        check_status("HBIND slot3", status);
        check_constant_slot("HBIND pattern xor complement", 4'd3, 64'hffff_ffff_ffff_ffff);

        issue(HDEC_HPERM, hperm_operand(4'd4, 4'd0, 4'd0, 6'd1), status);
        check_status("HPERM shift1", status);
        check_hperm_first_entry(6'd1);

        issue(HDEC_HCNTCLR, 64'd0, status);
        check_status("HCNTCLR acc0", status);

        issue(HDEC_HCNTADD, 64'd3, status);
        check_status("HCNTADD slot3 all ones", status);

        issue(HDEC_HCNTCLIP, hcntclip_operand(3'd5, 1'b0, 4'd1), status);
        check_status("HCNTCLIP slot5", status);
        check_constant_slot("HCNTCLIP threshold1", 4'd5, 64'hffff_ffff_ffff_ffff);

        issue(HDEC_HSIM, hsim_operand(4'd5, 4'd3), result);
        check_equal64("HSIM clipped prototype", result, 64'd0);

        issue(HDEC_HMATCH, hmatch_operand(4'd5, 4'd2, 8'd2), result);
        check_equal64("HMATCH zero vs ones classes", result, hmatch_result(8'd1, 11'd0));

        if (error_count == 0)
            $display("[HDEC_HDC_FULL_FLOW_V20] PASS");
        else
            $fatal(1, "[HDEC_HDC_FULL_FLOW_V20] FAIL errors=%0d", error_count);
        $finish;
    end
endmodule
