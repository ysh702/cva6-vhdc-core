module tb_vv33_square_hbind_contract;
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
                if ((h.dut.st_q != h.dut.S_UOP_P1_RD0)
                 || (h.dut.vrf_we !== 4'b1111)
                 || $isunknown({h.dut.vrf_wa, h.dut.vrf_wd}))
                    conflict_count <= conflict_count + 1;
            end
        end
    end

    initial begin
        vv31_timing_t start_timing, bind_timing;
        logic [63:0] result;
        logic [1023:0] expected_bind, observed_bind;

        h.load_vectors();
        h.reset_dut();
        h.validate_vector_contract();
        h.prepare_ecc_case(0);
        h.bus.write_hv(VV31_HDC_HV2_SLOT, h.hdc_query_vectors[0]);
        h.bus.write_hv(VV31_HDC_HV3_SLOT, h.hdc_prototypes_expected[0]);
        expected_bind = h.hdc_query_vectors[0] ^ h.hdc_prototypes_expected[0];

        h.start_background_pmul(0, start_timing);
        h.bus.issue_hdc(
            HDEC_HBIND,
            vv31_hbind_operand(4'd4, VV31_HDC_HV2_SLOT, VV31_HDC_HV3_SLOT),
            result,
            bind_timing
        );
        h.bus.expect_equal64("VV33 square-window HBIND status", result, '0);
        h.wait_background_done_no_poll();
        h.check_background_pmul(0, 1'b1);
        h.check_ecc_guards(0);
        h.bus.read_hv(4'd4, observed_bind);
        if (observed_bind !== expected_bind) begin
            h.harness_error_count++;
            $error("[VV33:HBIND] result mismatch");
        end
        if ((defer_count != 1) || (read_count != 1)
         || (write_count != 1) || (conflict_count != 0)) begin
            h.harness_error_count++;
            $error("[VV33:HBIND] lifecycle defer=%0d read=%0d write=%0d conflict=%0d",
                   defer_count, read_count, write_count, conflict_count);
        end

        $display("[VV33:HBIND_METRIC] K=%064h pmul_wall=%0d wait=%0d service=%0d defer=%0d read=%0d write=%0d conflicts=%0d",
                 h.scalar_inputs[0], h.pmul_wall_cycles,
                 bind_timing.accept_cycle - bind_timing.request_cycle,
                 bind_timing.response_cycle - bind_timing.accept_cycle,
                 defer_count, read_count, write_count, conflict_count);
        if (h.total_errors() == 0)
            $display("[VV33:square_hbind_contract] PASS");
        else
            $fatal(1, "[VV33:square_hbind_contract] FAIL errors=%0d",
                   h.total_errors());
        $finish;
    end
endmodule
