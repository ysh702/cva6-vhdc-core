`timescale 1ns/1ps

module tb_vv35_board_schedule_controller;
    logic clk_i = 1'b0;
    logic board_rst_ni = 1'b0;
    logic [1:0] run_mode_i = 2'd0;
    logic start_i = 1'b0;
    logic idle_o;
    logic busy_o;
    logic done_o;
    logic pass_o;
    logic fail_o;
    logic metric_active_o;
    logic [31:0] measured_cycles_o;
    logic [31:0] hmatch_completion_cycles_o;
    logic [31:0] hmatch_completed_o;
    logic [31:0] error_count_o;
    logic [31:0] error_code_o;
    logic [63:0] last_hmatch_o;
    logic [63:0] final_status_o;
    logic [31:0] preload_count_o;
    logic [7:0] phase_o;

    always #2.5 clk_i = ~clk_i;

    vv35_board_schedule_controller dut (.*);

    task automatic run_scenario(input logic [1:0] mode,
                                input string label);
        int unsigned waited;
        begin
            run_mode_i = mode;
            start_i = 1'b1;
            waited = 0;
            while (!done_o && (waited < 3_000_000)) begin
                @(posedge clk_i);
                waited++;
            end
            if (!done_o)
                $fatal(1, "[VV35:BOARD_CTRL] %0s timeout phase=%0d hmatch=%0d",
                       label, phase_o, hmatch_completed_o);
            $display("[VV35:BOARD_CTRL_METRIC] scenario=%0s window_cycles=%0d hmatch_completion_cycles=%0d hmatch=%0d preload=%0d pass=%0d fail=%0d errors=%0d error_code=%08h last_hmatch=%016h final_status=%016h",
                     label, measured_cycles_o, hmatch_completion_cycles_o,
                     hmatch_completed_o,
                     preload_count_o, pass_o, fail_o, error_count_o,
                     error_code_o, last_hmatch_o, final_status_o);
            if (!pass_o || fail_o || (error_count_o != 0)
                    || (hmatch_completed_o != 1632)
                    || (preload_count_o != 112)
                    || ((mode == 2'd0) && (measured_cycles_o != 337853))
                    || ((mode == 2'd1) && (measured_cycles_o != 200144))
                    || (last_hmatch_o != 64'h0000_0000_0000_01f9)
                    || (final_status_o[3:0] != 4'b1000))
                $fatal(1, "[VV35:BOARD_CTRL] %0s FAIL", label);
            start_i = 1'b0;
            wait (idle_o);
            repeat (4) @(posedge clk_i);
        end
    endtask

    initial begin
        repeat (8) @(posedge clk_i);
        board_rst_ni = 1'b1;
        repeat (8) @(posedge clk_i);

        run_scenario(2'd1, "INTERLEAVED");
        run_scenario(2'd0, "SERIAL");

        $display("[VV35:BOARD_CTRL] PASS");
        $finish;
    end
endmodule
