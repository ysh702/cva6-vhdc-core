module tb_vv31_mode_switch;
    import hdec_pkg::*;
    import hdec_vv31_ref_pkg::*;
    import hdec_vv31_driver_pkg::*;
    import hdec_vv31_vectors_pkg::*;

    hdec_vv31_system_harness h();

    initial begin
        logic [63:0] result;
        logic [10:0] expected_score;
        logic [1023:0] got_hv;
        vv31_timing_t hdc_timing;
        vv31_timing_t start_timing;

        h.load_vectors();
        h.reset_dut();
        h.validate_vector_contract();

        // Establish randomized HDC state before entering ECC background mode.
        h.bus.write_hv(
            VV31_HDC_HV2_SLOT,
            h.hdc_query_vectors[0]
        );
        h.bus.write_hv(
            VV31_HDC_HV3_SLOT,
            h.hdc_prototypes_expected[0]
        );
        expected_score = vv31_hdc_overlap(
            h.hdc_query_vectors[0],
            h.hdc_prototypes_expected[0]
        );
        h.bus.issue_hdc(
            HDEC_HSIM,
            vv31_hsim_operand(
                VV31_HDC_HV2_SLOT,
                VV31_HDC_HV3_SLOT
            ),
            result,
            hdc_timing
        );
        h.bus.expect_equal64(
            "pre-PMUL HSIM",
            result,
            {53'd0, expected_score}
        );

        h.prepare_ecc_case(0);
        h.start_background_pmul(0, start_timing);
        h.wait_background_done_no_poll();
        h.check_background_pmul(0, 1'b1);
        h.check_ecc_guards(0);

        if (h.dut.ecc_job_active_q || h.dut.ecc_job_bg_q
            || !h.dut.ecc_job_done_q) begin
            h.harness_error_count++;
            $error(
                "[VV31:mode_switch] ECC mode did not retire active=%0b bg=%0b done=%0b",
                h.dut.ecc_job_active_q,
                h.dut.ecc_job_bg_q,
                h.dut.ecc_job_done_q
            );
        end

        // The HDC rows must survive the ECC job and produce the same result
        // after the controller returns to normal foreground mode.
        h.bus.read_hv(VV31_HDC_HV2_SLOT, got_hv);
        h.bus.expect_equal1024(
            "post-PMUL query preservation",
            got_hv,
            h.hdc_query_vectors[0]
        );
        h.bus.read_hv(VV31_HDC_HV3_SLOT, got_hv);
        h.bus.expect_equal1024(
            "post-PMUL prototype preservation",
            got_hv,
            h.hdc_prototypes_expected[0]
        );
        h.bus.issue_hdc(
            HDEC_HSIM,
            vv31_hsim_operand(
                VV31_HDC_HV2_SLOT,
                VV31_HDC_HV3_SLOT
            ),
            result,
            hdc_timing
        );
        h.bus.expect_equal64(
            "post-PMUL HSIM",
            result,
            {53'd0, expected_score}
        );

        // Exercise the mode-dependent accumulator mapping after ECC retires.
        // In normal foreground mode acc0 is restored to its standalone rows.
        h.bus.issue_hdc(HDEC_HCNTCLR, 64'd0, result, hdc_timing);
        h.bus.expect_status_ok("post-PMUL HCNTCLR", result);
        h.bus.issue_hdc(
            HDEC_HCNTADD,
            {60'd0, VV31_HDC_HV2_SLOT},
            result,
            hdc_timing
        );
        h.bus.expect_status_ok("post-PMUL HCNTADD", result);
        h.bus.issue_hdc(
            HDEC_HCNTCLIP,
            vv31_hcntclip_operand(
                VV31_HDC_HV3_SLOT[2:0],
                1'b0,
                4'd1
            ),
            result,
            hdc_timing
        );
        h.bus.expect_status_ok("post-PMUL HCNTCLIP", result);
        h.bus.read_hv(VV31_HDC_HV3_SLOT, got_hv);
        h.bus.expect_equal1024(
            "post-PMUL accumulator mode",
            got_hv,
            h.hdc_query_vectors[0]
        );

        $display(
            "[VV31:MODE_SWITCH_METRIC] pmul_wall=%0d pmul_service=%0d hdc_compute_ops=%0d max_accept_wait=%0d",
            h.pmul_wall_cycles,
            h.pmul_service_cycles,
            h.bus.hdc_compute_count,
            h.bus.maximum_accept_wait
        );
        $display(
            "[VV31:COVERAGE] test=mode_switch observed=1 expected=1"
        );
        if (h.total_errors() == 0)
            $display("[VV31:mode_switch] PASS");
        else
            $fatal(
                1,
                "[VV31:mode_switch] FAIL errors=%0d",
                h.total_errors()
            );
        $finish;
    end
endmodule
