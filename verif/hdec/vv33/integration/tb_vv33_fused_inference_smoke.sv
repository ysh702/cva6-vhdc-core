module tb_vv33_fused_inference_smoke;
    import hdec_pkg::*;
    import hdec_vv31_ref_pkg::*;
    import hdec_vv31_driver_pkg::*;
    import hdec_vv31_check_pkg::*;
    import hdec_vv31_vectors_pkg::*;

    localparam logic [3:0] ROLE_SLOT  = 4'd2;
    localparam logic [3:0] QUERY_SLOT = 4'd3;
    localparam logic [3:0] PROTO_SLOT = 4'd4;
    localparam logic [3:0] INPUT_SLOT = 4'd7;

    hdec_vv31_system_harness h();
    defparam h.dut.VV33_FINE_INTERLEAVE = 1'b1;
    defparam h.dut.VV33_PAIRED_HMATCH = 1'b1;

    logic [1023:0] role_hv;
    logic [1023:0] input_hv;
    logic [1023:0] query_hv;
    logic [1023:0] proto0;
    logic [1023:0] proto1;
    logic [1023:0] proto2;
    logic [9:0] rotation;
    logic [63:0] descriptor;
    logic [63:0] expected_match;

    always @(posedge h.clk_i) begin
        if (h.rst_ni && h.dut.vv33_hinfer_field_accept)
            $display("[VV33:FUSED_SMOKE_TRACE] field_accept cycle=%0d step=%0d subop=%0d",
                     h.bus.cycle_count, h.dut.ecc_pmul_step_q,
                     h.dut.ecc_pmul_subop_q);
        if (h.rst_ni && h.dut.vv33_hinfer_pair_launch)
            $display("[VV33:FUSED_SMOKE_TRACE] pair_launch cycle=%0d step=%0d subop=%0d",
                     h.bus.cycle_count, h.dut.ecc_pmul_step_q,
                     h.dut.ecc_pmul_subop_q);
        if (h.rst_ni && h.dut.vv33_pair_resp_q)
            $display("[VV33:FUSED_SMOKE_TRACE] pair_response cycle=%0d",
                     h.bus.cycle_count);
        if (h.rst_ni && h.dut.vv33_hinfer_active
         && h.dut.vv33_pair_active_q
         && ((h.bus.cycle_count % 2000) == 0))
            $display("[VV33:FUSED_SMOKE_TRACE] pending cycle=%0d st=%0d phase=%0d step=%0d subop=%0d pair=%0d",
                     h.bus.cycle_count, h.dut.st_q, h.dut.ecc_job_phase_q,
                     h.dut.ecc_pmul_step_q, h.dut.ecc_pmul_subop_q,
                     h.dut.vv33_pair_active_q);
    end

    task automatic prepare_resident;
        begin
            h.bus.write_hv(ROLE_SLOT, role_hv);
            h.bus.write_hv(QUERY_SLOT, '0);
            h.bus.write_hv(PROTO_SLOT + 4'd0, proto0);
            h.bus.write_hv(PROTO_SLOT + 4'd1, proto1);
            h.bus.write_hv(PROTO_SLOT + 4'd2, proto2);
            h.bus.write_hv(INPUT_SLOT, input_hv);
        end
    endtask

    task automatic run_fused(input string label);
        logic [63:0] result;
        logic [1023:0] got_query;
        vv31_timing_t timing;
        begin
            h.bus.issue_hold(HDEC_HMATCH, descriptor, '0, result, timing);
            h.bus.expect_equal64({label, " result"}, result, expected_match);
            h.bus.read_hv(QUERY_SLOT, got_query);
            h.bus.expect_equal1024({label, " query"}, got_query, query_hv);
            $display(
                "[VV33:FUSED_SMOKE_EVENT] label=%s request=%0d accept=%0d response=%0d service=%0d",
                label, timing.request_cycle, timing.accept_cycle,
                timing.response_cycle,
                timing.response_cycle - timing.accept_cycle
            );
        end
    endtask

    initial begin
        vv31_timing_t start_timing;

        h.load_vectors();
        if (h.scalar_count != 1)
            $fatal(1, "[VV33:FUSED_SMOKE] expected one random K");

        role_hv = h.hdc_role_vectors[0];
        proto0 = h.hdc_query_vectors[0];
        rotation = {h.master_seed_mem[0][7:0], 2'b00};
        if (rotation == 10'd0)
            rotation = 10'd4;
        query_hv = proto0;
        input_hv = query_hv ^ vv31_rotr1024(role_hv, rotation);
        proto1 = ~proto0;
        proto2 = proto0 & {512{2'b01}};
        expected_match = vv31_hmatch_result(
            3'd0, vv31_hdc_overlap(query_hv, proto0)
        );

        descriptor = '0;
        descriptor[63] = 1'b1;
        descriptor[3:0] = QUERY_SLOT;
        descriptor[7:4] = ROLE_SLOT;
        descriptor[9:8] = rotation[1:0];
        descriptor[13:10] = rotation[5:2];
        descriptor[15:14] = rotation[7:6];
        descriptor[17:16] = rotation[9:8];
        descriptor[21:18] = INPUT_SLOT;
        descriptor[25:22] = PROTO_SLOT;
        descriptor[28:26] = 3'd2;

        h.reset_dut();
        h.validate_vector_contract();
        prepare_resident();
        run_fused("standalone");
        if (h.total_errors() != 0)
            $fatal(1, "[VV33:FUSED_SMOKE] standalone failed");

        h.reset_dut();
        h.validate_vector_contract();
        h.prepare_ecc_case(0);
        prepare_resident();
        h.start_background_pmul(0, start_timing);
        run_fused("background");
        h.wait_background_done_no_poll();
        h.check_background_pmul(0, 1'b1);
        h.check_ecc_guards(0);
        if (h.total_errors() != 0)
            $fatal(1, "[VV33:FUSED_SMOKE] background failed");

        $display(
            "[VV33:FUSED_SMOKE_METRIC] pmul=%0d pair_response=%0d errors=%0d",
            h.pmul_wall_cycles, h.dut.vv33_pair_resp_q, h.total_errors()
        );
        $display("[VV33:fused_inference_smoke] PASS");
        $finish;
    end
endmodule
