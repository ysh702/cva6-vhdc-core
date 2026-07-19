module tb_hdec_vv25_native_xor1;
    import hdec_pkg::*;
    import hdec_resource_pkg::*;
    import hdec_vv25_equation_pkg::*;

    logic clk;
    logic diag_mode;
    logic [7:0][31:0] matrix_product;
    logic [31:0] pop_byte_parity;
    logic [15:0] pop_byte_pair_parity;
    logic [13:0] pop_short_parity;
    logic [7:0] pop_tail_parity;
    logic [127:0] legacy_acc;
    logic [63:0] legacy_sub_product;
    logic [1:0] legacy_sub_idx;
    logic [31:0] legacy_leaf_a;
    logic [31:0] legacy_leaf_xor_a;
    logic [31:0] legacy_leaf_b;
    logic [31:0] legacy_leaf_xor_b;
    logic [30:0] diag16_product;
    logic [127:0] legacy_accum;
    logic [31:0] legacy_lowxor_a;
    logic [31:0] legacy_lowxor_b;

    hdec_xor1_shared_8x32 dut (
        .diag_mode_i              (diag_mode),
        .matrix_product_i         (matrix_product),
        .pop_byte_parity_i        (pop_byte_parity),
        .pop_byte_pair_parity_i   (pop_byte_pair_parity),
        .pop_short_parity_i       (pop_short_parity),
        .pop_tail_parity_i        (pop_tail_parity),
        .legacy_acc_i             (legacy_acc),
        .legacy_sub_product_i     (legacy_sub_product),
        .legacy_sub_idx_i         (legacy_sub_idx),
        .legacy_leaf_a_i          (legacy_leaf_a),
        .legacy_leaf_xor_a_i      (legacy_leaf_xor_a),
        .legacy_leaf_b_i          (legacy_leaf_b),
        .legacy_leaf_xor_b_i      (legacy_leaf_xor_b),
        .diag16_product_o         (diag16_product),
        .legacy_accum_o           (legacy_accum),
        .legacy_lowxor_a_o        (legacy_lowxor_a),
        .legacy_lowxor_b_o        (legacy_lowxor_b)
    );

    always #5 clk = ~clk;

    function automatic logic [30:0] diag_ref(input logic [7:0][31:0] matrix);
        logic [30:0] product;
        begin
            product = '0;
            for (int flat_idx = 0; flat_idx < 256; flat_idx++)
                product[hdec_vv25_matrix_diag(flat_idx)] ^=
                    matrix[flat_idx / 32][flat_idx % 32];
            diag_ref = product;
        end
    endfunction

    function automatic logic [127:0] legacy_accum_ref(
        input logic [127:0] acc,
        input logic [1:0] sub_idx,
        input logic [63:0] sub_product
    );
        logic [3:0][31:0] rows;
        logic [31:0] sub_lo;
        logic [31:0] sub_hi;
        begin
            rows[0] = acc[31:0];
            rows[1] = acc[63:32];
            rows[2] = acc[95:64];
            rows[3] = acc[127:96];
            sub_lo = sub_product[31:0];
            sub_hi = sub_product[63:32];
            unique case (sub_idx)
                2'd0: begin
                    rows[0] ^= sub_lo;
                    rows[1] ^= sub_hi ^ sub_lo;
                    rows[2] ^= sub_hi;
                end
                2'd1: begin
                    rows[1] ^= sub_lo;
                    rows[2] ^= sub_hi ^ sub_lo;
                    rows[3] ^= sub_hi;
                end
                2'd2: begin
                    rows[1] ^= sub_lo;
                    rows[2] ^= sub_hi;
                end
                default: begin
                end
            endcase
            legacy_accum_ref = {rows[3], rows[2], rows[1], rows[0]};
        end
    endfunction

    task automatic drive_pop_taps;
        int mixed_base;
        int tail_base;
        begin
            for (int byte_idx = 0; byte_idx < 32; byte_idx++) begin
                pop_byte_parity[byte_idx] = 1'b0;
                for (int bit_idx = 0; bit_idx < 8; bit_idx++)
                    pop_byte_parity[byte_idx] ^=
                        matrix_product[byte_idx / 4][(byte_idx % 4) * 8 + bit_idx];
            end
            for (int row = 0; row < 8; row++) begin
                for (int side = 0; side < 2; side++) begin
                    pop_byte_pair_parity[row * 2 + side] =
                        pop_byte_parity[row * 4 + side * 2]
                        ^ pop_byte_parity[row * 4 + side * 2 + 1];
                end
            end
            for (int row = 0; row < 7; row++) begin
                for (int side = 0; side < 2; side++) begin
                    mixed_base = (side * 2 + 1) * 8;
                    pop_short_parity[row * 2 + side] = 1'b0;
                    for (int bit_idx = 0; bit_idx < 8; bit_idx++) begin
                        if (bit_idx <= row)
                            pop_short_parity[row * 2 + side] ^=
                                matrix_product[row][mixed_base + bit_idx];
                    end
                    if ((row == 2) || (row == 4)
                        || (row == 5) || (row == 6)) begin
                        tail_base = (row == 2) ? 0
                                  : (row == 4) ? 2
                                  : (row == 5) ? 4 : 6;
                        pop_tail_parity[tail_base + side] = 1'b0;
                        for (int bit_idx = 0; bit_idx < 8; bit_idx++) begin
                            if (bit_idx > row)
                                pop_tail_parity[tail_base + side] ^=
                                    matrix_product[row][mixed_base + bit_idx];
                        end
                    end
                end
            end
        end
    endtask

    task automatic check_cycle(input int cycle_idx);
        begin
            if (legacy_lowxor_a !== (legacy_leaf_a ^ legacy_leaf_xor_a))
                $fatal(1, "[VV25_NATIVE_XOR1] legacy A mismatch cycle=%0d",
                       cycle_idx);
            if (legacy_lowxor_b !== (legacy_leaf_b ^ legacy_leaf_xor_b))
                $fatal(1, "[VV25_NATIVE_XOR1] legacy B mismatch cycle=%0d",
                       cycle_idx);
            if (diag_mode) begin
                if (diag16_product !== diag_ref(matrix_product))
                    $fatal(1,
                        "[VV25_NATIVE_XOR1] diag mismatch cycle=%0d got=%h exp=%h",
                        cycle_idx, diag16_product, diag_ref(matrix_product));
            end else begin
                if (legacy_accum !== legacy_accum_ref(
                        legacy_acc, legacy_sub_idx, legacy_sub_product))
                    $fatal(1, "[VV25_NATIVE_XOR1] legacy accum mismatch cycle=%0d",
                           cycle_idx);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        diag_mode = 1'b0;
        matrix_product = '0;
        pop_byte_parity = '0;
        pop_byte_pair_parity = '0;
        pop_short_parity = '0;
        pop_tail_parity = '0;
        legacy_acc = '0;
        legacy_sub_product = '0;
        legacy_sub_idx = '0;
        legacy_leaf_a = '0;
        legacy_leaf_xor_a = '0;
        legacy_leaf_b = '0;
        legacy_leaf_xor_b = '0;

        for (int cycle_idx = 0; cycle_idx < 4096; cycle_idx++) begin
            @(negedge clk);
            diag_mode = cycle_idx[0];
            for (int rid = 0; rid < 8; rid++)
                matrix_product[rid] = $urandom;
            legacy_acc = {$urandom, $urandom, $urandom, $urandom};
            legacy_sub_product = {$urandom, $urandom};
            legacy_sub_idx = cycle_idx[1:0];
            legacy_leaf_a = $urandom;
            legacy_leaf_xor_a = $urandom;
            legacy_leaf_b = $urandom;
            legacy_leaf_xor_b = $urandom;
            drive_pop_taps();
            #1;
            check_cycle(cycle_idx);
        end

        $display("[VV25_NATIVE_XOR1] PASS legacy_cycles=2048 diag_cycles=2048 native_nodes=224 diag_nodes=14");
        $finish;
    end
endmodule
