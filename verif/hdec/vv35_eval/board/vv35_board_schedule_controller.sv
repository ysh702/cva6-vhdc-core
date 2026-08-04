// Synthesizable standalone-board endpoint for the frozen VV35 workload.
//
// The controller intentionally uses only hdec_top's public request/response
// interface.  SERIAL, INTERLEAVED, and CLOCKED_IDLE use the same image and
// frozen preload table; only the foreground HMATCH release policy changes.
module vv35_board_schedule_controller import hdec_pkg::*; (
    input  logic        clk_i,
    input  logic        board_rst_ni,
    input  logic [1:0]  run_mode_i,
    input  logic        start_i,
    output logic        idle_o,
    output logic        busy_o,
    output logic        done_o,
    output logic        pass_o,
    output logic        fail_o,
    output logic        metric_active_o,
    output logic [31:0] measured_cycles_o,
    output logic [31:0] hmatch_completion_cycles_o,
    output logic [31:0] hmatch_completed_o,
    output wire  [31:0] error_count_o,
    output logic [31:0] error_code_o,
    output logic [63:0] last_hmatch_o,
    output logic [63:0] final_status_o,
    output logic [31:0] preload_count_o,
    output logic [7:0]  phase_o
);
    localparam logic [1:0] MODE_SERIAL      = 2'd0;
    localparam logic [1:0] MODE_INTERLEAVED = 2'd1;
    localparam logic [1:0] MODE_IDLE        = 2'd2;

    localparam int unsigned VV35_HMATCH_COUNT          = 1632;
    localparam int unsigned VV35_PMUL_WAIT_CYCLES      = 146908;
    // The registered board request engine needs three cycles from release to
    // the first accepting edge.  Release three cycles early so the accepted
    // SERIAL HMATCH still begins at the frozen 146908-cycle boundary.
    localparam int unsigned VV35_SERIAL_LAUNCH_COMPENSATION = 3;
    localparam int unsigned VV35_SERIAL_WINDOW_CYCLES  = 337853;
    localparam int unsigned VV35_INTERLEAVED_WINDOW_CYCLES = 200144;
    localparam int unsigned VV35_IDLE_WINDOW_CYCLES    = 2_000_000;
    localparam int unsigned VV35_COMMAND_TIMEOUT_CYCLES = 2_000_000;

