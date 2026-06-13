module tb_hdec_ecc_mul_cycle_count;
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

    hdec_top #(.ECC_DEBUG_FIELD_OPS(1'b1)) dut (
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
    always #5 clk_i = ~clk_i;

    task automatic run_cmd(
        input  hdec_op_t op,
        input  logic [63:0] operand,
        output logic [63:0] result
    );
        begin
            result = '0;
            @(posedge clk_i);
            while (!ready_o) @(posedge clk_i);
            operator_i  <= op;
            operand_a_i <= operand;
            operand_b_i <= '0;
            valid_i     <= 1'b1;
            @(posedge clk_i);
            valid_i     <= 1'b0;
            while (!valid_o) @(posedge clk_i);
            result = result_o;
        end
    endtask

    task automatic run_cmd_count(
        input  hdec_op_t op,
        input  logic [63:0] operand,
        output logic [63:0] result,
        output int unsigned cycles
    );
        begin
            result = '0;
            cycles = 0;
            @(posedge clk_i);
            while (!ready_o) @(posedge clk_i);
            operator_i  <= op;
            operand_a_i <= operand;
            operand_b_i <= '0;
            valid_i     <= 1'b1;
            do begin
                @(posedge clk_i);
                cycles++;
                valid_i <= 1'b0;
            end while (!valid_o);
            result = result_o;
        end
    endtask

    task automatic set_vaddr(input logic [5:0] entry, input logic [1:0] bank);
        logic [63:0] ignored;
        begin
            run_cmd(HDEC_VADDR, {56'b0, bank, entry}, ignored);
        end
    endtask

    task automatic write_word(
        input logic [5:0]  entry,
        input logic [1:0]  bank,
        input logic [63:0] data
    );
        logic [63:0] ignored;
        begin
            set_vaddr(entry, bank);
            run_cmd(HDEC_VWR64, data, ignored);
        end
    endtask

    task automatic read_word(
        input  logic [5:0]  entry,
        input  logic [1:0]  bank,
        output logic [63:0] data
    );
        begin
            set_vaddr(entry, bank);
            run_cmd(HDEC_VRD64, '0, data);
        end
    endtask

    task automatic check_word(
        input string        label,
        input logic [5:0]   entry,
        input logic [1:0]   bank,
        input logic [63:0]  expected
    );
        logic [63:0] got;
        begin
            read_word(entry, bank, got);
            if (got !== expected) begin
                $error("%s mismatch entry=%0d bank=%0d got=0x%016h expected=0x%016h",
                       label, entry, bank, got, expected);
                $fatal(1);
            end
        end
    endtask

    task automatic load_vec0;
        begin
            write_word(6'd56, 2'd0, 64'h0123456789abcdef);
            write_word(6'd56, 2'd1, 64'h0f1e2d3c4b5a6978);
            write_word(6'd56, 2'd2, 64'hffeeddccbbaa9988);
            write_word(6'd56, 2'd3, 64'h13579bdf2468ace0);

            write_word(6'd57, 2'd0, 64'hfedcba9876543210);
            write_word(6'd57, 2'd1, 64'h8877665544332211);
            write_word(6'd57, 2'd2, 64'h1020304050607080);
            write_word(6'd57, 2'd3, 64'h0badf00ddeadbeef);
        end
    endtask

    task automatic check_vec0;
        begin
            check_word("vec0 W0", 6'd58, 2'd0, 64'h40a0789828c810f0);
            check_word("vec0 W1", 6'd58, 2'd1, 64'hfde4b5ff0a349a2f);
            check_word("vec0 W2", 6'd58, 2'd2, 64'h3187383a526053ff);
            check_word("vec0 W3", 6'd58, 2'd3, 64'h94139be965f097c0);
            check_word("vec0 W4", 6'd59, 2'd0, 64'had56b84f9ef99ee3);
            check_word("vec0 W5", 6'd59, 2'd1, 64'h3d322526689d8fbf);
            check_word("vec0 W6", 6'd59, 2'd2, 64'h178aa7f9f467274f);
            check_word("vec0 W7", 6'd59, 2'd3, 64'h00a44fd84fb9a443);
        end
    endtask

    initial begin
        logic [63:0] status;
        int unsigned cycles;

        valid_i     = 1'b0;
        operator_i  = HDEC_VWR64;
        operand_a_i = '0;
        operand_b_i = '0;
        rst_ni      = 1'b0;

        repeat (8) @(posedge clk_i);
        rst_ni = 1'b1;
        repeat (300) @(posedge clk_i);

        load_vec0();
        run_cmd_count(HDEC_ECC_MUL, {46'b0, 6'd58, 6'd56, 6'd57}, status, cycles);
        if (status[1:0] !== STATUS_OK) begin
            $error("ECC_MUL returned bad status 0x%016h", status);
            $fatal(1);
        end
        check_vec0();

        $display("ECC_MUL_CYCLES=%0d", cycles);
        $display("[HDEC_ECC_MUL_CYCLE_COUNT] PASS");
        $finish;
    end

endmodule
