module tb_vv33_bank_hsim_interleave;
    import hdec_pkg::*;
    import hdec_vv31_ref_pkg::*;
    import hdec_vv31_driver_pkg::*;
    import hdec_vv31_check_pkg::*;
    import hdec_vv31_vectors_pkg::*;

    localparam logic [3:0] VV33_SRC0_SLOT = VV31_HDC_HV2_SLOT;
    localparam logic [3:0] VV33_SRC1_SLOT = VV31_HDC_HV3_SLOT;

    hdec_vv31_system_harness h();
    defparam h.dut.VV33_FINE_INTERLEAVE = 1'b1;

    logic [1023:0] src0_hv;
    logic [1023:0] src1_hv;
    logic [10:0]   expected_similarity;

    bit probe_active;
    bit hsim_request_active;

    logic [15:0] src0_read_seen;
    logic [15:0] src1_read_seen;
    logic [15:0] src0_return_seen;
    logic [15:0] src1_return_seen;
    logic [15:0] compute_seen;
    logic [15:0] accum_seen;

    longint unsigned accept_events;
    longint unsigned src0_read_events;
    longint unsigned src1_read_events;
    longint unsigned src0_return_events;
    longint unsigned src1_return_events;
    longint unsigned compute_events;
    longint unsigned accum_events;
    longint unsigned done_events;
    longint unsigned response_events;
    longint unsigned bus_response_events;
    longint unsigned vrf_read_conflicts;
    longint unsigned matrix_conflicts;
    longint unsigned popcount_conflicts;
    longint unsigned payload_conflicts;
    longint unsigned unknown_events;
    longint unsigned local_errors;
    int unsigned running_expected_sum;

    function automatic int unsigned popcount64(input logic [63:0] value);
        int unsigned count;
        begin
            count = 0;
            for (int bit_index = 0; bit_index < 64; bit_index++)
                count += value[bit_index];
            popcount64 = count;
        end
    endfunction

    task automatic clear_probe_metrics;
        begin
            src0_read_seen     = '0;
            src1_read_seen     = '0;
            src0_return_seen   = '0;
            src1_return_seen   = '0;
            compute_seen       = '0;
            accum_seen         = '0;
            accept_events      = 0;
            src0_read_events   = 0;
            src1_read_events   = 0;
            src0_return_events = 0;
            src1_return_events = 0;
            compute_events     = 0;
            accum_events       = 0;
            done_events        = 0;
            response_events    = 0;
            bus_response_events = 0;
            vrf_read_conflicts = 0;
            matrix_conflicts   = 0;
            popcount_conflicts = 0;
            payload_conflicts  = 0;
            unknown_events     = 0;
            local_errors       = 0;
            running_expected_sum = 0;
        end
    endtask

    task automatic record_unique_word(
        input string       label,
        input logic [3:0]  word_id,
        inout logic [15:0] seen
    );
        begin
            if ($isunknown(word_id)) begin
                unknown_events++;
                local_errors++;
                $error("[VV33:BANK_HSIM] %s word id is X/Z", label);
            end else if (seen[word_id]) begin
                local_errors++;
                $error(
                    "[VV33:BANK_HSIM] duplicate %s word id=%0d",
                    label,
                    word_id
                );
            end else begin
                seen[word_id] = 1'b1;
            end
        end
    endtask

    always @(posedge h.clk_i) begin : monitor_bank_hsim
        int unsigned word_index;
        int unsigned expected_word_popcount;
        int unsigned next_expected_sum;
        logic [63:0] expected_src0_word;
        logic [63:0] expected_src1_word;

        #1;
        if (h.rst_ni && probe_active) begin
            if ($isunknown({
                    h.dut.vv33_bank_hsim_accept_fire,
                    h.dut.vv33_bank_hsim_src0_read_fire,
                    h.dut.vv33_bank_hsim_src1_read_fire,
                    h.dut.vv33_bank_hsim_src0_return_fire,
                    h.dut.vv33_bank_hsim_src1_return_fire,
                    h.dut.vv33_bank_hsim_compute_fire,
                    h.dut.vv33_bank_hsim_accum_fire,
                    h.dut.vv33_bank_hsim_done_fire,
                    h.dut.vv33_bank_hsim_response_fire,
                    h.dut.vv33_bank_hsim_vrf_read_conflict,
                    h.dut.vv33_bank_hsim_matrix_conflict,
                    h.dut.vv33_bank_hsim_popcount_conflict,
                    h.dut.vv33_bank_hsim_payload_conflict,
                    h.bus.valid_o
                })) begin
                unknown_events++;
                local_errors++;
                $error(
                    "[VV33:BANK_HSIM] control event X/Z cycle=%0d",
                    h.bus.cycle_count
                );
            end

            if (h.dut.vv33_bank_hsim_accept_fire)
                accept_events++;

            if (h.dut.vv33_bank_hsim_src0_read_fire) begin
                src0_read_events++;
                record_unique_word(
                    "src0_read",
                    h.dut.vv33_bank_hsim_src0_read_word_id,
                    src0_read_seen
                );
            end
            if (h.dut.vv33_bank_hsim_src1_read_fire) begin
                src1_read_events++;
                record_unique_word(
                    "src1_read",
                    h.dut.vv33_bank_hsim_src1_read_word_id,
                    src1_read_seen
                );
            end
            if (h.dut.vv33_bank_hsim_src0_return_fire) begin
                src0_return_events++;
                record_unique_word(
                    "src0_return",
                    h.dut.vv33_bank_hsim_src0_return_word_id,
                    src0_return_seen
                );
            end
            if (h.dut.vv33_bank_hsim_src1_return_fire) begin
                src1_return_events++;
                record_unique_word(
                    "src1_return",
                    h.dut.vv33_bank_hsim_src1_return_word_id,
                    src1_return_seen
                );
            end

            if (h.dut.vv33_bank_hsim_compute_fire) begin
                compute_events++;
                record_unique_word(
                    "compute",
                    h.dut.vv33_bank_hsim_compute_word_id,
                    compute_seen
                );
                word_index = h.dut.vv33_bank_hsim_compute_word_id;
                if (!$isunknown(word_index) && (word_index < 16)) begin
                    expected_src0_word =
                        src0_hv[word_index * 64 +: 64];
                    expected_src1_word =
                        src1_hv[word_index * 64 +: 64];
                    expected_word_popcount = popcount64(
                        expected_src0_word & expected_src1_word
                    );
                    if (h.dut.vv33_bank_hsim_compute_src0_word
                        !== expected_src0_word) begin
                        local_errors++;
                        $error(
                            "[VV33:BANK_HSIM] src0 mismatch word=%0d got=%016h expected=%016h",
                            word_index,
                            h.dut.vv33_bank_hsim_compute_src0_word,
                            expected_src0_word
                        );
                    end
                    if (h.dut.vv33_bank_hsim_compute_src1_word
                        !== expected_src1_word) begin
                        local_errors++;
                        $error(
                            "[VV33:BANK_HSIM] src1 mismatch word=%0d got=%016h expected=%016h",
                            word_index,
                            h.dut.vv33_bank_hsim_compute_src1_word,
                            expected_src1_word
                        );
                    end
                    if (h.dut.vv33_bank_hsim_word_popcount
                        !== expected_word_popcount[6:0]) begin
                        local_errors++;
                        $error(
                            "[VV33:BANK_HSIM] popcount mismatch word=%0d got=%0d expected=%0d",
                            word_index,
                            h.dut.vv33_bank_hsim_word_popcount,
                            expected_word_popcount
                        );
                    end
                end
            end

            if (h.dut.vv33_bank_hsim_accum_fire) begin
                accum_events++;
                record_unique_word(
                    "accum",
                    h.dut.vv33_bank_hsim_accum_word_id,
                    accum_seen
                );
                word_index = h.dut.vv33_bank_hsim_accum_word_id;
                if (!$isunknown(word_index) && (word_index < 16)) begin
                    expected_word_popcount = popcount64(
                        src0_hv[word_index * 64 +: 64]
                      & src1_hv[word_index * 64 +: 64]
                    );
                    next_expected_sum =
                        running_expected_sum + expected_word_popcount;
                    if (h.dut.vv33_bank_hsim_partial_sum
                        !== next_expected_sum[10:0]) begin
                        local_errors++;
                        $error(
                            "[VV33:BANK_HSIM] partial sum mismatch word=%0d got=%0d expected=%0d",
                            word_index,
                            h.dut.vv33_bank_hsim_partial_sum,
                            next_expected_sum
                        );
                    end
                    running_expected_sum = next_expected_sum;
                end
            end

            if (h.dut.vv33_bank_hsim_done_fire)
                done_events++;
            if (h.dut.vv33_bank_hsim_response_fire)
                response_events++;
            if (hsim_request_active && h.bus.valid_o)
                bus_response_events++;

            if (h.dut.vv33_bank_hsim_vrf_read_conflict)
                vrf_read_conflicts++;
            if (h.dut.vv33_bank_hsim_matrix_conflict)
                matrix_conflicts++;
            if (h.dut.vv33_bank_hsim_popcount_conflict)
                popcount_conflicts++;
            if (h.dut.vv33_bank_hsim_payload_conflict)
                payload_conflicts++;

            if (h.bus.valid_o && $isunknown(h.bus.result_o)) begin
                unknown_events++;
                local_errors++;
                $error(
                    "[VV33:BANK_HSIM] response data X/Z cycle=%0d",
                    h.bus.cycle_count
                );
            end
            if ((|h.dut.vrf_we_direct)
             && $isunknown({h.dut.vrf_wa, h.dut.vrf_wd})) begin
                unknown_events++;
                local_errors++;
                $error(
                    "[VV33:BANK_HSIM] VRF write X/Z cycle=%0d",
                    h.bus.cycle_count
                );
            end
        end
    end

    initial begin
        logic [63:0] hsim_result;
        vv31_timing_t start_timing;
        vv31_timing_t hsim_timing;
        int unsigned errors;

        probe_active = 1'b0;
        hsim_request_active = 1'b0;
        clear_probe_metrics();

        h.load_vectors();
        if (h.scalar_count != 1)
            $fatal(
                1,
                "[VV33:BANK_HSIM] expected exactly one random K, got %0d",
                h.scalar_count
            );

        src0_hv = h.hdc_train_samples[0] ^ h.hdc_role_vectors[1];
        src1_hv = h.hdc_train_samples[1] ^ h.hdc_role_vectors[2];
        expected_similarity = vv31_hdc_overlap(src0_hv, src1_hv);
        if ($isunknown({src0_hv, src1_hv})
         || (src0_hv == '0)
         || (src1_hv == '0))
            $fatal(1, "[VV33:BANK_HSIM] invalid random HDC vectors");

        h.reset_dut();
        h.validate_vector_contract();
        h.prepare_ecc_case(0);
        h.bus.write_hv(VV33_SRC0_SLOT, src0_hv);
        h.bus.write_hv(VV33_SRC1_SLOT, src1_hv);

        clear_probe_metrics();
        h.start_background_pmul(0, start_timing);
        probe_active = 1'b1;
        hsim_request_active = 1'b1;
        h.bus.issue_hold(
            HDEC_HSIM,
            vv31_hsim_operand(VV33_SRC0_SLOT, VV33_SRC1_SLOT),
            '0,
            hsim_result,
            hsim_timing
        );
        h.bus.hdc_compute_count = h.bus.hdc_compute_count + 1;
        @(posedge h.clk_i);
        #1;
        hsim_request_active = 1'b0;

        h.bus.expect_equal64(
            "bank HSIM",
            hsim_result,
            {53'd0, expected_similarity}
        );
        if (!h.dut.ecc_job_done_q)
            h.wait_background_done_no_poll();
        probe_active = 1'b0;
        @(posedge h.clk_i);
        h.check_background_pmul(0, 1'b1);
        h.check_ecc_guards(0);

        errors = h.total_errors() + local_errors;
        if ((accept_events != 1)
         || (src0_read_events != 16)
         || (src1_read_events != 16)
         || (src0_return_events != 16)
         || (src1_return_events != 16)
         || (compute_events != 16)
         || (accum_events != 16)
         || (done_events != 1)
         || (response_events != 1)
         || (bus_response_events != 1)
         || (src0_read_seen != 16'hffff)
         || (src1_read_seen != 16'hffff)
         || (src0_return_seen != 16'hffff)
         || (src1_return_seen != 16'hffff)
         || (compute_seen != 16'hffff)
         || (accum_seen != 16'hffff)
         || (running_expected_sum != expected_similarity)) begin
            errors++;
            $error(
                "[VV33:BANK_HSIM] event contract failed accept=%0d src0_read=%0d src1_read=%0d src0_return=%0d src1_return=%0d compute=%0d accum=%0d done=%0d response=%0d bus_response=%0d masks=%04h/%04h/%04h/%04h/%04h/%04h sum=%0d expected=%0d",
                accept_events,
                src0_read_events,
                src1_read_events,
                src0_return_events,
                src1_return_events,
                compute_events,
                accum_events,
                done_events,
                response_events,
                bus_response_events,
                src0_read_seen,
                src1_read_seen,
                src0_return_seen,
                src1_return_seen,
                compute_seen,
                accum_seen,
                running_expected_sum,
                expected_similarity
            );
        end
        if ((vrf_read_conflicts != 0)
         || (matrix_conflicts != 0)
         || (popcount_conflicts != 0)
         || (payload_conflicts != 0)
         || (unknown_events != 0)) begin
            errors++;
            $error(
                "[VV33:BANK_HSIM] conflict/unknown failure vrf_read=%0d matrix=%0d popcount=%0d payload=%0d unknown=%0d",
                vrf_read_conflicts,
                matrix_conflicts,
                popcount_conflicts,
                payload_conflicts,
                unknown_events
            );
        end

        $display(
            "[VV33:BANK_HSIM_METRIC] K=%064h weight=%0d hsim_expected=%0d hsim_result=%0d request=%0d accept_cycle=%0d response_cycle=%0d service=%0d pmul=%0d pmul_service=%0d accept=%0d src0_read=%0d src1_read=%0d src0_return=%0d src1_return=%0d compute=%0d accum=%0d done=%0d response=%0d bus_response=%0d src0_read_seen=%04h src1_read_seen=%04h src0_return_seen=%04h src1_return_seen=%04h compute_seen=%04h accum_seen=%04h vrf_read_conflict=%0d matrix_conflict=%0d popcount_conflict=%0d payload_conflict=%0d unknown=%0d errors=%0d",
            h.scalar_inputs[0],
            vv31_hamming_weight256(h.scalar_inputs[0]),
            expected_similarity,
            hsim_result[10:0],
            hsim_timing.request_cycle,
            hsim_timing.accept_cycle,
            hsim_timing.response_cycle,
            hsim_timing.response_cycle - hsim_timing.accept_cycle,
            h.pmul_wall_cycles,
            h.pmul_service_cycles,
            accept_events,
            src0_read_events,
            src1_read_events,
            src0_return_events,
            src1_return_events,
            compute_events,
            accum_events,
            done_events,
            response_events,
            bus_response_events,
            src0_read_seen,
            src1_read_seen,
            src0_return_seen,
            src1_return_seen,
            compute_seen,
            accum_seen,
            vrf_read_conflicts,
            matrix_conflicts,
            popcount_conflicts,
            payload_conflicts,
            unknown_events,
            errors
        );

        if (errors == 0)
            $display("[VV33:bank_hsim_interleave] PASS");
        else
            $fatal(
                1,
                "[VV33:bank_hsim_interleave] FAIL errors=%0d",
                errors
            );
        $finish;
    end
endmodule
