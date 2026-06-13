module tb_hdec_ecc_add_v1;
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

    logic [3:0][63:0] vec_a;
    logic [3:0][63:0] vec_b;

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
    always #2.5 clk_i = ~clk_i;

    function automatic logic [63:0] ecc_add_operand(
        input logic [5:0] dst_idx,
        input logic [5:0] src_a_idx,
        input logic [5:0] src_b_idx
    );
        begin
            ecc_add_operand = {46'd0, dst_idx, src_a_idx, src_b_idx};
        end
    endfunction

    task automatic issue(input hdec_op_t op,
                         input logic [63:0] a,
                         output logic [63:0] result);
        begin
            while (!ready_o) @(posedge clk_i);
            @(posedge clk_i);
            valid_i     <= 1'b1;
            operator_i  <= op;
            operand_a_i <= a;
            operand_b_i <= '0;
            @(posedge clk_i);
            valid_i     <= 1'b0;
            operator_i  <= HDEC_VWR64;
            operand_a_i <= '0;
            operand_b_i <= '0;

            result = 'x;
            for (int cycles = 0; cycles < 1000; cycles++) begin
                @(posedge clk_i);
                #1;
                if (valid_o) begin
                    result = result_o;
                    return;
                end
            end
            $fatal(1, "Timeout waiting for op %0d", op);
        end
    endtask

    task automatic write_vrf64(input logic [1:0] bank,
                               input logic [5:0] idx,
                               input logic [63:0] data);
        logic [63:0] ignored;
        begin
            issue(HDEC_VADDR, {56'd0, bank, idx}, ignored);
            issue(HDEC_VWR64, data, ignored);
        end
    endtask

    task automatic read_vrf64(input logic [1:0] bank,
                              input logic [5:0] idx,
                              output logic [63:0] data);
        logic [63:0] ignored;
        begin
            issue(HDEC_VADDR, {56'd0, bank, idx}, ignored);
            issue(HDEC_VRD64, '0, data);
        end
    endtask

    task automatic load_entry(input logic [5:0] idx,
                              input logic [3:0][63:0] value);
        begin
            for (int bank = 0; bank < 4; bank++)
                write_vrf64(2'(bank), idx, value[bank]);
        end
    endtask

    task automatic check_entry_xor(input logic [5:0] idx,
                                   input logic [3:0][63:0] lhs,
                                   input logic [3:0][63:0] rhs);
        logic [63:0] got;
        begin
            for (int bank = 0; bank < 4; bank++) begin
                read_vrf64(2'(bank), idx, got);
                if (got !== (lhs[bank] ^ rhs[bank])) begin
                    $error("ECC_ADD bank=%0d got=0x%016h expected=0x%016h",
                           bank, got, lhs[bank] ^ rhs[bank]);
                    $fatal(1);
                end
            end
        end
    endtask

    initial begin
        logic [63:0] status;

        valid_i = 1'b0;
        operator_i = HDEC_VWR64;
        operand_a_i = '0;
        operand_b_i = '0;
        rst_ni = 1'b0;
        repeat (8) @(posedge clk_i);
        rst_ni = 1'b1;
        repeat (80) @(posedge clk_i);

        vec_a[0] = 64'h0123_4567_89ab_cdef;
        vec_a[1] = 64'hf0e1_d2c3_b4a5_9687;
        vec_a[2] = 64'h1357_9bdf_2468_ace0;
        vec_a[3] = 64'h0f1e_2d3c_4b5a_6978;
        vec_b[0] = 64'hdead_beef_cafe_babe;
        vec_b[1] = 64'h1122_3344_5566_7788;
        vec_b[2] = 64'ha5a5_5a5a_3c3c_c3c3;
        vec_b[3] = 64'h55aa_33cc_0ff0_f00f;

        load_entry(6'd20, vec_a);
        load_entry(6'd21, vec_b);

        issue(HDEC_ECC_ADD, ecc_add_operand(6'd22, 6'd20, 6'd21), status);
        if (status[1:0] !== STATUS_OK)
            $fatal(1, "ECC_ADD returned bad status 0x%016h", status);
        check_entry_xor(6'd22, vec_a, vec_b);

        issue(HDEC_ECC_ADD, ecc_add_operand(6'd20, 6'd20, 6'd21), status);
        if (status[1:0] !== STATUS_OK)
            $fatal(1, "ECC_ADD inplace returned bad status 0x%016h", status);
        check_entry_xor(6'd20, vec_a, vec_b);

        $display("[HDEC_ECC_ADD_V1] PASS");
        $finish;
    end
endmodule
