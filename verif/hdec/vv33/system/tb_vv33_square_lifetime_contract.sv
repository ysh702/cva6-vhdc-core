module tb_vv33_square_lifetime_contract;
    import hdec_pkg::*;
    import hdec_vv31_ref_pkg::*;
    import hdec_vv31_driver_pkg::*;
    import hdec_vv31_check_pkg::*;
    import hdec_vv31_vectors_pkg::*;

    hdec_vv31_system_harness h();

    int unsigned defer_count;
    int unsigned read_count;
    int unsigned write_count;
    int unsigned overlap_count;
    int unsigned conflict_count;
    int unsigned unknown_count;

    always @(posedge h.clk_i) begin
        if (!h.rst_ni) begin
            defer_count    <= 0;
            read_count     <= 0;
            write_count    <= 0;
            overlap_count  <= 0;
            conflict_count <= 0;
            unknown_count  <= 0;
        end else begin
            if (h.dut.vv33_sq_defer_fire)
                defer_count <= defer_count + 1;
            if (h.dut.vv33_sq_read_fire) begin
                read_count <= read_count + 1;
                if (h.dut.vv31_evt_hdc_vrf_read) begin
                    conflict_count <= conflict_count + 1;
                    $error("[VV33:SQUARE] simultaneous VRF reads cycle=%0d",
                           h.bus.cycle_count);
                end
            end
            if (h.dut.vv33_sq_write_fire) begin
                write_count <= write_count + 1;
                if (h.foreground_inflight_q)
                    overlap_count <= overlap_count + 1;
                if ((h.dut.vrf_we !== 4'b1111)
                 || $isunknown({h.dut.vrf_wa, h.dut.vrf_wd})) begin
                    unknown_count <= unknown_count + 1;
                    $error("[VV33:SQUARE] invalid square write cycle=%0d",
                           h.bus.cycle_count);
                end
                if (!((h.dut.st_q == h.dut.S_UOP_P3_POP_CAPTURE)
                   || (h.dut.st_q == h.dut.S_UOP_P1_RD0)
                   || (h.dut.st_q == h.dut.S_UOP_P3_VRF_WAIT)
                   || (h.dut.st_q == h.dut.S_UOP_P4_RESP))) begin
                    conflict_count <= conflict_count + 1;
                    $error("[VV33:SQUARE] write outside compatible slot state=%0d",
                           h.dut.st_q);
                end
            end
            if ($isunknown({h.dut.vv33_sq_phase_q,
                            h.dut.vv33_sq_defer_fire,
                            h.dut.vv33_sq_read_fire,
                            h.dut.vv33_sq_write_fire,
                            h.bus.valid_o})) begin
                unknown_count <= unknown_count + 1;
                $error("[VV33:SQUARE] control X/Z cycle=%0d",
                       h.bus.cycle_count);
            end
        end
    end

    initial begin
        vv31_timing_t start_timing;
        vv31_timing_t hsim_timing;
        logic [63:0] result;
        logic [10:0] expected_hsim;

        h.load_vectors();
        h.reset_dut();
        h.validate_vector_contract();
        if (h.scalar_count != 1)
            $fatal(1, "[VV33:SQUARE] expected one random K got=%0d",
                   h.scalar_count);

        h.prepare_ecc_case(0);
        h.bus.write_hv(VV31_HDC_HV2_SLOT, h.hdc_query_vectors[0]);
        h.bus.write_hv(VV31_HDC_HV3_SLOT,
                       h.hdc_prototypes_expected[0]);
        expected_hsim = vv31_hdc_overlap(
            h.hdc_query_vectors[0], h.hdc_prototypes_expected[0]
        );

        h.start_background_pmul(0, start_timing);

        h.bus.issue_hdc(
            HDEC_HSIM,
            vv31_hsim_operand(VV31_HDC_HV2_SLOT, VV31_HDC_HV3_SLOT),
            result,
            hsim_timing
        );
        h.bus.expect_equal64(
            "VV33 square-window HSIM", result, {53'd0, expected_hsim}
        );

        h.wait_background_done_no_poll();
        h.check_background_pmul(0, 1'b1);
        h.check_ecc_guards(0);

        if ((defer_count != 1) || (read_count != 1)
         || (write_count != 1) || (overlap_count != 1)) begin
            h.harness_error_count++;
            $error("[VV33:SQUARE] insufficient overlap defer=%0d read=%0d write=%0d overlap=%0d",
                   defer_count, read_count, write_count, overlap_count);
        end
        if ((conflict_count != 0) || (unknown_count != 0)) begin
            h.harness_error_count++;
            $error("[VV33:SQUARE] conflicts=%0d unknown=%0d",
                   conflict_count, unknown_count);
        end

        $display("[VV33:SQUARE_METRIC] K=%064h weight=%0d pmul_wall=%0d hsim_wait=%0d hsim_service=%0d defer=%0d read=%0d write=%0d overlap=%0d conflicts=%0d unknown=%0d",
                 h.scalar_inputs[0],
                 vv31_hamming_weight256(h.scalar_inputs[0]),
                 h.pmul_wall_cycles,
                 hsim_timing.accept_cycle - hsim_timing.request_cycle,
                 hsim_timing.response_cycle - hsim_timing.accept_cycle,
                 defer_count, read_count, write_count, overlap_count,
                 conflict_count, unknown_count);
        if (h.total_errors() == 0)
            $display("[VV33:square_lifetime_contract] PASS");
        else
            $fatal(1, "[VV33:square_lifetime_contract] FAIL errors=%0d",
                   h.total_errors());
        $finish;
    end
endmodule
