package hdec_vv30_ref_pkg;

    localparam int VV30_GF_M = 233;

    function automatic logic [63:0] vv30_align64(
        input logic [63:0] src_a,
        input logic [63:0] src_b,
        input logic [5:0]  bit_shift
    );
        begin
            if (bit_shift == 6'd0)
                vv30_align64 = src_a;
            else
                vv30_align64 = (src_a >> bit_shift)
                               | (src_b << (7'd64 - {1'b0, bit_shift}));
        end
    endfunction

    function automatic logic [232:0] vv30_gf233_reduce(
        input logic [465:0] polynomial
    );
        logic [465:0] work;
        begin
            work = polynomial;
            // x^233 = x^74 + 1 over GF(2).
            for (int degree = 465; degree >= 233; degree--) begin
                if (work[degree]) begin
                    work[degree]       = 1'b0;
                    work[degree - 233] = work[degree - 233] ^ 1'b1;
                    work[degree - 159] = work[degree - 159] ^ 1'b1;
                end
            end
            vv30_gf233_reduce = work[232:0];
        end
    endfunction

    function automatic logic [232:0] vv30_gf233_reduce512(
        input logic [511:0] polynomial
    );
        logic [511:0] work;
        begin
            work = polynomial;
            for (int degree = 511; degree >= 233; degree--) begin
                if (work[degree]) begin
                    work[degree]       = 1'b0;
                    work[degree - 233] = work[degree - 233] ^ 1'b1;
                    work[degree - 159] = work[degree - 159] ^ 1'b1;
                end
            end
            vv30_gf233_reduce512 = work[232:0];
        end
    endfunction

    function automatic logic [232:0] vv30_gf233_square(
        input logic [232:0] operand
    );
        logic [465:0] polynomial;
        begin
            polynomial = '0;
            for (int bit_idx = 0; bit_idx < VV30_GF_M; bit_idx++)
                polynomial[2 * bit_idx] = operand[bit_idx];
            vv30_gf233_square = vv30_gf233_reduce(polynomial);
        end
    endfunction

    function automatic logic [232:0] vv30_gf233_mul(
        input logic [232:0] operand_a,
        input logic [232:0] operand_b
    );
        logic [465:0] polynomial;
        begin
            polynomial = '0;
            for (int bit_a = 0; bit_a < VV30_GF_M; bit_a++) begin
                for (int bit_b = 0; bit_b < VV30_GF_M; bit_b++)
                    polynomial[bit_a + bit_b] =
                        polynomial[bit_a + bit_b]
                        ^ (operand_a[bit_a] & operand_b[bit_b]);
            end
            vv30_gf233_mul = vv30_gf233_reduce(polynomial);
        end
    endfunction

    function automatic logic [1023:0] vv30_rotr1024(
        input logic [1023:0] value,
        input logic [9:0]    rotate
    );
        begin
            if (rotate == 10'd0)
                vv30_rotr1024 = value;
            else
                vv30_rotr1024 = (value >> rotate)
                                | (value << (11'd1024 - {1'b0, rotate}));
        end
    endfunction

endpackage
