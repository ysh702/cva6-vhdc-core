module tb_vv33_pmul_opportunity_count;
    import hdec_pkg::*;
    import hdec_vv31_ref_pkg::*;
    import hdec_vv31_driver_pkg::*;
    import hdec_vv31_vectors_pkg::*;

    hdec_vv31_system_harness h();

    longint unsigned pmul_active_cycles;
    longint unsigned eligible_cap2_slots;
    longint unsigned eligible_cap2_by_sub [0:2];
    longint unsigned corresponding_fold_slots;
    longint unsigned safe_cap2_read_slots;
    longint unsigned safe_fold_read_slots;
    longint unsigned safe_read_issue_slots;
    longint unsigned final_leaf_write_pair_slots;
    longint unsigned final_leaf_write_drain_slots;
    longint unsigned final_leaf_write_pair_drain_pairs;
    longint unsigned unexpected_fold_misses;
    longint unsigned unexpected_pair_misses;
    longint unsigned scalar_hamming_weight;

    bit monitor_active;
    bit previous_eligible_cap2;
    bit previous_final_leaf_write_pair;

    wire cap2_slot = monitor_active
                   && h.dut.ecc_job_active_q
                   && (h.dut.st_q == h.dut.S_ECC_DIAG_CAPTURE2);
    wire eligible_cap2 = cap2_slot
                       && !((h.dut.ecc_kpd64_sub_q == 2'd2)
                         && !h.dut.ecc_leaf_last);

    // Under the accepted VV31 schedule, CAP2(sub1) issues next-leaf B.
    wire cap2_uses_vrf_read = cap2_slot
                            && h.dut.VV31_SCHED_ENABLE
                            && h.dut.ecc_diag_sub_shadow_mode
                            && (h.dut.ecc_kpd64_sub_q == 2'd1)
                            && !h.dut.ecc_leaf_last;

    wire fold_slot = monitor_active
                   && h.dut.ecc_job_active_q
                   && (h.dut.st_q == h.dut.S_ECC_DIAG_FOLD_ISSUE);
    wire corresponding_fold = fold_slot && previous_eligible_cap2;

    // FOLD(sub1) issues next-leaf A.  The final ADD step-5 fold also starts
    // the continuation operand read, so neither cycle is a free read issue.
    wire fold_uses_vrf_read = fold_slot
                            && (((h.dut.ecc_kpd64_sub_q == 2'd1)
                              && h.dut.ecc_diag_fold_preissue
                              && !h.dut.ecc_leaf_last)
                             || ((h.dut.ecc_kpd64_sub_q == 2'd2)
                              && h.dut.ecc_leaf_last
                              && h.dut.ecc_pmul_add_step5_complete));

    wire final_leaf_write_pair = monitor_active
                               && h.dut.ecc_job_active_q
                               && (h.dut.st_q == h.dut.S_ECC_WRITE_PAIR)
                               && h.dut.ecc_leaf_last
                               && h.dut.ecc_autoreduce_q;

    function automatic longint unsigned popcount256(input logic [255:0] value);
        longint unsigned count;
        begin
            count = 0;
            for (int bit_index = 0; bit_index < 256; bit_index++)
                count += value[bit_index];
            return count;
        end
    endfunction

    always @(posedge h.clk_i) begin
        if (!h.rst_ni) begin
            previous_eligible_cap2 <= 1'b0;
            previous_final_leaf_write_pair <= 1'b0;
        end else begin
            if (monitor_active && h.dut.ecc_job_active_q)
                pmul_active_cycles <= pmul_active_cycles + 1;

            if (eligible_cap2) begin
                eligible_cap2_slots <= eligible_cap2_slots + 1;
                if (h.dut.ecc_kpd64_sub_q <= 2'd2)
                    eligible_cap2_by_sub[h.dut.ecc_kpd64_sub_q]
                        <= eligible_cap2_by_sub[h.dut.ecc_kpd64_sub_q] + 1;
                if (!cap2_uses_vrf_read) begin
                    safe_cap2_read_slots <= safe_cap2_read_slots + 1;
                    safe_read_issue_slots <= safe_read_issue_slots + 1;
                end
            end

            if (corresponding_fold) begin
                corresponding_fold_slots <= corresponding_fold_slots + 1;
                if (!fold_uses_vrf_read) begin
                    safe_fold_read_slots <= safe_fold_read_slots + 1;
                    safe_read_issue_slots <= safe_read_issue_slots + 1;
                end
            end

            if (previous_eligible_cap2 && !fold_slot)
                unexpected_fold_misses <= unexpected_fold_misses + 1;

            if (final_leaf_write_pair)
                final_leaf_write_pair_slots <= final_leaf_write_pair_slots + 1;

            if (previous_final_leaf_write_pair) begin
                if (monitor_active
                    && h.dut.ecc_job_active_q
                    && (h.dut.st_q == h.dut.S_ECC_WRITE_DRAIN)) begin
                    final_leaf_write_drain_slots
                        <= final_leaf_write_drain_slots + 1;
                    final_leaf_write_pair_drain_pairs
                        <= final_leaf_write_pair_drain_pairs + 1;
                end else begin
                    unexpected_pair_misses <= unexpected_pair_misses + 1;
                end
            end

            previous_eligible_cap2 <= eligible_cap2;
            previous_final_leaf_write_pair <= final_leaf_write_pair;
        end
    end

    initial begin
        vv31_timing_t start_timing;
        longint unsigned compute_slot_upper_bound;
        longint unsigned boundary_slot_upper_bound;
        longint unsigned nondoublecounted_upper_bound;
        longint unsigned target_cycles;
        longint unsigned whole_episode_upper_bound;

        monitor_active = 1'b0;
        previous_eligible_cap2 = 1'b0;
        previous_final_leaf_write_pair = 1'b0;
        pmul_active_cycles = 0;
        eligible_cap2_slots = 0;
        corresponding_fold_slots = 0;
        safe_cap2_read_slots = 0;
        safe_fold_read_slots = 0;
        safe_read_issue_slots = 0;
        final_leaf_write_pair_slots = 0;
        final_leaf_write_drain_slots = 0;
        final_leaf_write_pair_drain_pairs = 0;
        unexpected_fold_misses = 0;
        unexpected_pair_misses = 0;
        scalar_hamming_weight = 0;
        for (int sub_index = 0; sub_index < 3; sub_index++)
            eligible_cap2_by_sub[sub_index] = 0;

        h.load_vectors();
        h.reset_dut();
        h.validate_vector_contract();
        h.prepare_ecc_case(0);
        scalar_hamming_weight = popcount256(h.scalar_inputs[0]);

        monitor_active = 1'b1;
        h.start_background_pmul(0, start_timing);
        h.wait_background_done_no_poll();
        monitor_active = 1'b0;
        @(posedge h.clk_i);
        h.check_background_pmul(0, 1'b1);

        compute_slot_upper_bound = eligible_cap2_slots
                                 + corresponding_fold_slots;
        boundary_slot_upper_bound = 2 * final_leaf_write_pair_drain_pairs;
        // Read slots overlap the CAP2/FOLD physical cycles, so they are
        // reported as enabling capacity and deliberately not added twice.
        nondoublecounted_upper_bound = compute_slot_upper_bound
                                     + boundary_slot_upper_bound;
        target_cycles = 9356;
        whole_episode_upper_bound = nondoublecounted_upper_bound / 874;

        $display(
            "[VV33:OPPORTUNITY:RUN] K=%064h K_weight=%0d pmul_active=%0d",
            h.scalar_inputs[0],
            scalar_hamming_weight,
            pmul_active_cycles
        );
        $display(
            "[VV33:OPPORTUNITY:COMPUTE] cap2_eligible=%0d cap2_sub0=%0d cap2_sub1=%0d cap2_sub2=%0d fold_corresponding=%0d compute_upper=%0d fold_miss=%0d",
            eligible_cap2_slots,
            eligible_cap2_by_sub[0],
            eligible_cap2_by_sub[1],
            eligible_cap2_by_sub[2],
            corresponding_fold_slots,
            compute_slot_upper_bound,
            unexpected_fold_misses
        );
        $display(
            "[VV33:OPPORTUNITY:READ] safe_read_total=%0d safe_read_cap2=%0d safe_read_fold=%0d",
            safe_read_issue_slots,
            safe_cap2_read_slots,
            safe_fold_read_slots
        );
        $display(
            "[VV33:OPPORTUNITY:BOUNDARY] final_write_pair=%0d final_write_drain=%0d final_pairs=%0d pair_miss=%0d boundary_upper=%0d",
            final_leaf_write_pair_slots,
            final_leaf_write_drain_slots,
            final_leaf_write_pair_drain_pairs,
            unexpected_pair_misses,
            boundary_slot_upper_bound
        );
        $display(
            "[VV33:OPPORTUNITY:UPPER] nonoverlap_upper=%0d episodes874=%0d target9356_plausible=%0d errors=%0d",
            nondoublecounted_upper_bound,
            whole_episode_upper_bound,
            (nondoublecounted_upper_bound >= target_cycles),
            h.total_errors()
        );

        if (eligible_cap2_slots != corresponding_fold_slots)
            $fatal(
                1,
                "[VV33:opportunity_count] CAP2/FOLD mismatch cap2=%0d fold=%0d",
                eligible_cap2_slots,
                corresponding_fold_slots
            );
        if (unexpected_fold_misses != 0)
            $fatal(
                1,
                "[VV33:opportunity_count] unexpected fold misses=%0d",
                unexpected_fold_misses
            );
        if (h.total_errors() != 0)
            $fatal(
                1,
                "[VV33:opportunity_count] FAIL errors=%0d",
                h.total_errors()
            );

        $display("[VV33:opportunity_count] PASS");
        $finish;
    end
endmodule
