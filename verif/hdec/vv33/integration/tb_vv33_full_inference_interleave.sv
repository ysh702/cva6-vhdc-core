module tb_vv33_full_inference_interleave;
    import hdec_pkg::*;
    import hdec_vv31_ref_pkg::*;
    import hdec_vv31_driver_pkg::*;
    import hdec_vv31_check_pkg::*;
    import hdec_vv31_vectors_pkg::*;

    // PMUL uses rows 0--7 and 32--63.  The complete HDC inference keeps its
    // resident state in rows 8--31: role, encoded query, three prototypes and
    // one input HV.  No counter bank is used because background HCNTADD would
    // overlap prototype rows 16--31 in the current one-VRF organization.
    localparam logic [3:0] VV33_ROLE_SLOT       = 4'd2;
    localparam logic [3:0] VV33_QUERY_SLOT      = 4'd3;
    localparam logic [3:0] VV33_PROTO_BASE_SLOT = 4'd4;
    localparam logic [7:0] VV33_PROTO_COUNT     = 8'd3;
    localparam logic [3:0] VV33_INPUT_SLOT      = 4'd7;

    hdec_vv31_system_harness h();
    defparam h.dut.VV33_FINE_INTERLEAVE = 1'b1;

    logic [1023:0] role_hv;
    logic [1023:0] input_hv;
    logic [1023:0] encoded_query;
    logic [1023:0] prototype0;
    logic [1023:0] prototype1;
    logic [1023:0] prototype2;
    logic [9:0]    inference_rotation;
    logic [10:0]   expected_score;
    logic [63:0]   expected_match;

    bit mixed_active;
    longint unsigned vrf_read_conflicts;
    longint unsigned matrix_conflicts;
    longint unsigned xor0_conflicts;
    longint unsigned payload_conflicts;
    longint unsigned unknown_events;
    longint unsigned pair_accept_events;
    longint unsigned pair_response_events;
    longint unsigned pair_matrix_events;
    longint unsigned pair_pop_events;
    longint unsigned hperm_responses;
    longint unsigned hbind_responses;
    longint unsigned hmatch_responses;
    int unsigned local_errors;
    int unsigned pair_matrix_inflight;
    int unsigned pair_pop_inflight;
    bit pair_request_inflight;

    wire hdc_payload_producer =
           h.dut.vv31_evt_hdc_matrix
        || h.dut.vv33_pair_product_fire
        || h.dut.vv31_evt_hdc_xor0
        || ((h.dut.st_q == h.dut.S_UOP_P2_LANE)
            && h.dut.uop_p0_q.valid
            && (h.dut.uop_p0_use_counter
             || h.dut.uop_p0_use_clip
             || h.dut.uop_p0_use_shift));

    wire vrf_read_conflict =
        h.dut.vv31_evt_hdc_vrf_read
        && (h.dut.vv31_evt_ecc_vrf_prefetch
         || h.dut.vv33_sq_read_fire);
    wire matrix_conflict =
        (h.dut.vv31_evt_hdc_matrix || h.dut.vv33_pair_product_fire)
        && h.dut.vv31_evt_ecc_matrix;
    wire xor0_conflict =
        h.dut.vv31_evt_hdc_xor0 && h.dut.vv31_evt_ecc_xor0;
    wire payload_conflict =
        hdc_payload_producer && h.dut.vv31_evt_ecc_matrix;

    task automatic clear_local_metrics;
        begin
            mixed_active = 1'b0;
            vrf_read_conflicts = 0;
            matrix_conflicts = 0;
            xor0_conflicts = 0;
            payload_conflicts = 0;
            unknown_events = 0;
            pair_accept_events = 0;
            pair_response_events = 0;
            pair_matrix_events = 0;
            pair_pop_events = 0;
            hperm_responses = 0;
            hbind_responses = 0;
            hmatch_responses = 0;
            local_errors = 0;
            pair_matrix_inflight = 0;
            pair_pop_inflight = 0;
            pair_request_inflight = 1'b0;
        end
    endtask

    task automatic prepare_hdc_resident_state;
        begin
            h.bus.write_hv(VV33_ROLE_SLOT, role_hv);
            h.bus.write_hv(VV33_QUERY_SLOT, '0);
            h.bus.write_hv(VV33_PROTO_BASE_SLOT + 4'd0, prototype0);
            h.bus.write_hv(VV33_PROTO_BASE_SLOT + 4'd1, prototype1);
            h.bus.write_hv(VV33_PROTO_BASE_SLOT + 4'd2, prototype2);
            h.bus.write_hv(VV33_INPUT_SLOT, input_hv);
        end
    endtask

    task automatic issue_status_op(
        input hdec_op_t operation,
        input logic [63:0] operand,
        input string label,
        output vv31_timing_t timing
    );
        logic [63:0] result;
        begin
            h.bus.issue_hold(operation, operand, '0, result, timing);
            h.bus.hdc_compute_count = h.bus.hdc_compute_count + 1;
            h.bus.expect_status_ok(label, result);
        end
    endtask

    function automatic logic [63:0] vv33_fused_inference_operand;
        logic [63:0] operand;
        begin
            operand = '0;
            operand[63]    = 1'b1;
            operand[3:0]   = VV33_QUERY_SLOT;
            operand[7:4]   = VV33_ROLE_SLOT;
            operand[9:8]   = inference_rotation[1:0];
            operand[13:10] = inference_rotation[5:2];
            operand[15:14] = inference_rotation[7:6];
            operand[17:16] = inference_rotation[9:8];
            operand[21:18] = VV33_INPUT_SLOT;
            operand[25:22] = VV33_PROTO_BASE_SLOT;
            operand[28:26] = VV33_PROTO_COUNT[2:0] - 3'd1;
            vv33_fused_inference_operand = operand;
        end
    endfunction

    // Accelerator-resident complete inference.  One macro request keeps the
    // complete dependency chain in HDEC: HPERM produces the role transform,
    // the shared XOR0 forms the query, then the existing three-class HMATCH
    // sidecar consumes compatible ECC diagonal windows.
    task automatic run_one_full_inference(
        output longint unsigned response_cycle
    );
        logic [63:0] result;
        vv31_timing_t timing;
        begin
            h.bus.issue_hold(
                HDEC_HMATCH,
                vv33_fused_inference_operand(),
                '0,
                result,
                timing
            );
            h.bus.hdc_compute_count = h.bus.hdc_compute_count + 1;
            h.bus.expect_equal64("full inference HMATCH", result, expected_match);
            // These counters denote completed semantic stages.  The external
            // protocol contains one response, not three responses.
            hperm_responses++;
            hbind_responses++;
            hmatch_responses++;
            h.bus.complete_episode_count = h.bus.complete_episode_count + 1;
            response_cycle = timing.response_cycle;
        end
    endtask

    task automatic run_full_inference_batch(
        input int unsigned inference_count,
        output longint unsigned batch_cycles,
        output longint unsigned last_response_cycle
    );
        longint unsigned start_cycle;
        begin
            start_cycle = h.bus.cycle_count;
            last_response_cycle = start_cycle;
            for (int unsigned inference_index = 0;
                 inference_index < inference_count;
                 inference_index++) begin
                run_one_full_inference(last_response_cycle);
            end
            batch_cycles = last_response_cycle - start_cycle;
        end
    endtask

    always @(posedge h.clk_i) begin : monitor_full_inference_contract
        bit accept_at_edge;
        bit product_at_edge;
        bit pop_at_edge;
        accept_at_edge = h.dut.vv33_pair_start;
        product_at_edge = h.dut.vv33_pair_product_fire;
        pop_at_edge = h.dut.vv33_pair_pop_fire;
        #1;
        if (h.rst_ni && mixed_active) begin
            if (accept_at_edge) begin
                pair_accept_events++;
                if (pair_request_inflight) begin
                    local_errors++;
                    $error("[VV33:FULL_INFERENCE] overlapping paired HMATCH requests");
                end
                pair_request_inflight = 1'b1;
                pair_matrix_inflight = 0;
                pair_pop_inflight = 0;
            end
            if (product_at_edge) begin
                pair_matrix_events++;
                pair_matrix_inflight++;
            end
            if (pop_at_edge) begin
                pair_pop_events++;
                pair_pop_inflight++;
                if (pair_pop_inflight > pair_matrix_inflight) begin
                    local_errors++;
                    $error("[VV33:FULL_INFERENCE] POPCOUNT outran matrix");
                end
            end
            if (h.dut.vv33_pair_resp_q) begin
                pair_response_events++;
                if (!pair_request_inflight
                 || (pair_matrix_inflight != 12)
                 || (pair_pop_inflight != 12)) begin
                    local_errors++;
                    $error(
                        "[VV33:FULL_INFERENCE] paired response mismatch active=%0d matrix=%0d pop=%0d",
                        pair_request_inflight,
                        pair_matrix_inflight,
                        pair_pop_inflight
                    );
                end
                pair_request_inflight = 1'b0;
                pair_matrix_inflight = 0;
                pair_pop_inflight = 0;
            end

            if (vrf_read_conflict)
                vrf_read_conflicts++;
            if (matrix_conflict)
                matrix_conflicts++;
            if (xor0_conflict)
                xor0_conflicts++;
            if (payload_conflict)
                payload_conflicts++;
            if ($isunknown({
                    h.dut.vv31_evt_hdc_matrix,
                    h.dut.vv31_evt_ecc_matrix,
                    h.dut.vv31_evt_hdc_xor0,
                    h.dut.vv31_evt_ecc_xor0,
                    h.dut.vv31_evt_hdc_vrf_read,
                    h.dut.vv31_evt_ecc_vrf_prefetch,
                    h.dut.vv33_sq_read_fire,
                    h.dut.vv33_sq_write_fire,
                    h.dut.vv33_pair_start,
                    h.dut.vv33_pair_product_fire,
                    h.dut.vv33_pair_pop_fire,
                    h.dut.vv33_pair_resp_q,
                    h.bus.valid_o
                })) begin
                unknown_events++;
                local_errors++;
                $error("[VV33:FULL_INFERENCE] control event X/Z");
            end
            if (h.bus.valid_o && $isunknown(h.bus.result_o)) begin
                unknown_events++;
                local_errors++;
                $error("[VV33:FULL_INFERENCE] response X/Z");
            end
        end
    end

    initial begin
        vv31_timing_t start_timing;
        logic [1023:0] got_query;
        longint unsigned single_inference_cycles;
        longint unsigned hdc_batch_cycles;
        longint unsigned standalone_pmul_cycles;
        longint unsigned capacity_start_cycle;
        longint unsigned capacity_pmul_cycles;
        longint unsigned capacity_last_response;
        longint unsigned fixed_mixed_start_cycle;
        longint unsigned fixed_mixed_end_cycle;
        longint unsigned fixed_mixed_cycles;
        longint unsigned fixed_mixed_pmul_cycles;
        longint unsigned fixed_last_response;
        longint unsigned serial_start_cycle;
        longint unsigned serial_end_cycle;
        longint unsigned serial_measured_cycles;
        longint unsigned serial_calc_cycles;
        longint unsigned serial_transition_cycles;
        longint unsigned independent_dual_cycles;
        longint unsigned saved_cycles;
        longint unsigned serial_reduction_bp;
        longint unsigned speedup_bp;
        longint unsigned gap_closure_bp;
        longint unsigned dual_efficiency_bp;
        longint unsigned mixed_pmul_stretch_cycles;
        longint signed mixed_pmul_stretch_bp;
        longint unsigned response_cycle;
        int unsigned capacity_n_fit;
        int unsigned capacity_partial;
        int unsigned fixed_n;
        int unsigned forced_n;
        bit forced_fixed_work;
        int unsigned errors;

        clear_local_metrics();
        forced_fixed_work = $value$plusargs("VV33_FIXED_N=%d", forced_n);
        h.load_vectors();
        if (h.scalar_count != 1)
            $fatal(
                1,
                "[VV33:FULL_INFERENCE] expected exactly one random K, got %0d",
                h.scalar_count
            );

        role_hv = h.hdc_role_vectors[0];
        prototype0 = h.hdc_query_vectors[0];
        inference_rotation = {
            h.master_seed_mem[0][7:0], 2'b00
        };
        if (inference_rotation == 10'd0)
            inference_rotation = 10'd4;
        encoded_query = prototype0;
        input_hv = encoded_query
                 ^ vv31_rotr1024(role_hv, inference_rotation);
        prototype1 = ~prototype0;
        prototype2 = prototype0 & {512{2'b01}};
        expected_score = vv31_hdc_overlap(encoded_query, prototype0);
        expected_match = vv31_hmatch_result(3'd0, expected_score);
        if ($isunknown({role_hv, input_hv, prototype0})
         || (role_hv == '0)
         || (prototype0 == '0))
            $fatal(1, "[VV33:FULL_INFERENCE] invalid resident vector set");

        // One standalone complete inference establishes the accelerator-kernel
        // latency.  Model construction and all resident writes are excluded.
        h.reset_dut();
        h.validate_vector_contract();
        prepare_hdc_resident_state();
        run_full_inference_batch(1, single_inference_cycles, response_cycle);
        h.bus.read_hv(VV33_QUERY_SLOT, got_query);
        h.bus.expect_equal1024(
            "standalone full-inference encoded query",
            got_query,
            encoded_query
        );
        if (h.total_errors() != 0)
            $fatal(1, "[VV33:FULL_INFERENCE] standalone inference failed");

        // Standalone PMUL uses the same random K as every mixed replay.
        h.reset_dut();
        h.validate_vector_contract();
        h.prepare_ecc_case(0);
        h.start_background_pmul(0, start_timing);
        h.wait_background_done_no_poll();
        standalone_pmul_cycles = h.pmul_wall_cycles;
        h.check_background_pmul(0, 1'b1);
        h.check_ecc_guards(0);
        if (h.total_errors() != 0)
            $fatal(1, "[VV33:FULL_INFERENCE] standalone PMUL failed");

        // Capacity probe: stop launching new work after the PMUL-done edge.
        // A chain whose final HMATCH response occurs after that edge is partial
        // for this capacity statistic, even though its protocol is completed.
        if (forced_fixed_work) begin
            capacity_n_fit=forced_n;
            capacity_partial=0;
            capacity_pmul_cycles=0;
        end else begin
            h.reset_dut();
            h.validate_vector_contract();
            h.prepare_ecc_case(0);
            prepare_hdc_resident_state();
            clear_local_metrics();
            h.start_background_pmul(0, start_timing);
            capacity_start_cycle = start_timing.response_cycle;
            mixed_active = 1'b1;
            capacity_n_fit = 0;
            capacity_partial = 0;
            capacity_last_response = capacity_start_cycle;
            while (!h.dut.ecc_job_done_q) begin
                run_one_full_inference(capacity_last_response);
                if ((h.pmul_wall_end_cycle == 0)
                 || (capacity_last_response <= h.pmul_wall_end_cycle))
                    capacity_n_fit++;
                else
                    capacity_partial = 1;
            end
            h.wait_background_done_no_poll();
            capacity_pmul_cycles = h.pmul_wall_cycles;
            mixed_active = 1'b0;
            h.check_background_pmul(0, 1'b1);
            h.check_ecc_guards(0);
            if (capacity_n_fit == 0)
                $fatal(1, "[VV33:FULL_INFERENCE] capacity probe retired no inference");
        end

        // Measure the exact HDC workload selected by the capacity probe with no
        // ECC activity.  This is a direct batch measurement, not N*C_single.
        fixed_n = forced_fixed_work ? forced_n : capacity_n_fit;
        h.reset_dut();
        h.validate_vector_contract();
        prepare_hdc_resident_state();
        run_full_inference_batch(fixed_n, hdc_batch_cycles, response_cycle);
        if (h.total_errors() != 0)
            $fatal(1, "[VV33:FULL_INFERENCE] standalone HDC batch failed");

        // Actual serial HDEC: identical resident inputs are prepared before t0,
        // one PMUL completes, then the same N complete inferences execute.
        h.reset_dut();
        h.validate_vector_contract();
        h.prepare_ecc_case(0);
        prepare_hdc_resident_state();
        h.start_background_pmul(0, start_timing);
        serial_start_cycle = start_timing.response_cycle;
        h.wait_background_done_no_poll();
        run_full_inference_batch(fixed_n, response_cycle, serial_end_cycle);
        serial_measured_cycles = serial_end_cycle - serial_start_cycle;
        h.check_background_pmul(0, 1'b1);
        h.check_ecc_guards(0);
        serial_calc_cycles = standalone_pmul_cycles + hdc_batch_cycles;
        serial_transition_cycles = serial_measured_cycles - serial_calc_cycles;
        if (h.total_errors() != 0)
            $fatal(1, "[VV33:FULL_INFERENCE] serial HDEC failed");

        // Fixed-work mixed replay: launch exactly N inferences and then wait for
        // whichever side finishes last.  No uncounted N+1 partial work exists.
        h.reset_dut();
        h.validate_vector_contract();
        h.prepare_ecc_case(0);
        prepare_hdc_resident_state();
        clear_local_metrics();
        h.start_background_pmul(0, start_timing);
        fixed_mixed_start_cycle = start_timing.response_cycle;
        mixed_active = 1'b1;
        run_full_inference_batch(fixed_n, response_cycle, fixed_last_response);
        if (!h.dut.ecc_job_done_q)
            h.wait_background_done_no_poll();
        fixed_mixed_pmul_cycles = h.pmul_wall_cycles;
        fixed_mixed_end_cycle = (h.pmul_wall_end_cycle > fixed_last_response)
            ? h.pmul_wall_end_cycle : fixed_last_response;
        fixed_mixed_cycles = fixed_mixed_end_cycle - fixed_mixed_start_cycle;
        mixed_active = 1'b0;
        h.check_background_pmul(0, 1'b1);
        h.check_ecc_guards(0);

        independent_dual_cycles = (standalone_pmul_cycles > hdc_batch_cycles)
            ? standalone_pmul_cycles : hdc_batch_cycles;
        saved_cycles = serial_measured_cycles - fixed_mixed_cycles;
        serial_reduction_bp = (saved_cycles * 10000)
                            / serial_measured_cycles;
        speedup_bp = (serial_measured_cycles * 10000)
                   / fixed_mixed_cycles;
        if (serial_measured_cycles > independent_dual_cycles)
            gap_closure_bp = (saved_cycles * 10000)
                           / (serial_measured_cycles - independent_dual_cycles);
        else
            gap_closure_bp = 0;
        dual_efficiency_bp = (independent_dual_cycles * 10000)
                           / fixed_mixed_cycles;
        mixed_pmul_stretch_cycles = fixed_mixed_pmul_cycles
                                  - standalone_pmul_cycles;
        mixed_pmul_stretch_bp = ($signed(fixed_mixed_pmul_cycles)
                               - $signed(standalone_pmul_cycles)) * 10000
                              / $signed(standalone_pmul_cycles);

        errors = h.total_errors() + local_errors;
        if ((vrf_read_conflicts != 0)
         || (matrix_conflicts != 0)
         || (xor0_conflicts != 0)
         || (payload_conflicts != 0)
         || (unknown_events != 0)
         || pair_request_inflight
         || (pair_accept_events != pair_response_events)
         || (pair_matrix_events != (pair_response_events * 12))
         || (pair_pop_events != pair_matrix_events)) begin
            errors++;
            $error(
                "[VV33:FULL_INFERENCE] resource/paired contract failed vrf=%0d matrix=%0d xor0=%0d payload=%0d unknown=%0d active=%0d accept=%0d response=%0d pair_matrix=%0d pair_pop=%0d",
                vrf_read_conflicts,
                matrix_conflicts,
                xor0_conflicts,
                payload_conflicts,
                unknown_events,
                pair_request_inflight,
                pair_accept_events,
                pair_response_events,
                pair_matrix_events,
                pair_pop_events
            );
        end
        if ((fixed_mixed_cycles > serial_measured_cycles)
         || (fixed_mixed_cycles < independent_dual_cycles)
         || (saved_cycles == 0)) begin
            errors++;
            $error(
                "[VV33:FULL_INFERENCE] performance ordering invalid dual=%0d mixed=%0d serial=%0d saved=%0d",
                independent_dual_cycles,
                fixed_mixed_cycles,
                serial_measured_cycles,
                saved_cycles
            );
        end

        $display(
            "[VV33:FULL_INFERENCE_METRIC] K=%064h weight=%0d classes=%0d inference_ops=3 rotation=%0d standalone_inference=%0d capacity_n_fit=%0d capacity_partial=%0d capacity_pmul=%0d fixed_n=%0d standalone_hdc_batch=%0d independent_dual=%0d interleaved_hdec=%0d serial_hdec=%0d serial_calc=%0d serial_transition=%0d saved_cycles=%0d serial_reduction_bp=%0d speedup_bp=%0d gap_closure_bp=%0d dual_efficiency_bp=%0d standalone_pmul=%0d mixed_pmul=%0d mixed_pmul_stretch=%0d mixed_pmul_stretch_bp=%0d hperm_response=%0d hbind_response=%0d hmatch_response=%0d pair_accept=%0d pair_response=%0d pair_matrix=%0d pair_pop=%0d vrf_read_conflict=%0d matrix_conflict=%0d xor0_conflict=%0d payload_conflict=%0d unknown=%0d errors=%0d",
            h.scalar_inputs[0],
            vv31_hamming_weight256(h.scalar_inputs[0]),
            VV33_PROTO_COUNT,
            inference_rotation,
            single_inference_cycles,
            capacity_n_fit,
            capacity_partial,
            capacity_pmul_cycles,
            fixed_n,
            hdc_batch_cycles,
            independent_dual_cycles,
            fixed_mixed_cycles,
            serial_measured_cycles,
            serial_calc_cycles,
            serial_transition_cycles,
            saved_cycles,
            serial_reduction_bp,
            speedup_bp,
            gap_closure_bp,
            dual_efficiency_bp,
            standalone_pmul_cycles,
            fixed_mixed_pmul_cycles,
            mixed_pmul_stretch_cycles,
            mixed_pmul_stretch_bp,
            hperm_responses,
            hbind_responses,
            hmatch_responses,
            pair_accept_events,
            pair_response_events,
            pair_matrix_events,
            pair_pop_events,
            vrf_read_conflicts,
            matrix_conflicts,
            xor0_conflicts,
            payload_conflicts,
            unknown_events,
            errors
        );
        $display(
            "[VV33:FULL_INFERENCE_PRIMARY] independent_dual=%0d interleaved_hdec=%0d serial_hdec=%0d reduced_cycles=%0d reduction_bp=%0d",
            independent_dual_cycles,
            fixed_mixed_cycles,
            serial_measured_cycles,
            saved_cycles,
            serial_reduction_bp
        );

        if (errors == 0)
            $display("[VV33:full_inference_interleave] PASS");
        else
            $fatal(
                1,
                "[VV33:full_inference_interleave] FAIL errors=%0d",
                errors
            );
        $finish;
    end
endmodule
