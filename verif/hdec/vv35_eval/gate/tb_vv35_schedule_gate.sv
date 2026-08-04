`timescale 1ns/1ps

// Post-route, public-interface-only scheduling workload for gate-level SAIF.
//
// This testbench deliberately treats hdec_top as a black box.  It does not
// reference parameters, state bits, event probes, VRF signals, or any other
// synthesized-away RTL name.  SERIAL and INTERLEAVED therefore exercise the
// same routed netlist and differ only in when the resident HMATCH requests are
// presented to the nine-port public interface.
module tb_vv35_schedule_gate;
    import hdec_pkg::*;
    import hdec_vv31_ref_pkg::*;
    import hdec_vv31_driver_pkg::*;
    import hdec_vv31_check_pkg::*;
    import hdec_vv31_vectors_pkg::*;

    localparam logic [3:0] VV35_QUERY_SLOT = VV31_HDC_HV3_SLOT;
    localparam logic [3:0] VV35_PROTO_BASE_SLOT = 4'd4;
    localparam logic [7:0] VV35_PROTO_COUNT = 8'd4;
    localparam int unsigned VV35_DEFAULT_TASK_COUNT = 1632;
    localparam int unsigned VV35_DEFAULT_PMUL_WAIT_CYCLES = 146908;
    localparam int unsigned VV35_SERIAL_WINDOW_CYCLES = 337853;
    localparam int unsigned VV35_INTERLEAVED_WINDOW_CYCLES = 200144;
    localparam int unsigned VV35_REQUEST_TIMEOUT = 2_000_000;

    logic        clk_i;
    logic        rst_ni;
    logic        valid_i;
    logic        ready_o;
    hdec_op_t    operator_i;
    logic [63:0] operand_a_i;
    logic [63:0] operand_b_i;
    logic        valid_o;
    logic [63:0] result_o;

    // The SAIF Tcl script uses only this public testbench signal to delimit
    // the measured workload.  Vector preload and result checking are outside.
    logic metric_active;

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

    string scenario;
    string vector_dir;
    bit serial_mode;
    int unsigned task_count;
    int unsigned window_cycles;
    int unsigned pmul_wait_cycles;
    int unsigned error_count;
    int unsigned unknown_public_samples;
    longint unsigned cycle_count;
    longint unsigned hmatch_requested;
    longint unsigned hmatch_completed;

    logic [31:0] scalar_count_mem [0:0];
    logic [255:0] master_seed_mem [0:0];
    logic [255:0] point_x_inputs [0:0];
    logic [255:0] point_y_inputs [0:0];
    logic [255:0] scalar_inputs [0:0];
    logic [255:0] expected_x [0:0];
    logic [255:0] expected_y [0:0];
    logic [1023:0] hdc_train_samples [0:3];
    logic [1023:0] hdc_role_vectors [0:3];

    initial clk_i = 1'b0;
    always #2.5 clk_i = ~clk_i;

    always @(posedge clk_i)
        cycle_count <= cycle_count + 1;

    // Only stable, opposite-edge samples are used under SDF.  Short gate
    // glitches are intentionally left to SAIF and are not treated as protocol
    // events by the public-interface checker.
    always @(negedge clk_i) begin
        if (rst_ni && metric_active) begin
            if ($isunknown({ready_o, valid_o}))
                unknown_public_samples++;
            if ((valid_o === 1'b1) && $isunknown(result_o))
                unknown_public_samples++;
        end
    end

    function automatic string vector_file(input string leaf_name);
        vector_file = {vector_dir, "/", leaf_name};
    endfunction

    task automatic load_vectors;
        begin
            $readmemh(
                vector_file("scalar_count.mem"), scalar_count_mem, 0, 0
            );
            $readmemh(
                vector_file("master_seed.mem"), master_seed_mem, 0, 0
            );
            $readmemh(
                vector_file("pmul_point_x.mem"), point_x_inputs, 0, 0
            );
            $readmemh(
                vector_file("pmul_point_y.mem"), point_y_inputs, 0, 0
            );
            $readmemh(
                vector_file("pmul_scalars.mem"), scalar_inputs, 0, 0
            );
            $readmemh(
                vector_file("pmul_expected_x.mem"), expected_x, 0, 0
            );
            $readmemh(
                vector_file("pmul_expected_y.mem"), expected_y, 0, 0
            );
            $readmemh(
                vector_file("hdc_train_samples.mem"),
                hdc_train_samples,
                0,
                3
            );
            $readmemh(
                vector_file("hdc_role_vectors.mem"),
                hdc_role_vectors,
                0,
                3
            );

            if (scalar_count_mem[0] < 1)
                $fatal(1, "[VV35:GATE] vector bundle contains no scalar");
            if (!vv31_legal_random_k(scalar_inputs[0]))
                $fatal(
                    1,
                    "[VV35:GATE] illegal random K=%064h",
                    scalar_inputs[0]
                );
            if ($isunknown({
                point_x_inputs[0], point_y_inputs[0], scalar_inputs[0],
                expected_x[0], expected_y[0], hdc_train_samples[0],
                hdc_role_vectors[1]
            }))
                $fatal(1, "[VV35:GATE] vector bundle contains unknown data");
        end
    endtask

    task automatic reset_dut;
        begin
            valid_i = 1'b0;
            operator_i = HDEC_VWR64;
            operand_a_i = '0;
            operand_b_i = '0;
            rst_ni = 1'b0;
            repeat (8) @(posedge clk_i);
            @(negedge clk_i);
            rst_ni = 1'b1;
            repeat (40) @(posedge clk_i);
        end
    endtask

    // Gate-safe ready/valid BFM.  Requests are driven and responses are sampled
    // at falling edges.  valid_i is held until ready_o has been observed across
    // a rising edge, which also preserves VV33's paired-HMATCH behavior while
    // the PMUL controller owns the main state machine.
    task automatic issue_hold(
        input  hdec_op_t operation,
        input  logic [63:0] operand_a,
        input  logic [63:0] operand_b,
        output logic [63:0] result,
        output vv31_timing_t timing
    );
        bit accepted;
        bit responded;
        int unsigned waited;
        begin
            if (valid_i)
                $fatal(1, "[VV35:GATE] overlapping request attempts");

            // Sequential callers normally return on a falling edge.  The
            // guard also makes the first call after reset safe.
            if (clk_i !== 1'b0)
                @(negedge clk_i);

            timing = '0;
            result = 'x;
            accepted = 1'b0;
            responded = 1'b0;
            waited = 0;
            timing.request_cycle = cycle_count;
            valid_i = 1'b1;
            operator_i = operation;
            operand_a_i = operand_a;
            operand_b_i = operand_b;

            while (!accepted) begin
                // ready_o is the value consumed by the DUT at this rising
                // edge.  In particular, the paired-HMATCH ready pulse may be
                // withdrawn immediately after the accepting transition and
                // therefore must not be inferred from the following negedge.
                @(posedge clk_i);
                waited++;
                if (ready_o === 1'b1) begin
                    accepted = 1'b1;
                    timing.accept_cycle = cycle_count;
                end
                if (waited >= VV35_REQUEST_TIMEOUT)
                    $fatal(
                        1,
                        "[VV35:GATE] request timeout op=%0d cycle=%0d",
                        operation,
                        cycle_count
                    );
            end

            // Withdraw the accepted request away from the active edge, and
            // also catch the unlikely case of a one-cycle response already
            // being visible at this first safe sample point.
            @(negedge clk_i);
            if (valid_o === 1'b1) begin
                responded = 1'b1;
                timing.response_cycle = cycle_count;
                result = result_o;
            end
            valid_i = 1'b0;
            operator_i = HDEC_VWR64;
            operand_a_i = '0;
            operand_b_i = '0;

            waited = 0;
            while (!responded) begin
                @(negedge clk_i);
                waited++;
                if (valid_o === 1'b1) begin
                    responded = 1'b1;
                    timing.response_cycle = cycle_count;
                    result = result_o;
                end
                if (waited >= VV35_REQUEST_TIMEOUT)
                    $fatal(
                        1,
                        "[VV35:GATE] response timeout op=%0d cycle=%0d",
                        operation,
                        cycle_count
                    );
            end

            if ($isunknown(result)) begin
                error_count++;
                $error(
                    "[VV35:GATE] unknown public response op=%0d cycle=%0d",
                    operation,
                    cycle_count
                );
            end
        end
    endtask

    task automatic issue(
        input  hdec_op_t operation,
        input  logic [63:0] operand,
        output logic [63:0] result
    );
        vv31_timing_t timing;
        begin
            issue_hold(operation, operand, '0, result, timing);
        end
    endtask

    task automatic write_vrf64(
        input logic [1:0] bank,
        input logic [5:0] row,
        input logic [63:0] data
    );
        logic [63:0] ignored;
        begin
            issue(HDEC_VADDR, vv31_vaddr_operand(bank, row), ignored);
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
            issue(HDEC_VADDR, vv31_vaddr_operand(bank, row), ignored);
            issue(HDEC_VRD64, '0, data);
        end
    endtask

    task automatic write_row(
        input logic [5:0] row,
        input logic [255:0] value
    );
        begin
            for (int bank = 0; bank < 4; bank++)
                write_vrf64(bank[1:0], row, value[bank * 64 +: 64]);
        end
    endtask

    task automatic read_row(
        input logic [5:0] row,
        output logic [255:0] value
    );
        begin
            for (int bank = 0; bank < 4; bank++)
                read_vrf64(bank[1:0], row, value[bank * 64 +: 64]);
        end
    endtask

    task automatic write_hv(
        input logic [3:0] slot,
        input logic [1023:0] value
    );
        int word_index;
        begin
            for (int row_offset = 0; row_offset < 4; row_offset++) begin
                for (int bank = 0; bank < 4; bank++) begin
                    word_index = row_offset * 4 + bank;
                    write_vrf64(
                        bank[1:0],
                        {slot, 2'b00} + row_offset,
                        value[word_index * 64 +: 64]
                    );
                end
            end
        end
    endtask

    task automatic prepare_resident_workload(
        input logic [1023:0] query,
        input logic [1023:0] prototype0,
        input logic [1023:0] prototype1,
        input logic [1023:0] prototype2,
        input logic [1023:0] prototype3
    );
        logic [255:0] guard3;
        begin
            guard3 = {
                master_seed_mem[0][191:0],
                32'h31c0_0003,
                32'd0
            };
            write_row(VV31_ECC_POINT_X_ROW, point_x_inputs[0]);
            write_row(VV31_ECC_POINT_Y_ROW, point_y_inputs[0]);
            write_row(VV31_ECC_SCALAR_ROW, scalar_inputs[0]);
            write_row(6'd3, guard3);
            write_row(VV31_ECC_OUT_X_ROW, '0);
            write_row(VV31_ECC_OUT_Y_ROW, '0);
            write_row(6'd6, ~guard3);
            write_row(
                6'd7,
                guard3
                ^ 256'h5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5aa5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5
            );
            write_hv(VV35_QUERY_SLOT, query);
            write_hv(VV35_PROTO_BASE_SLOT + 4'd0, prototype0);
            write_hv(VV35_PROTO_BASE_SLOT + 4'd1, prototype1);
            write_hv(VV35_PROTO_BASE_SLOT + 4'd2, prototype2);
            write_hv(VV35_PROTO_BASE_SLOT + 4'd3, prototype3);
        end
    endtask

    task automatic wait_elapsed(
        input longint unsigned start_cycle,
        input longint unsigned elapsed_cycles
    );
        begin
            while ((cycle_count - start_cycle) < elapsed_cycles)
                @(negedge clk_i);
        end
    endtask

    task automatic run_hmatch_stream(
        input logic [63:0] expected_match,
        output longint unsigned last_response_cycle
    );
        logic [63:0] result;
        vv31_timing_t timing;
        begin
            last_response_cycle = 0;
            for (int unsigned task_index = 0;
                 task_index < task_count;
                 task_index++) begin
                hmatch_requested++;
                issue_hold(
                    HDEC_HMATCH,
                    vv31_hmatch_operand(
                        VV35_QUERY_SLOT,
                        VV35_PROTO_BASE_SLOT,
                        VV35_PROTO_COUNT
                    ),
                    '0,
                    result,
                    timing
                );
                last_response_cycle = timing.response_cycle;
                if (result !== expected_match) begin
                    error_count++;
                    $error(
                        "[VV35:GATE_HMATCH] scenario=%0s task=%0d got=%016h expected=%016h",
                        scenario,
                        task_index,
                        result,
                        expected_match
                    );
                end else begin
                    hmatch_completed++;
                end
            end
        end
    endtask

    task automatic check_final_pmul;
        logic [63:0] status;
        logic [255:0] got_x;
        logic [255:0] got_y;
        logic [255:0] got_guard;
        logic [255:0] guard3;
        begin
            // Exactly one completion query is issued, and only after SAIF has
            // closed.  No polling traffic contaminates the measured window.
            issue(HDEC_ECC_STATUS, '0, status);
            if ((status[1:0] !== STATUS_OK)
             || (status[2] !== 1'b0)
             || (status[3] !== 1'b1)) begin
                error_count++;
                $error(
                    "[VV35:GATE_PMUL] final status=%016h expected done",
                    status
                );
            end
            read_row(VV31_ECC_OUT_X_ROW, got_x);
            read_row(VV31_ECC_OUT_Y_ROW, got_y);
            if ((got_x !== expected_x[0]) || (got_y !== expected_y[0])) begin
                error_count++;
                $error(
                    "[VV35:GATE_PMUL] result got=(%064h,%064h) expected=(%064h,%064h)",
                    got_x,
                    got_y,
                    expected_x[0],
                    expected_y[0]
                );
            end
            if ((got_x[255:233] != 0) || (got_y[255:233] != 0)) begin
                error_count++;
                $error("[VV35:GATE_PMUL] nonzero K-233 padding");
            end

            guard3 = {
                master_seed_mem[0][191:0],
                32'h31c0_0003,
                32'd0
            };
            read_row(6'd3, got_guard);
            if (got_guard !== guard3) begin
                error_count++;
                $error("[VV35:GATE_PMUL] guard row3 changed");
            end
            read_row(6'd6, got_guard);
            if (got_guard !== ~guard3) begin
                error_count++;
                $error("[VV35:GATE_PMUL] guard row6 changed");
            end
            read_row(6'd7, got_guard);
            if (got_guard !== (
                guard3
                ^ 256'h5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5aa5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5
            )) begin
                error_count++;
                $error("[VV35:GATE_PMUL] guard row7 changed");
            end
        end
    endtask

    initial begin : run_gate_schedule
        logic [1023:0] query;
        logic [1023:0] prototype0;
        logic [1023:0] prototype1;
        logic [1023:0] prototype2;
        logic [1023:0] prototype3;
        logic [10:0] expected_score;
        logic [63:0] expected_match;
        logic [63:0] start_status;
        vv31_timing_t start_timing;
        longint unsigned active_start_cycle;
        longint unsigned active_end_cycle;
        longint unsigned last_hmatch_response_cycle;
        int scenario_arg_seen;
        int task_count_arg_seen;
        int window_arg_seen;
        int pmul_wait_arg_seen;
        int vector_dir_arg_seen;

        cycle_count = 0;
        error_count = 0;
        unknown_public_samples = 0;
        hmatch_requested = 0;
        hmatch_completed = 0;
        metric_active = 1'b0;
        scenario = "INTERLEAVED";
        vector_dir = ".";
        task_count = VV35_DEFAULT_TASK_COUNT;
        pmul_wait_cycles = VV35_DEFAULT_PMUL_WAIT_CYCLES;

        scenario_arg_seen = $value$plusargs("SCENARIO=%s", scenario);
        task_count_arg_seen = $value$plusargs("TASK_COUNT=%d", task_count);
        vector_dir_arg_seen = $value$plusargs(
            "VV31_VECTOR_DIR=%s",
            vector_dir
        );
        serial_mode = (scenario == "SERIAL");
        if (!serial_mode && (scenario != "INTERLEAVED"))
            $fatal(
                1,
                "[VV35:GATE] SCENARIO must be SERIAL or INTERLEAVED, got %0s",
                scenario
            );
        window_cycles = serial_mode
            ? VV35_SERIAL_WINDOW_CYCLES
            : VV35_INTERLEAVED_WINDOW_CYCLES;
        window_arg_seen = $value$plusargs(
            "WINDOW_CYCLES=%d",
            window_cycles
        );
        pmul_wait_arg_seen = $value$plusargs(
            "PMUL_WAIT_CYCLES=%d",
            pmul_wait_cycles
        );
        if ((task_count == 0) || (task_count > 100000))
            $fatal(1, "[VV35:GATE] invalid TASK_COUNT=%0d", task_count);
        if ((window_cycles == 0) || (window_cycles > 2_000_000))
            $fatal(
                1,
                "[VV35:GATE] invalid WINDOW_CYCLES=%0d",
                window_cycles
            );
        if (pmul_wait_cycles > window_cycles)
            $fatal(
                1,
                "[VV35:GATE] PMUL_WAIT_CYCLES=%0d exceeds window=%0d",
                pmul_wait_cycles,
                window_cycles
            );

        load_vectors();
        query = hdc_train_samples[0] ^ hdc_role_vectors[1];
        prototype0 = query;
        prototype1 = ~query;
        prototype2 = query ^ {512{2'b01}};
        prototype3 = query ^ {256{4'b0001}};
        expected_score = vv31_hdc_overlap(query, prototype0);
        expected_match = vv31_hmatch_result(3'd0, expected_score);
        if ($isunknown({query, prototype0, prototype1, prototype2, prototype3})
         || (query == '0))
            $fatal(1, "[VV35:GATE] invalid resident HDC workload");

        reset_dut();
        prepare_resident_workload(
            query,
            prototype0,
            prototype1,
            prototype2,
            prototype3
        );

        issue_hold(
            HDEC_ECC_STATUS,
            vv31_ecc_pmul_operand(
                1'b1,
                VV31_ECC_OUT_X_ROW,
                VV31_ECC_POINT_X_ROW,
                VV31_ECC_SCALAR_ROW
            ),
            '0,
            start_status,
            start_timing
        );
        if ((start_status[1:0] !== STATUS_OK)
         || (start_status[2] !== 1'b1)) begin
            error_count++;
            $error(
                "[VV35:GATE_PMUL] background start failed status=%016h",
                start_status
            );
        end

        active_start_cycle = cycle_count;
        metric_active = 1'b1;
        fork
            begin : foreground_stream
                if (serial_mode)
                    wait_elapsed(active_start_cycle, pmul_wait_cycles);
                run_hmatch_stream(
                    expected_match,
                    last_hmatch_response_cycle
                );
            end
            begin : fixed_activity_window
                wait_elapsed(active_start_cycle, window_cycles);
            end
        join
        active_end_cycle = cycle_count;
        metric_active = 1'b0;

        if ((active_end_cycle - active_start_cycle) != window_cycles) begin
            error_count++;
            $error(
                "[VV35:GATE] workload exceeded frozen window actual=%0d expected=%0d last_hmatch=%0d",
                active_end_cycle - active_start_cycle,
                window_cycles,
                last_hmatch_response_cycle
            );
        end
        if ((hmatch_requested != task_count)
         || (hmatch_completed != task_count)) begin
            error_count++;
            $error(
                "[VV35:GATE] HMATCH count requested=%0d completed=%0d expected=%0d",
                hmatch_requested,
                hmatch_completed,
                task_count
            );
        end
        if (unknown_public_samples != 0) begin
            error_count++;
            $error(
                "[VV35:GATE] unknown public samples=%0d",
                unknown_public_samples
            );
        end

        check_final_pmul();
        $display(
            "[VV35:GATE_METRIC] scenario=%0s scenario_arg=%0d task_count_arg=%0d window_arg=%0d pmul_wait_arg=%0d vector_dir_arg=%0d K=%064h K_weight=%0d task_count=%0d hmatch_completed=%0d expected_class=%0d expected_score=%0d active_start=%0d active_end=%0d window_cycles=%0d last_hmatch=%0d unknown_public=%0d errors=%0d",
            scenario,
            scenario_arg_seen,
            task_count_arg_seen,
            window_arg_seen,
            pmul_wait_arg_seen,
            vector_dir_arg_seen,
            scalar_inputs[0],
            vv31_hamming_weight256(scalar_inputs[0]),
            task_count,
            hmatch_completed,
            expected_match[13:11],
            expected_match[10:0],
            active_start_cycle,
            active_end_cycle,
            active_end_cycle - active_start_cycle,
            last_hmatch_response_cycle,
            unknown_public_samples,
            error_count
        );

        if (error_count == 0)
            $display("[VV35:GATE_SCHEDULE] PASS scenario=%0s", scenario);
        else
            $fatal(
                1,
                "[VV35:GATE_SCHEDULE] FAIL scenario=%0s errors=%0d",
                scenario,
                error_count
            );
        $finish;
    end
endmodule
