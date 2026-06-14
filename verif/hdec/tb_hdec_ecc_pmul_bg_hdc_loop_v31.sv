module tb_hdec_ecc_pmul_bg_hdc_loop_v31;
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
    int unsigned cycle_count;

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

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;
    end

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

    function automatic logic [63:0] ecc_pmul_operand(
        input logic bg,
        input logic [5:0] dst_idx,
        input logic [5:0] point_x_idx,
        input logic [5:0] scalar_idx
    );
        ecc_pmul_operand = (64'h1 << 30)
                         | ({63'd0, bg} << 29)
                         | ({58'd0, dst_idx} << 12)
                         | ({58'd0, point_x_idx} << 6)
                         | {58'd0, scalar_idx};
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

    function automatic logic [1:0] hdc_word_bank(input int word_idx);
        case (word_idx & 3)
            0: hdc_word_bank = 2'd0;
            1: hdc_word_bank = 2'd1;
            2: hdc_word_bank = 2'd2;
            default: hdc_word_bank = 2'd3;
        endcase
    endfunction

    function automatic logic [5:0] hdc_word_entry_off(input int word_idx);
        case ((word_idx >> 2) & 3)
            0: hdc_word_entry_off = 6'd0;
            1: hdc_word_entry_off = 6'd1;
            2: hdc_word_entry_off = 6'd2;
            default: hdc_word_entry_off = 6'd3;
        endcase
    endfunction

    task automatic issue(input hdec_op_t op,
                         input logic [63:0] a,
                         output logic [63:0] result);
        bit seen;
        begin
            @(negedge clk_i);
            valid_i     = 1'b1;
            operator_i  = op;
            operand_a_i = a;
            operand_b_i = '0;
            do @(posedge clk_i); while (!ready_o);
            @(negedge clk_i);
            valid_i     = 1'b0;
            operator_i  = HDEC_VWR64;
            operand_a_i = '0;
            operand_b_i = '0;

            result = 'x;
            seen = 1'b0;
            for (int cycles = 0; cycles < 1000000 && !seen; cycles++) begin
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

    task automatic write_hv_word(input logic [3:0] slot,
                                 input int word_idx,
                                 input logic [63:0] data);
        logic [5:0] entry_idx;
        logic [1:0] bank;
        begin
            entry_idx = {slot, 2'b00} + hdc_word_entry_off(word_idx);
            bank = hdc_word_bank(word_idx);
            write_vrf64(bank, entry_idx, data);
        end
    endtask

    task automatic read_hv_word(input logic [3:0] slot,
                                input int word_idx,
                                output logic [63:0] data);
        logic [5:0] entry_idx;
        logic [1:0] bank;
        begin
            entry_idx = {slot, 2'b00} + hdc_word_entry_off(word_idx);
            bank = hdc_word_bank(word_idx);
            read_vrf64(bank, entry_idx, data);
        end
    endtask

    task automatic write_pattern_slot(input logic [3:0] slot, input logic invert);
        logic [63:0] word_data;
        begin
            for (int word_idx = 0; word_idx < 16; word_idx++) begin
                word_data = pattern_word(word_idx);
                if (invert)
                    word_data = ~word_data;
                write_hv_word(slot, word_idx, word_data);
            end
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

    task automatic check_constant_slot(input string label,
                                       input logic [3:0] slot,
                                       input logic [63:0] value);
        logic [63:0] got;
        begin
            for (int word_idx = 0; word_idx < 16; word_idx++) begin
                read_hv_word(slot, word_idx, got);
                if (got !== value) begin
                    error_count++;
                    $error("%s word%0d mismatch got=0x%016h expected=0x%016h",
                           label, word_idx, got, value);
                end
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

    task automatic run_hdc_foreground_flow(output logic [63:0] last_result);
        logic [63:0] status;
        begin
            write_pattern_slot(4'd2, 1'b0);
            write_pattern_slot(4'd3, 1'b1);

            issue(HDEC_HSIM, hsim_operand(4'd2, 4'd3), last_result);
            check_equal64("V31 HSIM complement", last_result, 64'd1024);

            issue(HDEC_HBIND, hbind_operand(4'd2, 4'd2, 4'd3), status);
            check_status("V31 HBIND slot2", status);
            check_constant_slot("V31 HBIND slot2 ones", 4'd2, 64'hffff_ffff_ffff_ffff);

            issue(HDEC_HPERM, hperm_operand(4'd3, 4'd2, 4'd0, 6'd1), status);
            check_status("V31 HPERM slot3", status);
            check_constant_slot("V31 HPERM slot3 ones", 4'd3, 64'hffff_ffff_ffff_ffff);

            issue(HDEC_HCNTCLR, 64'd0, status);
            check_status("V31 HCNTCLR acc0", status);

            issue(HDEC_HCNTADD, 64'd2, status);
            check_status("V31 HCNTADD slot2", status);

            issue(HDEC_HCNTCLIP, hcntclip_operand(3'd3, 1'b0, 4'd1), status);
            check_status("V31 HCNTCLIP slot3", status);
            check_constant_slot("V31 HCNTCLIP slot3", 4'd3, 64'hffff_ffff_ffff_ffff);

            issue(HDEC_HSIM, hsim_operand(4'd3, 4'd2), last_result);
            check_equal64("V31 HSIM clipped prototype", last_result, 64'd0);

            issue(HDEC_HMATCH, hmatch_operand(4'd3, 4'd2, 8'd2), last_result);
            check_equal64("V31 HMATCH local classes", last_result, hmatch_result(8'd0, 11'd0));
        end
    endtask

    initial begin
        logic [63:0] status;
        logic [63:0] result;
        logic [255:0] gx;
        logic [255:0] gy;
        logic [255:0] scalar;
        logic [255:0] expected_x_3g;
        logic [255:0] expected_y_3g;
        int unsigned start_cycle;
        int unsigned standalone_hdc_cycles;
        int unsigned hdc_iters;
        bit done;

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

        start_cycle = cycle_count;
        run_hdc_foreground_flow(result);
        standalone_hdc_cycles = cycle_count - start_cycle;
        $display("HDC_FULL_FLOW_STANDALONE_CYCLES=%0d", standalone_hdc_cycles);

        issue(HDEC_ECC_STATUS, ecc_pmul_operand(1'b1, 6'd4, 6'd0, 6'd2), status);
        if ((status[1:0] !== STATUS_OK) || (status[2] !== 1'b1) || (status[3] !== 1'b0)) begin
            error_count++;
            $error("Background PMUL start bad status 0x%016h", status);
        end

        start_cycle = cycle_count;
        hdc_iters = 0;
        done = 1'b0;
        while (!done && (hdc_iters < 2000)) begin
            run_hdc_foreground_flow(result);
            hdc_iters++;
            issue(HDEC_ECC_STATUS, '0, status);
            done = (status[3] === 1'b1) && (status[2] === 1'b0);
        end

        if (!done) begin
            error_count++;
            $fatal(1, "Timeout waiting for interleaved PMUL status=0x%016h hdc_iters=%0d",
                   status, hdc_iters);
        end

        $display("PMUL_BG_HDC_LOOP_WALL_CYCLES=%0d", cycle_count - start_cycle);
        $display("PMUL_BG_HDC_LOOP_HDC_ITERS=%0d", hdc_iters);
        $display("PMUL_BG_HDC_LOOP_EQUIV_HDC_CYCLES=%0d", hdc_iters * standalone_hdc_cycles);
        $display("PMUL_BG_HDC_LOOP_STATUS_LOW16=%0d", status[31:16]);

        check_row("PMUL_BG_HDC_LOOP_3G_X", 6'd4, expected_x_3g);
        check_row("PMUL_BG_HDC_LOOP_3G_Y", 6'd5, expected_y_3g);

        if (error_count == 0)
            $display("[HDEC_ECC_PMUL_BG_HDC_LOOP_V31] PASS");
        else
            $fatal(1, "[HDEC_ECC_PMUL_BG_HDC_LOOP_V31] FAIL errors=%0d", error_count);
        $finish;
    end
endmodule
