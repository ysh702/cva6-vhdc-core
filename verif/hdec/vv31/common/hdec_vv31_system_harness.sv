module hdec_vv31_system_harness;
    import hdec_pkg::*;
    import hdec_vv31_ref_pkg::*;
    import hdec_vv31_driver_pkg::*;
    import hdec_vv31_check_pkg::*;
    import hdec_vv31_vectors_pkg::*;

    logic clk_i;
    logic rst_ni;

    hdec_vv31_bfm_if bus(clk_i);

    hdec_top dut (
        .clk_i,
        .rst_ni,
        .valid_i(bus.valid_i),
        .ready_o(bus.ready_o),
        .operator_i(bus.operator_i),
        .operand_a_i(bus.operand_a_i),
        .operand_b_i(bus.operand_b_i),
        .valid_o(bus.valid_o),
        .result_o(bus.result_o)
    );

    logic [255:0] master_seed_mem [0:0];
    logic [31:0]  scalar_count_mem [0:0];
    logic [31:0]  episode_count_mem [0:0];
    logic [255:0] point_x_inputs [0:VV31_MAX_SCALARS-1];
    logic [255:0] point_y_inputs [0:VV31_MAX_SCALARS-1];
    logic [255:0] scalar_inputs  [0:VV31_MAX_SCALARS-1];
    logic [255:0] expected_x     [0:VV31_MAX_SCALARS-1];
    logic [255:0] expected_y     [0:VV31_MAX_SCALARS-1];

    logic [1023:0] hdc_train_samples
        [0:VV31_MAX_TRAINING_VECTORS-1];
    logic [1023:0] hdc_role_vectors
        [0:VV31_MAX_TRAINING_VECTORS-1];
    logic [31:0] hdc_role_rotations
        [0:VV31_MAX_TRAINING_VECTORS-1];
    logic [1023:0] hdc_permuted_roles_expected
        [0:VV31_MAX_TRAINING_VECTORS-1];
    logic [1023:0] hdc_bound_expected
        [0:VV31_MAX_TRAINING_VECTORS-1];
    logic [1023:0] hdc_prototypes_expected
        [0:VV31_MAX_EPISODES-1];
    logic [1023:0] hdc_query_vectors
        [0:VV31_MAX_EPISODES-1];
    logic [31:0] hdc_hsim_expected
        [0:VV31_MAX_EPISODES-1];
    logic [63:0] hdc_hmatch_expected
        [0:VV31_MAX_EPISODES-1];

    int unsigned scalar_count;
    int unsigned episode_count;
    int unsigned harness_error_count;

    longint unsigned hdc_pop_cycles;
    longint unsigned hdc_xor_cycles;
    longint unsigned ecc_diag_cycles;
    longint unsigned ecc_xor0_update_cycles;
    longint unsigned ecc_square_write_cycles;
    longint unsigned vrf_write_cycles;
    longint unsigned simultaneous_product_conflicts;
    longint unsigned simultaneous_xor_conflicts;
    longint unsigned observed_resource_pair_cycles;
    longint unsigned pmul_wall_start_cycle;
    longint unsigned pmul_wall_end_cycle;
    longint unsigned pmul_wall_cycles;
    longint unsigned pmul_service_cycles;
    longint unsigned foreground_only_cycles;
    longint unsigned foreground_prefix_start;
    longint unsigned foreground_prefix_completed;
    logic            pmul_tracking_q;
    logic            foreground_inflight_q;

    wire ecc_square_write_event =
        dut.ecc_job_active_q
        && dut.hperm_spread_q
        && dut.ecc_autoreduce_q
        && (|dut.vrf_we_direct);
    wire ecc_visible_progress_event =
        dut.ecc_diag_product_issue
        || dut.hdc_src0_acc_we
        || ecc_square_write_event;
    wire hdc_visible_compute_event =
        dut.hdc_pop_product_issue
        || dut.hdc_xor_issue
        || ((dut.st_q == dut.S_UOP_P2_LANE)
            && dut.uop_p0_q.valid
            && (dut.uop_p0_use_counter
             || dut.uop_p0_use_clip
             || dut.uop_p0_use_shift));

    initial begin
        clk_i = 1'b0;
        rst_ni = 1'b0;
        scalar_count = 0;
        episode_count = 0;
        harness_error_count = 0;
        pmul_tracking_q = 1'b0;
        foreground_inflight_q = 1'b0;
        clear_trace_metrics();
    end

    always #2.5 clk_i = ~clk_i;

    always @(posedge clk_i) begin
        if (!rst_ni) begin
            foreground_inflight_q <= 1'b0;
        end else begin
            if (bus.valid_i && bus.ready_o
                && (bus.operator_i != HDEC_ECC_STATUS))
                foreground_inflight_q <= 1'b1;
            if (bus.valid_o)
                foreground_inflight_q <= 1'b0;
        end

        if (rst_ni) begin
            if (dut.hdc_pop_product_issue)
                hdc_pop_cycles <= hdc_pop_cycles + 1;
            if (dut.hdc_xor_issue)
                hdc_xor_cycles <= hdc_xor_cycles + 1;
            if (dut.ecc_diag_product_issue)
                ecc_diag_cycles <= ecc_diag_cycles + 1;
            if (dut.ecc_job_active_q && dut.hdc_src0_acc_we)
                ecc_xor0_update_cycles <= ecc_xor0_update_cycles + 1;
            if (ecc_square_write_event)
                ecc_square_write_cycles <= ecc_square_write_cycles + 1;
            if (|dut.vrf_we_direct)
                vrf_write_cycles <= vrf_write_cycles + 1;

            if (dut.hdc_pop_product_issue
                && dut.ecc_diag_product_issue) begin
                simultaneous_product_conflicts
                    <= simultaneous_product_conflicts + 1;
                harness_error_count <= harness_error_count + 1;
                $error(
                    "[VV31:RESOURCE] shared product conflict cycle=%0d",
                    bus.cycle_count
                );
            end
            if (dut.hdc_xor_issue && dut.hdc_src0_acc_we) begin
                simultaneous_xor_conflicts
                    <= simultaneous_xor_conflicts + 1;
                harness_error_count <= harness_error_count + 1;
                $error(
                    "[VV31:RESOURCE] XOR0 conflict cycle=%0d",
                    bus.cycle_count
                );
            end
            if (dut.ecc_job_active_q
                && hdc_visible_compute_event
                && ecc_visible_progress_event)
                observed_resource_pair_cycles
                    <= observed_resource_pair_cycles + 1;

            if (pmul_tracking_q && dut.ecc_job_active_q) begin
                if (!foreground_inflight_q || ecc_visible_progress_event)
                    pmul_service_cycles <= pmul_service_cycles + 1;
                else
                    foreground_only_cycles <= foreground_only_cycles + 1;
            end
            if (pmul_tracking_q && dut.ecc_job_done_q
                && (pmul_wall_end_cycle == 0)) begin
                pmul_wall_end_cycle <= bus.cycle_count;
                pmul_wall_cycles <= bus.cycle_count - pmul_wall_start_cycle;
            end
        end
    end

    task automatic clear_trace_metrics;
        begin
            hdc_pop_cycles = 0;
            hdc_xor_cycles = 0;
            ecc_diag_cycles = 0;
            ecc_xor0_update_cycles = 0;
            ecc_square_write_cycles = 0;
            vrf_write_cycles = 0;
            simultaneous_product_conflicts = 0;
            simultaneous_xor_conflicts = 0;
            observed_resource_pair_cycles = 0;
            pmul_wall_start_cycle = 0;
            pmul_wall_end_cycle = 0;
            pmul_wall_cycles = 0;
            pmul_service_cycles = 0;
            foreground_only_cycles = 0;
            foreground_prefix_start = 0;
            foreground_prefix_completed = 0;
        end
    endtask

    task automatic reset_dut;
        begin
            rst_ni = 1'b0;
            bus.valid_i = 1'b0;
            bus.operator_i = HDEC_VWR64;
            bus.operand_a_i = '0;
            bus.operand_b_i = '0;
            pmul_tracking_q = 1'b0;
            foreground_inflight_q = 1'b0;
            repeat (8) @(posedge clk_i);
            rst_ni = 1'b1;
            repeat (20) @(posedge clk_i);
            bus.reset_metrics();
            harness_error_count = 0;
            clear_trace_metrics();
        end
    endtask

    task automatic load_vectors;
        int total_training_vectors;
        begin
            $readmemh("master_seed.mem", master_seed_mem);
            $readmemh("scalar_count.mem", scalar_count_mem);
            $readmemh("hdc_episode_count.mem", episode_count_mem);
            scalar_count = scalar_count_mem[0];
            episode_count = episode_count_mem[0];
            if ((scalar_count < 1)
                || (scalar_count > VV31_MAX_SCALARS))
                $fatal(
                    1,
                    "[VV31:HARNESS] invalid scalar_count=%0d",
                    scalar_count
                );
            if ((episode_count < 1)
                || (episode_count > VV31_MAX_EPISODES))
                $fatal(
                    1,
                    "[VV31:HARNESS] invalid episode_count=%0d",
                    episode_count
                );

            $readmemh(
                "pmul_point_x.mem",
                point_x_inputs,
                0,
                scalar_count - 1
            );
            $readmemh(
                "pmul_point_y.mem",
                point_y_inputs,
                0,
                scalar_count - 1
            );
            $readmemh(
                "pmul_scalars.mem",
                scalar_inputs,
                0,
                scalar_count - 1
            );
            $readmemh(
                "pmul_expected_x.mem",
                expected_x,
                0,
                scalar_count - 1
            );
            $readmemh(
                "pmul_expected_y.mem",
                expected_y,
                0,
                scalar_count - 1
            );

            total_training_vectors =
                episode_count * VV31_TRAINING_PER_EPISODE;
            $readmemh(
                "hdc_train_samples.mem",
                hdc_train_samples,
                0,
                total_training_vectors - 1
            );
            $readmemh(
                "hdc_role_vectors.mem",
                hdc_role_vectors,
                0,
                total_training_vectors - 1
            );
            $readmemh(
                "hdc_role_rotations.mem",
                hdc_role_rotations,
                0,
                total_training_vectors - 1
            );
            $readmemh(
                "hdc_permuted_roles_expected.mem",
                hdc_permuted_roles_expected,
                0,
                total_training_vectors - 1
            );
            $readmemh(
                "hdc_bound_expected.mem",
                hdc_bound_expected,
                0,
                total_training_vectors - 1
            );
            $readmemh(
                "hdc_prototypes_expected.mem",
                hdc_prototypes_expected,
                0,
                episode_count - 1
            );
            $readmemh(
                "hdc_query_vectors.mem",
                hdc_query_vectors,
                0,
                episode_count - 1
            );
            $readmemh(
                "hdc_hsim_expected.mem",
                hdc_hsim_expected,
                0,
                episode_count - 1
            );
            $readmemh(
                "hdc_hmatch_expected.mem",
                hdc_hmatch_expected,
                0,
                episode_count - 1
            );
        end
    endtask

    task automatic validate_vector_contract;
        logic [1023:0] calculated_permuted;
        logic [1023:0] calculated_bound;
        logic [1023:0] calculated_prototype;
        logic [10:0] calculated_score;
        int vector_index;
        begin
            for (int case_index = 0;
                 case_index < scalar_count;
                 case_index++) begin
                if (!vv31_legal_random_k(scalar_inputs[case_index])) begin
                    harness_error_count++;
                    $error(
                        "[VV31:VECTOR] illegal random K case=%0d K=%064h",
                        case_index,
                        scalar_inputs[case_index]
                    );
                end
                for (int previous = 0;
                     previous < case_index;
                     previous++) begin
                    if (scalar_inputs[case_index]
                        == scalar_inputs[previous]) begin
                        harness_error_count++;
                        $error(
                            "[VV31:VECTOR] duplicate random K cases=%0d,%0d",
                            previous,
                            case_index
                        );
                    end
                end
            end

            for (int episode = 0; episode < episode_count; episode++) begin
                calculated_prototype = '0;
                for (int sample = 0; sample < 4; sample++) begin
                    vector_index = episode * 4 + sample;
                    if (hdc_role_rotations[vector_index][1:0] != 0) begin
                        harness_error_count++;
                        $error(
                            "[VV31:VECTOR] unaligned HPERM episode=%0d sample=%0d rotation=%0d",
                            episode,
                            sample,
                            hdc_role_rotations[vector_index]
                        );
                    end
                    calculated_permuted = vv31_rotr1024(
                        hdc_role_vectors[vector_index],
                        hdc_role_rotations[vector_index][9:0]
                    );
                    calculated_bound = vv31_hdc_bind(
                        hdc_train_samples[vector_index],
                        calculated_permuted
                    );
                    if (calculated_permuted
                        !== hdc_permuted_roles_expected[vector_index]) begin
                        harness_error_count++;
                        $error(
                            "[VV31:VECTOR] permuted role mismatch episode=%0d sample=%0d",
                            episode,
                            sample
                        );
                    end
                    if (calculated_bound
                        !== hdc_bound_expected[vector_index]) begin
                        harness_error_count++;
                        $error(
                            "[VV31:VECTOR] bound mismatch episode=%0d sample=%0d",
                            episode,
                            sample
                        );
                    end
                    calculated_prototype |= calculated_bound;
                end
                calculated_score = vv31_hdc_overlap(
                    hdc_query_vectors[episode],
                    calculated_prototype
                );
                if (calculated_prototype
                    !== hdc_prototypes_expected[episode]) begin
                    harness_error_count++;
                    $error(
                        "[VV31:VECTOR] prototype mismatch episode=%0d",
                        episode
                    );
                end
                if ({21'd0, calculated_score}
                    !== hdc_hsim_expected[episode]) begin
                    harness_error_count++;
                    $error(
                        "[VV31:VECTOR] HSIM mismatch episode=%0d",
                        episode
                    );
                end
                if (vv31_hmatch_result(3'd0, calculated_score)
                    !== hdc_hmatch_expected[episode]) begin
                    harness_error_count++;
                    $error(
                        "[VV31:VECTOR] HMATCH mismatch episode=%0d",
                        episode
                    );
                end
            end
        end
    endtask

    task automatic prepare_ecc_case(input int case_index);
        logic [255:0] guard3;
        logic [255:0] guard6;
        logic [255:0] guard7;
        begin
            guard3 = {
                master_seed_mem[0][191:0],
                32'h31c0_0003,
                case_index[31:0]
            };
            guard6 = ~guard3;
            guard7 = guard3
                   ^ 256'h5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5aa5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5;
            bus.write_row(VV31_ECC_POINT_X_ROW, point_x_inputs[case_index]);
            bus.write_row(VV31_ECC_POINT_Y_ROW, point_y_inputs[case_index]);
            bus.write_row(VV31_ECC_SCALAR_ROW, scalar_inputs[case_index]);
            bus.write_row(6'd3, guard3);
            bus.write_row(VV31_ECC_OUT_X_ROW, '0);
            bus.write_row(VV31_ECC_OUT_Y_ROW, '0);
            bus.write_row(6'd6, guard6);
            bus.write_row(6'd7, guard7);
        end
    endtask

    task automatic check_ecc_guards(input int case_index);
        logic [255:0] expected_guard3;
        logic [255:0] expected_guard6;
        logic [255:0] expected_guard7;
        logic [255:0] got;
        begin
            expected_guard3 = {
                master_seed_mem[0][191:0],
                32'h31c0_0003,
                case_index[31:0]
            };
            expected_guard6 = ~expected_guard3;
            expected_guard7 =
                expected_guard3
                ^ 256'h5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5aa5a5a5a5a5a5a5a5a5a5a5a5a5a5a5a5;
            bus.read_row(6'd3, got);
            if (got !== expected_guard3) begin
                harness_error_count++;
                $error("[VV31:GUARD] row3 changed case=%0d", case_index);
            end
            bus.read_row(6'd6, got);
            if (got !== expected_guard6) begin
                harness_error_count++;
                $error("[VV31:GUARD] row6 changed case=%0d", case_index);
            end
            bus.read_row(6'd7, got);
            if (got !== expected_guard7) begin
                harness_error_count++;
                $error("[VV31:GUARD] row7 changed case=%0d", case_index);
            end
        end
    endtask

    task automatic start_background_pmul(
        input int case_index,
        output vv31_timing_t start_timing
    );
        logic [63:0] status;
        begin
            clear_trace_metrics();
            foreground_prefix_start = bus.total_response_count;
            bus.issue_hold(
                HDEC_ECC_STATUS,
                vv31_ecc_pmul_operand(
                    1'b1,
                    VV31_ECC_OUT_X_ROW,
                    VV31_ECC_POINT_X_ROW,
                    VV31_ECC_SCALAR_ROW
                ),
                '0,
                status,
                start_timing
            );
            if ((status[1:0] !== STATUS_OK) || (status[2] !== 1'b1)) begin
                harness_error_count++;
                $error(
                    "[VV31:PMUL] background start failed case=%0d status=%016h",
                    case_index,
                    status
                );
            end
            pmul_tracking_q = 1'b1;
            pmul_wall_start_cycle = start_timing.response_cycle;
            $display(
                "[VV31:PMUL_START] case=%0d K=%064h weight=%0d request=%0d accept=%0d response=%0d",
                case_index,
                scalar_inputs[case_index],
                vv31_hamming_weight256(scalar_inputs[case_index]),
                start_timing.request_cycle,
                start_timing.accept_cycle,
                start_timing.response_cycle
            );
        end
    endtask

    task automatic wait_background_done_no_poll;
        int unsigned timeout_cycles;
        begin
            timeout_cycles = 0;
            while (!dut.ecc_job_done_q) begin
                @(posedge clk_i);
                timeout_cycles++;
                if (timeout_cycles >= 2_000_000)
                    $fatal(1, "[VV31:PMUL] background completion timeout");
            end
            @(posedge clk_i);
        end
    endtask

    task automatic check_background_pmul(
        input int case_index,
        input bit query_status_once
    );
        logic [63:0] status;
        logic [63:0] ignored;
        logic [255:0] got_x;
        logic [255:0] got_y;
        begin
            if (query_status_once) begin
                bus.issue(HDEC_ECC_STATUS, '0, status);
                if ((status[1:0] !== STATUS_OK)
                    || (status[2] !== 1'b0)
                    || (status[3] !== 1'b1)) begin
                    harness_error_count++;
                    $error(
                        "[VV31:PMUL] final status failed case=%0d status=%016h",
                        case_index,
                        status
                    );
                end
            end else begin
                ignored = '0;
            end
            bus.read_row(VV31_ECC_OUT_X_ROW, got_x);
            bus.read_row(VV31_ECC_OUT_Y_ROW, got_y);
            if ((got_x !== expected_x[case_index])
                || (got_y !== expected_y[case_index])) begin
                harness_error_count++;
                $error(
                    "[VV31:PMUL] result mismatch case=%0d K=%064h got=(%064h,%064h) expected=(%064h,%064h)",
                    case_index,
                    scalar_inputs[case_index],
                    got_x,
                    got_y,
                    expected_x[case_index],
                    expected_y[case_index]
                );
            end
            if ((got_x[255:233] != 0) || (got_y[255:233] != 0)) begin
                harness_error_count++;
                $error(
                    "[VV31:PMUL] nonzero result padding case=%0d",
                    case_index
                );
            end
            pmul_tracking_q = 1'b0;
            foreground_prefix_completed =
                bus.total_response_count - foreground_prefix_start;
            $display(
                "[VV31:PMUL_METRIC] case=%0d wall_start=%0d wall_end=%0d wall_cycles=%0d service_cycles=%0d foreground_only_cycles=%0d completed_prefix=%0d complete_episodes=%0d",
                case_index,
                pmul_wall_start_cycle,
                pmul_wall_end_cycle,
                pmul_wall_cycles,
                pmul_service_cycles,
                foreground_only_cycles,
                foreground_prefix_completed,
                bus.complete_episode_count
            );
        end
    endtask

    task automatic run_episode_index(input int requested_episode);
        int episode;
        int base;
        logic [1023:0] prototype;
        logic [10:0] similarity;
        logic [63:0] match_result;
        logic [63:0] episode_start;
        logic [63:0] episode_end;
        begin
            episode = requested_episode % episode_count;
            base = episode * 4;
            bus.run_hdc_episode(
                hdc_train_samples[base + 0],
                hdc_train_samples[base + 1],
                hdc_train_samples[base + 2],
                hdc_train_samples[base + 3],
                hdc_role_vectors[base + 0],
                hdc_role_vectors[base + 1],
                hdc_role_vectors[base + 2],
                hdc_role_vectors[base + 3],
                hdc_role_rotations[base + 0][9:0],
                hdc_role_rotations[base + 1][9:0],
                hdc_role_rotations[base + 2][9:0],
                hdc_role_rotations[base + 3][9:0],
                hdc_query_vectors[episode],
                prototype,
                similarity,
                match_result,
                episode_start,
                episode_end
            );
            if (prototype !== hdc_prototypes_expected[episode]) begin
                harness_error_count++;
                $error(
                    "[VV31:HDC] episode prototype mismatch episode=%0d",
                    episode
                );
            end
            if ({21'd0, similarity} !== hdc_hsim_expected[episode]) begin
                harness_error_count++;
                $error(
                    "[VV31:HDC] episode HSIM mismatch episode=%0d",
                    episode
                );
            end
            if (match_result !== hdc_hmatch_expected[episode]) begin
                harness_error_count++;
                $error(
                    "[VV31:HDC] episode HMATCH mismatch episode=%0d",
                    episode
                );
            end
        end
    endtask

    task automatic print_resource_metrics(input string test_name);
        begin
            $display(
                "[VV31:RESOURCE_METRIC] test=%s hdc_pop=%0d hdc_xor=%0d ecc_diag=%0d ecc_xor0=%0d ecc_square=%0d vrf_write=%0d paired=%0d product_conflicts=%0d xor_conflicts=%0d",
                test_name,
                hdc_pop_cycles,
                hdc_xor_cycles,
                ecc_diag_cycles,
                ecc_xor0_update_cycles,
                ecc_square_write_cycles,
                vrf_write_cycles,
                observed_resource_pair_cycles,
                simultaneous_product_conflicts,
                simultaneous_xor_conflicts
            );
        end
    endtask

    function automatic int unsigned total_errors;
        total_errors = harness_error_count + bus.error_count;
    endfunction

endmodule
