module tb_vv30_shift_align_unit;
    import hdec_vv30_ref_pkg::*;
    import hdec_vv30_vectors_pkg::*;

    logic [63:0] src_a;
    logic [63:0] src_b;
    logic [5:0]  bit_shift;
    logic [63:0] result;
    int unsigned observed;

    hdec_lane_shift_align dut (
        .src_a_i     (src_a),
        .src_b_i     (src_b),
        .bit_shift_i (bit_shift),
        .result_o    (result)
    );

    initial begin
        logic [127:0] basis_window;
        logic [63:0] expected;

        src_a = '0;
        src_b = '0;
        bit_shift = '0;
        observed = 0;

        for (int nibble = 0; nibble < 16; nibble++) begin
            for (int basis = 0; basis < 128; basis++) begin
                basis_window = '0;
                basis_window[basis] = 1'b1;
                src_a = basis_window[63:0];
                src_b = basis_window[127:64];
                bit_shift = 6'(nibble * 4);
                #1;
                expected = vv30_align64(src_a, src_b, bit_shift);
                if (result !== expected)
                    $fatal(1,
                        "[VV30:shift_align_basis] mismatch nibble=%0d basis=%0d got=%016h expected=%016h",
                        nibble, basis, result, expected);
                observed++;
            end
        end

        $display("[VV30:COVERAGE] test=shift_align_basis observed=%0d expected=%0d",
                 observed, VV30_SHIFT_BASIS_COVERAGE);
        if (observed != VV30_SHIFT_BASIS_COVERAGE)
            $fatal(1, "[VV30:shift_align_basis] incomplete coverage");
        $display("[VV30:shift_align_basis] PASS");
        $finish;
    end
endmodule