`include "vv35_board_preload.svh"

    typedef enum logic [3:0] {
        PH_IDLE,
        PH_DUT_RESET,
        PH_DUT_SETTLE,
        PH_PRELOAD,
        PH_PMUL_START,
        PH_SERIAL_WAIT,
        PH_HMATCH,
        PH_WINDOW_WAIT,
        PH_FINAL_STATUS,
        PH_CHECK_ADDR,
        PH_CHECK_READ,
        PH_IDLE_WINDOW,
        PH_DONE
    } phase_e;

    typedef enum logic [1:0] {
        CMD_IDLE,
        CMD_WAIT_ACCEPT,
        CMD_WAIT_RESPONSE
    } cmd_state_e;

    phase_e     phase_q;
    cmd_state_e cmd_state_q;
    logic [1:0] mode_q;
    logic       start_seen_q;
    logic       dut_rst_ni;
    logic [7:0] reset_count_q;
    logic [6:0] preload_index_q;
    logic       preload_data_q;
    logic [2:0] check_row_q;
    logic [1:0] check_bank_q;
    logic [31:0] metric_cycles_q;
    logic [7:0]  error_count_q;

    logic        valid_i;
    logic        ready_o;
    hdec_op_t    operator_i;
    logic [63:0] operand_a_i;
    logic [63:0] operand_b_i;
    logic        valid_o;
    logic [63:0] result_o;

    logic        cmd_launch_q;
    hdec_op_t    cmd_request_op_q;
    logic [63:0] cmd_request_operand_q;
    logic        cmd_done_q;
    logic        cmd_timeout_q;
    logic [63:0] cmd_result_q;
    logic [31:0] cmd_wait_q;

    (* DONT_TOUCH = "yes", keep_hierarchy = "yes" *)
    hdec_top i_hdec_top (
        .clk_i,
        .rst_ni     (dut_rst_ni),
        .valid_i,
        .ready_o,
        .operator_i,
        .operand_a_i,
        .operand_b_i,
        .valid_o,
        .result_o
    );

    function automatic logic [5:0] vv35_check_row_number(
        input logic [2:0] row_select
    );
        unique case (row_select)
            3'd0: vv35_check_row_number = 6'd4;
            3'd1: vv35_check_row_number = 6'd5;
            3'd2: vv35_check_row_number = 6'd3;
            3'd3: vv35_check_row_number = 6'd6;
            default: vv35_check_row_number = 6'd7;
        endcase
    endfunction

    function automatic logic [63:0] vv35_expected_check_word(
        input logic [2:0] row_select,
        input logic [1:0] bank
    );
        logic [255:0] row_value;
        begin
            unique case (row_select)
                3'd0: row_value = VV35_EXPECTED_X;
                3'd1: row_value = VV35_EXPECTED_Y;
                3'd2: row_value = VV35_GUARD3;
                3'd3: row_value = VV35_GUARD6;
                default: row_value = VV35_GUARD7;
            endcase
            unique case (bank)
                2'd0: vv35_expected_check_word = row_value[63:0];
                2'd1: vv35_expected_check_word = row_value[127:64];
                2'd2: vv35_expected_check_word = row_value[191:128];
                default: vv35_expected_check_word = row_value[255:192];
            endcase
        end
    endfunction

    function automatic logic [7:0] vv35_increment_error(
        input logic [7:0] value
    );
        vv35_increment_error = (&value) ? value : value + 8'd1;
    endfunction

    assign idle_o  = (phase_q == PH_IDLE);
    assign busy_o  = (phase_q != PH_IDLE) && (phase_q != PH_DONE);
    assign phase_o = {4'd0, phase_q};
    assign error_count_o = {24'd0, error_count_q};

    // Public-interface request engine.  Driving and sampling on the positive
    // edge gives all controller-to-HDEC paths one full board clock period.
    always_ff @(posedge clk_i or negedge board_rst_ni) begin
        if (!board_rst_ni) begin
            valid_i          <= 1'b0;
            operator_i       <= HDEC_VWR64;
            operand_a_i      <= 64'd0;
            operand_b_i      <= 64'd0;
            cmd_state_q      <= CMD_IDLE;
            cmd_done_q       <= 1'b0;
            cmd_timeout_q    <= 1'b0;
            cmd_result_q     <= 64'd0;
            cmd_wait_q       <= 32'd0;
        end else if (!dut_rst_ni) begin
            valid_i          <= 1'b0;
            operator_i       <= HDEC_VWR64;
            operand_a_i      <= 64'd0;
            operand_b_i      <= 64'd0;
            cmd_state_q      <= CMD_IDLE;
            cmd_done_q       <= 1'b0;
            cmd_timeout_q    <= 1'b0;
            cmd_result_q     <= 64'd0;
            cmd_wait_q       <= 32'd0;
        end else begin
            cmd_done_q    <= 1'b0;
            cmd_timeout_q <= 1'b0;
            unique case (cmd_state_q)
                CMD_IDLE: begin
                    valid_i     <= 1'b0;
                    operator_i  <= HDEC_VWR64;
                    operand_a_i <= 64'd0;
                    operand_b_i <= 64'd0;
                    cmd_wait_q  <= 32'd0;
                    if (cmd_launch_q) begin
                        valid_i     <= 1'b1;
                        operator_i  <= cmd_request_op_q;
                        operand_a_i <= cmd_request_operand_q;
                        cmd_state_q <= CMD_WAIT_ACCEPT;
                    end
                end

                CMD_WAIT_ACCEPT: begin
                    valid_i    <= 1'b1;
                    cmd_wait_q <= cmd_wait_q + 32'd1;
                    if (ready_o) begin
                        valid_i     <= 1'b0;
                        operator_i  <= HDEC_VWR64;
                        operand_a_i <= 64'd0;
                        if (valid_o) begin
                            cmd_result_q <= result_o;
                            cmd_done_q   <= 1'b1;
                            cmd_state_q  <= CMD_IDLE;
                        end else begin
                            cmd_state_q <= CMD_WAIT_RESPONSE;
                        end
                    end else if (cmd_wait_q >= VV35_COMMAND_TIMEOUT_CYCLES - 1) begin
                        valid_i       <= 1'b0;
                        cmd_timeout_q <= 1'b1;
                        cmd_state_q   <= CMD_IDLE;
                    end
                end

                CMD_WAIT_RESPONSE: begin
                    valid_i    <= 1'b0;
                    cmd_wait_q <= cmd_wait_q + 32'd1;
                    if (valid_o) begin
                        cmd_result_q <= result_o;
                        cmd_done_q   <= 1'b1;
                        // Match the frozen gate BFM: after a foreground
                        // HMATCH response, present the next HMATCH for the
                        // immediately following accepting edge.  Returning
                        // through CMD_IDLE/cmd_launch would insert exactly
                        // three controller-only cycles per operation.
                        if ((phase_q == PH_HMATCH)
                                && (hmatch_completed_o
                                    < VV35_HMATCH_COUNT - 1)) begin
                            valid_i     <= 1'b1;
                            operator_i  <= HDEC_HMATCH;
                            operand_a_i <= VV35_HMATCH_OPERAND;
                            operand_b_i <= 64'd0;
                            cmd_wait_q  <= 32'd0;
                            cmd_state_q <= CMD_WAIT_ACCEPT;
                        end else begin
                            cmd_state_q <= CMD_IDLE;
                        end
                    end else if (cmd_wait_q >= VV35_COMMAND_TIMEOUT_CYCLES - 1) begin
                        cmd_timeout_q <= 1'b1;
                        cmd_state_q   <= CMD_IDLE;
                    end
                end

                default: begin
                    valid_i       <= 1'b0;
                    cmd_timeout_q <= 1'b1;
                    cmd_state_q   <= CMD_IDLE;
                end
            endcase
        end
    end

    // Workload sequencer and result checker.
    always_ff @(posedge clk_i or negedge board_rst_ni) begin
        if (!board_rst_ni) begin
            phase_q             <= PH_IDLE;
            mode_q              <= MODE_SERIAL;
            start_seen_q        <= 1'b0;
            dut_rst_ni          <= 1'b0;
            reset_count_q       <= 8'd0;
            preload_index_q     <= 7'd0;
            preload_data_q      <= 1'b0;
            check_row_q         <= 3'd0;
            check_bank_q        <= 2'd0;
            metric_cycles_q     <= 32'd0;
            cmd_launch_q        <= 1'b0;
            cmd_request_op_q    <= HDEC_VWR64;
            cmd_request_operand_q <= 64'd0;
            done_o              <= 1'b0;
            pass_o              <= 1'b0;
            fail_o              <= 1'b0;
            metric_active_o     <= 1'b0;
            measured_cycles_o   <= 32'd0;
            hmatch_completion_cycles_o <= 32'd0;
            hmatch_completed_o  <= 32'd0;
            error_count_q       <= 8'd0;
            error_code_o        <= 32'd0;
            last_hmatch_o       <= 64'd0;
            final_status_o      <= 64'd0;
            preload_count_o     <= 32'd0;
        end else begin
            cmd_launch_q <= 1'b0;
            if (metric_active_o)
                metric_cycles_q <= metric_cycles_q + 32'd1;

            if (cmd_timeout_q) begin
                if (error_count_q == 0)
                    error_code_o <= {8'hf0, 16'd0, phase_o};
                error_count_q   <= vv35_increment_error(error_count_q);
                metric_active_o <= 1'b0;
                measured_cycles_o <= metric_cycles_q;
                done_o          <= 1'b1;
                pass_o          <= 1'b0;
                fail_o          <= 1'b1;
                phase_q         <= PH_DONE;
            end else begin
                unique case (phase_q)
                    PH_IDLE: begin
                        dut_rst_ni      <= 1'b0;
                        metric_active_o <= 1'b0;
                        if (!start_i)
                            start_seen_q <= 1'b0;
                        if (start_i && !start_seen_q) begin
                            start_seen_q        <= 1'b1;
                            mode_q              <= run_mode_i;
                            reset_count_q       <= 8'd0;
                            preload_index_q     <= 7'd0;
                            preload_data_q      <= 1'b0;
                            check_row_q         <= 3'd0;
                            check_bank_q        <= 2'd0;
                            metric_cycles_q     <= 32'd0;
                            measured_cycles_o   <= 32'd0;
                            hmatch_completion_cycles_o <= 32'd0;
                            hmatch_completed_o  <= 32'd0;
                            error_count_q       <= 8'd0;
                            error_code_o        <= 32'd0;
                            last_hmatch_o       <= 64'd0;
                            final_status_o      <= 64'd0;
                            preload_count_o     <= 32'd0;
                            done_o              <= 1'b0;
                            pass_o              <= 1'b0;
                            fail_o              <= 1'b0;
                            if (run_mode_i == 2'd3) begin
                                error_count_q <= 8'd1;
                                error_code_o  <= 32'h0100_0003;
                                done_o        <= 1'b1;
                                fail_o        <= 1'b1;
                                phase_q       <= PH_DONE;
                            end else begin
                                phase_q <= PH_DUT_RESET;
                            end
                        end
                    end

                    PH_DUT_RESET: begin
                        dut_rst_ni    <= 1'b0;
                        reset_count_q <= reset_count_q + 8'd1;
                        if (reset_count_q == 8'd15) begin
                            dut_rst_ni    <= 1'b1;
                            reset_count_q <= 8'd0;
                            phase_q       <= PH_DUT_SETTLE;
                        end
                    end

                    PH_DUT_SETTLE: begin
                        dut_rst_ni    <= 1'b1;
                        reset_count_q <= reset_count_q + 8'd1;
                        if (reset_count_q == 8'd39) begin
                            reset_count_q <= 8'd0;
                            phase_q       <= PH_PRELOAD;
                        end
                    end

                    PH_PRELOAD: begin
                        if (cmd_done_q) begin
                            if (cmd_result_q[1:0] != STATUS_OK) begin
                                error_count_q <= vv35_increment_error(error_count_q);
                                if (error_count_q == 0)
                                    error_code_o <= {8'h10, preload_data_q, 16'd0,
                                                     preload_index_q};
                            end
                            if (!preload_data_q) begin
                                preload_data_q <= 1'b1;
                            end else begin
                                preload_count_o <= preload_count_o + 32'd1;
                                preload_data_q  <= 1'b0;
                                if (preload_index_q == VV35_PRELOAD_PAIR_COUNT - 1) begin
                                    if (mode_q == MODE_IDLE) begin
                                        metric_cycles_q <= 32'd0;
                                        metric_active_o <= 1'b1;
                                        phase_q         <= PH_IDLE_WINDOW;
                                    end else begin
                                        phase_q <= PH_PMUL_START;
                                    end
                                end else begin
                                    preload_index_q <= preload_index_q + 7'd1;
                                end
                            end
                        end else if ((cmd_state_q == CMD_IDLE) && !cmd_launch_q) begin
                            cmd_request_op_q <= preload_data_q ? HDEC_VWR64 : HDEC_VADDR;
                            cmd_request_operand_q <= preload_data_q
                                ? vv35_preload_data(preload_index_q)
                                : {56'd0, vv35_preload_address(preload_index_q)};
                            cmd_launch_q <= 1'b1;
                        end
                    end

                    PH_PMUL_START: begin
                        if (cmd_done_q) begin
                            if ((cmd_result_q[1:0] != STATUS_OK)
                                    || (cmd_result_q[2] != 1'b1)) begin
                                error_count_q <= vv35_increment_error(error_count_q);
                                if (error_count_q == 0)
                                    error_code_o <= 32'h2000_0001;
                            end
                            metric_cycles_q <= 32'd0;
                            metric_active_o <= 1'b1;
                            phase_q <= (mode_q == MODE_SERIAL)
                                ? PH_SERIAL_WAIT : PH_HMATCH;
                        end else if ((cmd_state_q == CMD_IDLE) && !cmd_launch_q) begin
                            cmd_request_op_q      <= HDEC_ECC_STATUS;
                            cmd_request_operand_q <= VV35_PMUL_OPERAND;
                            cmd_launch_q          <= 1'b1;
                        end
                    end

                    PH_SERIAL_WAIT: begin
                        if (metric_cycles_q >= (VV35_PMUL_WAIT_CYCLES
                                - VV35_SERIAL_LAUNCH_COMPENSATION))
                            phase_q <= PH_HMATCH;
                    end

                    PH_HMATCH: begin
                        if (cmd_done_q) begin
                            last_hmatch_o <= cmd_result_q;
                            if (cmd_result_q != VV35_EXPECTED_HMATCH) begin
                                error_count_q <= vv35_increment_error(error_count_q);
                                if (error_count_q == 0)
                                    error_code_o <= 32'h3000_0001;
                            end
                            hmatch_completed_o <= hmatch_completed_o + 32'd1;
                            if (hmatch_completed_o == VV35_HMATCH_COUNT - 1) begin
                                // metric_cycles_q is incremented by NBA on
                                // this same accepting edge; include that edge
                                // in the natural HMATCH completion latency.
                                hmatch_completion_cycles_o <= metric_cycles_q + 32'd1;
                                phase_q <= PH_WINDOW_WAIT;
                            end
                        end else if ((cmd_state_q == CMD_IDLE) && !cmd_launch_q) begin
                            cmd_request_op_q      <= HDEC_HMATCH;
                            cmd_request_operand_q <= VV35_HMATCH_OPERAND;
                            cmd_launch_q          <= 1'b1;
                        end
                    end

                    PH_WINDOW_WAIT: begin
                        if (metric_cycles_q >= ((mode_q == MODE_SERIAL)
                                ? VV35_SERIAL_WINDOW_CYCLES
                                : VV35_INTERLEAVED_WINDOW_CYCLES)) begin
                            metric_active_o   <= 1'b0;
                            measured_cycles_o <= metric_cycles_q;
                            if (metric_cycles_q != ((mode_q == MODE_SERIAL)
                                    ? VV35_SERIAL_WINDOW_CYCLES
                                    : VV35_INTERLEAVED_WINDOW_CYCLES)) begin
                                error_count_q <= vv35_increment_error(error_count_q);
                                if (error_count_q == 0)
                                    error_code_o <= 32'h3800_0001;
                            end
                            phase_q           <= PH_FINAL_STATUS;
                        end
                    end

                    PH_FINAL_STATUS: begin
                        if (cmd_done_q) begin
                            final_status_o <= cmd_result_q;
                            if (cmd_result_q[3:0] != 4'b1000) begin
                                error_count_q <= vv35_increment_error(error_count_q);
                                if (error_count_q == 0)
                                    error_code_o <= 32'h4000_0001;
                            end
                            check_row_q  <= 3'd0;
                            check_bank_q <= 2'd0;
                            phase_q      <= PH_CHECK_ADDR;
                        end else if ((cmd_state_q == CMD_IDLE) && !cmd_launch_q) begin
                            cmd_request_op_q      <= HDEC_ECC_STATUS;
                            cmd_request_operand_q <= 64'd0;
                            cmd_launch_q          <= 1'b1;
                        end
                    end

                    PH_CHECK_ADDR: begin
                        if (cmd_done_q) begin
                            if (cmd_result_q[1:0] != STATUS_OK) begin
                                error_count_q <= vv35_increment_error(error_count_q);
                                if (error_count_q == 0)
                                    error_code_o <= {8'h50, check_row_q, check_bank_q,
                                                     19'd0};
                            end
                            phase_q <= PH_CHECK_READ;
                        end else if ((cmd_state_q == CMD_IDLE) && !cmd_launch_q) begin
                            cmd_request_op_q <= HDEC_VADDR;
                            cmd_request_operand_q <= {
                                56'd0, check_bank_q,
                                vv35_check_row_number(check_row_q)
                            };
                            cmd_launch_q <= 1'b1;
                        end
                    end

                    PH_CHECK_READ: begin
                        if (cmd_done_q) begin
                            if (cmd_result_q != vv35_expected_check_word(
                                    check_row_q, check_bank_q)) begin
                                error_count_q <= vv35_increment_error(error_count_q);
                                if (error_count_q == 0)
                                    error_code_o <= {8'h60, check_row_q, check_bank_q,
                                                     19'd0};
                            end
                            if ((check_row_q == 3'd4) && (check_bank_q == 2'd3)) begin
                                done_o <= 1'b1;
                                pass_o <= (error_count_q == 0)
                                    && (cmd_result_q == vv35_expected_check_word(
                                        check_row_q, check_bank_q));
                                fail_o <= (error_count_q != 0)
                                    || (cmd_result_q != vv35_expected_check_word(
                                        check_row_q, check_bank_q));
                                phase_q <= PH_DONE;
                            end else if (check_bank_q == 2'd3) begin
                                check_bank_q <= 2'd0;
                                check_row_q  <= check_row_q + 3'd1;
                                phase_q      <= PH_CHECK_ADDR;
                            end else begin
                                check_bank_q <= check_bank_q + 2'd1;
                                phase_q      <= PH_CHECK_ADDR;
                            end
                        end else if ((cmd_state_q == CMD_IDLE) && !cmd_launch_q) begin
                            cmd_request_op_q      <= HDEC_VRD64;
                            cmd_request_operand_q <= 64'd0;
                            cmd_launch_q          <= 1'b1;
                        end
                    end

                    PH_IDLE_WINDOW: begin
                        if (metric_cycles_q >= VV35_IDLE_WINDOW_CYCLES - 1) begin
                            metric_active_o   <= 1'b0;
                            measured_cycles_o <= VV35_IDLE_WINDOW_CYCLES;
                            done_o            <= 1'b1;
                            pass_o            <= (error_count_q == 0);
                            fail_o            <= (error_count_q != 0);
                            phase_q           <= PH_DONE;
                        end
                    end

                    PH_DONE: begin
                        metric_active_o <= 1'b0;
                        if (!start_i) begin
                            done_o       <= 1'b0;
                            pass_o       <= 1'b0;
                            fail_o       <= 1'b0;
                            dut_rst_ni   <= 1'b0;
                            phase_q      <= PH_IDLE;
                        end
                    end

                    default: begin
                        error_count_q <= vv35_increment_error(error_count_q);
                        error_code_o  <= 32'hffff_0001;
                        done_o        <= 1'b1;
                        pass_o        <= 1'b0;
                        fail_o        <= 1'b1;
                        phase_q       <= PH_DONE;
                    end
                endcase
            end
        end
    end
endmodule
