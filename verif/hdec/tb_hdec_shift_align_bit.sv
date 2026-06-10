module tb_hdec_shift_align_bit;
    logic [63:0] src_a;
    logic [63:0] src_b;
    logic [5:0]  bit_shift;
    logic [63:0] result;

    hdec_lane_shift_align dut (
        .src_a_i    (src_a),
        .src_b_i    (src_b),
        .bit_shift_i(bit_shift),
        .result_o   (result)
    );

    function automatic logic [63:0] expected_align(
        input logic [63:0] a,
        input logic [63:0] b,
        input logic [5:0]  sh
    );
        begin
            if (sh == 6'd0)
                expected_align = a;
            else
                expected_align = (a >> sh) | (b << (7'd64 - {1'b0, sh}));
        end
    endfunction

    task automatic check_case(
        input string       label,
        input logic [63:0] a,
        input logic [63:0] b,
        input logic [5:0]  sh
    );
        logic [63:0] exp;
        begin
            src_a = a;
            src_b = b;
            bit_shift = sh;
            #1;
            exp = expected_align(a, b, sh);
            if (result !== exp) begin
                $error("%s shift=%0d got=0x%016h expected=0x%016h",
                       label, sh, result, exp);
                $fatal(1);
            end
        end
    endtask

    initial begin
        logic [63:0] a;
        logic [63:0] b;

        a = 64'h0123_4567_89ab_cdef;
        b = 64'hf0e1_d2c3_b4a5_9687;

        check_case("direct shift0",  a, b, 6'd0);
        check_case("direct shift1",  a, b, 6'd1);
        check_case("direct shift4",  a, b, 6'd4);
        check_case("direct shift60", a, b, 6'd60);
        check_case("direct shift63", a, b, 6'd63);

        for (int seed = 0; seed < 64; seed++) begin
            a = 64'h9e37_79b9_7f4a_7c15 ^ (64'(seed) * 64'h0001_0001_0001_0001);
            b = 64'hd1b5_4a32_d192_ed03 ^ (64'(seed) * 64'h0100_0000_0000_0101);
            for (int sh = 0; sh < 64; sh++)
                check_case("random bit-align", a, b, 6'(sh));
            for (int nib = 0; nib < 16; nib++)
                check_case("HDC nibble compat", a, b, 6'(nib << 2));
        end

        $display("[HDEC_SHIFT_ALIGN_BIT] PASS");
        $finish;
    end
endmodule
