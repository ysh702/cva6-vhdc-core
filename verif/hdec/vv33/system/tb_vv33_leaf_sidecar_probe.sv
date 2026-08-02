module tb_vv33_leaf_sidecar_probe;
    import hdec_pkg::*;
    import hdec_vv31_ref_pkg::*;
    import hdec_vv31_driver_pkg::*;
    import hdec_vv31_check_pkg::*;
    import hdec_vv31_vectors_pkg::*;

    localparam logic [3:0] SRC0_SLOT = VV31_HDC_HV2_SLOT;
    localparam logic [3:0] SRC1_SLOT = VV31_HDC_HV3_SLOT;
    localparam longint unsigned EXPECTED_PMUL_CYCLES = 146908;

    hdec_vv31_system_harness h();
    defparam h.dut.VV33_FINE_INTERLEAVE = 1'b1;

    longint unsigned accept_events;
    longint unsigned clear_write_events;
    longint unsigned bind_src0_events;
    longint unsigned bind_src1_events;
    longint unsigned bind_capture_events;
    longint unsigned bind_compute_events;
    longint unsigned bind_write_events;
    longint unsigned response_events;
    longint unsigned resource_conflicts;
    longint unsigned unknown_writes;
    bit probe_active;

    always @(posedge h.clk_i) begin
        if (!h.rst_ni) begin
            accept_events      <= 0;
            clear_write_events <= 0;
            bind_src0_events   <= 0;
            bind_src1_events   <= 0;
            bind_capture_events <= 0;
            bind_compute_events <= 0;
            bind_write_events  <= 0;
            response_events    <= 0;
            resource_conflicts <= 0;
            unknown_writes     <= 0;
        end else if (probe_active) begin
            if (h.dut.vv33_fg_accept_fire)
                accept_events <= accept_events + 1;
            if (h.dut.vv33_fg_clear_write_fire)
                clear_write_events <= clear_write_events + 1;
            if (h.dut.vv33_fg_bind_src0_read_fire)
                bind_src0_events <= bind_src0_events + 1;
            if (h.dut.vv33_fg_bind_src1_read_fire)
                bind_src1_events <= bind_src1_events + 1;
            if (h.dut.vv33_fg_bind_capture_fire)
                bind_capture_events <= bind_capture_events + 1;
            if (h.dut.vv33_fg_bind_compute_fire)
                bind_compute_events <= bind_compute_events + 1;
            if (h.dut.vv33_fg_bind_write_fire)
                bind_write_events <= bind_write_events + 1;
            if (h.dut.vv33_fg_response_fire)
                response_events <= response_events + 1;

            if (h.dut.vv33_fg_accept_fire
             || h.dut.vv33_fg_bind_src0_read_fire
             || h.dut.vv33_fg_bind_src1_read_fire
             || h.dut.vv33_fg_bind_capture_fire
             || h.dut.vv33_fg_bind_compute_fire
             || h.dut.vv33_fg_bind_write_fire
             || h.dut.vv33_fg_response_fire)
                $display("[VV33:SIDECAR_EVT] cycle=%0d st=%0d phase=%0d op=%0d chunk=%0d accept=%0b r0=%0b r1=%0b cap=%0b comp=%0b wr=%0b resp=%0b rd0=%016h rd3=%016h h0=%016h h3=%016h",
                         h.bus.cycle_count, h.dut.st_q, h.dut.vv33_fg_phase_q,
                         h.dut.op_q, h.dut.clr_cnt_q[1:0],
                         h.dut.vv33_fg_accept_fire,
                         h.dut.vv33_fg_bind_src0_read_fire,
                         h.dut.vv33_fg_bind_src1_read_fire,
                         h.dut.vv33_fg_bind_capture_fire,
                         h.dut.vv33_fg_bind_compute_fire,
                         h.dut.vv33_fg_bind_write_fire,
                         h.dut.vv33_fg_response_fire,
                         h.dut.vrf_rd[0], h.dut.vrf_rd[3],
                         h.dut.hdc_src0_q[0], h.dut.hdc_src0_q[3]);

            if (h.dut.vv33_fg_bind_compute_fire
             && (h.dut.ecc_diag_product_issue || h.dut.hdc_src0_acc_we))
                resource_conflicts <= resource_conflicts + 1;
            if ((h.dut.vv33_fg_clear_write_fire
              || h.dut.vv33_fg_bind_write_fire)
             && h.dut.vv33_main_vrf_write_busy)
                resource_conflicts <= resource_conflicts + 1;

            if (|h.dut.vrf_we_direct) begin
                if ($isunknown(h.dut.vrf_wa))
                    unknown_writes <= unknown_writes + 1;
                for (int lane = 0; lane < 4; lane++) begin
                    if (h.dut.vrf_we_direct[lane]
                     && $isunknown(h.dut.vrf_wd[lane]))
                        unknown_writes <= unknown_writes + 1;
                end
            end
        end
    end

    initial begin
        logic [1023:0] src0;
        logic [1023:0] src1;
        logic [1023:0] expected_bind;
        logic [1023:0] got_bind;
        logic [255:0] counter_row;
        logic [63:0] response;
        vv31_timing_t start_timing;
        vv31_timing_t hdc_timing;
        int unsigned errors;

        probe_active = 1'b0;
        h.load_vectors();
        h.reset_dut();
        h.validate_vector_contract();
        h.prepare_ecc_case(0);

        src0 = h.hdc_train_samples[0] ^ h.hdc_role_vectors[0];
        src1 = h.hdc_train_samples[1] ^ h.hdc_role_vectors[1];
        expected_bind = vv31_hdc_bind(src0, src1);
        h.bus.write_hv(SRC0_SLOT, src0);
        h.bus.write_hv(SRC1_SLOT, src1);
        for (int row = 16; row < 32; row++) begin
            counter_row = {4{64'hc33c_5aa5_9000_0000}};
            h.bus.write_row(row[5:0], counter_row);
        end

        probe_active = 1'b1;
        h.start_background_pmul(0, start_timing);

        h.bus.issue_hdc(HDEC_HCNTCLR, 64'd0, response, hdc_timing);
        h.bus.expect_status_ok("VV33 sidecar HCNTCLR", response);
        h.bus.issue_hdc(
            HDEC_HBIND,
            vv31_hbind_operand(SRC0_SLOT, SRC0_SLOT, SRC1_SLOT),
            response,
            hdc_timing
        );
        h.bus.expect_status_ok("VV33 sidecar HBIND", response);

        h.wait_background_done_no_poll();
        probe_active = 1'b0;
        @(posedge h.clk_i);
        h.check_background_pmul(0, 1'b1);
        h.bus.read_hv(SRC0_SLOT, got_bind);
        h.bus.expect_equal1024("VV33 sidecar HBIND result", got_bind, expected_bind);
        for (int row = 16; row < 32; row++) begin
            h.bus.read_row(row[5:0], counter_row);
            if (counter_row !== '0) begin
                h.harness_error_count++;
                $error("[VV33:SIDECAR] clear row %0d got=%064h", row, counter_row);
            end
        end
        h.check_ecc_guards(0);

        errors = h.total_errors();
        if (accept_events != 2) begin
            errors++;
            $error("[VV33:SIDECAR] accept events got=%0d expected=2", accept_events);
        end
        if (clear_write_events != 16) begin
            errors++;
            $error("[VV33:SIDECAR] clear writes got=%0d expected=16", clear_write_events);
        end
        if ((bind_src0_events != 4) || (bind_src1_events != 4)
         || (bind_capture_events != 4) || (bind_compute_events != 4)
         || (bind_write_events != 4)) begin
            errors++;
            $error("[VV33:SIDECAR] HBIND lifecycle src0=%0d src1=%0d capture=%0d compute=%0d write=%0d",
                   bind_src0_events, bind_src1_events, bind_capture_events,
                   bind_compute_events, bind_write_events);
        end
        if (response_events != 2) begin
            errors++;
            $error("[VV33:SIDECAR] response events got=%0d expected=2", response_events);
        end
        if ((resource_conflicts != 0) || (unknown_writes != 0)) begin
            errors++;
            $error("[VV33:SIDECAR] conflicts=%0d unknown_writes=%0d",
                   resource_conflicts, unknown_writes);
        end
        if (h.pmul_wall_cycles != EXPECTED_PMUL_CYCLES) begin
            errors++;
            $error("[VV33:SIDECAR] PMUL cycles got=%0d expected=%0d",
                   h.pmul_wall_cycles, EXPECTED_PMUL_CYCLES);
        end

        $display("[VV33:LEAF_SIDECAR] K=%064h weight=%0d pmul=%0d accept=%0d clear=%0d bind_reads=%0d/%0d bind_capture=%0d bind_compute=%0d bind_write=%0d response=%0d conflicts=%0d unknown=%0d errors=%0d",
                 h.scalar_inputs[0],
                 vv31_hamming_weight256(h.scalar_inputs[0]),
                 h.pmul_wall_cycles,
                 accept_events,
                 clear_write_events,
                 bind_src0_events,
                 bind_src1_events,
                 bind_capture_events,
                 bind_compute_events,
                 bind_write_events,
                 response_events,
                 resource_conflicts,
                 unknown_writes,
                 errors);
        if (errors == 0)
            $display("[VV33:leaf_sidecar_probe] PASS");
        else
            $fatal(1, "[VV33:leaf_sidecar_probe] FAIL errors=%0d", errors);
        $finish;
    end
endmodule
