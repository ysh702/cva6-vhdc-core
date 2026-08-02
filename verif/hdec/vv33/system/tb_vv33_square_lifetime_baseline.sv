module tb_vv33_square_lifetime_baseline;
    import hdec_pkg::*;
    import hdec_vv31_ref_pkg::*;
    import hdec_vv31_driver_pkg::*;
    import hdec_vv31_check_pkg::*;
    import hdec_vv31_vectors_pkg::*;

    hdec_vv31_system_harness h();
    defparam h.dut.VV33_FINE_INTERLEAVE = 1'b0;

    initial begin
        vv31_timing_t start_timing;
        vv31_timing_t hsim_timing;
        logic [63:0] result;
        logic [10:0] expected_hsim;

        h.load_vectors();
        h.reset_dut();
        h.validate_vector_contract();
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
            "VV33 baseline HSIM", result, {53'd0, expected_hsim}
        );

        h.wait_background_done_no_poll();
        h.check_background_pmul(0, 1'b1);
        h.check_ecc_guards(0);

        $display("[VV33:BASELINE_METRIC] K=%064h weight=%0d pmul_wall=%0d hsim_wait=%0d hsim_service=%0d",
                 h.scalar_inputs[0],
                 vv31_hamming_weight256(h.scalar_inputs[0]),
                 h.pmul_wall_cycles,
                 hsim_timing.accept_cycle - hsim_timing.request_cycle,
                 hsim_timing.response_cycle - hsim_timing.accept_cycle);
        if (h.total_errors() == 0)
            $display("[VV33:square_lifetime_baseline] PASS");
        else
            $fatal(1, "[VV33:square_lifetime_baseline] FAIL errors=%0d",
                   h.total_errors());
        $finish;
    end
endmodule
