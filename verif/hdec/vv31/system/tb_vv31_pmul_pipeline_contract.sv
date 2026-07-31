module tb_vv31_pmul_pipeline_contract;
    import hdec_vv31_driver_pkg::*;
    import hdec_vv31_check_pkg::*;

    hdec_vv31_system_harness h();

    initial begin
        vv31_timing_t start_timing;
        longint unsigned reference_cycles;
        longint unsigned observed_cycles;

        reference_cycles = 0;
        h.load_vectors();
        h.reset_dut();
        h.validate_vector_contract();

        for (int case_index = 0;
             case_index < h.scalar_count;
             case_index++) begin
            h.prepare_ecc_case(case_index);
            h.start_background_pmul(case_index, start_timing);

            // No foreground request is issued while the background job is
            // active.  Completion is observed hierarchically, not by polling.
            h.wait_background_done_no_poll();
            h.check_background_pmul(case_index, 1'b1);
            h.check_ecc_guards(case_index);
            observed_cycles = h.pmul_wall_cycles;

            if (case_index == 0)
                reference_cycles = observed_cycles;
            else if (observed_cycles != reference_cycles) begin
                h.harness_error_count++;
                $error(
                    "[VV31:pmul_pipeline_contract] scalar-dependent cycles case=%0d got=%0d expected=%0d",
                    case_index,
                    observed_cycles,
                    reference_cycles
                );
            end

            $display(
                "[VV31:PMUL_CYCLE] case=%0d K=%064h weight=%0d cycles=%0d",
                case_index,
                h.scalar_inputs[case_index],
                vv31_hamming_weight256(h.scalar_inputs[case_index]),
                observed_cycles
            );
        end

        $display(
            "[VV31:COVERAGE] test=pmul_pipeline_contract observed=%0d expected=%0d",
            h.scalar_count,
            h.scalar_count
        );
        if (h.total_errors() == 0)
            $display("[VV31:pmul_pipeline_contract] PASS");
        else
            $fatal(
                1,
                "[VV31:pmul_pipeline_contract] FAIL errors=%0d",
                h.total_errors()
            );
        $finish;
    end
endmodule
