module vv35_zynq7020_board_top (
    input  wire L16,
    input  wire KEY,
    output wire LED_H15
);
    logic clk_i;
    logic mmcm_locked;
    vv35_zynq7020_clk200 i_clk200 (
        .clk50_i  (L16),
        .rst_i    (!KEY),
        .clk200_o (clk_i),
        .locked_o (mmcm_locked)
    );

    logic [1:0] key_sync_q = 2'b11;
    logic [7:0] por_count_q = 8'd0;
    logic board_rst_ni = 1'b0;
    always_ff @(posedge clk_i) begin
        key_sync_q <= {key_sync_q[0], KEY};
        if (!mmcm_locked || !key_sync_q[1]) begin
            por_count_q  <= 8'd0;
            board_rst_ni <= 1'b0;
        end else if (!board_rst_ni) begin
            por_count_q <= por_count_q + 8'd1;
            if (&por_count_q)
                board_rst_ni <= 1'b1;
        end
    end

    logic [1:0] vio_mode;
    logic       vio_arm_toggle;
    logic       arm_seen_q;
    logic [1:0] run_mode_q;
    logic       start_q;

    logic        idle;
    logic        busy;
    logic        done;
    logic        pass;
    logic        fail;
    logic        metric_active;
    logic [31:0] measured_cycles;
    logic [31:0] hmatch_completion_cycles;
    logic [31:0] hmatch_completed;
    logic [31:0] error_count;
    logic [31:0] error_code;
    logic [63:0] last_hmatch;
    logic [63:0] final_status;
    logic [31:0] preload_count;
    logic [7:0]  phase;

    (* DONT_TOUCH = "yes", keep_hierarchy = "yes" *)
    vv35_board_schedule_controller i_controller (
        .clk_i,
        .board_rst_ni,
        .run_mode_i          (run_mode_q),
        .start_i             (start_q),
        .idle_o              (idle),
        .busy_o              (busy),
        .done_o              (done),
        .pass_o              (pass),
        .fail_o              (fail),
        .metric_active_o     (metric_active),
        .measured_cycles_o   (measured_cycles),
        .hmatch_completion_cycles_o (hmatch_completion_cycles),
        .hmatch_completed_o  (hmatch_completed),
        .error_count_o       (error_count),
        .error_code_o        (error_code),
        .last_hmatch_o       (last_hmatch),
        .final_status_o      (final_status),
        .preload_count_o     (preload_count),
        .phase_o             (phase)
    );

    logic        snapshot_valid_q;
    logic        snapshot_pass_q;
    logic        snapshot_fail_q;
    logic [1:0]  snapshot_mode_q;
    logic [31:0] snapshot_sequence_q;
    logic [31:0] snapshot_cycles_q;
    logic [31:0] snapshot_hmatch_q;
    logic [31:0] snapshot_hmatch_completion_cycles_q;
    logic [31:0] snapshot_errors_q;
    logic [31:0] snapshot_error_code_q;
    logic [63:0] snapshot_last_hmatch_q;
    logic [63:0] snapshot_final_status_q;
    logic [31:0] snapshot_preload_q;

    always_ff @(posedge clk_i or negedge board_rst_ni) begin
        if (!board_rst_ni) begin
            arm_seen_q                <= 1'b0;
            run_mode_q                <= 2'd0;
            start_q                   <= 1'b0;
            snapshot_valid_q          <= 1'b0;
            snapshot_pass_q           <= 1'b0;
            snapshot_fail_q           <= 1'b0;
            snapshot_mode_q           <= 2'd0;
            snapshot_sequence_q       <= 32'd0;
            snapshot_cycles_q         <= 32'd0;
            snapshot_hmatch_q         <= 32'd0;
            snapshot_hmatch_completion_cycles_q <= 32'd0;
            snapshot_errors_q         <= 32'd0;
            snapshot_error_code_q     <= 32'd0;
            snapshot_last_hmatch_q    <= 64'd0;
            snapshot_final_status_q   <= 64'd0;
            snapshot_preload_q        <= 32'd0;
        end else begin
            if (!start_q && idle && (vio_arm_toggle != arm_seen_q)) begin
                arm_seen_q       <= vio_arm_toggle;
                run_mode_q       <= vio_mode;
                snapshot_valid_q <= 1'b0;
                start_q          <= 1'b1;
            end
            if (start_q && done) begin
                snapshot_valid_q        <= 1'b1;
                snapshot_pass_q         <= pass;
                snapshot_fail_q         <= fail;
                snapshot_mode_q         <= run_mode_q;
                snapshot_sequence_q     <= snapshot_sequence_q + 32'd1;
                snapshot_cycles_q       <= measured_cycles;
                snapshot_hmatch_q       <= hmatch_completed;
                snapshot_hmatch_completion_cycles_q <= hmatch_completion_cycles;
                snapshot_errors_q       <= error_count;
                snapshot_error_code_q   <= error_code;
                snapshot_last_hmatch_q  <= last_hmatch;
                snapshot_final_status_q <= final_status;
                snapshot_preload_q      <= preload_count;
                start_q                 <= 1'b0;
            end
        end
    end

    wire [31:0] snapshot_flags = {
        snapshot_sequence_q[7:0],
        8'd0,
        phase,
        snapshot_mode_q,
        metric_active,
        busy,
        idle,
        snapshot_valid_q,
        snapshot_fail_q,
        snapshot_pass_q
    };

    vv35_zynq7020_board_vio i_board_vio (
        .clk        (clk_i),
        .probe_in0  (snapshot_flags),
        .probe_in1  (snapshot_cycles_q),
        .probe_in2  (snapshot_hmatch_q),
        .probe_in3  (snapshot_errors_q),
        .probe_in4  (snapshot_error_code_q),
        .probe_in5  (snapshot_last_hmatch_q),
        .probe_in6  (snapshot_final_status_q),
        .probe_in7  (snapshot_preload_q),
        .probe_in8  (snapshot_sequence_q),
        .probe_in9  (snapshot_hmatch_completion_cycles_q),
        .probe_out0 (vio_arm_toggle),
        .probe_out1 (vio_mode)
    );

    // H15 is the board's user LED and is used only as a terminal PASS light.
    // It is intentionally not the activity-window marker: LED current would
    // contaminate a physical energy measurement.  A measurement campaign must
    // first bind metric_active to a verified unloaded header/test-point pin.
    assign LED_H15 = snapshot_valid_q && snapshot_pass_q && !snapshot_fail_q;
endmodule
