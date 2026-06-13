module tb_hdec_ecc_align_v1;
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

    logic [3:0][63:0] vec_a;
    logic [3:0][63:0] vec_b;

    hdec_top #(.ECC_DEBUG_FIELD_OPS(1'b1)) dut (
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

    function automatic logic [63:0] ecc_align_operand(
        input logic [5:0] dst_idx,
        input logic [5:0] src0_idx,
        input logic [5:0] src1_idx,
        input logic [1:0] lane_base,
        input logic [5:0] bit_shift
    );
        begin
            ecc_align_operand = {38'd0, lane_base, bit_shift, dst_idx, src1_idx, src0_idx};
        end
    endfunction

    function automatic logic [63:0] pick_word(
        input logic [3:0][63:0] src0,
        input logic [3:0][63:0] src1,
        input int unsigned idx
    );
        begin
            unique case (idx)
                0: pick_word = src0[0];
                1: pick_word = src0[1];
                2: pick_word = src0[2];
                3: pick_word = src0[3];
                4: pick_word = src1[0];
                5: pick_word = src1[1];
                6: pick_word = src1[2];
                7: pick_word = src1[3];
                default: pick_word = '0;
            endcase
        end
    endfunction

    function automatic logic [3:0][63:0] expected_align(
        input logic [3:0][63:0] src0,
        input logic [3:0][63:0] src1,
        input logic [1:0] lane_base,
        input logic [5:0] bit_shift
    );
        logic [3:0][63:0] out;
        logic [127:0] pair_word;
        logic [127:0] shifted_word;
        begin
            for (int bank = 0; bank < 4; bank++) begin
                pair_word = {pick_word(src0, src1, lane_base + bank + 1),
                             pick_word(src0, src1, lane_base + bank)};
                shifted_word = pair_word >> bit_shift;
                out[bank] = shifted_word[63:0];
            end
            expected_align = out;
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

    task automatic load_entry(input logic [5:0] idx,
                              input logic [3:0][63:0] value);
        begin
            for (int bank = 0; bank < 4; bank++)
                write_vrf64(2'(bank), idx, value[bank]);
        end
    endtask

    task automatic check_entry(input logic [5:0] idx,
                               input logic [3:0][63:0] expected,
                               input string label);
        logic [63:0] got;
        begin
            for (int bank = 0; bank < 4; bank++) begin
                read_vrf64(2'(bank), idx, got);
                if (got !== expected[bank]) begin
                    $error("%s bank=%0d got=0x%016h expected=0x%016h",
                           label, bank, got, expected[bank]);
                    $fatal(1);
                end
            end
        end
    endtask

    initial begin
        logic [63:0] status;
        logic [3:0][63:0] expected;

        valid_i = 1'b0;
        operator_i = HDEC_VWR64;
        operand_a_i = '0;
        operand_b_i = '0;
        rst_ni = 1'b0;
        repeat (8) @(posedge clk_i);
        rst_ni = 1'b1;
        repeat (80) @(posedge clk_i);

        vec_a[0] = 64'h0102_0304_0506_0708;
        vec_a[1] = 64'h8877_6655_4433_2211;
        vec_a[2] = 64'h0123_4567_89ab_cdef;
        vec_a[3] = 64'hfedc_ba98_7654_3210;
        vec_b[0] = 64'h1357_9bdf_2468_ace0;
        vec_b[1] = 64'h0f1e_2d3c_4b5a_6978;
        vec_b[2] = 64'hdead_beef_cafe_babe;
        vec_b[3] = 64'ha5a5_5a5a_3c3c_c3c3;

        load_entry(6'd24, vec_a);
        load_entry(6'd25, vec_b);

        issue(HDEC_ECC_ALIGN, ecc_align_operand(6'd26, 6'd24, 6'd24, 2'd0, 6'd0), status);
        if (status[1:0] !== STATUS_OK)
            $fatal(1, "ECC_ALIGN copy returned bad status 0x%016h", status);
        check_entry(6'd26, vec_a, "ECC_ALIGN copy");

        expected = expected_align(vec_a, vec_b, 2'd1, 6'd5);
        issue(HDEC_ECC_ALIGN, ecc_align_operand(6'd27, 6'd24, 6'd25, 2'd1, 6'd5), status);
        if (status[1:0] !== STATUS_OK)
            $fatal(1, "ECC_ALIGN shift returned bad status 0x%016h", status);
        check_entry(6'd27, expected, "ECC_ALIGN shift");

        $display("[HDEC_ECC_ALIGN_V1] PASS");
        $finish;
    end
endmodule
