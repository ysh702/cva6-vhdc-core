module tb_hdec_vv23_shared_xor1;
    import hdec_pkg::*;
    import hdec_resource_pkg::*;

    logic clk;
    logic diag_mode;
    logic [LANE_NUM*2-1:0][31:0] matrix_product;
    logic [LANE_NUM*2-1:0]       matrix_parity;
    logic [127:0] legacy_acc;
    logic [63:0]  legacy_sub_product;
    logic [1:0]   legacy_sub_idx;
    logic [31:0]  legacy_leaf_a;
    logic [31:0]  legacy_leaf_xor_a;
    logic [31:0]  legacy_leaf_b;
    logic [31:0]  legacy_leaf_xor_b;
    logic [30:0]  diag16_product;
    logic [127:0] legacy_accum;
    logic [31:0]  legacy_lowxor_a;
    logic [31:0]  legacy_lowxor_b;

    for (genvar rid = 0; rid < LANE_NUM*2; rid++) begin : gen_matrix_parity
        assign matrix_parity[rid] = ^matrix_product[rid];
    end

    hdec_xor1_shared_8x32 dut (
        .diag_mode_i              (diag_mode),
        .matrix_product_i         (matrix_product),
        .matrix_parity_i          (matrix_parity),
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

    function automatic logic xor_range(
        input logic [31:0] row,
        input int unsigned start_idx,
        input int unsigned bit_count
    );
        logic parity;
        begin
            parity = 1'b0;
            for (int bit_idx = 0; bit_idx < 32; bit_idx++) begin
                if ((bit_idx >= start_idx) && (bit_idx < start_idx + bit_count))
                    parity ^= row[bit_idx];
            end
            xor_range = parity;
        end
    endfunction

    function automatic logic [30:0] diag16_ref(
        input logic [LANE_NUM*2-1:0][31:0] matrix
    );
        logic [30:0] product;
        int unsigned edge_len;
        begin
            product = '0;
            for (int rid = 0; rid < 7; rid++) begin
                edge_len = rid + 1;
                product[rid] = xor_range(matrix[rid], 0, edge_len);
                product[30-rid] = xor_range(matrix[rid], edge_len, edge_len);
                product[14-rid] = xor_range(
                    matrix[rid], 2 * edge_len, 16 - edge_len
                );
                product[16+rid] = xor_range(
                    matrix[rid], 16 + edge_len, 16 - edge_len
                );
            end
            product[7]  = xor_range(matrix[7], 0, 8);
            product[15] = xor_range(matrix[7], 8, 16);
            product[23] = xor_range(matrix[7], 24, 8);
            diag16_ref = product;
        end
    endfunction

    function automatic logic [127:0] legacy_accum_ref(
        input logic [127:0] acc,
        input logic [1:0]   sub_idx,
        input logic [63:0]  sub_product
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

    task automatic check_selected_mode(input int unsigned cycle_idx);
        logic [30:0] expected_diag;
        logic [127:0] expected_accum;
        begin
            if (diag_mode) begin
                expected_diag = diag16_ref(matrix_product);
                if (diag16_product !== expected_diag)
                    $fatal(1,
                           "[VV23_SHARED_XOR1] diagonal mismatch cycle=%0d got=%h exp=%h",
                           cycle_idx, diag16_product, expected_diag);
            end else begin
                expected_accum = legacy_accum_ref(
                    legacy_acc, legacy_sub_idx, legacy_sub_product
                );
                if (legacy_accum !== expected_accum)
                    $fatal(1,
                           "[VV23_SHARED_XOR1] legacy accum mismatch cycle=%0d got=%h exp=%h",
                           cycle_idx, legacy_accum, expected_accum);
                if (legacy_lowxor_a !== (legacy_leaf_a ^ legacy_leaf_xor_a))
                    $fatal(1, "[VV23_SHARED_XOR1] legacy leaf-A mismatch cycle=%0d",
                           cycle_idx);
                if (legacy_lowxor_b !== (legacy_leaf_b ^ legacy_leaf_xor_b))
                    $fatal(1, "[VV23_SHARED_XOR1] legacy leaf-B mismatch cycle=%0d",
                           cycle_idx);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        diag_mode = 1'b0;
        matrix_product = '0;
        legacy_acc = '0;
        legacy_sub_product = '0;
        legacy_sub_idx = '0;
        legacy_leaf_a = '0;
        legacy_leaf_xor_a = '0;
        legacy_leaf_b = '0;
        legacy_leaf_xor_b = '0;

        #1;
        check_selected_mode(0);
        matrix_product = '1;
        legacy_acc = '1;
        legacy_sub_product = 64'h01234567_89abcdef;
        legacy_sub_idx = 2'd1;
        legacy_leaf_a = 32'ha5a55a5a;
        legacy_leaf_xor_a = 32'h0f0ff0f0;
        legacy_leaf_b = 32'h13579bdf;
        legacy_leaf_xor_b = 32'h2468ace0;
        diag_mode = 1'b1;
        #1;
        check_selected_mode(1);

        // Alternate modes every cycle: exactly 2048 checks for the untouched
        // VV22 behavior and 2048 checks for the VV23 diagonal behavior.
        for (int cycle_idx = 2; cycle_idx < 4096; cycle_idx++) begin
            @(negedge clk);
            diag_mode = cycle_idx[0];
            for (int rid = 0; rid < LANE_NUM*2; rid++)
                matrix_product[rid] = $urandom;
            legacy_acc = {$urandom, $urandom, $urandom, $urandom};
            legacy_sub_product = {$urandom, $urandom};
            legacy_sub_idx = cycle_idx[1:0];
            legacy_leaf_a = $urandom;
            legacy_leaf_xor_a = $urandom;
            legacy_leaf_b = $urandom;
            legacy_leaf_xor_b = $urandom;
            #1;
            check_selected_mode(cycle_idx);
        end

        $display("[VV23_SHARED_XOR1] PASS legacy_cycles=2048 diag_cycles=2048");
        $finish;
    end

endmodule
