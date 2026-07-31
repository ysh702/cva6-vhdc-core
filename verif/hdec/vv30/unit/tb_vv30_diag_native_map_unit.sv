module tb_vv30_diag_native_map_unit;
    import hdec_pkg::*;

    localparam int unsigned EXPECTED_COVERAGE = 16 * 3 * 3 * 31;

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

    function automatic bit digit_has_term(
        input logic [1:0] digit,
        input int unsigned term
    );
        begin
            case (digit)
                2'd0: digit_has_term = (term == 0) || (term == 1);
                2'd1: digit_has_term = (term == 1);
                2'd2: digit_has_term = (term == 1) || (term == 2);
                default: digit_has_term = 1'b0;
            endcase
        end
    endfunction

    function automatic logic [232:0] reduce_gf233(
        input logic [511:0] polynomial
    );
        logic [511:0] work;
        begin
            work = polynomial;
            for (int degree = 511; degree >= 233; degree--) begin
                if (work[degree]) begin
                    work[degree]       = 1'b0;
                    work[degree - 233] ^= 1'b1;
                    work[degree - 159] ^= 1'b1;
                end
            end
            reduce_gf233 = work[232:0];
        end
    endfunction

    function automatic logic [255:0] independent_diagonal_map(
        input logic [3:0]  path,
        input logic [1:0]  sub_idx,
        input logic [1:0]  group_idx,
        input logic [30:0] diagonal
    );
        logic [63:0]  diagonal64;
        logic [63:0]  local_product;
        logic [127:0] local_product128;
        logic [127:0] leaf_product;
        logic [511:0] raw_polynomial;
        logic [232:0] reduced;
        begin
            diagonal64 = {33'd0, diagonal};
            case (group_idx)
                2'd0: local_product = diagonal64
                                         ^ (diagonal64 << 16);
                2'd1: local_product = (diagonal64 << 32)
                                         ^ (diagonal64 << 16);
                2'd2: local_product = diagonal64 << 16;
                default: local_product = '0;
            endcase

            local_product128 = {64'd0, local_product};
            case (sub_idx)
                2'd0: leaf_product = local_product128
                                         ^ (local_product128 << 32);
                2'd1: leaf_product = (local_product128 << 64)
                                         ^ (local_product128 << 32);
                2'd2: leaf_product = local_product128 << 32;
                default: leaf_product = '0;
            endcase

            raw_polynomial = '0;
            for (int outer_term = 0; outer_term < 3; outer_term++) begin
                for (int inner_term = 0; inner_term < 3; inner_term++) begin
                    if (digit_has_term(path[3:2], outer_term)
                        && digit_has_term(path[1:0], inner_term))
                        raw_polynomial ^= ({384'd0, leaf_product}
                                           << (64 * ((2 * outer_term)
                                                     + inner_term)));
                end
            end
            reduced = reduce_gf233(raw_polynomial);
            independent_diagonal_map = {23'd0, reduced};
        end
    endfunction

    initial begin
        logic [30:0] diagonal;
        logic [6:0] path_mask;
        logic [3:0][63:0] got_packet;
        logic [255:0] got;
        logic [255:0] expected;
        int unsigned observed;

        clk_i = 1'b0;
        rst_ni = 1'b0;
        valid_i = 1'b0;
        operator_i = HDEC_VWR64;
        operand_a_i = '0;
        operand_b_i = '0;
        observed = 0;

        for (int path = 0; path < 16; path++) begin
            for (int sub_idx = 0; sub_idx < 3; sub_idx++) begin
                for (int group_idx = 0; group_idx < 3; group_idx++) begin
                    for (int basis = 0; basis < 31; basis++) begin
                        diagonal = '0;
                        diagonal[basis] = 1'b1;
                        expected = independent_diagonal_map(
                            4'(path), 2'(sub_idx), 2'(group_idx),
                            diagonal
                        );
                        path_mask = dut.ecc_kpd64_leaf_offset_mask(
                            4'(path)
                        );
                        got_packet = dut.ecc_kpd64_diagonal_reduce_packet(
                            path_mask, 2'(sub_idx), 2'(group_idx),
                            diagonal
                        );
                        got = {got_packet[3], got_packet[2],
                               got_packet[1], got_packet[0]};

                        if (got !== expected)
                            $fatal(1,
                                "[VV30:diag_native_map] path=%0h sub=%0d group=%0d basis=%0d got=%064h expected=%064h",
                                path, sub_idx, group_idx, basis,
                                got, expected);
                        if (got[255:233] !== 23'd0)
                            $fatal(1,
                                "[VV30:diag_native_map] nonzero padding");
                        observed++;
                    end
                end
            end
        end

        $display(
            "[VV30:COVERAGE] test=diag_native_map observed=%0d expected=%0d",
            observed, EXPECTED_COVERAGE
        );
        if (observed != EXPECTED_COVERAGE)
            $fatal(1, "[VV30:diag_native_map] incomplete coverage");
        $display("[VV30:diag_native_map] PASS");
        $finish;
    end
endmodule
