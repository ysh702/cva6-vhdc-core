package hdec_vv31_ref_pkg;

    localparam int VV31_GF_M    = 233;
    localparam int VV31_HV_BITS = 1024;

    function automatic logic [1023:0] vv31_rotr1024(
        input logic [1023:0] value,
        input logic [9:0]    rotate
    );
        begin
            if (rotate == 10'd0)
                vv31_rotr1024 = value;
            else
                vv31_rotr1024 = (value >> rotate)
                              | (value << (11'd1024 - {1'b0, rotate}));
        end
    endfunction

    function automatic logic [1023:0] vv31_hdc_bind(
        input logic [1023:0] operand_a,
        input logic [1023:0] operand_b
    );
        vv31_hdc_bind = operand_a ^ operand_b;
    endfunction

    function automatic logic [10:0] vv31_hdc_overlap(
        input logic [1023:0] operand_a,
        input logic [1023:0] operand_b
    );
        int unsigned count;
        begin
            count = 0;
            for (int bit_index = 0; bit_index < VV31_HV_BITS; bit_index++)
                count += operand_a[bit_index] & operand_b[bit_index];
            vv31_hdc_overlap = count[10:0];
        end
    endfunction

    function automatic logic [1023:0] vv31_hdc_or4(
        input logic [1023:0] sample0,
        input logic [1023:0] sample1,
        input logic [1023:0] sample2,
        input logic [1023:0] sample3
    );
        vv31_hdc_or4 = sample0 | sample1 | sample2 | sample3;
    endfunction

    function automatic logic [63:0] vv31_hmatch_result(
        input logic [2:0]  class_index,
        input logic [10:0] score
    );
        vv31_hmatch_result = {50'd0, class_index, score};
    endfunction

    function automatic logic [232:0] vv31_gf233_reduce(
        input logic [465:0] polynomial
    );
        logic [465:0] work;
        begin
            work = polynomial;
            // sect233k1 uses f(x) = x^233 + x^74 + 1.
            for (int degree = 465; degree >= VV31_GF_M; degree--) begin
                if (work[degree]) begin
                    work[degree]       = 1'b0;
                    work[degree - 233] = work[degree - 233] ^ 1'b1;
                    work[degree - 159] = work[degree - 159] ^ 1'b1;
                end
            end
            vv31_gf233_reduce = work[232:0];
        end
    endfunction

    function automatic logic [232:0] vv31_gf233_square(
        input logic [232:0] operand
    );
        logic [465:0] polynomial;
        begin
            polynomial = '0;
            for (int bit_index = 0; bit_index < VV31_GF_M; bit_index++)
                polynomial[2 * bit_index] = operand[bit_index];
            vv31_gf233_square = vv31_gf233_reduce(polynomial);
        end
    endfunction

    function automatic logic [232:0] vv31_gf233_mul(
        input logic [232:0] operand_a,
        input logic [232:0] operand_b
    );
        logic [465:0] polynomial;
        begin
            polynomial = '0;
            for (int bit_a = 0; bit_a < VV31_GF_M; bit_a++) begin
                for (int bit_b = 0; bit_b < VV31_GF_M; bit_b++)
                    polynomial[bit_a + bit_b] =
                        polynomial[bit_a + bit_b]
                        ^ (operand_a[bit_a] & operand_b[bit_b]);
            end
            vv31_gf233_mul = vv31_gf233_reduce(polynomial);
        end
    endfunction

endpackage
