module tb_vv30_square_basis_unit;
    import hdec_pkg::*;
    import hdec_vv30_ref_pkg::*;
    import hdec_vv30_vectors_pkg::*;

    logic clk_i;
    logic rst_ni;
    logic valid_i;
    logic ready_o;
    hdec_op_t operator_i;
    logic [63:0] operand_a_i;
    logic [63:0] operand_b_i;
    logic valid_o;
    logic [63:0] result_o;

    logic [255:0] random_square [0:VV30_MAX_RANDOM_FIELDS-1];
    logic [31:0] random_count_mem [0:0];
    int unsigned observed;

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

    task automatic check_square(input logic [232:0] operand);
        logic [3:0][63:0] source_words;
        logic [3:0][63:0] got_words;
        logic [232:0] got;
        logic [232:0] expected;
        begin
            source_words[0] = operand[63:0];
            source_words[1] = operand[127:64];
            source_words[2] = operand[191:128];
            source_words[3] = {23'd0, operand[232:192]};
            expected = vv30_gf233_square(operand);
            got_words = dut.ecc_square_reduce233_loop(source_words);
            got = {got_words[3][40:0], got_words[2],
                   got_words[1], got_words[0]};
            if (got !== expected)
                $fatal(1,
                    "[VV30:square_basis] operand=%059h got=%059h expected=%059h",
                    operand, got, expected);
            if (got_words[3][63:41] !== 23'd0)
                $fatal(1, "[VV30:square_basis] nonzero high padding");
            observed++;
        end
    endtask

    initial begin
        logic [232:0] operand;
        string vector_file;
        int random_count;

        clk_i = 1'b0;
        rst_ni = 1'b0;
        valid_i = 1'b0;
        operator_i = HDEC_VWR64;
        operand_a_i = '0;
        operand_b_i = '0;
        observed = 0;
        random_count = 0;

        for (int basis = 0; basis < 233; basis++) begin
            operand = '0;
            operand[basis] = 1'b1;
            check_square(operand);
        end

        operand = '0;
        check_square(operand);
        operand = '1;
        check_square(operand);
        for (int bit_idx = 0; bit_idx < 233; bit_idx++)
            operand[bit_idx] = bit_idx[0];
        check_square(operand);
        operand = ~operand;
        check_square(operand);
        operand = '0; operand[0] = 1'b1;   check_square(operand);
        operand = '0; operand[232] = 1'b1; check_square(operand);
        operand = '0; operand[116] = 1'b1; check_square(operand);
        operand = '0; operand[117] = 1'b1; check_square(operand);
        operand = '0; operand[195] = 1'b1; check_square(operand);
        operand = '0; operand[196] = 1'b1; check_square(operand);

        $readmemh("random_count.mem", random_count_mem);
        random_count = random_count_mem[0];
        if (random_count != 0) begin
            if (random_count > VV30_MAX_RANDOM_FIELDS)
                $fatal(1, "[VV30:square_basis] random count too large");
            vector_file = "square_inputs.mem";
            $readmemh(vector_file, random_square);
            for (int vector_idx = 0; vector_idx < random_count; vector_idx++) begin
                if (random_square[vector_idx][255:233] !== 23'd0)
                    $fatal(1,
                        "[VV30:square_basis] vector %0d has nonzero high padding",
                        vector_idx);
                check_square(random_square[vector_idx][232:0]);
            end
        end

        $display("[VV30:COVERAGE] test=square_basis observed=%0d expected=%0d",
                 observed, VV30_SQUARE_BASIS_COVERAGE
                           + VV30_SQUARE_DIRECTED_COVERAGE + random_count);
        if (observed != VV30_SQUARE_BASIS_COVERAGE
                        + VV30_SQUARE_DIRECTED_COVERAGE + random_count)
            $fatal(1, "[VV30:square_basis] incomplete coverage");
        $display("[VV30:square_basis] PASS");
        $finish;
    end
endmodule
