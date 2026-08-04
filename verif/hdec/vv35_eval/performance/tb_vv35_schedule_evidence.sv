// Canonical VV35 same-netlist scheduling experiment.
//
// The DUT is instantiated with the committed/default VV35 parameters.  The
// SERIAL and INTERLEAVED cases differ only in when the identical resident
// HMATCH stream is presented.  Select the case at run time with:
//
//   --testplusarg SCENARIO=SERIAL
//   --testplusarg SCENARIO=INTERLEAVED
//
// TASK_COUNT defaults to the frozen 1632-search workload and can be reduced
// for compile/simulation smoke tests without changing the hardware image.
module tb_vv35_schedule_evidence;
    import hdec_pkg::*;
    import hdec_vv31_ref_pkg::*;
    import hdec_vv31_driver_pkg::*;
    import hdec_vv31_check_pkg::*;
    import hdec_vv31_vectors_pkg::*;

    localparam logic [3:0] VV35_QUERY_SLOT = VV31_HDC_HV3_SLOT;
    localparam logic [3:0] VV35_PROTO_BASE_SLOT = 4'd4;
    localparam logic [7:0] VV35_PROTO_COUNT = 8'd4;
    localparam int unsigned VV35_DEFAULT_TASK_COUNT = 1632;

    // Deliberately no defparam or parameter override: both scenarios use the
    // exact same default VV35 RTL/netlist.
    hdec_vv31_system_harness h();

    string scenario;
    bit serial_mode;
    bit metric_active;
    int unsigned task_count;

    longint unsigned hmatch_requested;
    longint unsigned hmatch_completed;
    longint unsigned hmatch_result_errors;
    longint unsigned pair_accept_events;
    longint unsigned pair_product_events;
    longint unsigned pair_pop_events;
    longint unsigned pair_response_events;
    longint unsigned data_overlap_events;
    longint unsigned control_overlap_events;
    longint unsigned vrf_read_conflicts;
    longint unsigned vrf_write_conflicts;
    longint unsigned matrix_conflicts;
    longint unsigned popcount_conflicts;
    longint unsigned xor0_conflicts;
    longint unsigned payload_conflicts;
    longint unsigned unknown_events;

    wire hdc_payload_producer =
           h.dut.vv31_evt_hdc_matrix
        || h.dut.vv33_pair_product_fire
        || h.dut.vv31_evt_hdc_xor0
        || ((h.dut.st_q == h.dut.S_UOP_P2_LANE)
            && h.dut.uop_p0_q.valid
            && (h.dut.uop_p0_use_counter
             || h.dut.uop_p0_use_clip
             || h.dut.uop_p0_use_shift));

    wire hdc_write_state =
           (h.dut.st_q == h.dut.S_UOP_P3_GLOBAL)
        || (h.dut.st_q == h.dut.S_UOP_CLIP_WRITE)
        || (h.dut.st_q == h.dut.S_CLR);

    wire vrf_read_conflict_now =
        h.dut.vv31_evt_hdc_vrf_read
        && (h.dut.vv31_evt_ecc_vrf_prefetch
         || h.dut.vv33_sq_read_fire);
    wire vrf_write_conflict_now =
        h.dut.vv33_sq_write_fire && hdc_write_state;
    wire matrix_conflict_now =
        (h.dut.vv31_evt_hdc_matrix || h.dut.vv33_pair_product_fire)
        && h.dut.vv31_evt_ecc_matrix;
    wire xor0_conflict_now =
        h.dut.vv31_evt_hdc_xor0 && h.dut.vv31_evt_ecc_xor0;
    wire payload_conflict_now =
        hdc_payload_producer && h.dut.vv31_evt_ecc_matrix;

    wire hdc_data_event =
           h.dut.vv31_evt_hdc_matrix
        || h.dut.vv33_pair_product_fire
        || h.dut.vv33_pair_pop_fire
        || h.dut.vv31_evt_hdc_xor0;
    wire ecc_data_event =
           h.dut.vv31_evt_ecc_vrf_prefetch
        || h.dut.vv31_evt_ecc_square
        || h.dut.vv33_sq_read_fire
        || h.dut.vv33_sq_write_fire;

    task automatic clear_metrics;
        begin
            hmatch_requested = 0;
            hmatch_completed = 0;
            hmatch_result_errors = 0;
            pair_accept_events = 0;
            pair_product_events = 0;
            pair_pop_events = 0;
            pair_response_events = 0;
            data_overlap_events = 0;
            control_overlap_events = 0;
            vrf_read_conflicts = 0;
            vrf_write_conflicts = 0;
            matrix_conflicts = 0;
            popcount_conflicts = 0;
            xor0_conflicts = 0;
            payload_conflicts = 0;
            unknown_events = 0;
        end
    endtask

    // Capture the event values before the DUT's nonblocking state transition.
    // This is required for the CAP2/FOLD paired-HMATCH side path.
    always @(posedge h.clk_i) begin : monitor_schedule_contract
        bit pair_accept_at_edge;
        bit pair_product_at_edge;
        bit pair_pop_at_edge;
        bit pair_response_at_edge;
        bit data_overlap_at_edge;
        bit control_overlap_at_edge;
        bit vrf_read_conflict_at_edge;
        bit vrf_write_conflict_at_edge;
        bit matrix_conflict_at_edge;
        bit xor0_conflict_at_edge;
        bit payload_conflict_at_edge;
        bit unknown_at_edge;

        pair_accept_at_edge = h.dut.vv33_pair_accept;
        pair_product_at_edge = h.dut.vv33_pair_product_fire;
        pair_pop_at_edge = h.dut.vv33_pair_pop_fire;
        pair_response_at_edge = h.dut.vv33_pair_resp_q;
        data_overlap_at_edge = hdc_data_event && ecc_data_event;
        control_overlap_at_edge =
            hdc_data_event && h.dut.vv31_evt_ecc_control_progress;
        vrf_read_conflict_at_edge = vrf_read_conflict_now;
        vrf_write_conflict_at_edge = vrf_write_conflict_now;
        matrix_conflict_at_edge = matrix_conflict_now;
        xor0_conflict_at_edge = xor0_conflict_now;
        payload_conflict_at_edge = payload_conflict_now;
        unknown_at_edge = $isunknown({
            h.dut.vv33_pair_accept,
            h.dut.vv33_pair_product_fire,
            h.dut.vv33_pair_pop_fire,
            h.dut.vv33_pair_resp_q,
            h.dut.vv31_evt_hdc_matrix,
            h.dut.vv31_evt_ecc_matrix,
            h.dut.vv31_evt_hdc_xor0,
            h.dut.vv31_evt_ecc_xor0,
            h.dut.vv31_evt_hdc_vrf_read,
            h.dut.vv31_evt_ecc_vrf_prefetch,
            h.dut.vv31_evt_ecc_control_progress,
            h.dut.vv33_sq_read_fire,
            h.dut.vv33_sq_write_fire,
            h.bus.valid_o
        });

        #1;
        if (h.rst_ni && metric_active) begin
            if (pair_accept_at_edge)
                pair_accept_events++;
            if (pair_product_at_edge)
                pair_product_events++;
            if (pair_pop_at_edge)
                pair_pop_events++;
            if (pair_response_at_edge)
                pair_response_events++;
            if (data_overlap_at_edge)
                data_overlap_events++;
            if (control_overlap_at_edge)
                control_overlap_events++;
            if (vrf_read_conflict_at_edge)
                vrf_read_conflicts++;
            if (vrf_write_conflict_at_edge)
                vrf_write_conflicts++;
            if (matrix_conflict_at_edge) begin
                matrix_conflicts++;
                popcount_conflicts++;
            end
            if (xor0_conflict_at_edge)
                xor0_conflicts++;
            if (payload_conflict_at_edge)
                payload_conflicts++;
            if (unknown_at_edge
             || (h.bus.valid_o && $isunknown(h.bus.result_o))
             || ((|h.dut.vrf_we_direct)
                 && $isunknown({h.dut.vrf_wa, h.dut.vrf_wd})))
                unknown_events++;
        end
    end

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
                h.bus.issue_hold(
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
                h.bus.hdc_compute_count = h.bus.hdc_compute_count + 1;
                last_response_cycle = timing.response_cycle;
                if (result !== expected_match) begin
                    hmatch_result_errors++;
                    $error(
                        "[VV35:EVAL_HMATCH] scenario=%0s task=%0d got=%016h expected=%016h",
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

    initial begin
        logic [1023:0] query;
        logic [1023:0] prototype0;
        logic [1023:0] prototype1;
        logic [1023:0] prototype2;
        logic [1023:0] prototype3;
        logic [10:0] expected_score;
        logic [63:0] expected_match;
        vv31_timing_t start_timing;
        longint unsigned last_hmatch_response_cycle;
        longint unsigned experiment_start_cycle;
        longint unsigned experiment_end_cycle;
        longint unsigned wall_cycles;
        longint unsigned conflicts;
        int scenario_plusarg_seen;
        int task_count_plusarg_seen;
        int unsigned errors;

        metric_active = 1'b0;
        clear_metrics();
        scenario = "INTERLEAVED";
        task_count = VV35_DEFAULT_TASK_COUNT;
        scenario_plusarg_seen = $value$plusargs(
            "SCENARIO=%s", scenario
        );
        task_count_plusarg_seen = $value$plusargs(
            "TASK_COUNT=%d", task_count
        );
        serial_mode = (scenario == "SERIAL");
        if (!serial_mode && (scenario != "INTERLEAVED"))
            $fatal(
                1,
                "[VV35:EVAL] SCENARIO must be SERIAL or INTERLEAVED, got %0s",
                scenario
            );
        if ((task_count == 0) || (task_count > 100000))
            $fatal(1, "[VV35:EVAL] invalid TASK_COUNT=%0d", task_count);
        if ((h.dut.VV33_FINE_INTERLEAVE !== 1'b1)
         || (h.dut.VV33_PAIRED_HMATCH !== 1'b1))
            $fatal(
                1,
                "[VV35:EVAL] committed/default scheduler parameters are not enabled"
            );

        h.load_vectors();
        if (h.scalar_count < 1)
            $fatal(1, "[VV35:EVAL] vector bundle contains no legal K");

        // One random resident query and four deterministic resident classes.
        // Class zero is exact, so the earliest-index tie rule makes the golden
        // result independent of the scenario and of PMUL timing.
        query = h.hdc_train_samples[0] ^ h.hdc_role_vectors[1];
        prototype0 = query;
        prototype1 = ~query;
        prototype2 = query ^ {512{2'b01}};
        prototype3 = query ^ {256{4'b0001}};
        expected_score = vv31_hdc_overlap(query, prototype0);
        expected_match = vv31_hmatch_result(3'd0, expected_score);
        if ($isunknown({query, prototype0, prototype1, prototype2, prototype3})
         || (query == '0))
            $fatal(1, "[VV35:EVAL] invalid HDC vector bundle");

        h.reset_dut();
        h.validate_vector_contract();
        h.prepare_ecc_case(0);
        h.bus.write_hv(VV35_QUERY_SLOT, query);
        h.bus.write_hv(VV35_PROTO_BASE_SLOT + 4'd0, prototype0);
        h.bus.write_hv(VV35_PROTO_BASE_SLOT + 4'd1, prototype1);
        h.bus.write_hv(VV35_PROTO_BASE_SLOT + 4'd2, prototype2);
        h.bus.write_hv(VV35_PROTO_BASE_SLOT + 4'd3, prototype3);

        clear_metrics();
        h.start_background_pmul(0, start_timing);
        experiment_start_cycle = start_timing.response_cycle;
        metric_active = 1'b1;

        // Runtime scheduling policy is the sole experimental variable.
        if (serial_mode)
            h.wait_background_done_no_poll();
        run_hmatch_stream(expected_match, last_hmatch_response_cycle);
        if (!h.dut.ecc_job_done_q)
            h.wait_background_done_no_poll();
        @(posedge h.clk_i);
        #1;

        experiment_end_cycle = last_hmatch_response_cycle;
        if (h.pmul_wall_end_cycle > experiment_end_cycle)
            experiment_end_cycle = h.pmul_wall_end_cycle;
        wall_cycles = experiment_end_cycle - experiment_start_cycle;
        metric_active = 1'b0;

        h.check_background_pmul(0, 1'b1);
        conflicts = vrf_read_conflicts
                  + vrf_write_conflicts
                  + matrix_conflicts
                  + xor0_conflicts
                  + payload_conflicts;
        errors = h.total_errors()
               + hmatch_result_errors
               + unknown_events;
        if (hmatch_requested != task_count
         || hmatch_completed != task_count) begin
            errors++;
            $error(
                "[VV35:EVAL] HMATCH count mismatch requested=%0d completed=%0d expected=%0d",
                hmatch_requested,
                hmatch_completed,
                task_count
            );
        end
        if (conflicts != 0) begin
            errors++;
            $error("[VV35:EVAL] shared-resource conflicts=%0d", conflicts);
        end
        if ((pair_product_events != pair_accept_events * 16)
         || (pair_pop_events != pair_product_events)
         || (pair_response_events != pair_accept_events)) begin
            errors++;
            $error(
                "[VV35:EVAL] paired-HMATCH contract accept=%0d product=%0d pop=%0d response=%0d",
                pair_accept_events,
                pair_product_events,
                pair_pop_events,
                pair_response_events
            );
        end

        $display(
            "[VV35:EVAL_METRIC] scenario=%0s same_default_rtl=1 scenario_plusarg=%0d task_count_plusarg=%0d K=%064h K_weight=%0d task_count=%0d hmatch_requested=%0d hmatch_completed=%0d expected_class=%0d expected_score=%0d start_cycle=%0d end_cycle=%0d wall_cycles=%0d pmul_wall=%0d pmul_service=%0d foreground_only=%0d pair_accept=%0d pair_product=%0d pair_pop=%0d pair_response=%0d data_overlap=%0d control_overlap=%0d vrf_read_conflict=%0d vrf_write_conflict=%0d matrix_conflict=%0d popcount_conflict=%0d xor0_conflict=%0d payload_conflict=%0d unknown=%0d errors=%0d",
            scenario,
            scenario_plusarg_seen,
            task_count_plusarg_seen,
            h.scalar_inputs[0],
            vv31_hamming_weight256(h.scalar_inputs[0]),
            task_count,
            hmatch_requested,
            hmatch_completed,
            expected_match[13:11],
            expected_match[10:0],
            experiment_start_cycle,
            experiment_end_cycle,
            wall_cycles,
            h.pmul_wall_cycles,
            h.pmul_service_cycles,
            h.foreground_only_cycles,
            pair_accept_events,
            pair_product_events,
            pair_pop_events,
            pair_response_events,
            data_overlap_events,
            control_overlap_events,
            vrf_read_conflicts,
            vrf_write_conflicts,
            matrix_conflicts,
            popcount_conflicts,
            xor0_conflicts,
            payload_conflicts,
            unknown_events,
            errors
        );

        if (errors == 0)
            $display("[VV35:schedule_evidence] PASS scenario=%0s", scenario);
        else
            $fatal(
                1,
                "[VV35:schedule_evidence] FAIL scenario=%0s errors=%0d",
                scenario,
                errors
            );
        $finish;
    end
endmodule
