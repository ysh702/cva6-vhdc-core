module tb_vv31_vrf_roundtrip;
    import hdec_pkg::*;
    import hdec_vv31_ref_pkg::*;
    import hdec_vv31_driver_pkg::*;

    logic clk_i;
    logic rst_ni;
    logic [255:0] expected;
    logic [255:0] observed;
    logic [1023:0] query_mem [0:1];
    logic [1023:0] prototype_mem [0:1];
    logic [1023:0] hv_observed;
    logic [63:0] hsim_result;
    logic [10:0] hsim_expected;

    hdec_vv31_bfm_if bus(clk_i);
    hdec_top dut (
        .clk_i,
        .rst_ni,
        .valid_i(bus.valid_i),
        .ready_o(bus.ready_o),
        .operator_i(bus.operator_i),
        .operand_a_i(bus.operand_a_i),
        .operand_b_i(bus.operand_b_i),
        .valid_o(bus.valid_o),
        .result_o(bus.result_o)
    );

    initial clk_i = 1'b0;
    always #2.5 clk_i = ~clk_i;

    initial begin
        rst_ni = 1'b0;
        repeat (8) @(posedge clk_i);
        rst_ni = 1'b1;
        repeat (4) @(posedge clk_i);

        expected = {
            64'h0123_4567_89ab_cdef,
            64'hfedc_ba98_7654_3210,
            64'h55aa_55aa_aa55_aa55,
            64'h0f0f_f0f0_f00f_0ff0
        };
        bus.write_row(6'd8, expected);
        bus.read_row(6'd8, observed);
        if (observed !== expected)
            $fatal(
                1,
                "[VV31:vrf_roundtrip] FAIL got=%064h expected=%064h",
                observed,
                expected
            );
        if (bus.error_count != 0)
            $fatal(
                1,
                "[VV31:vrf_roundtrip] FAIL bfm_errors=%0d",
                bus.error_count
            );

        $readmemh("hdc_query_vectors.mem", query_mem, 0, 1);
        $readmemh("hdc_prototypes_expected.mem", prototype_mem, 0, 1);
        bus.write_hv(4'd2, query_mem[0]);
        bus.write_hv(4'd3, prototype_mem[0]);
        bus.read_hv(4'd2, hv_observed);
        if (hv_observed !== query_mem[0])
            $fatal(
                1,
                "[VV31:vrf_roundtrip] query HV readback failed got=%0256h expected=%0256h",
                hv_observed,
                query_mem[0]
            );
        bus.read_hv(4'd3, hv_observed);
        if (hv_observed !== prototype_mem[0])
            $fatal(1, "[VV31:vrf_roundtrip] prototype HV readback failed");
        bus.issue(
            HDEC_HSIM,
            vv31_hsim_operand(4'd2, 4'd3),
            hsim_result
        );
        hsim_expected = vv31_hdc_overlap(query_mem[0], prototype_mem[0]);
        if (hsim_result !== {53'd0, hsim_expected})
            $fatal(
                1,
                "[VV31:vrf_roundtrip] random HSIM failed got=%016h expected=%016h",
                hsim_result,
                {53'd0, hsim_expected}
            );
        $display("[VV31:vrf_roundtrip] PASS");
        $finish;
    end
endmodule
