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

    initial begin
        logic [3:0] paths [0:8];
        logic [LANE_NUM-1:0][LANE_WIDTH-1:0] got;
        logic [LANE_NUM-1:0][LANE_WIDTH-1:0] exp;
        logic [63:0] group_product;
        logic [127:0] leaf_delta;
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

        for (int p = 0; p < 9; p++) begin
            for (int sub = 0; sub < 3; sub++) begin
                for (int group = 0; group < 8; group++) begin
                    for (int row = 0; row < 256; row++) begin
                        logic [LANE_NUM*2-1:0] parity_row;
                        parity_row = row[LANE_NUM*2-1:0];
                        if (group == 7)
                            parity_row[7] = 1'b0;

                        got = '0;
                        for (int slot = 0; slot < 4; slot++) begin
                            got ^= dut.ecc_kpd64_diag_reduce_packet(
                                paths[p],
                                sub[1:0],
                                group[2:0],
                                parity_row,
                                slot[1:0]
                            );
                        end
                        group_product = dut.ecc_diag32_leaf_store_bitband('0, group[2:0], parity_row);
                        leaf_delta = dut.ecc_kpd64_sub32_accum('0, sub[1:0], group_product);
                        exp = dut.ecc_kpd64_leaf_reduce_packet(
                            dut.ecc_kpd64_leaf_offset_mask(paths[p]),
                            leaf_delta
                        );

                        if (got !== exp) begin
                            errors++;
                            $display("DIAG_REDUCE_MAP mismatch path=%b sub=%0d group=%0d row=0x%02x got=%h exp=%h",
                                     paths[p], sub, group, row, got, exp);
                        end
                    end
                end
            end
        end

        if (errors == 0) begin
            $display("[HDEC_ECC_DIAG_REDUCE_MAP_V1] PASS");
        end else begin
            $fatal(1, "[HDEC_ECC_DIAG_REDUCE_MAP_V1] FAIL errors=%0d", errors);
        end
        $finish;
    end
endmodule
