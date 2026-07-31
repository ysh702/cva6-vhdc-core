module tb_vv31_ecc_schedule_trace;
    import hdec_vv31_driver_pkg::*;
    import hdec_vv31_check_pkg::*;

    localparam longint unsigned VV31_EXPECTED_PMUL_CYCLES = 146_908;
    localparam logic [2:0] VV31_VRF_OWNER_NONE = 3'd0;
    localparam logic [2:0] VV31_VRF_OWNER_HDC  = 3'd1;
    localparam logic [2:0] VV31_VRF_OWNER_ECC  = 3'd2;

    hdec_vv31_system_harness h();

    longint unsigned entry_b_prefetch_count;
    longint unsigned leaf_operand_prefetch_count;
    longint unsigned leaf_preissue_count;
    longint unsigned t1_prefetch_count;
    longint unsigned t2_prefetch_a_count;
    longint unsigned t2_prefetch_b_count;
    longint unsigned matrix_count;
    longint unsigned xor0_add_count;
    longint unsigned xor0_count;
    longint unsigned square_count;
    longint unsigned ecc_vrf_read_count;
    longint unsigned ecc_vrf_write_count;
    longint unsigned ecc_vrf_read_write_overlap_count;

    longint unsigned unknown_probe_count;
    longint unsigned matrix_conflict_count;
    longint unsigned xor0_conflict_count;
    longint unsigned read_owner_conflict_count;
    longint unsigned write_owner_conflict_count;
    longint unsigned prefetch_owner_mismatch_count;

    wire vv31_prefetch_event =
        h.dut.vv31_evt_ecc_entry_b_prefetch
      || h.dut.vv31_evt_ecc_leaf_operand_prefetch
      || h.dut.vv31_evt_ecc_t1_prefetch
      || h.dut.vv31_evt_ecc_t2_prefetch_a
      || h.dut.vv31_evt_ecc_t2_prefetch_b;

    always @(posedge h.clk_i) begin
        if (!h.rst_ni) begin
            entry_b_prefetch_count <= 0;
            leaf_operand_prefetch_count <= 0;
            leaf_preissue_count <= 0;
            t1_prefetch_count <= 0;
            t2_prefetch_a_count <= 0;
            t2_prefetch_b_count <= 0;
            matrix_count <= 0;
            xor0_add_count <= 0;
            xor0_count <= 0;
            square_count <= 0;
            ecc_vrf_read_count <= 0;
            ecc_vrf_write_count <= 0;
            ecc_vrf_read_write_overlap_count <= 0;
            unknown_probe_count <= 0;
            matrix_conflict_count <= 0;
            xor0_conflict_count <= 0;
            read_owner_conflict_count <= 0;
            write_owner_conflict_count <= 0;
            prefetch_owner_mismatch_count <= 0;
        end else if (h.dut.ecc_job_active_q) begin
            if (h.dut.vv31_evt_ecc_entry_b_prefetch === 1'b1)
                entry_b_prefetch_count <= entry_b_prefetch_count + 1;
            if (h.dut.vv31_evt_ecc_leaf_operand_prefetch === 1'b1)
                leaf_operand_prefetch_count <=
                    leaf_operand_prefetch_count + 1;
            if (h.dut.vv31_evt_ecc_leaf_preissue === 1'b1)
                leaf_preissue_count <= leaf_preissue_count + 1;
            if (h.dut.vv31_evt_ecc_t1_prefetch === 1'b1)
                t1_prefetch_count <= t1_prefetch_count + 1;
            if (h.dut.vv31_evt_ecc_t2_prefetch_a === 1'b1)
                t2_prefetch_a_count <= t2_prefetch_a_count + 1;
            if (h.dut.vv31_evt_ecc_t2_prefetch_b === 1'b1)
                t2_prefetch_b_count <= t2_prefetch_b_count + 1;

            if (h.dut.vv31_evt_ecc_matrix === 1'b1)
                matrix_count <= matrix_count + 1;
            if (h.dut.vv31_evt_hdc_xor0 === 1'b1)
                xor0_add_count <= xor0_add_count + 1;
            if (h.dut.vv31_evt_ecc_xor0 === 1'b1)
                xor0_count <= xor0_count + 1;
            if (h.dut.vv31_evt_ecc_square === 1'b1)
                square_count <= square_count + 1;
            if (h.dut.vv31_evt_vrf_read_owner === VV31_VRF_OWNER_ECC)
                ecc_vrf_read_count <= ecc_vrf_read_count + 1;
            if (h.dut.vv31_evt_vrf_write_owner === VV31_VRF_OWNER_ECC)
                ecc_vrf_write_count <= ecc_vrf_write_count + 1;
            if ((h.dut.vv31_evt_vrf_read_owner === VV31_VRF_OWNER_ECC)
                && (h.dut.vv31_evt_vrf_write_owner
                    === VV31_VRF_OWNER_ECC))
                ecc_vrf_read_write_overlap_count <=
                    ecc_vrf_read_write_overlap_count + 1;

            if ($isunknown({
                h.dut.vv31_evt_ecc_entry_b_prefetch,
                h.dut.vv31_evt_ecc_leaf_operand_prefetch,
                h.dut.vv31_evt_ecc_leaf_preissue,
                h.dut.vv31_evt_ecc_t1_prefetch,
                h.dut.vv31_evt_ecc_t2_prefetch_a,
                h.dut.vv31_evt_ecc_t2_prefetch_b,
                h.dut.vv31_evt_hdc_matrix,
                h.dut.vv31_evt_ecc_matrix,
                h.dut.vv31_evt_hdc_xor0,
                h.dut.vv31_evt_ecc_xor0,
                h.dut.vv31_evt_ecc_square,
                h.dut.vv31_evt_vrf_read_owner,
                h.dut.vv31_evt_vrf_write_owner
            })) begin
                unknown_probe_count <= unknown_probe_count + 1;
                $error(
                    "[VV31:ecc_schedule_trace] unknown resource probe cycle=%0d",
                    h.bus.cycle_count
                );
            end

            if ((h.dut.vv31_evt_hdc_matrix === 1'b1)
                && (h.dut.vv31_evt_ecc_matrix === 1'b1)) begin
                matrix_conflict_count <= matrix_conflict_count + 1;
                $error(
                    "[VV31:ecc_schedule_trace] matrix owner conflict cycle=%0d",
                    h.bus.cycle_count
                );
            end
            if ((h.dut.vv31_evt_hdc_xor0 === 1'b1)
                && (h.dut.vv31_evt_ecc_xor0 === 1'b1)) begin
                xor0_conflict_count <= xor0_conflict_count + 1;
                $error(
                    "[VV31:ecc_schedule_trace] XOR0 owner conflict cycle=%0d",
                    h.bus.cycle_count
                );
            end
            if ((h.dut.vv31_evt_vrf_read_owner !== VV31_VRF_OWNER_NONE)
                && (h.dut.vv31_evt_vrf_read_owner
                    !== VV31_VRF_OWNER_ECC)) begin
                read_owner_conflict_count <= read_owner_conflict_count + 1;
                $error(
                    "[VV31:ecc_schedule_trace] VRF read owner conflict cycle=%0d owner=%0d",
                    h.bus.cycle_count,
                    h.dut.vv31_evt_vrf_read_owner
                );
            end
            if ((h.dut.vv31_evt_vrf_write_owner !== VV31_VRF_OWNER_NONE)
                && (h.dut.vv31_evt_vrf_write_owner
                    !== VV31_VRF_OWNER_ECC)) begin
                write_owner_conflict_count <= write_owner_conflict_count + 1;
                $error(
                    "[VV31:ecc_schedule_trace] VRF write owner conflict cycle=%0d owner=%0d",
                    h.bus.cycle_count,
                    h.dut.vv31_evt_vrf_write_owner
                );
            end
            if ((vv31_prefetch_event === 1'b1)
                && (h.dut.vv31_evt_vrf_read_owner
                    !== VV31_VRF_OWNER_ECC)) begin
                prefetch_owner_mismatch_count <=
                    prefetch_owner_mismatch_count + 1;
                $error(
                    "[VV31:ecc_schedule_trace] prefetch without ECC VRF owner cycle=%0d owner=%0d",
                    h.bus.cycle_count,
                    h.dut.vv31_evt_vrf_read_owner
                );
            end
        end
    end

    initial begin
        vv31_timing_t start_timing;
        longint unsigned observed_cycles;
        longint unsigned conflict_count;
        int unsigned observed_windows;
        int unsigned postcheck_errors;

        observed_cycles = 0;
        observed_windows = 0;
        postcheck_errors = 0;

        h.load_vectors();
        h.reset_dut();
        h.validate_vector_contract();
        h.prepare_ecc_case(0);
        h.start_background_pmul(0, start_timing);
        h.wait_background_done_no_poll();
        h.check_background_pmul(0, 1'b1);
        h.check_ecc_guards(0);
        @(negedge h.clk_i);

        observed_cycles = h.pmul_wall_cycles;
        conflict_count = unknown_probe_count
                       + matrix_conflict_count
                       + xor0_conflict_count
                       + read_owner_conflict_count
                       + write_owner_conflict_count
                       + prefetch_owner_mismatch_count;

        if (entry_b_prefetch_count != 0)
            observed_windows++;
        else begin
            postcheck_errors++;
            $error("[VV31:ecc_schedule_trace] entry-B prefetch not observed");
        end
        if (leaf_operand_prefetch_count != 0)
            observed_windows++;
        else begin
            postcheck_errors++;
            $error("[VV31:ecc_schedule_trace] leaf operand prefetch not observed");
        end
        if (leaf_preissue_count != 0)
            observed_windows++;
        else begin
            postcheck_errors++;
            $error("[VV31:ecc_schedule_trace] leaf preissue not observed");
        end
        if (t1_prefetch_count != 0)
            observed_windows++;
        else begin
            postcheck_errors++;
            $error("[VV31:ecc_schedule_trace] T1 prefetch not observed");
        end
        if (t2_prefetch_a_count != 0)
            observed_windows++;
        else begin
            postcheck_errors++;
            $error("[VV31:ecc_schedule_trace] T2-A prefetch not observed");
        end
        if (t2_prefetch_b_count != 0)
            observed_windows++;
        else begin
            postcheck_errors++;
            $error("[VV31:ecc_schedule_trace] T2-B prefetch not observed");
        end

        if ((matrix_count == 0) || (xor0_count == 0)
            || (square_count == 0) || (ecc_vrf_read_count == 0)
            || (ecc_vrf_write_count == 0)) begin
            postcheck_errors++;
            $error(
                "[VV31:ecc_schedule_trace] incomplete PMUL resource trace matrix=%0d xor0=%0d square=%0d vrf_read=%0d vrf_write=%0d",
                matrix_count,
                xor0_count,
                square_count,
                ecc_vrf_read_count,
                ecc_vrf_write_count
            );
        end
        if (observed_cycles != VV31_EXPECTED_PMUL_CYCLES) begin
            postcheck_errors++;
            $error(
                "[VV31:ecc_schedule_trace] PMUL cycle mismatch got=%0d expected=%0d",
                observed_cycles,
                VV31_EXPECTED_PMUL_CYCLES
            );
        end

        $display(
            "[VV31:ECC_SCHED_TRACE] case=0 K=%064h cycles=%0d entry_b=%0d leaf_operand=%0d leaf_preissue=%0d t1=%0d t2_a=%0d t2_b=%0d matrix=%0d xor0_add=%0d xor0_fold=%0d square=%0d ecc_vrf_read=%0d ecc_vrf_write=%0d ecc_rw_overlap=%0d conflicts=%0d",
            h.scalar_inputs[0],
            observed_cycles,
            entry_b_prefetch_count,
            leaf_operand_prefetch_count,
            leaf_preissue_count,
            t1_prefetch_count,
            t2_prefetch_a_count,
            t2_prefetch_b_count,
            matrix_count,
            xor0_add_count,
            xor0_count,
            square_count,
            ecc_vrf_read_count,
            ecc_vrf_write_count,
            ecc_vrf_read_write_overlap_count,
            conflict_count
        );
        $display(
            "[VV31:PMUL_CYCLE] case=0 K=%064h weight=%0d cycles=%0d",
            h.scalar_inputs[0],
            vv31_hamming_weight256(h.scalar_inputs[0]),
            observed_cycles
        );
        $display(
            "[VV31:COVERAGE] test=ecc_schedule_trace observed=%0d expected=6",
            observed_windows
        );

        if ((h.total_errors() == 0) && (conflict_count == 0)
            && (postcheck_errors == 0))
            $display("[VV31:ecc_schedule_trace] PASS");
        else
            $fatal(
                1,
                "[VV31:ecc_schedule_trace] FAIL harness=%0d conflicts=%0d postcheck=%0d",
                h.total_errors(),
                conflict_count,
                postcheck_errors
            );
        $finish;
    end
endmodule
