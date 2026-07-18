module tb_hdec_ecc_diag_reduce_map_v1;
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

    function automatic logic [31:0] clmul16_ref(
        input logic [15:0] a,
        input logic [15:0] b
    );
        logic [31:0] product;
        begin
            product = '0;
            for (int bit_idx = 0; bit_idx < 16; bit_idx++) begin
                if (a[bit_idx])
                    product ^= ({16'b0, b} << bit_idx);
            end
            clmul16_ref = product;
        end
    endfunction

    function automatic logic [63:0] clmul32_ref(
        input logic [31:0] a,
        input logic [31:0] b
    );
        logic [63:0] product;
        begin
            product = '0;
            for (int bit_idx = 0; bit_idx < 32; bit_idx++) begin
                if (a[bit_idx])
                    product ^= ({32'b0, b} << bit_idx);
            end
            clmul32_ref = product;
        end
    endfunction

    initial begin
        logic [3:0] paths [0:8];
        logic [31:0] a;
        logic [31:0] b;
        logic [31:0] z0;
        logic [31:0] z2;
        logic [31:0] zm;
        logic [63:0] streamed_product;
        logic [63:0] expected_product;
        logic [127:0] streamed_delta;
        logic [127:0] expected_delta;
        logic [LANE_NUM-1:0][LANE_WIDTH-1:0] got_packet;
        logic [LANE_NUM-1:0][LANE_WIDTH-1:0] expected_packet;
        int unsigned errors;

        paths[0] = 4'b00_00;
        paths[1] = 4'b00_01;
        paths[2] = 4'b00_10;
        paths[3] = 4'b01_00;
        paths[4] = 4'b01_01;
        paths[5] = 4'b01_10;
        paths[6] = 4'b10_00;
        paths[7] = 4'b10_01;
        paths[8] = 4'b10_10;

        rst_ni = 1'b1;
        valid_i = 1'b0;
        operator_i = HDEC_VWR64;
        operand_a_i = '0;
        operand_b_i = '0;
        errors = 0;

        // VV23 no longer has the VV22 per-diagonal ECC AND+XOR packet path.
        // Check the replacement path directly: three products from the one
        // shared 16x16 bit matrix are combined by the 32x32 Karatsuba token,
        // then enter the unchanged leaf-placement and modular-fold mapping.
        for (int test_idx = 0; test_idx < 4096; test_idx++) begin
            unique case (test_idx)
                0: begin a = 32'h0000_0000; b = 32'h0000_0000; end
                1: begin a = 32'h0000_0001; b = 32'h0000_0001; end
                2: begin a = 32'hffff_ffff; b = 32'hffff_ffff; end
                3: begin a = 32'haaaa_aaaa; b = 32'h5555_5555; end
                4: begin a = 32'h8000_0000; b = 32'h0000_0001; end
                5: begin a = 32'h0123_4567; b = 32'h89ab_cdef; end
                default: begin a = $urandom; b = $urandom; end
            endcase

            z0 = clmul16_ref(a[15:0], b[15:0]);
            z2 = clmul16_ref(a[31:16], b[31:16]);
            zm = clmul16_ref(a[15:0] ^ a[31:16], b[15:0] ^ b[31:16]);
            streamed_product = dut.ecc_diag16_karatsuba_token(3'd0, z0)
                             ^ dut.ecc_diag16_karatsuba_token(3'd1, z2)
                             ^ dut.ecc_diag16_karatsuba_token(3'd2, zm);
            expected_product = clmul32_ref(a, b);

            if (streamed_product !== expected_product) begin
                errors++;
                $display("VV23 token mismatch test=%0d a=%h b=%h got=%h exp=%h",
                         test_idx, a, b, streamed_product, expected_product);
            end

            for (int path_idx = 0; path_idx < 9; path_idx++) begin
                for (int sub_idx = 0; sub_idx < 3; sub_idx++) begin
                    streamed_delta = dut.ecc_kpd64_sub32_delta(
                        sub_idx[1:0], streamed_product
                    );
                    expected_delta = dut.ecc_kpd64_sub32_accum(
                        '0, sub_idx[1:0], expected_product
                    );
                    got_packet = dut.ecc_kpd64_leaf_reduce_packet(
                        dut.ecc_kpd64_leaf_offset_mask(paths[path_idx]),
                        streamed_delta
                    );
                    expected_packet = dut.ecc_kpd64_leaf_reduce_packet(
                        dut.ecc_kpd64_leaf_offset_mask(paths[path_idx]),
                        expected_delta
                    );

                    if ((streamed_delta !== expected_delta)
                        || (got_packet !== expected_packet)) begin
                        errors++;
                        $display("VV23 reduce-map mismatch test=%0d path=%b sub=%0d got=%h exp=%h",
                                 test_idx, paths[path_idx], sub_idx,
                                 got_packet, expected_packet);
                    end
                end
            end
        end

        if (errors == 0) begin
            $display("[HDEC_ECC_DIAG_REDUCE_MAP_V1] PASS vectors=4096");
        end else begin
            $fatal(1, "[HDEC_ECC_DIAG_REDUCE_MAP_V1] FAIL errors=%0d", errors);
        end
        $finish;
    end
endmodule
