module tb_vv31_baseline_gap;
    import hdec_pkg::*;
    import hdec_vv31_ref_pkg::*;
    import hdec_vv31_driver_pkg::*;
    import hdec_vv31_vectors_pkg::*;

    hdec_vv31_system_harness h();

    initial begin
        logic [63:0] result;
        logic [10:0] expected_score;
        vv31_timing_t start_timing;
        vv31_timing_t hdc_timing;

        h.load_vectors();
        h.reset_dut();
        h.validate_vector_contract();
        h.prepare_ecc_case(0);

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

        h.start_background_pmul(0, start_timing);
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
            "baseline pending HSIM",
            result,
            {53'd0, expected_score}
        );
        $display(
            "[VV31:BASELINE_GAP] hdc_request=%0d hdc_accept=%0d hdc_response=%0d accept_wait=%0d service=%0d ecc_done_at_accept=%0b",
            hdc_timing.request_cycle,
            hdc_timing.accept_cycle,
            hdc_timing.response_cycle,
            hdc_timing.accept_cycle - hdc_timing.request_cycle,
            hdc_timing.response_cycle - hdc_timing.accept_cycle,
            h.dut.ecc_job_done_q
        );

        if (!h.dut.ecc_job_done_q)
            h.wait_background_done_no_poll();
        h.check_background_pmul(0, 1'b1);
        h.check_ecc_guards(0);
        h.print_resource_metrics("baseline_gap");

        if (h.total_errors() == 0)
            $display("[VV31:baseline_gap] PASS");
        else
            $fatal(
                1,
                "[VV31:baseline_gap] FAIL errors=%0d",
                h.total_errors()
            );
        $finish;
    end
endmodule
