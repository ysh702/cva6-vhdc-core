module tb_vv30_gfmac_tail_fusion;
    import hdec_pkg::*;
    import hdec_vv30_ref_pkg::*;

    localparam int MAX_RANDOM_CASES = 8192;
    localparam logic [1:0] STATUS_OK = 2'b00;

    logic clk_i;
    logic rst_ni;
    logic valid_i;
    logic ready_o;
    hdec_op_t operator_i;
    logic [63:0] operand_a_i;
    logic [63:0] operand_b_i;
    logic valid_o;
    logic [63:0] result_o;

    logic [31:0] random_count_mem [0:0];
    logic [255:0] master_seed_mem [0:0];
    logic [255:0] operand_a_mem [0:MAX_RANDOM_CASES-1];
    logic [255:0] operand_b_mem [0:MAX_RANDOM_CASES-1];
    logic [255:0] accumulator_mem [0:MAX_RANDOM_CASES-1];
    logic [255:0] expected_mem [0:MAX_RANDOM_CASES-1];

    bit monitor_gfmac;
    int unsigned gfmac_tmp_writes;
    int unsigned gfmac_acc_writes;

    hdec_top #(
        .ECC_DEBUG_FIELD_OPS(1'b1)
    ) dut (
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

    always_ff @(posedge clk_i) begin
        if (!rst_ni) begin
            gfmac_tmp_writes <= 0;
            gfmac_acc_writes <= 0;
        end else if (monitor_gfmac && (|dut.vrf_we)) begin
            if (dut.vrf_wa == 6'd40)
                gfmac_tmp_writes <= gfmac_tmp_writes + 1;
            if (dut.vrf_wa == 6'd42)
                gfmac_acc_writes <= gfmac_acc_writes + 1;
        end
    end

    function automatic logic [63:0] gfmul_operand(
        input logic [5:0] dst_idx,
        input logic [5:0] src_a_idx,
        input logic [5:0] src_b_idx
    );
        begin
            gfmul_operand = {46'd0, dst_idx, src_a_idx, src_b_idx}
                          | (64'h1 << 31);
        end
    endfunction

    function automatic logic [63:0] gfmac_operand(
        input logic [5:0] acc_dst_idx,
        input logic [5:0] tmp_idx,
        input logic [5:0] src_a_idx,
        input logic [5:0] src_b_idx
    );
        begin
            gfmac_operand = {46'd0, tmp_idx, src_a_idx, src_b_idx}
                          | ({58'd0, acc_dst_idx} << 18)
                          | (64'h1 << 32);
        end
    endfunction

    task automatic issue_counted(
        input hdec_op_t op,
        input logic [63:0] operand,
        output logic [63:0] result,
        output int unsigned cycles
    );
        bit seen;
        begin
            while (!ready_o)
                @(posedge clk_i);
            @(posedge clk_i);
            valid_i     <= 1'b1;
            operator_i  <= op;
            operand_a_i <= operand;
            operand_b_i <= '0;
            @(posedge clk_i);
            valid_i     <= 1'b0;
            operator_i  <= HDEC_VWR64;
            operand_a_i <= '0;
            operand_b_i <= '0;

            result = 'x;
            cycles = 0;
            seen = 1'b0;
            while ((cycles < 4096) && !seen) begin
                @(posedge clk_i);
                #1;
                cycles++;
                if (valid_o) begin
                    result = result_o;
                    seen = 1'b1;
                end
            end
            if (!seen)
                $fatal(1,
                    "[VV30:gfmac_tail_fusion] timeout op=%0d", op);
        end
    endtask

    task automatic issue(
        input hdec_op_t op,
        input logic [63:0] operand,
        output logic [63:0] result
    );
        int unsigned ignored_cycles;
        begin
            issue_counted(op, operand, result, ignored_cycles);
        end
    endtask

    task automatic write_vrf64(
        input logic [1:0] bank,
        input logic [5:0] row,
        input logic [63:0] data
    );
        logic [63:0] ignored;
        begin
            issue(HDEC_VADDR, {56'd0, bank, row}, ignored);
            issue(HDEC_VWR64, data, ignored);
        end
    endtask

    task automatic read_vrf64(
        input logic [1:0] bank,
        input logic [5:0] row,
        output logic [63:0] data
    );
        logic [63:0] ignored;
        begin
            issue(HDEC_VADDR, {56'd0, bank, row}, ignored);
            issue(HDEC_VRD64, '0, data);
        end
    endtask

    task automatic write_row(
        input logic [5:0] row,
        input logic [255:0] value
    );
        begin
            write_vrf64(2'd0, row, value[63:0]);
            write_vrf64(2'd1, row, value[127:64]);
            write_vrf64(2'd2, row, value[191:128]);
            write_vrf64(2'd3, row, value[255:192]);
        end
    endtask

    task automatic read_row(
        input logic [5:0] row,
        output logic [255:0] value
    );
        begin
            read_vrf64(2'd0, row, value[63:0]);
            read_vrf64(2'd1, row, value[127:64]);
            read_vrf64(2'd2, row, value[191:128]);
            read_vrf64(2'd3, row, value[255:192]);
        end
    endtask

    initial begin
        int unsigned random_count;
        int unsigned mul_cycles;
        int unsigned mac_cycles;
        int unsigned reference_mul_cycles;
        int unsigned reference_mac_cycles;
        logic [63:0] status;
        logic [255:0] got;
        logic [232:0] independent_product;

        $readmemh("random_count.mem", random_count_mem);
        $readmemh("master_seed.mem", master_seed_mem);
        $readmemh("gf_a_inputs.mem", operand_a_mem);
        $readmemh("gf_b_inputs.mem", operand_b_mem);
        $readmemh("gf_acc_inputs.mem", accumulator_mem);
        $readmemh("gf_mac_expected.mem", expected_mem);
        random_count = random_count_mem[0];
        if ((random_count == 0) || (random_count > MAX_RANDOM_CASES))
            $fatal(1,
                "[VV30:gfmac_tail_fusion] invalid random count %0d",
                random_count);

        valid_i = 1'b0;
        operator_i = HDEC_VWR64;
        operand_a_i = '0;
        operand_b_i = '0;
        monitor_gfmac = 1'b0;
        reference_mul_cycles = 0;
        reference_mac_cycles = 0;
        rst_ni = 1'b0;
        repeat (8)
            @(posedge clk_i);
        rst_ni = 1'b1;
        repeat (120)
            @(posedge clk_i);

        for (int case_idx = 0; case_idx < random_count; case_idx++) begin
            if ((|operand_a_mem[case_idx][255:233])
                || (|operand_b_mem[case_idx][255:233])
                || (|accumulator_mem[case_idx][255:233])
                || (|expected_mem[case_idx][255:233]))
                $fatal(1,
                    "[VV30:gfmac_tail_fusion] high padding is nonzero case=%0d",
                    case_idx);

            independent_product = vv30_gf233_mul(
                operand_a_mem[case_idx][232:0],
                operand_b_mem[case_idx][232:0]
            );
            if (expected_mem[case_idx][232:0]
                !== (accumulator_mem[case_idx][232:0]
                     ^ independent_product))
                $fatal(1,
                    "[VV30:gfmac_tail_fusion] vector/golden mismatch case=%0d",
                    case_idx);

            write_row(6'd24, operand_a_mem[case_idx]);
            write_row(6'd25, operand_b_mem[case_idx]);
            write_row(6'd42, accumulator_mem[case_idx]);
            write_row(6'd40, 256'h1);

            issue_counted(
                HDEC_ECC_MUL,
                gfmul_operand(6'd30, 6'd24, 6'd25),
                status,
                mul_cycles
            );
            if (status[1:0] !== STATUS_OK)
                $fatal(1,
                    "[VV30:gfmac_tail_fusion] GFMUL status=%016h case=%0d",
                    status, case_idx);
            read_row(6'd30, got);
            if (got !== {23'd0, independent_product})
                $fatal(1,
                    "[VV30:gfmac_tail_fusion] GFMUL mismatch case=%0d got=%064h expected=%064h",
                    case_idx, got, {23'd0, independent_product});

            monitor_gfmac = 1'b1;
            issue_counted(
                HDEC_ECC_MUL,
                gfmac_operand(6'd42, 6'd40, 6'd24, 6'd25),
                status,
                mac_cycles
            );
            monitor_gfmac = 1'b0;
            if (status[1:0] !== STATUS_OK)
                $fatal(1,
                    "[VV30:gfmac_tail_fusion] GFMAC status=%016h case=%0d",
                    status, case_idx);
            read_row(6'd42, got);
            if (got !== expected_mem[case_idx])
                $fatal(1,
                    "[VV30:gfmac_tail_fusion] GFMAC mismatch case=%0d got=%064h expected=%064h",
                    case_idx, got, expected_mem[case_idx]);

            if (case_idx == 0) begin
                reference_mul_cycles = mul_cycles;
                reference_mac_cycles = mac_cycles;
            end else if ((mul_cycles != reference_mul_cycles)
                         || (mac_cycles != reference_mac_cycles)) begin
                $fatal(1,
                    "[VV30:gfmac_tail_fusion] data-dependent cycles case=%0d mul=%0d/%0d mac=%0d/%0d",
                    case_idx, mul_cycles, reference_mul_cycles,
                    mac_cycles, reference_mac_cycles);
            end
        end

        $display(
            "[VV30:GFMAC_METRICS] seed=%064h cases=%0d gfmul_cycles=%0d gfmac_cycles=%0d delta=%0d tmp_writes=%0d acc_writes=%0d",
            master_seed_mem[0], random_count,
            reference_mul_cycles, reference_mac_cycles,
            $signed(reference_mac_cycles) - $signed(reference_mul_cycles),
            gfmac_tmp_writes, gfmac_acc_writes
        );
        $display(
            "[VV30:COVERAGE] test=gfmac_tail_fusion observed=%0d expected=%0d",
            random_count, random_count
        );
        $display("[VV30:gfmac_tail_fusion] PASS");
        $finish;
    end
endmodule
