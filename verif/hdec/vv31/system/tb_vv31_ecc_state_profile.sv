module tb_vv31_ecc_state_profile;
    import hdec_pkg::*;
    import hdec_vv31_ref_pkg::*;
    import hdec_vv31_driver_pkg::*;
    import hdec_vv31_vectors_pkg::*;

    hdec_vv31_system_harness h();

    longint unsigned state_cycles [0:127];
    longint unsigned substep_cycles [0:7][0:31];
    longint unsigned transition_count [0:127][0:127];
    logic [6:0] previous_state;
    bit previous_state_valid;

    always @(posedge h.clk_i) begin
        if (!h.rst_ni) begin
            previous_state_valid <= 1'b0;
            previous_state <= '0;
        end else if (h.dut.ecc_job_active_q) begin
            state_cycles[int'(h.dut.st_q)]
                <= state_cycles[int'(h.dut.st_q)] + 1;
            substep_cycles[int'(h.dut.ecc_pmul_subop_q)]
                          [int'(h.dut.ecc_pmul_step_q)]
                <= substep_cycles[int'(h.dut.ecc_pmul_subop_q)]
                                 [int'(h.dut.ecc_pmul_step_q)] + 1;
            if (previous_state_valid)
                transition_count[int'(previous_state)]
                                [int'(h.dut.st_q)]
                    <= transition_count[int'(previous_state)]
                                       [int'(h.dut.st_q)] + 1;
            previous_state <= h.dut.st_q;
            previous_state_valid <= 1'b1;
        end
    end

    initial begin
        vv31_timing_t start_timing;

        for (int state_index = 0; state_index < 128; state_index++) begin
            state_cycles[state_index] = 0;
            for (int next_state = 0; next_state < 128; next_state++)
                transition_count[state_index][next_state] = 0;
        end
        for (int subop = 0; subop < 8; subop++)
            for (int step = 0; step < 32; step++)
                substep_cycles[subop][step] = 0;

        h.load_vectors();
        h.reset_dut();
        h.validate_vector_contract();
        h.prepare_ecc_case(0);
        h.start_background_pmul(0, start_timing);
        h.wait_background_done_no_poll();
        h.check_background_pmul(0, 1'b1);

        for (int state_index = 0; state_index < 128; state_index++)
            if (state_cycles[state_index] != 0)
                $display(
                    "[VV31:ECC_STATE] state=%0d cycles=%0d",
                    state_index,
                    state_cycles[state_index]
                );

        for (int subop = 0; subop < 8; subop++)
            for (int step = 0; step < 32; step++)
                if (substep_cycles[subop][step] != 0)
                    $display(
                        "[VV31:ECC_SUBSTEP] subop=%0d step=%0d cycles=%0d",
                        subop,
                        step,
                        substep_cycles[subop][step]
                    );

        for (int state_index = 0; state_index < 128; state_index++)
            for (int next_state = 0; next_state < 128; next_state++)
                if (transition_count[state_index][next_state] != 0)
                    $display(
                        "[VV31:ECC_TRANSITION] from=%0d to=%0d count=%0d",
                        state_index,
                        next_state,
                        transition_count[state_index][next_state]
                    );

        if (h.total_errors() == 0)
            $display("[VV31:ecc_state_profile] PASS");
        else
            $fatal(
                1,
                "[VV31:ecc_state_profile] FAIL errors=%0d",
                h.total_errors()
            );
        $finish;
    end
endmodule
