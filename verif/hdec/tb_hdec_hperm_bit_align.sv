module tb_hdec_hperm_bit_align;
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

    logic [63:0] src_words [0:15];

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

    function automatic logic [63:0] align_word(
        input int          word_idx,
        input logic [5:0]  sh
    );
        logic [63:0] a;
        logic [63:0] b;
        begin
            a = src_words[word_idx];
            b = src_words[(word_idx + 1) & 15];
            if (sh == 6'd0)
                align_word = a;
            else
                align_word = (a >> sh) | (b << (7'd64 - {1'b0, sh}));
        end
    endfunction

    function automatic logic [63:0] spread_word(
        input int   word_idx,
        input logic hi
    );
        logic [31:0] half;
        begin
            half = hi ? src_words[word_idx][63:32] : src_words[word_idx][31:0];
            spread_word = '0;
            for (int bit_idx = 0; bit_idx < 32; bit_idx++)
                spread_word[bit_idx << 1] = half[bit_idx];
        end
    endfunction

    function automatic logic [63:0] hperm_operand(
        input logic [3:0] dst_slot,
        input logic [3:0] src_slot,
        input logic [3:0] word_off,
        input logic [5:0] bit_shift
    );
        begin
            hperm_operand = {46'd0, word_off, bit_shift[5:2], bit_shift[1:0],
                             src_slot, dst_slot};
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

    task automatic issue(input hdec_op_t op,
                         input logic [63:0] a,
                         output logic [63:0] result);
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
            for (int cycles = 0; cycles < 1000; cycles++) begin
                @(posedge clk_i);
                #1;
                if (valid_o) begin
                    result = result_o;
                    return;
                end
            end
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

    task automatic write_src_hv0;
        begin
            src_words[0]  = 64'h0123_4567_89ab_cdef;
            src_words[1]  = 64'hf0e1_d2c3_b4a5_9687;
            src_words[2]  = 64'h1357_9bdf_2468_ace0;
            src_words[3]  = 64'h0f1e_2d3c_4b5a_6978;
            src_words[4]  = 64'h89ab_cdef_0123_4567;
            src_words[5]  = 64'h7654_3210_fedc_ba98;
            src_words[6]  = 64'ha5a5_5a5a_3c3c_c3c3;
            src_words[7]  = 64'hdead_beef_cafe_babe;
            src_words[8]  = 64'h1021_3243_5465_7687;
            src_words[9]  = 64'h8877_6655_4433_2211;
            src_words[10] = 64'h3141_5926_5358_9793;
            src_words[11] = 64'h2718_2818_2845_9045;
            src_words[12] = 64'h55aa_33cc_0ff0_f00f;
            src_words[13] = 64'hc001_d00d_1234_fedc;
            src_words[14] = 64'h7e57_d15e_a11c_e5e5;
            src_words[15] = 64'hbadc_0ffe_e0dd_f00d;

            for (int entry = 0; entry < 4; entry++) begin
                for (int bank = 0; bank < 4; bank++)
                    write_vrf64(2'(bank), 6'(entry), src_words[entry * 4 + bank]);
            end
        end
    endtask

    task automatic check_first_entry(input logic [5:0] sh);
        logic [63:0] got;
        begin
            for (int bank = 0; bank < 4; bank++) begin
                read_vrf64(2'(bank), 6'd4, got);
                if (got !== align_word(bank, sh)) begin
                    $error("HPERM bit shift=%0d bank=%0d got=0x%016h expected=0x%016h",
                           sh, bank, got, align_word(bank, sh));
                    $fatal(1);
                end
            end
        end
    endtask

    task automatic check_spread_entry(input logic [5:0] idx,
                                      input logic       hi);
        logic [63:0] got;
        int word_idx;
        logic half_sel;
        begin
            for (int bank = 0; bank < 4; bank++) begin
                read_vrf64(2'(bank), idx, got);
                word_idx = hi ? (2 + (bank >> 1)) : (bank >> 1);
                half_sel = bank[0];
                if (got !== spread_word(word_idx, half_sel)) begin
                    $error("HSPREAD hi=%0d bank=%0d got=0x%016h expected=0x%016h",
                           hi, bank, got, spread_word(word_idx, half_sel));
                    $fatal(1);
                end
            end
        end
    endtask

    initial begin
        logic [63:0] status;

        valid_i = 1'b0;
        operator_i = HDEC_VWR64;
        operand_a_i = '0;
        operand_b_i = '0;
        rst_ni = 1'b0;
        repeat (8) @(posedge clk_i);
        rst_ni = 1'b1;
        repeat (300) @(posedge clk_i);

        write_src_hv0();
        issue(HDEC_HPERM, hperm_operand(4'd1, 4'd0, 4'd0, 6'd1), status);
        if (status[1:0] !== STATUS_OK)
            $fatal(1, "HPERM shift1 returned bad status 0x%016h", status);
        check_first_entry(6'd1);

        issue(HDEC_HPERM, hperm_operand(4'd1, 4'd0, 4'd0, 6'd5), status);
        if (status[1:0] !== STATUS_OK)
            $fatal(1, "HPERM shift5 returned bad status 0x%016h", status);
        check_first_entry(6'd5);

        issue(HDEC_HPERM, hspread_operand(6'd9, 6'd0), status);
        if (status[1:0] !== STATUS_OK)
            $fatal(1, "HSPREAD returned bad status 0x%016h", status);
        check_spread_entry(6'd9, 1'b0);
        check_spread_entry(6'd10, 1'b1);

        issue(HDEC_HPERM, hspread_operand(6'd63, 6'd0), status);
        if (status[1:0] !== STATUS_ERROR)
            $fatal(1, "HSPREAD dst=63 should be rejected, got 0x%016h", status);

        issue(HDEC_HPERM, hperm_operand(4'd0, 4'd0, 4'd0, 6'd1), status);
        if (status[1:0] !== STATUS_ERROR)
            $fatal(1, "HPERM dst==src should be rejected, got 0x%016h", status);

        $display("[HDEC_HPERM_BIT_ALIGN] PASS");
        $finish;
    end
endmodule
