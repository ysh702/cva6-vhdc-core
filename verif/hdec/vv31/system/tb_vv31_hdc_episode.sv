module tb_vv31_hdc_episode;
    hdec_vv31_system_harness h();

    initial begin
        h.load_vectors();
        h.reset_dut();
        h.validate_vector_contract();

        for (int episode = 0; episode < h.episode_count; episode++)
            h.run_episode_index(episode);

        h.print_resource_metrics("hdc_episode");
        $display(
            "[VV31:HDC_SUMMARY] requests=%0d accepts=%0d responses=%0d compute_prefix=%0d complete_episodes=%0d max_accept_wait=%0d",
            h.bus.total_request_count,
            h.bus.total_accept_count,
            h.bus.total_response_count,
            h.bus.hdc_compute_count,
            h.bus.complete_episode_count,
            h.bus.maximum_accept_wait
        );
        if (h.total_errors() == 0)
            $display("[VV31:hdc_episode] PASS");
        else
            $fatal(
                1,
                "[VV31:hdc_episode] FAIL errors=%0d",
                h.total_errors()
            );
        $finish;
    end
endmodule
