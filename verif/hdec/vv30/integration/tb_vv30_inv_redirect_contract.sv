module tb_vv30_inv_redirect_contract;
    import hdec_pkg::*;

    localparam int MAX_CASES = 64;

    logic clk_i;
    logic rst_ni;

    logic valid_on;
    logic ready_on;
    hdec_op_t operator_on;
    logic [63:0] operand_a_on;
    logic [63:0] operand_b_on;
    logic valid_o_on;
    logic [63:0] result_o_on;

    logic valid_off;
    logic ready_off;
    hdec_op_t operator_off;
    logic [63:0] operand_a_off;
    logic [63:0] operand_b_off;
    logic valid_o_off;
    logic [63:0] result_o_off;

    logic [255:0] inv_inputs   [0:MAX_CASES-1];
    logic [255:0] inv_expected [0:MAX_CASES-1];
    logic [31:0]  inv_count_mem [0:0];
    logic [255:0] master_seed_mem [0:0];

    int unsigned error_count;

    hdec_top #(
        .ECC_DEBUG_FIELD_OPS(1'b1),
        .ECC_INV_SQUARE_REDIRECT(1'b1)
    ) dut_on (
        .clk_i,
        .rst_ni,
        .valid_i(valid_on),
        .ready_o(ready_on),
        .operator_i(operator_on),
        .operand_a_i(operand_a_on),
        .operand_b_i(operand_b_on),
        .valid_o(valid_o_on),
        .result_o(result_o_on)
    );

    hdec_top #(
        .ECC_DEBUG_FIELD_OPS(1'b1),
        .ECC_INV_SQUARE_REDIRECT(1'b0)
    ) dut_off (
        .clk_i,
        .rst_ni,
        .valid_i(valid_off),
        .ready_o(ready_off),
        .operator_i(operator_off),
        .operand_a_i(operand_a_off),
        .operand_b_i(operand_b_off),
        .valid_o(valid_o_off),
        .result_o(result_o_off)
    );

    initial clk_i = 1'b0;
    always #2.5 clk_i = ~clk_i;

    function automatic logic [63:0] ecc_inv_operand(
        input logic [5:0] dst_idx,
        input logic [5:0] src_idx
    );
        ecc_inv_operand = (64'h1 << 31)
                        | ({58'd0, dst_idx} << 12)
                        | {58'd0, src_idx};
    endfunction

    task automatic issue_both(
        input hdec_op_t op,
        input logic [63:0] operand,
        output logic [63:0] result_on,
        output logic [63:0] result_off,
        output int unsigned cycles_on,
        output int unsigned cycles_off
    );
        bit seen_on;
        bit seen_off;
        begin
            while (!(ready_on && ready_off))
                @(posedge clk_i);
            @(posedge clk_i);
            valid_on      <= 1'b1;
            valid_off     <= 1'b1;
            operator_on   <= op;
            operator_off  <= op;
            operand_a_on  <= operand;
            operand_a_off <= operand;
            operand_b_on  <= '0;
            operand_b_off <= '0;
            @(posedge clk_i);
            valid_on      <= 1'b0;
            valid_off     <= 1'b0;
            operator_on   <= HDEC_VWR64;
            operator_off  <= HDEC_VWR64;
            operand_a_on  <= '0;
            operand_a_off <= '0;

            result_on  = 'x;
            result_off = 'x;
            cycles_on  = 0;
            cycles_off = 0;
            seen_on    = 1'b0;
            seen_off   = 1'b0;
            for (int unsigned cycle_idx = 1;
                 cycle_idx <= 140000 && !(seen_on && seen_off);
                 cycle_idx++) begin
                @(posedge clk_i);
                #1;
                if (!seen_on && valid_o_on) begin
                    result_on = result_o_on;
                    cycles_on = cycle_idx;
                    seen_on = 1'b1;
                end
                if (!seen_off && valid_o_off) begin
                    result_off = result_o_off;
                    cycles_off = cycle_idx;
                    seen_off = 1'b1;
                end
            end
            if (!(seen_on && seen_off))
                $fatal(1, "[VV30:inv_redirect_contract] timeout op=%0d", op);
        end
    endtask

    task automatic write_vrf64_both(
        input logic [1:0] bank,
        input logic [5:0] row,
        input logic [63:0] data
    );
        logic [63:0] ignored_on;
        logic [63:0] ignored_off;
        int unsigned ignored_cycles_on;
        int unsigned ignored_cycles_off;
        begin
            issue_both(
                HDEC_VADDR, {56'd0, bank, row},
                ignored_on, ignored_off,
                ignored_cycles_on, ignored_cycles_off
            );
            issue_both(
                HDEC_VWR64, data,
                ignored_on, ignored_off,
                ignored_cycles_on, ignored_cycles_off
            );
        end
    endtask

    task automatic read_vrf64_both(
        input logic [1:0] bank,
        input logic [5:0] row,
        output logic [63:0] data_on,
        output logic [63:0] data_off
    );
        logic [63:0] ignored_on;
        logic [63:0] ignored_off;
        int unsigned ignored_cycles_on;
        int unsigned ignored_cycles_off;
        begin
            issue_both(
                HDEC_VADDR, {56'd0, bank, row},
                ignored_on, ignored_off,
                ignored_cycles_on, ignored_cycles_off
            );
            issue_both(
                HDEC_VRD64, '0,
                data_on, data_off,
                ignored_cycles_on, ignored_cycles_off
            );
        end
    endtask

    task automatic write_row_both(
        input logic [5:0] row,
        input logic [255:0] value
    );
        begin
            for (int unsigned bank = 0; bank < 4; bank++)
                write_vrf64_both(bank[1:0], row, value[bank*64 +: 64]);
        end
    endtask

    task automatic read_row_both(
        input logic [5:0] row,
        output logic [255:0] value_on,
        output logic [255:0] value_off
    );
        begin
            for (int unsigned bank = 0; bank < 4; bank++)
                read_vrf64_both(
                    bank[1:0], row,
                    value_on[bank*64 +: 64],
                    value_off[bank*64 +: 64]
                );
        end
    endtask

    initial begin
        logic [63:0] status_on;
        logic [63:0] status_off;
        logic [255:0] got_on;
        logic [255:0] got_off;
        int unsigned cycles_on;
        int unsigned cycles_off;
        int signed first_delta;
        int signed delta;
        int unsigned case_count;

        $readmemh("inv_count.mem", inv_count_mem);
        $readmemh("inv_inputs.mem", inv_inputs);
        $readmemh("inv_expected.mem", inv_expected);
        $readmemh("master_seed.mem", master_seed_mem);
        case_count = inv_count_mem[0];
        if (case_count == 0 || case_count > MAX_CASES)
            $fatal(1, "[VV30:inv_redirect_contract] invalid case_count=%0d",
                   case_count);

        error_count  = 0;
        first_delta  = -1;
        rst_ni       = 1'b0;
        valid_on     = 1'b0;
        valid_off    = 1'b0;
        operator_on  = HDEC_VWR64;
        operator_off = HDEC_VWR64;
        operand_a_on = '0;
        operand_a_off = '0;
        operand_b_on = '0;
        operand_b_off = '0;

        repeat (8) @(posedge clk_i);
        rst_ni = 1'b1;
        repeat (20) @(posedge clk_i);

        for (int unsigned case_idx = 0;
             case_idx < case_count;
             case_idx++) begin
            if (inv_inputs[case_idx] == 0
                || inv_inputs[case_idx][255:233] != '0)
                $fatal(1,
                    "[VV30:inv_redirect_contract] invalid input case=%0d",
                    case_idx);
            write_row_both(6'd24, inv_inputs[case_idx]);
            issue_both(
                HDEC_ECC_STATUS, ecc_inv_operand(6'd26, 6'd24),
                status_on, status_off, cycles_on, cycles_off
            );
            if (status_on[1:0] !== STATUS_OK
                || status_off[1:0] !== STATUS_OK) begin
                error_count++;
                $error(
                    "[VV30:inv_redirect_contract] bad status case=%0d on=%h off=%h",
                    case_idx, status_on, status_off
                );
            end
            read_row_both(6'd26, got_on, got_off);
            if (got_on !== inv_expected[case_idx]
                || got_off !== inv_expected[case_idx]
                || got_on !== got_off) begin
                error_count++;
                $error(
                    "[VV30:inv_redirect_contract] mismatch case=%0d seed=%064h input=%064h on=%064h off=%064h expected=%064h",
                    case_idx, master_seed_mem[0], inv_inputs[case_idx],
                    got_on, got_off, inv_expected[case_idx]
                );
            end
            delta = $signed(cycles_off) - $signed(cycles_on);
            if (first_delta < 0)
                first_delta = delta;
            if (delta <= 0 || delta != first_delta) begin
                error_count++;
                $error(
                    "[VV30:inv_redirect_contract] cycle delta case=%0d on=%0d off=%0d delta=%0d expected_delta=%0d",
                    case_idx, cycles_on, cycles_off, delta, first_delta
                );
            end
            $display(
                "[VV30:INV_REDIRECT_CYCLE] case=%0d input_weight=%0d on=%0d off=%0d delta=%0d",
                case_idx, $countones(inv_inputs[case_idx]),
                cycles_on, cycles_off, delta
            );
        end

        $display(
            "[VV30:COVERAGE] test=inv_redirect_contract observed=%0d expected=%0d",
            case_count, case_count
        );
        if (error_count == 0)
            $display(
                "[VV30:inv_redirect_contract] PASS cases=%0d delta=%0d",
                case_count, first_delta
            );
        else
            $fatal(1,
                "[VV30:inv_redirect_contract] FAIL errors=%0d seed=%064h",
                error_count, master_seed_mem[0]
            );
        $finish;
    end
endmodule
