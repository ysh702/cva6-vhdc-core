module tb_vv33_square_hcntadd_contract;
    import hdec_pkg::*;
    import hdec_vv31_ref_pkg::*;
    import hdec_vv31_driver_pkg::*;
    import hdec_vv31_check_pkg::*;
    import hdec_vv31_vectors_pkg::*;

    hdec_vv31_system_harness h();
    int unsigned defer_count, read_count, write_count, conflict_count;

    always @(posedge h.clk_i) begin
        if (!h.rst_ni) begin
            defer_count <= 0;
            read_count <= 0;
            write_count <= 0;
            conflict_count <= 0;
        end else begin
            if (h.dut.vv33_sq_defer_fire) defer_count <= defer_count + 1;
            if (h.dut.vv33_sq_read_fire) begin
                read_count <= read_count + 1;
                if (h.dut.vv31_evt_hdc_vrf_read) conflict_count <= conflict_count + 1;
            end
            if (h.dut.vv33_sq_write_fire) begin
                write_count <= write_count + 1;
                if ((h.dut.st_q != h.dut.S_UOP_P3_VRF_WAIT)
                 || (h.dut.vrf_we !== 4'b1111)
                 || $isunknown({h.dut.vrf_wa, h.dut.vrf_wd}))
                    conflict_count <= conflict_count + 1;
            end
        end
    end

    initial begin
        vv31_timing_t start_timing, add_timing;
        logic [63:0] result, observed_word, expected_word;
        logic [1023:0] sample;

        h.load_vectors();
        h.reset_dut();
        h.validate_vector_contract();
        h.prepare_ecc_case(0);
        sample = h.hdc_query_vectors[0];
        h.bus.write_hv(VV31_HDC_HV2_SLOT, sample);
        for (int row = 16; row < 32; row++)
            for (int bank = 0; bank < 4; bank++)
                h.bus.write_vrf64(bank[1:0], row[5:0], 64'd0);

        h.start_background_pmul(0, start_timing);
        h.bus.issue_hdc(
            HDEC_HCNTADD,
            {60'd0, VV31_HDC_HV2_SLOT},
            result,
            add_timing
        );
        h.bus.expect_equal64("VV33 square-window HCNTADD status", result, '0);
        h.wait_background_done_no_poll();
        h.check_background_pmul(0, 1'b1);
        h.check_ecc_guards(0);

        for (int chunk = 0; chunk < 4; chunk++) begin
            for (int subgroup = 0; subgroup < 4; subgroup++) begin
                for (int bank = 0; bank < 4; bank++) begin
                    h.bus.read_vrf64(
                        bank[1:0],
                        (16 + chunk * 4 + subgroup),
                        observed_word
                    );
                    expected_word = {
                        48'd0,
                        sample[chunk * 256 + bank * 64
                             + subgroup * 16 +: 16]
                    };
                    if (observed_word !== expected_word) begin
                        h.harness_error_count++;
                        $error("[VV33:HCNTADD] row=%0d bank=%0d got=%016h expected=%016h",
                               16 + chunk * 4 + subgroup, bank,
                               observed_word, expected_word);
                    end
                end
            end
        end
        if ((defer_count != 1) || (read_count != 1)
         || (write_count != 1) || (conflict_count != 0)) begin
            h.harness_error_count++;
            $error("[VV33:HCNTADD] lifecycle defer=%0d read=%0d write=%0d conflict=%0d",
                   defer_count, read_count, write_count, conflict_count);
        end

        $display("[VV33:HCNTADD_METRIC] K=%064h pmul_wall=%0d wait=%0d service=%0d defer=%0d read=%0d write=%0d conflicts=%0d",
                 h.scalar_inputs[0], h.pmul_wall_cycles,
                 add_timing.accept_cycle - add_timing.request_cycle,
                 add_timing.response_cycle - add_timing.accept_cycle,
                 defer_count, read_count, write_count, conflict_count);
        if (h.total_errors() == 0)
            $display("[VV33:square_hcntadd_contract] PASS");
        else
            $fatal(1, "[VV33:square_hcntadd_contract] FAIL errors=%0d",
                   h.total_errors());
        $finish;
    end
endmodule
