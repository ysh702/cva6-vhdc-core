module vv33_fixed_workload_case #(
    parameter bit ENABLE_INTERLEAVE = 1'b1
);
    import hdec_pkg::*;
    import hdec_vv31_ref_pkg::*;
    import hdec_vv31_driver_pkg::*;
    import hdec_vv31_check_pkg::*;
    import hdec_vv31_vectors_pkg::*;

    localparam int unsigned VV33_MAX_EPISODES = 168;
    localparam logic [3:0] VV33_WORK_SLOT  = VV31_HDC_HV2_SLOT;
    localparam logic [3:0] VV33_QUERY_SLOT = VV31_HDC_HV3_SLOT;

    hdec_vv31_system_harness h();
    defparam h.dut.VV33_FINE_INTERLEAVE = ENABLE_INTERLEAVE;

    logic [31:0] episode_limit_mem [0:0];
    int unsigned episode_limit;
    bit probe_active;

    longint unsigned matrix_conflicts;
    longint unsigned xor0_conflicts;
    longint unsigned payload_conflicts;
    longint unsigned vrf_read_conflicts;
    longint unsigned vrf_write_conflicts;
    longint unsigned unknown_events;
    longint unsigned square_read_overlap;
    longint unsigned square_write_overlap;
    longint unsigned prefetch_overlap;
    longint unsigned control_overlap;
    longint unsigned data_overlap;
    longint unsigned any_overlap;

    wire hdc_payload_producer =
           h.dut.vv31_evt_hdc_matrix
        || h.dut.vv31_evt_hdc_xor0
        || ((h.dut.st_q == h.dut.S_UOP_P2_LANE)
            && h.dut.uop_p0_q.valid
            && (h.dut.uop_p0_use_counter
             || h.dut.uop_p0_use_clip
             || h.dut.uop_p0_use_shift));

    wire matrix_conflict =
        h.dut.vv31_evt_hdc_matrix && h.dut.vv31_evt_ecc_matrix;
    wire xor0_conflict =
        h.dut.vv31_evt_hdc_xor0 && h.dut.vv31_evt_ecc_xor0;
    wire payload_conflict =
        hdc_payload_producer && h.dut.vv31_evt_ecc_matrix;
    wire vrf_read_conflict =
        h.dut.vv31_evt_hdc_vrf_read
        && (h.dut.vv31_evt_ecc_vrf_prefetch
         || h.dut.vv33_sq_read_fire);
    wire hdc_write_state =
           (h.dut.st_q == h.dut.S_UOP_P3_GLOBAL)
        || (h.dut.st_q == h.dut.S_UOP_CLIP_WRITE)
        || (h.dut.st_q == h.dut.S_CLR);
    wire vrf_write_conflict =
        h.dut.vv33_sq_write_fire && hdc_write_state;

    function automatic logic [9:0] episode_rotation(
        input logic [7:0] seed_byte,
        input int unsigned episode,
        input int unsigned sample
    );
        int unsigned quarter_turn;
        begin
            // Multipliers 37 and 53 are both odd.  The resulting sequence
            // traverses the 256 legal four-bit-aligned HPERM positions without
            // collapsing the four samples in one episode to the same role.
            quarter_turn = (seed_byte + episode * 37 + sample * 53) & 8'hff;
            episode_rotation = (quarter_turn << 2) & 10'h3ff;
        end
    endfunction

    task automatic clear_probe_metrics;
        begin
            matrix_conflicts    = 0;
            xor0_conflicts      = 0;
            payload_conflicts   = 0;
            vrf_read_conflicts  = 0;
            vrf_write_conflicts = 0;
            unknown_events      = 0;
            square_read_overlap = 0;
            square_write_overlap = 0;
            prefetch_overlap    = 0;
            control_overlap     = 0;
            data_overlap        = 0;
            any_overlap         = 0;
        end
    endtask

    always @(posedge h.clk_i) begin
        if (!h.rst_ni) begin
            clear_probe_metrics();
        end else if (probe_active) begin
            if (matrix_conflict)
                matrix_conflicts <= matrix_conflicts + 1;
            if (xor0_conflict)
                xor0_conflicts <= xor0_conflicts + 1;
            if (payload_conflict)
                payload_conflicts <= payload_conflicts + 1;
            if (vrf_read_conflict)
                vrf_read_conflicts <= vrf_read_conflicts + 1;
            if (vrf_write_conflict)
                vrf_write_conflicts <= vrf_write_conflicts + 1;

            if (h.foreground_inflight_q && h.dut.vv33_sq_read_fire) begin
                square_read_overlap <= square_read_overlap + 1;
                data_overlap <= data_overlap + 1;
                any_overlap <= any_overlap + 1;
            end
            if (h.foreground_inflight_q && h.dut.vv33_sq_write_fire) begin
                square_write_overlap <= square_write_overlap + 1;
                data_overlap <= data_overlap + 1;
                any_overlap <= any_overlap + 1;
            end
            if (h.foreground_inflight_q
             && h.dut.vv31_evt_ecc_vrf_prefetch
             && !h.dut.vv33_sq_read_fire) begin
                prefetch_overlap <= prefetch_overlap + 1;
                data_overlap <= data_overlap + 1;
                any_overlap <= any_overlap + 1;
            end
            if (h.foreground_inflight_q
             && h.dut.vv31_evt_ecc_control_progress) begin
                control_overlap <= control_overlap + 1;
                any_overlap <= any_overlap + 1;
            end

            if ($isunknown({
                    h.dut.vv31_evt_hdc_matrix,
                    h.dut.vv31_evt_ecc_matrix,
                    h.dut.vv31_evt_hdc_xor0,
                    h.dut.vv31_evt_ecc_xor0,
                    h.dut.vv31_evt_hdc_vrf_read,
                    h.dut.vv31_evt_ecc_vrf_prefetch,
                    h.dut.vv31_evt_vrf_write,
                    h.dut.vv31_evt_vrf_read_owner,
                    h.dut.vv31_evt_vrf_write_owner,
                    h.dut.vv33_sq_read_fire,
                    h.dut.vv33_sq_write_fire,
                    h.bus.valid_o
                })) begin
                unknown_events <= unknown_events + 1;
                $error(
                    "[VV33:FIXED_UNKNOWN] control X/Z cycle=%0d",
                    h.bus.cycle_count
                );
            end
            if (h.bus.valid_o && $isunknown(h.bus.result_o)) begin
                unknown_events <= unknown_events + 1;
                $error(
                    "[VV33:FIXED_UNKNOWN] response X/Z cycle=%0d",
                    h.bus.cycle_count
                );
            end
            if ((|h.dut.vrf_we_direct)
             && $isunknown({h.dut.vrf_wa, h.dut.vrf_wd})) begin
                unknown_events <= unknown_events + 1;
                $error(
                    "[VV33:FIXED_UNKNOWN] VRF write X/Z cycle=%0d",
                    h.bus.cycle_count
                );
            end
        end
    end

    task automatic run_preloaded_episode(
        input int unsigned episode,
        input logic [1023:0] base_vector,
        output logic [1023:0] expected_prototype,
        output logic [10:0] expected_similarity
    );
        logic [1023:0] permuted_role;
        logic [1023:0] encoded_sample;
        logic [63:0] result;
        logic [63:0] expected_match;
        logic [9:0] rotation;
        vv31_timing_t timing;
        begin
            expected_prototype = '0;
            h.bus.issue_hdc(HDEC_HCNTCLR, 64'd0, result, timing);
            h.bus.expect_status_ok("fixed HCNTCLR", result);

            for (int unsigned sample = 0; sample < 4; sample++) begin
                rotation = episode_rotation(
                    h.master_seed_mem[0][7:0], episode, sample
                );
                h.bus.issue_hdc(
                    HDEC_HPERM,
                    vv31_hperm_operand(
                        VV33_WORK_SLOT, VV33_QUERY_SLOT, rotation
                    ),
                    result,
                    timing
                );
                h.bus.expect_status_ok("fixed HPERM", result);

                h.bus.issue_hdc(
                    HDEC_HBIND,
                    vv31_hbind_operand(
                        VV33_WORK_SLOT,
                        VV33_WORK_SLOT,
                        VV33_QUERY_SLOT
                    ),
                    result,
                    timing
                );
                h.bus.expect_status_ok("fixed HBIND", result);

                permuted_role = vv31_rotr1024(base_vector, rotation);
                encoded_sample = vv31_hdc_bind(
                    permuted_role, base_vector
                );
                expected_prototype |= encoded_sample;

                h.bus.issue_hdc(
                    HDEC_HCNTADD,
                    {60'd0, VV33_WORK_SLOT},
                    result,
                    timing
                );
                h.bus.expect_status_ok("fixed HCNTADD", result);
            end

            h.bus.issue_hdc(
                HDEC_HCNTCLIP,
                vv31_hcntclip_operand(VV33_WORK_SLOT[2:0], 1'b0, 4'd1),
                result,
                timing
            );
            h.bus.expect_status_ok("fixed HCNTCLIP", result);

            expected_similarity = vv31_hdc_overlap(
                base_vector, expected_prototype
            );
            h.bus.issue_hdc(
                HDEC_HSIM,
                vv31_hsim_operand(VV33_QUERY_SLOT, VV33_WORK_SLOT),
                result,
                timing
            );
            h.bus.expect_equal64(
                "fixed HSIM", result, {53'd0, expected_similarity}
            );

            expected_match = vv31_hmatch_result(
                3'd0, expected_similarity
            );
            h.bus.issue_hdc(
                HDEC_HMATCH,
                vv31_hmatch_operand(
                    VV33_QUERY_SLOT, VV33_WORK_SLOT, 8'd1
                ),
                result,
                timing
            );
            h.bus.expect_equal64("fixed HMATCH", result, expected_match);
            h.bus.complete_episode_count = h.bus.complete_episode_count + 1;
        end
    endtask

    task automatic run_episode_batch(
        input int unsigned count,
        input logic [1023:0] base_vector,
        output logic [1023:0] final_prototype,
        output logic [10:0] final_similarity
    );
        begin
            final_prototype = '0;
            final_similarity = '0;
            for (int unsigned episode = 0; episode < count; episode++) begin
                run_preloaded_episode(
                    episode,
                    base_vector,
                    final_prototype,
                    final_similarity
                );
                $display(
                    "[VV33:FIXED_EPISODE] mode=%0s episode=%0d/%0d score=%0d responses=%0d",
                    ENABLE_INTERLEAVE ? "INTERLEAVED" : "SERIAL",
                    episode + 1,
                    count,
                    final_similarity,
                    h.bus.total_response_count
                );
            end
        end
    endtask

    initial begin
        logic [1023:0] base_vector;
        logic [1023:0] expected_prototype;
        logic [1023:0] got_prototype;
        logic [10:0] expected_similarity;
        vv31_timing_t start_timing;
        longint unsigned standalone_preload_start;
        longint unsigned standalone_preload_cycles;
        longint unsigned standalone_start;
        longint unsigned standalone_cycles;
        longint unsigned mixed_preload_start;
        longint unsigned mixed_preload_cycles;
        longint unsigned mixed_start;
        longint unsigned mixed_cycles;
        longint unsigned expected_responses;
        int unsigned errors;

        probe_active = 1'b0;
        clear_probe_metrics();
        h.load_vectors();
        $readmemh("vv33_episode_count.mem", episode_limit_mem);
        episode_limit = episode_limit_mem[0];
        if ((episode_limit < 1)
         || (episode_limit > VV33_MAX_EPISODES))
            $fatal(
                1,
                "[VV33:FIXED] episode count must be 1..%0d, got %0d",
                VV33_MAX_EPISODES,
                episode_limit
            );

        base_vector = h.hdc_train_samples[0] ^ h.hdc_role_vectors[1];
        if ($isunknown(base_vector) || (base_vector == '0))
            $fatal(1, "[VV33:FIXED] invalid preloaded base vector");

        // First measure the exact HDC work alone.  Only the base-vector load is
        // outside the timed interval; every HDC training/inference operation is
        // included.  A reset separates this measurement from the mixed run.
        h.reset_dut();
        h.validate_vector_contract();
        standalone_preload_start = h.bus.cycle_count;
        h.bus.write_hv(VV33_QUERY_SLOT, base_vector);
        standalone_preload_cycles =
            h.bus.cycle_count - standalone_preload_start;
        standalone_start = h.bus.cycle_count;
        run_episode_batch(
            episode_limit,
            base_vector,
            expected_prototype,
            expected_similarity
        );
        standalone_cycles = h.bus.cycle_count - standalone_start;
        h.bus.read_hv(VV33_WORK_SLOT, got_prototype);
        h.bus.expect_equal1024(
            "fixed standalone final prototype",
            got_prototype,
            expected_prototype
        );
        if (h.total_errors() != 0)
            $fatal(
                1,
                "[VV33:FIXED] standalone HDC failed errors=%0d",
                h.total_errors()
            );

        h.reset_dut();
        h.validate_vector_contract();
        mixed_preload_start = h.bus.cycle_count;
        h.prepare_ecc_case(0);
        h.bus.write_hv(VV33_QUERY_SLOT, base_vector);
        mixed_preload_cycles = h.bus.cycle_count - mixed_preload_start;

        clear_probe_metrics();
        probe_active = 1'b1;
        mixed_start = h.bus.cycle_count;
        h.start_background_pmul(0, start_timing);
        // The disabled configuration is a strict serial reference: no HDC
        // request is presented while PMUL owns the accelerator.  Merely
        // disabling the VV33 window is insufficient because the pre-existing
        // background protocol can still yield at coarse task boundaries.
        if (!ENABLE_INTERLEAVE)
            h.wait_background_done_no_poll();
        run_episode_batch(
            episode_limit,
            base_vector,
            expected_prototype,
            expected_similarity
        );
        if (!h.dut.ecc_job_done_q)
            h.wait_background_done_no_poll();
        mixed_cycles = h.bus.cycle_count - mixed_start;
        probe_active = 1'b0;
        @(posedge h.clk_i);

        h.check_background_pmul(0, 1'b1);
        h.bus.read_hv(VV33_WORK_SLOT, got_prototype);
        h.bus.expect_equal1024(
            "fixed mixed final prototype",
            got_prototype,
            expected_prototype
        );
        h.check_ecc_guards(0);

        errors = h.total_errors();
        expected_responses = episode_limit * 16;
        if (h.bus.complete_episode_count != episode_limit) begin
            errors++;
            $error(
                "[VV33:FIXED] completed episodes got=%0d expected=%0d",
                h.bus.complete_episode_count,
                episode_limit
            );
        end
        if (h.bus.hdc_compute_count != expected_responses) begin
            errors++;
            $error(
                "[VV33:FIXED] HDC operations got=%0d expected=%0d",
                h.bus.hdc_compute_count,
                expected_responses
            );
        end
        if ((matrix_conflicts != 0)
         || (xor0_conflicts != 0)
         || (payload_conflicts != 0)
         || (vrf_read_conflicts != 0)
         || (vrf_write_conflicts != 0)
         || (unknown_events != 0)) begin
            errors++;
            $error(
                "[VV33:FIXED] resource/unknown failure matrix=%0d xor0=%0d payload=%0d vrf_read=%0d vrf_write=%0d unknown=%0d",
                matrix_conflicts,
                xor0_conflicts,
                payload_conflicts,
                vrf_read_conflicts,
                vrf_write_conflicts,
                unknown_events
            );
        end

        $display(
            "[VV33:FIXED_WORKLOAD] mode=%0s K=%064h weight=%0d episodes=%0d hdc_ops=%0d standalone_hdc=%0d pmul=%0d pmul_service=%0d pmul_foreground_only=%0d mixed_wall=%0d standalone_preload=%0d mixed_preload=%0d completed=%0d square_read_overlap=%0d square_write_overlap=%0d prefetch_overlap=%0d control_overlap=%0d data_overlap=%0d any_overlap=%0d matrix_conflict=%0d xor0_conflict=%0d payload_conflict=%0d vrf_read_conflict=%0d vrf_write_conflict=%0d unknown=%0d errors=%0d",
            ENABLE_INTERLEAVE ? "INTERLEAVED" : "SERIAL",
            h.scalar_inputs[0],
            vv31_hamming_weight256(h.scalar_inputs[0]),
            episode_limit,
            expected_responses,
            standalone_cycles,
            h.pmul_wall_cycles,
            h.pmul_service_cycles,
            h.foreground_only_cycles,
            mixed_cycles,
            standalone_preload_cycles,
            mixed_preload_cycles,
            h.bus.complete_episode_count,
            square_read_overlap,
            square_write_overlap,
            prefetch_overlap,
            control_overlap,
            data_overlap,
            any_overlap,
            matrix_conflicts,
            xor0_conflicts,
            payload_conflicts,
            vrf_read_conflicts,
            vrf_write_conflicts,
            unknown_events,
            errors
        );

        if (errors == 0) begin
            if (ENABLE_INTERLEAVE)
                $display("[VV33:fixed_workload_interleaved] PASS");
            else
                $display("[VV33:fixed_workload_serial] PASS");
        end else begin
            $fatal(
                1,
                "[VV33:fixed_workload] FAIL mode=%0s errors=%0d",
                ENABLE_INTERLEAVE ? "INTERLEAVED" : "SERIAL",
                errors
            );
        end
        $finish;
    end
endmodule

module tb_vv33_fixed_workload_interleaved;
    vv33_fixed_workload_case #(.ENABLE_INTERLEAVE(1'b1)) c();
endmodule

module tb_vv33_fixed_workload_serial;
    vv33_fixed_workload_case #(.ENABLE_INTERLEAVE(1'b0)) c();
endmodule
