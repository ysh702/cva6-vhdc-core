module tb_vv33_bank_episode_interleave;
    import hdec_pkg::*;
    import hdec_vv31_ref_pkg::*;
    import hdec_vv31_driver_pkg::*;
    import hdec_vv31_check_pkg::*;
    import hdec_vv31_vectors_pkg::*;

    localparam logic [3:0] VV33_WORK_SLOT  = VV31_HDC_HV2_SLOT;
    localparam logic [3:0] VV33_QUERY_SLOT = VV31_HDC_HV3_SLOT;
    localparam logic [3:0] VV33_PROTO_BASE_SLOT = 4'd4;
    localparam logic [7:0] VV33_PROTO_COUNT = 8'd4;
    localparam int unsigned VV33_EPISODE_STAGES = 16;

    hdec_vv31_system_harness h();
    defparam h.dut.VV33_FINE_INTERLEAVE = 1'b1;

    logic [1023:0] base_vector;
    logic [1023:0] expected_prototype;
    logic [10:0]   expected_similarity;

    bit mixed_probe_active;
    bit pmul_done_seen;
    bit episode_active;
    bit stage_active;
    logic [4:0] current_stage_id;
    int unsigned completed_stages_in_episode;
    int unsigned completed_episodes;
    longint unsigned completed_hdc_ops;

    longint unsigned pmul_done_cycle;
    int unsigned completed_episodes_at_pmul_done;
    int unsigned completed_stages_at_pmul_done;
    int unsigned unfinished_stage_at_pmul_done;
    bit unfinished_stage_active_at_pmul_done;
    longint unsigned completed_hdc_ops_at_pmul_done;

    longint unsigned data_overlap_events;
    longint unsigned control_overlap_events;
    longint unsigned resource_pair_events;
    longint unsigned pair_matrix_events;
    longint unsigned pair_pop_events;
    longint unsigned pair_accept_events;
    longint unsigned pair_response_events;
    longint unsigned vrf_read_conflicts;
    longint unsigned matrix_conflicts;
    longint unsigned xor0_conflicts;
    longint unsigned popcount_conflicts;
    longint unsigned payload_conflicts;
    longint unsigned unknown_events;
    longint unsigned local_errors;
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

    wire existing_vrf_read_conflict =
        h.dut.vv31_evt_hdc_vrf_read
        && (h.dut.vv31_evt_ecc_vrf_prefetch
         || h.dut.vv33_sq_read_fire);
    wire existing_matrix_conflict =
        (h.dut.vv31_evt_hdc_matrix || h.dut.vv33_pair_product_fire)
        && h.dut.vv31_evt_ecc_matrix;
    wire existing_xor0_conflict =
        h.dut.vv31_evt_hdc_xor0 && h.dut.vv31_evt_ecc_xor0;
    wire existing_payload_conflict =
        hdc_payload_producer && h.dut.vv31_evt_ecc_matrix;
    wire hdc_visible_compute =
           h.dut.vv31_evt_hdc_matrix
        || h.dut.vv31_evt_hdc_xor0
        || h.dut.hdc_pop_capture
        || ((h.dut.st_q == h.dut.S_UOP_P3_POP_CAPTURE)
            && ((h.dut.uop_p3_q.op_type == h.dut.UOP_HSIM_CHUNK)
             || (h.dut.uop_p3_q.op_type == h.dut.UOP_HMATCH_CHUNK)))
        || ((h.dut.st_q == h.dut.S_UOP_P2_LANE)
            && h.dut.uop_p0_q.valid
            && (h.dut.uop_p0_use_counter
             || h.dut.uop_p0_use_clip
             || h.dut.uop_p0_use_shift));
    wire ecc_visible_data_progress =
           h.dut.vv31_evt_ecc_vrf_prefetch
        || h.dut.vv31_evt_ecc_square
        || h.dut.vv33_sq_read_fire
        || h.dut.vv33_sq_write_fire;

    function automatic logic [9:0] episode_rotation(
        input logic [7:0] seed_byte,
        input int unsigned sample
    );
        int unsigned quarter_turn;
        begin
            quarter_turn = (seed_byte + sample * 53) & 8'hff;
            episode_rotation = (quarter_turn << 2) & 10'h3ff;
        end
    endfunction

    function automatic string stage_name(input int unsigned stage_id);
        case (stage_id)
            1:  stage_name = "HCNTCLR";
            2:  stage_name = "HPERM0";
            3:  stage_name = "HBIND0";
            4:  stage_name = "HCNTADD0";
            5:  stage_name = "HPERM1";
            6:  stage_name = "HBIND1";
            7:  stage_name = "HCNTADD1";
            8:  stage_name = "HPERM2";
            9:  stage_name = "HBIND2";
            10: stage_name = "HCNTADD2";
            11: stage_name = "HPERM3";
            12: stage_name = "HBIND3";
            13: stage_name = "HCNTADD3";
            14: stage_name = "HCNTCLIP";
            15: stage_name = "HSIM";
            16: stage_name = "HMATCH";
            default: stage_name = "BETWEEN_EPISODES";
        endcase
    endfunction

    task automatic clear_mixed_metrics;
        begin
            mixed_probe_active = 1'b0;
            pmul_done_seen = 1'b0;
            episode_active = 1'b0;
            stage_active = 1'b0;
            current_stage_id = '0;
            completed_stages_in_episode = 0;
            completed_episodes = 0;
            completed_hdc_ops = 0;
            pmul_done_cycle = 0;
            completed_episodes_at_pmul_done = 0;
            completed_stages_at_pmul_done = 0;
            unfinished_stage_at_pmul_done = 0;
            unfinished_stage_active_at_pmul_done = 1'b0;
            completed_hdc_ops_at_pmul_done = 0;
            data_overlap_events = 0;
            control_overlap_events = 0;
            resource_pair_events = 0;
            pair_matrix_events = 0;
            pair_pop_events = 0;
            pair_accept_events = 0;
            pair_response_events = 0;
            vrf_read_conflicts = 0;
            matrix_conflicts = 0;
            xor0_conflicts = 0;
            popcount_conflicts = 0;
            payload_conflicts = 0;
            unknown_events = 0;
            local_errors = 0;
            pair_matrix_inflight = 0;
            pair_pop_inflight = 0;
            pair_request_inflight = 1'b0;
        end
    endtask

    task automatic begin_stage(input int unsigned stage_id);
        begin
            current_stage_id = stage_id[4:0];
            stage_active = 1'b1;
        end
    endtask

    task automatic finish_stage;
        begin
            // issue_hold samples a response at posedge+#1.  Moving the driver
            // bookkeeping one delta later lets the PMUL-done monitor retain
            // the exact instruction that was in flight on the completion edge.
            #1;
            stage_active = 1'b0;
            completed_stages_in_episode++;
            completed_hdc_ops++;
        end
    endtask

    task automatic issue_status_stage(
        input int unsigned stage_id,
        input hdec_op_t operation,
        input logic [63:0] operand,
        input string label
    );
        logic [63:0] result;
        vv31_timing_t timing;
        begin
            begin_stage(stage_id);
            h.bus.issue_hold(operation, operand, '0, result, timing);
            h.bus.hdc_compute_count = h.bus.hdc_compute_count + 1;
            h.bus.expect_status_ok(label, result);
            finish_stage();
        end
    endtask

    task automatic issue_value_stage(
        input int unsigned stage_id,
        input hdec_op_t operation,
        input logic [63:0] operand,
        input logic [63:0] expected,
        input string label
    );
        logic [63:0] result;
        vv31_timing_t timing;
        begin
            begin_stage(stage_id);
            h.bus.issue_hold(operation, operand, '0, result, timing);
            h.bus.hdc_compute_count = h.bus.hdc_compute_count + 1;
            h.bus.expect_equal64(label, result, expected);
            finish_stage();
        end
    endtask

    task automatic run_one_episode(
        output bit completed,
        output longint unsigned prototype_construction_cycles
    );
        logic [1023:0] permuted_role;
        logic [1023:0] encoded_sample;
        logic [63:0] expected_match;
        logic [9:0] rotation;
        int unsigned stage_id;
        longint unsigned prototype_construction_start;
        begin
            completed = 1'b0;
            prototype_construction_cycles = 0;
            prototype_construction_start = h.bus.cycle_count;
            episode_active = 1'b1;
            completed_stages_in_episode = 0;
            current_stage_id = '0;
            expected_prototype = '0;

            issue_status_stage(1, HDEC_HCNTCLR, 64'd0, "episode HCNTCLR");

            stage_id = 2;
            for (int unsigned sample = 0; sample < 4; sample++) begin
                rotation = episode_rotation(
                    h.master_seed_mem[0][7:0], sample
                );
                issue_status_stage(
                    stage_id,
                    HDEC_HPERM,
                    vv31_hperm_operand(
                        VV33_WORK_SLOT, VV33_QUERY_SLOT, rotation
                    ),
                    "episode HPERM"
                );
                stage_id++;

                issue_status_stage(
                    stage_id,
                    HDEC_HBIND,
                    vv31_hbind_operand(
                        VV33_WORK_SLOT,
                        VV33_WORK_SLOT,
                        VV33_QUERY_SLOT
                    ),
                    "episode HBIND"
                );
                stage_id++;

                permuted_role = vv31_rotr1024(base_vector, rotation);
                encoded_sample = vv31_hdc_bind(
                    permuted_role, base_vector
                );
                expected_prototype |= encoded_sample;
                issue_status_stage(
                    stage_id,
                    HDEC_HCNTADD,
                    {60'd0, VV33_WORK_SLOT},
                    "episode HCNTADD"
                );
                stage_id++;
            end

            issue_status_stage(
                14,
                HDEC_HCNTCLIP,
                vv31_hcntclip_operand(VV33_WORK_SLOT[2:0], 1'b0, 4'd1),
                "episode HCNTCLIP"
            );
            prototype_construction_cycles =
                h.bus.cycle_count - prototype_construction_start;

            expected_similarity = vv31_hdc_overlap(
                base_vector, expected_prototype
            );
            issue_value_stage(
                15,
                HDEC_HSIM,
                vv31_hsim_operand(VV33_QUERY_SLOT, VV33_WORK_SLOT),
                {53'd0, expected_similarity},
                "episode HSIM"
            );

            expected_match = vv31_hmatch_result(3'd0, expected_similarity);
            issue_value_stage(
                16,
                HDEC_HMATCH,
                vv31_hmatch_operand(
                    VV33_QUERY_SLOT, VV33_WORK_SLOT, 8'd1
                ),
                expected_match,
                "episode HMATCH"
            );
            completed = 1'b1;
            completed_episodes++;
            h.bus.complete_episode_count =
                h.bus.complete_episode_count + 1;
            current_stage_id = '0;
            completed_stages_in_episode = 0;
            episode_active = 1'b0;
        end
    endtask

    // Online inference reuses previously constructed prototypes.  Query
    // encoding and prototype construction are outside this kernel boundary;
    // HMATCH performs a four-class highest-overlap prototype search.
    task automatic run_one_inference(output bit completed);
        logic [63:0] expected_match;
        begin
            completed = 1'b0;
            episode_active = 1'b1;
            completed_stages_in_episode = 0;
            current_stage_id = '0;

            expected_match = vv31_hmatch_result(3'd0, expected_similarity);
            issue_value_stage(
                16,
                HDEC_HMATCH,
                vv31_hmatch_operand(
                    VV33_QUERY_SLOT,
                    VV33_PROTO_BASE_SLOT,
                    VV33_PROTO_COUNT
                ),
                expected_match,
                "four-class inference HMATCH"
            );
            if (mixed_probe_active && pmul_done_seen)
                return;

            completed = 1'b1;
            completed_episodes++;
            h.bus.complete_episode_count =
                h.bus.complete_episode_count + 1;
            current_stage_id = '0;
            completed_stages_in_episode = 0;
            episode_active = 1'b0;
        end
    endtask

    // Sample the sidecar handshakes before the DUT's nonblocking state update.
    // One accepted four-class HMATCH must traverse four 256-bit chunks for each
    // of four resident prototypes, hence exactly 16 paired matrix launches and
    // 16 matching POPCOUNT captures before its single response.
    always @(posedge h.clk_i) begin : monitor_paired_hmatch_contract
        bit mixed_at_edge;
        bit accept_at_edge;
        bit product_at_edge;
        bit pop_at_edge;
        bit product_state_ok_at_edge;
        bit pop_state_ok_at_edge;
        int unsigned state_at_edge;

        mixed_at_edge = mixed_probe_active;
        accept_at_edge = h.dut.vv33_pair_accept;
        product_at_edge = h.dut.vv33_pair_product_fire;
        pop_at_edge = h.dut.vv33_pair_pop_fire;
        state_at_edge = h.dut.st_q;
        product_state_ok_at_edge =
            (h.dut.st_q == h.dut.S_ECC_DIAG_CAPTURE2);
        pop_state_ok_at_edge =
            (h.dut.st_q == h.dut.S_ECC_DIAG_FOLD_ISSUE);
        #1;

        if (h.rst_ni && mixed_at_edge) begin
            if (accept_at_edge) begin
                pair_accept_events++;
                if (pair_request_inflight) begin
                    local_errors++;
                    $error(
                        "[VV33:PAIR_CONTRACT] accept while request active cycle=%0d",
                        h.bus.cycle_count
                    );
                end
                pair_request_inflight = 1'b1;
                pair_matrix_inflight = 0;
                pair_pop_inflight = 0;
            end

            if (product_at_edge) begin
                pair_matrix_events++;
                resource_pair_events++;
                pair_matrix_inflight++;
                if (!pair_request_inflight) begin
                    local_errors++;
                    $error(
                        "[VV33:PAIR_CONTRACT] matrix event without request cycle=%0d",
                        h.bus.cycle_count
                    );
                end
                if (!product_state_ok_at_edge) begin
                    local_errors++;
                    $error(
                        "[VV33:PAIR_CONTRACT] matrix event outside CAP2 cycle=%0d state=%0d",
                        h.bus.cycle_count,
                        state_at_edge
                    );
                end
            end

            if (pop_at_edge) begin
                pair_pop_events++;
                resource_pair_events++;
                pair_pop_inflight++;
                if (!pair_request_inflight) begin
                    local_errors++;
                    $error(
                        "[VV33:PAIR_CONTRACT] POPCOUNT event without request cycle=%0d",
                        h.bus.cycle_count
                    );
                end
                if (!pop_state_ok_at_edge) begin
                    local_errors++;
                    $error(
                        "[VV33:PAIR_CONTRACT] POPCOUNT event outside FOLD cycle=%0d state=%0d",
                        h.bus.cycle_count,
                        state_at_edge
                    );
                end
                if (pair_pop_inflight > pair_matrix_inflight) begin
                    local_errors++;
                    $error(
                        "[VV33:PAIR_CONTRACT] POPCOUNT outran matrix cycle=%0d matrix=%0d pop=%0d",
                        h.bus.cycle_count,
                        pair_matrix_inflight,
                        pair_pop_inflight
                    );
                end
            end

            if (h.dut.vv33_pair_resp_q) begin
                pair_response_events++;
                if (!pair_request_inflight) begin
                    local_errors++;
                    $error(
                        "[VV33:PAIR_CONTRACT] response without request cycle=%0d",
                        h.bus.cycle_count
                    );
                end
                if ((pair_matrix_inflight != 16)
                 || (pair_pop_inflight != 16)) begin
                    local_errors++;
                    $error(
                        "[VV33:PAIR_CONTRACT] response event count mismatch cycle=%0d matrix=%0d pop=%0d expected=16",
                        h.bus.cycle_count,
                        pair_matrix_inflight,
                        pair_pop_inflight
                    );
                end
                pair_request_inflight = 1'b0;
                pair_matrix_inflight = 0;
                pair_pop_inflight = 0;
            end
        end
    end

    always @(posedge h.clk_i) begin : monitor_mixed_execution
        #1;
        if (h.rst_ni && mixed_probe_active) begin
            if (!pmul_done_seen && h.dut.ecc_job_done_q) begin
                pmul_done_seen = 1'b1;
                pmul_done_cycle = h.bus.cycle_count;
                completed_episodes_at_pmul_done = completed_episodes;
                completed_stages_at_pmul_done =
                    completed_stages_in_episode;
                unfinished_stage_active_at_pmul_done = stage_active;
                if (!episode_active)
                    unfinished_stage_at_pmul_done = 0;
                else if (stage_active)
                    unfinished_stage_at_pmul_done = current_stage_id;
                else if (completed_stages_in_episode < VV33_EPISODE_STAGES)
                    unfinished_stage_at_pmul_done =
                        completed_stages_in_episode + 1;
                else
                    unfinished_stage_at_pmul_done = 0;
                completed_hdc_ops_at_pmul_done = completed_hdc_ops;
                $display(
                    "[VV33:BANK_EPISODE_DONE_EDGE] cycle=%0d completed_episodes=%0d completed_stages=%0d unfinished_stage=%0d unfinished_name=%0s active=%0d hdc_ops=%0d",
                    pmul_done_cycle,
                    completed_episodes_at_pmul_done,
                    completed_stages_at_pmul_done,
                    unfinished_stage_at_pmul_done,
                    stage_name(unfinished_stage_at_pmul_done),
                    unfinished_stage_active_at_pmul_done,
                    completed_hdc_ops_at_pmul_done
                );
            end

            if (hdc_visible_compute
             && h.dut.vv31_evt_ecc_control_progress)
                control_overlap_events++;
            if (stage_active && ecc_visible_data_progress)
                data_overlap_events++;
            if (hdc_visible_compute && ecc_visible_data_progress)
                resource_pair_events++;

            if (existing_vrf_read_conflict)
                vrf_read_conflicts++;
            if (existing_matrix_conflict)
                matrix_conflicts++;
            if (existing_xor0_conflict)
                xor0_conflicts++;
            if (existing_matrix_conflict)
                popcount_conflicts++;
            if (existing_payload_conflict)
                payload_conflicts++;

            if ($isunknown({
                    h.dut.vv31_evt_hdc_matrix,
                    h.dut.vv31_evt_ecc_matrix,
                    h.dut.vv31_evt_hdc_xor0,
                    h.dut.vv31_evt_ecc_xor0,
                    h.dut.vv31_evt_hdc_vrf_read,
                    h.dut.vv31_evt_ecc_vrf_prefetch,
                    h.dut.vv31_evt_ecc_square,
                    h.dut.vv31_evt_ecc_control_progress,
                    h.dut.vv33_sq_read_fire,
                    h.dut.vv33_sq_write_fire,
                    h.dut.vv33_pair_accept,
                    h.dut.vv33_pair_product_fire,
                    h.dut.vv33_pair_pop_fire,
                    h.dut.vv33_pair_resp_q,
                    h.bus.valid_o
                })) begin
                unknown_events++;
                local_errors++;
                $error(
                    "[VV33:BANK_EPISODE] control event X/Z cycle=%0d",
                    h.bus.cycle_count
                );
            end
            if (h.bus.valid_o && $isunknown(h.bus.result_o)) begin
                unknown_events++;
                local_errors++;
                $error(
                    "[VV33:BANK_EPISODE] response X/Z cycle=%0d",
                    h.bus.cycle_count
                );
            end
            if ((|h.dut.vrf_we_direct)
             && $isunknown({h.dut.vrf_wa, h.dut.vrf_wd})) begin
                unknown_events++;
                local_errors++;
                $error(
                    "[VV33:BANK_EPISODE] VRF write X/Z cycle=%0d",
                    h.bus.cycle_count
                );
            end
        end
    end

    initial begin
        bit episode_completed;
        logic [1023:0] got_prototype;
        logic [1023:0] trained_prototype;
        logic [1023:0] inference_query;
        logic [1023:0] inference_proto0;
        logic [1023:0] inference_proto1;
        logic [1023:0] inference_proto2;
        logic [1023:0] inference_proto3;
        vv31_timing_t start_timing;
        longint unsigned standalone_inference_start;
        longint unsigned standalone_inference_cycles;
        longint unsigned repeat_inference_start;
        longint unsigned repeat_inference_cycles;
        longint unsigned prototype_construction_cycles;
        longint unsigned standalone_pmul_cycles;
        longint unsigned mixed_pmul_service_cycles;
        longint unsigned mixed_foreground_only_cycles;
        longint unsigned mixed_start_cycle;
        longint unsigned mixed_wall_cycles;
        longint unsigned completed_work_cycles;
        longint unsigned serial_baseline_cycles;
        longint unsigned ideal_dual_cycles;
        longint unsigned serial_gap_cycles;
        longint signed saved_cycles;
        longint signed gap_closure_bp;
        longint signed mixed_pmul_stretch_cycles;
        int unsigned standalone_repeat_mismatches;
        int unsigned errors;

        clear_mixed_metrics();
        h.load_vectors();
        if (h.scalar_count != 1)
            $fatal(
                1,
                "[VV33:BANK_EPISODE] expected exactly one random K, got %0d",
                h.scalar_count
            );
        base_vector = h.hdc_train_samples[0] ^ h.hdc_role_vectors[1];
        if ($isunknown(base_vector) || (base_vector == '0))
            $fatal(1, "[VV33:BANK_EPISODE] invalid random base vector");

        // Build and verify one prototype before the timed inference experiment.
        // Training is an infrequent setup operation and is reported separately
        // from the repeated online-inference stream.
        h.reset_dut();
        h.validate_vector_contract();
        h.bus.write_hv(VV33_QUERY_SLOT, base_vector);
        run_one_episode(
            episode_completed,
            prototype_construction_cycles
        );
        if (!episode_completed)
            $fatal(1, "[VV33:BANK_EPISODE] standalone episode incomplete");
        h.bus.read_hv(VV33_WORK_SLOT, got_prototype);
        h.bus.expect_equal1024(
            "standalone episode prototype",
            got_prototype,
            expected_prototype
        );
        trained_prototype = expected_prototype;

        // Construct a deterministic four-class associative memory from the
        // trained prototype.  Class 0 is the exact query prototype; the other
        // classes cannot exceed its AND-POPCOUNT overlap score.  The defined
        // earliest-index tie rule therefore keeps class 0 as the winner.
        inference_query  = trained_prototype;
        inference_proto0 = trained_prototype;
        inference_proto1 = ~trained_prototype;
        inference_proto2 = trained_prototype ^ {512{2'b01}};
        inference_proto3 = trained_prototype ^ {256{4'b0001}};
        expected_similarity = vv31_hdc_overlap(
            inference_query, inference_proto0
        );
        h.bus.write_hv(VV33_QUERY_SLOT, inference_query);
        h.bus.write_hv(VV33_PROTO_BASE_SLOT + 4'd0, inference_proto0);
        h.bus.write_hv(VV33_PROTO_BASE_SLOT + 4'd1, inference_proto1);
        h.bus.write_hv(VV33_PROTO_BASE_SLOT + 4'd2, inference_proto2);
        h.bus.write_hv(VV33_PROTO_BASE_SLOT + 4'd3, inference_proto3);

        // Measure one four-class highest-overlap prototype search with the
        // query and constructed prototypes already resident in the shared VRF.
        standalone_inference_start = h.bus.cycle_count;
        run_one_inference(episode_completed);
        standalone_inference_cycles =
            h.bus.cycle_count - standalone_inference_start;
        if (!episode_completed)
            $fatal(1, "[VV33:BANK_EPISODE] standalone inference incomplete");
        if (h.total_errors() != 0)
            $fatal(
                1,
                "[VV33:BANK_EPISODE] standalone HDC failed errors=%0d",
                h.total_errors()
            );

        // Confirm that multiplying a standalone search latency by the number
        // of completed searches is valid for this fixed resident data set.
        // These four checks are outside the mixed-run timing interval.
        standalone_repeat_mismatches = 0;
        for (int unsigned repeat_index = 0;
             repeat_index < 4;
             repeat_index++) begin
            repeat_inference_start = h.bus.cycle_count;
            run_one_inference(episode_completed);
            repeat_inference_cycles =
                h.bus.cycle_count - repeat_inference_start;
            if (!episode_completed
             || (repeat_inference_cycles != standalone_inference_cycles)) begin
                standalone_repeat_mismatches++;
                $error(
                    "[VV33:INFERENCE_REPEAT] index=%0d completed=%0d cycles=%0d expected=%0d",
                    repeat_index,
                    episode_completed,
                    repeat_inference_cycles,
                    standalone_inference_cycles
                );
            end
        end
        if (standalone_repeat_mismatches != 0)
            $fatal(
                1,
                "[VV33:INFERENCE_REPEAT] latency mismatch count=%0d",
                standalone_repeat_mismatches
            );

        // Measure the standalone PMUL with the same K used by the mixed run.
        h.reset_dut();
        h.validate_vector_contract();
        h.prepare_ecc_case(0);
        h.start_background_pmul(0, start_timing);
        h.wait_background_done_no_poll();
        standalone_pmul_cycles = h.pmul_wall_cycles;
        h.check_background_pmul(0, 1'b1);
        h.check_ecc_guards(0);
        if (h.total_errors() != 0)
            $fatal(
                1,
                "[VV33:BANK_EPISODE] standalone PMUL failed errors=%0d",
                h.total_errors()
            );

        // Run online inference continuously until ECC completes.  Only fully
        // retired inference kernels before the PMUL-done edge contribute to the
        // matched serial and independent-accelerator baselines.
        h.reset_dut();
        h.validate_vector_contract();
        h.prepare_ecc_case(0);
        h.bus.write_hv(VV33_QUERY_SLOT, inference_query);
        h.bus.write_hv(VV33_PROTO_BASE_SLOT + 4'd0, inference_proto0);
        h.bus.write_hv(VV33_PROTO_BASE_SLOT + 4'd1, inference_proto1);
        h.bus.write_hv(VV33_PROTO_BASE_SLOT + 4'd2, inference_proto2);
        h.bus.write_hv(VV33_PROTO_BASE_SLOT + 4'd3, inference_proto3);
        clear_mixed_metrics();
        h.start_background_pmul(0, start_timing);
        mixed_start_cycle = start_timing.response_cycle;
        mixed_probe_active = 1'b1;
        while (!pmul_done_seen) begin
            run_one_inference(episode_completed);
        end
        mixed_wall_cycles = pmul_done_cycle - mixed_start_cycle;
        mixed_probe_active = 1'b0;
        @(posedge h.clk_i);

        h.check_background_pmul(0, 1'b1);
        h.check_ecc_guards(0);
        mixed_pmul_service_cycles = h.pmul_service_cycles;
        mixed_foreground_only_cycles = h.foreground_only_cycles;
        mixed_pmul_stretch_cycles =
            $signed(mixed_pmul_service_cycles)
          - $signed(standalone_pmul_cycles);

        completed_work_cycles =
            completed_episodes_at_pmul_done * standalone_inference_cycles;
        serial_baseline_cycles =
            standalone_pmul_cycles + completed_work_cycles;
        ideal_dual_cycles = (standalone_pmul_cycles > completed_work_cycles)
            ? standalone_pmul_cycles : completed_work_cycles;
        serial_gap_cycles = serial_baseline_cycles - ideal_dual_cycles;
        saved_cycles = $signed(serial_baseline_cycles)
                     - $signed(mixed_wall_cycles);
        if (serial_gap_cycles != 0)
            gap_closure_bp = (saved_cycles * 10000)
                           / $signed(serial_gap_cycles);
        else
            gap_closure_bp = 0;

        errors = h.total_errors() + local_errors;
        if ((vrf_read_conflicts != 0)
         || (matrix_conflicts != 0)
         || (xor0_conflicts != 0)
         || (popcount_conflicts != 0)
         || (payload_conflicts != 0)
         || (unknown_events != 0)) begin
            errors++;
            $error(
                "[VV33:BANK_EPISODE] conflict/unknown failure vrf_read=%0d matrix=%0d xor0=%0d popcount=%0d payload=%0d unknown=%0d",
                vrf_read_conflicts,
                matrix_conflicts,
                xor0_conflicts,
                popcount_conflicts,
                payload_conflicts,
                unknown_events
            );
        end
        if (pair_request_inflight
         || (pair_accept_events != pair_response_events)
         || (pair_matrix_events != (pair_response_events * 16))
         || (pair_pop_events != pair_matrix_events)) begin
            errors++;
            $error(
                "[VV33:PAIR_CONTRACT] aggregate mismatch active=%0d accept=%0d response=%0d matrix=%0d pop=%0d",
                pair_request_inflight,
                pair_accept_events,
                pair_response_events,
                pair_matrix_events,
                pair_pop_events
            );
        end

        $display(
            "[VV33:INFERENCE_STREAM_METRIC] K=%064h weight=%0d prototype_construction=%0d standalone_pmul=%0d standalone_inference=%0d standalone_repeat_count=4 standalone_repeat_mismatch=%0d completed_inferences=%0d completed_work=%0d unfinished_stage=%0d unfinished_active=%0d completed_stages=%0d completed_hdc_ops=%0d mixed_wall=%0d mixed_pmul_service=%0d mixed_pmul_stretch=%0d mixed_foreground_only=%0d serial_baseline=%0d ideal_dual=%0d serial_gap=%0d saved=%0d gap_closure_bp=%0d data_overlap=%0d control_overlap=%0d resource_pair=%0d pair_matrix=%0d pair_pop=%0d pair_accept=%0d pair_response=%0d vrf_read_conflict=%0d matrix_conflict=%0d xor0_conflict=%0d popcount_conflict=%0d payload_conflict=%0d unknown=%0d errors=%0d",
            h.scalar_inputs[0],
            vv31_hamming_weight256(h.scalar_inputs[0]),
            prototype_construction_cycles,
            standalone_pmul_cycles,
            standalone_inference_cycles,
            standalone_repeat_mismatches,
            completed_episodes_at_pmul_done,
            completed_work_cycles,
            unfinished_stage_at_pmul_done,
            unfinished_stage_active_at_pmul_done,
            completed_stages_at_pmul_done,
            completed_hdc_ops_at_pmul_done,
            mixed_wall_cycles,
            mixed_pmul_service_cycles,
            mixed_pmul_stretch_cycles,
            mixed_foreground_only_cycles,
            serial_baseline_cycles,
            ideal_dual_cycles,
            serial_gap_cycles,
            saved_cycles,
            gap_closure_bp,
            data_overlap_events,
            control_overlap_events,
            resource_pair_events,
            pair_matrix_events,
            pair_pop_events,
            pair_accept_events,
            pair_response_events,
            vrf_read_conflicts,
            matrix_conflicts,
            xor0_conflicts,
            popcount_conflicts,
            payload_conflicts,
            unknown_events,
            errors
        );
        $display(
            "[VV33:BANK_EPISODE_PARTIAL] stage=%0d name=%0s active=%0d completed_stages=%0d excluded_from_gap_metric=1",
            unfinished_stage_at_pmul_done,
            stage_name(unfinished_stage_at_pmul_done),
            unfinished_stage_active_at_pmul_done,
            completed_stages_at_pmul_done
        );

        if (errors == 0)
            $display("[VV33:bank_episode_interleave] PASS");
        else
            $fatal(
                1,
                "[VV33:bank_episode_interleave] FAIL errors=%0d",
                errors
            );
        $finish;
    end
endmodule
