interface hdec_vv31_bfm_if(input logic clk_i);
    import hdec_pkg::*;
    import hdec_vv31_ref_pkg::*;
    import hdec_vv31_driver_pkg::*;
    import hdec_vv31_vectors_pkg::*;

    localparam int VV31_REQUEST_TIMEOUT = 2_000_000;

    logic        valid_i;
    logic        ready_o;
    hdec_op_t    operator_i;
    logic [63:0] operand_a_i;
    logic [63:0] operand_b_i;
    logic        valid_o;
    logic [63:0] result_o;

    longint unsigned cycle_count;
    longint unsigned total_request_count;
    longint unsigned total_accept_count;
    longint unsigned total_response_count;
    longint unsigned hdc_compute_count;
    longint unsigned complete_episode_count;
    longint unsigned maximum_accept_wait;
    int unsigned     error_count;

    initial begin
        cycle_count          = 0;
        total_request_count  = 0;
        total_accept_count   = 0;
        total_response_count = 0;
        hdc_compute_count    = 0;
        complete_episode_count = 0;
        maximum_accept_wait  = 0;
        error_count          = 0;
        valid_i              = 1'b0;
        operator_i           = HDEC_VWR64;
        operand_a_i          = '0;
        operand_b_i          = '0;
    end

    always @(posedge clk_i)
        cycle_count <= cycle_count + 1;

    task automatic reset_metrics;
        begin
            total_request_count    = 0;
            total_accept_count     = 0;
            total_response_count   = 0;
            hdc_compute_count      = 0;
            complete_episode_count = 0;
            maximum_accept_wait    = 0;
            error_count            = 0;
        end
    endtask

    task automatic issue_hold(
        input  hdec_op_t      operation,
        input  logic [63:0]   operand_a,
        input  logic [63:0]   operand_b,
        output logic [63:0]   result,
        output vv31_timing_t  timing
    );
        bit accepted;
        bit responded;
        int unsigned wait_cycles;
        begin
            if (valid_i)
                $fatal(1, "[VV31:BFM] overlapping request attempts");

            timing = '0;
            result = 'x;
            accepted = 1'b0;
            responded = 1'b0;
            wait_cycles = 0;

            timing.request_cycle = cycle_count;
            total_request_count++;
            valid_i     = 1'b1;
            operator_i  = operation;
            operand_a_i = operand_a;
            operand_b_i = operand_b;

            // The request is presented immediately.  It remains stable until
            // ready_o is sampled high at a rising clock edge.
            while (!accepted) begin
                @(posedge clk_i);
                wait_cycles++;
                if (ready_o) begin
                    accepted = 1'b1;
                    timing.accept_cycle = cycle_count;
                    total_accept_count++;
                end
                if (wait_cycles >= VV31_REQUEST_TIMEOUT)
                    $fatal(1,
                           "[VV31:BFM] request timeout op=%0d request_cycle=%0d",
                           operation, timing.request_cycle);
            end

            valid_i     <= 1'b0;
            operator_i  <= HDEC_VWR64;
            operand_a_i <= '0;
            operand_b_i <= '0;

            wait_cycles = 0;
            while (!responded) begin
                @(posedge clk_i);
                #1;
                wait_cycles++;
                if (valid_o) begin
                    responded = 1'b1;
                    timing.response_cycle = cycle_count;
                    result = result_o;
                    total_response_count++;
                end
                if (wait_cycles >= VV31_REQUEST_TIMEOUT)
                    $fatal(1,
                           "[VV31:BFM] response timeout op=%0d accept_cycle=%0d",
                           operation, timing.accept_cycle);
            end

            if ((timing.accept_cycle - timing.request_cycle)
                > maximum_accept_wait)
                maximum_accept_wait =
                    timing.accept_cycle - timing.request_cycle;
            if ($isunknown(result)) begin
                error_count++;
                $error("[VV31:BFM] unknown response op=%0d", operation);
            end
        end
    endtask

    task automatic issue(
        input  hdec_op_t    operation,
        input  logic [63:0] operand,
        output logic [63:0] result
    );
        vv31_timing_t timing;
        begin
            issue_hold(operation, operand, '0, result, timing);
        end
    endtask

    task automatic issue_hdc(
        input  hdec_op_t      operation,
        input  logic [63:0]   operand,
        output logic [63:0]   result,
        output vv31_timing_t  timing
    );
        begin
            issue_hold(operation, operand, '0, result, timing);
            hdc_compute_count++;
            $display(
                "[VV31:HDC_TIMING] prefix=%0d op=%0d request=%0d accept=%0d response=%0d wait=%0d service=%0d",
                hdc_compute_count,
                operation,
                timing.request_cycle,
                timing.accept_cycle,
                timing.response_cycle,
                timing.accept_cycle - timing.request_cycle,
                timing.response_cycle - timing.accept_cycle
            );
        end
    endtask

    task automatic expect_status_ok(
        input string       label,
        input logic [63:0] status
    );
        begin
            if (status[1:0] !== STATUS_OK) begin
                error_count++;
                $error("[VV31:HDC] %s bad status=%016h", label, status);
            end
        end
    endtask

    task automatic expect_equal64(
        input string       label,
        input logic [63:0] got,
        input logic [63:0] expected
    );
        begin
            if (got !== expected) begin
                error_count++;
                $error(
                    "[VV31:HDC] %s mismatch got=%016h expected=%016h",
                    label, got, expected
                );
            end
        end
    endtask

    task automatic expect_equal1024(
        input string         label,
        input logic [1023:0] got,
        input logic [1023:0] expected
    );
        begin
            if (got !== expected) begin
                error_count++;
                $error(
                    "[VV31:HDC] %s mismatch got=%0256h expected=%0256h",
                    label, got, expected
                );
            end
        end
    endtask

    task automatic write_vrf64(
        input logic [1:0]  bank,
        input logic [5:0]  row,
        input logic [63:0] data
    );
        logic [63:0] ignored;
        begin
            issue(HDEC_VADDR, vv31_vaddr_operand(bank, row), ignored);
            issue(HDEC_VWR64, data, ignored);
        end
    endtask

    task automatic read_vrf64(
        input  logic [1:0]  bank,
        input  logic [5:0]  row,
        output logic [63:0] data
    );
        logic [63:0] ignored;
        begin
            issue(HDEC_VADDR, vv31_vaddr_operand(bank, row), ignored);
            issue(HDEC_VRD64, '0, data);
        end
    endtask

    task automatic write_row(
        input logic [5:0]   row,
        input logic [255:0] value
    );
        begin
            for (int bank = 0; bank < 4; bank++)
                write_vrf64(bank[1:0], row, value[bank * 64 +: 64]);
        end
    endtask

    task automatic read_row(
        input  logic [5:0]   row,
        output logic [255:0] value
    );
        begin
            for (int bank = 0; bank < 4; bank++)
                read_vrf64(bank[1:0], row, value[bank * 64 +: 64]);
        end
    endtask

    function automatic logic [1:0] hv_word_bank(input int word_index);
        case (word_index & 3)
            0: hv_word_bank = 2'd0;
            1: hv_word_bank = 2'd1;
            2: hv_word_bank = 2'd2;
            default: hv_word_bank = 2'd3;
        endcase
    endfunction

    function automatic logic [5:0] hv_word_entry_offset(
        input int word_index
    );
        case ((word_index >> 2) & 3)
            0: hv_word_entry_offset = 6'd0;
            1: hv_word_entry_offset = 6'd1;
            2: hv_word_entry_offset = 6'd2;
            default: hv_word_entry_offset = 6'd3;
        endcase
    endfunction

    function automatic logic [5:0] hv_word_row(
        input logic [3:0] slot,
        input int         word_index
    );
        hv_word_row = {slot, 2'b00} + hv_word_entry_offset(word_index);
    endfunction

    task automatic write_hv(
        input logic [3:0]    slot,
        input logic [1023:0] value
    );
        int word_index;
        begin
            for (int row_offset = 0; row_offset < 4; row_offset++) begin
                for (int bank = 0; bank < 4; bank++) begin
                    word_index = row_offset * 4 + bank;
                    write_vrf64(
                        bank[1:0],
                        {slot, 2'b00} + row_offset,
                        value[word_index * 64 +: 64]
                    );
                end
            end
        end
    endtask

    task automatic read_hv(
        input  logic [3:0]    slot,
        output logic [1023:0] value
    );
        int word_index;
        begin
            for (int row_offset = 0; row_offset < 4; row_offset++) begin
                for (int bank = 0; bank < 4; bank++) begin
                    word_index = row_offset * 4 + bank;
                    read_vrf64(
                        bank[1:0],
                        {slot, 2'b00} + row_offset,
                        value[word_index * 64 +: 64]
                    );
                end
            end
        end
    endtask

    task automatic run_hdc_episode(
        input logic [1023:0] train0,
        input logic [1023:0] train1,
        input logic [1023:0] train2,
        input logic [1023:0] train3,
        input logic [1023:0] role0,
        input logic [1023:0] role1,
        input logic [1023:0] role2,
        input logic [1023:0] role3,
        input logic [9:0]    rotation0,
        input logic [9:0]    rotation1,
        input logic [9:0]    rotation2,
        input logic [9:0]    rotation3,
        input logic [1023:0] query,
        output logic [1023:0] prototype,
        output logic [10:0]   similarity,
        output logic [63:0]   match_result,
        output logic [63:0]   episode_start_cycle,
        output logic [63:0]   episode_end_cycle
    );
        logic [1023:0] train_value;
        logic [1023:0] role_value;
        logic [1023:0] permuted_role;
        logic [1023:0] expected_bound;
        logic [1023:0] got_hv;
        logic [1023:0] bound0;
        logic [1023:0] bound1;
        logic [1023:0] bound2;
        logic [1023:0] bound3;
        logic [9:0] rotation;
        logic [63:0] result;
        vv31_timing_t timing;
        begin
            episode_start_cycle = cycle_count;
            bound0 = '0;
            bound1 = '0;
            bound2 = '0;
            bound3 = '0;

            issue_hdc(HDEC_HCNTCLR, 64'd0, result, timing);
            expect_status_ok("HCNTCLR acc0", result);

            for (int sample_index = 0; sample_index < 4; sample_index++) begin
                case (sample_index)
                    0: begin
                        train_value = train0;
                        role_value = role0;
                        rotation = rotation0;
                    end
                    1: begin
                        train_value = train1;
                        role_value = role1;
                        rotation = rotation1;
                    end
                    2: begin
                        train_value = train2;
                        role_value = role2;
                        rotation = rotation2;
                    end
                    default: begin
                        train_value = train3;
                        role_value = role3;
                        rotation = rotation3;
                    end
                endcase

                if (rotation[1:0] != 2'b00) begin
                    error_count++;
                    $error(
                        "[VV31:HDC] non-aligned rotation sample=%0d rotation=%0d",
                        sample_index, rotation
                    );
                end

                // Only slots 2 and 3 are used.  The role is loaded to HV2,
                // permuted into HV3, then HV2 is replaced by the sample.
                write_hv(VV31_HDC_HV2_SLOT, role_value);
                issue_hdc(
                    HDEC_HPERM,
                    vv31_hperm_operand(
                        VV31_HDC_HV3_SLOT,
                        VV31_HDC_HV2_SLOT,
                        rotation
                    ),
                    result,
                    timing
                );
                expect_status_ok("HPERM role", result);
                permuted_role = vv31_rotr1024(role_value, rotation);
                read_hv(VV31_HDC_HV3_SLOT, got_hv);
                expect_equal1024("HPERM role", got_hv, permuted_role);

                write_hv(VV31_HDC_HV2_SLOT, train_value);
                issue_hdc(
                    HDEC_HBIND,
                    vv31_hbind_operand(
                        VV31_HDC_HV2_SLOT,
                        VV31_HDC_HV2_SLOT,
                        VV31_HDC_HV3_SLOT
                    ),
                    result,
                    timing
                );
                expect_status_ok("HBIND encoded sample", result);
                expected_bound = vv31_hdc_bind(train_value, permuted_role);
                read_hv(VV31_HDC_HV2_SLOT, got_hv);
                expect_equal1024("HBIND encoded sample", got_hv, expected_bound);

                case (sample_index)
                    0: bound0 = expected_bound;
                    1: bound1 = expected_bound;
                    2: bound2 = expected_bound;
                    default: bound3 = expected_bound;
                endcase

                issue_hdc(
                    HDEC_HCNTADD,
                    {60'd0, VV31_HDC_HV2_SLOT},
                    result,
                    timing
                );
                expect_status_ok("HCNTADD encoded sample", result);
            end

            prototype = vv31_hdc_or4(bound0, bound1, bound2, bound3);
            issue_hdc(
                HDEC_HCNTCLIP,
                vv31_hcntclip_operand(
                    VV31_HDC_HV3_SLOT[2:0],
                    1'b0,
                    4'd1
                ),
                result,
                timing
            );
            expect_status_ok("HCNTCLIP OR prototype", result);
            read_hv(VV31_HDC_HV3_SLOT, got_hv);
            expect_equal1024("HCNTCLIP OR prototype", got_hv, prototype);

            write_hv(VV31_HDC_HV2_SLOT, query);
            issue_hdc(
                HDEC_HSIM,
                vv31_hsim_operand(
                    VV31_HDC_HV2_SLOT,
                    VV31_HDC_HV3_SLOT
                ),
                result,
                timing
            );
            similarity = vv31_hdc_overlap(query, prototype);
            expect_equal64("HSIM query/prototype", result, {53'd0, similarity});

            issue_hdc(
                HDEC_HMATCH,
                vv31_hmatch_operand(
                    VV31_HDC_HV2_SLOT,
                    VV31_HDC_HV3_SLOT,
                    8'd1
                ),
                result,
                timing
            );
            match_result = vv31_hmatch_result(3'd0, similarity);
            expect_equal64("HMATCH one prototype", result, match_result);

            complete_episode_count++;
            episode_end_cycle = cycle_count;
            $display(
                "[VV31:HDC_EPISODE] episode=%0d start=%0d end=%0d cycles=%0d compute_ops=16",
                complete_episode_count,
                episode_start_cycle,
                episode_end_cycle,
                episode_end_cycle - episode_start_cycle
            );
        end
    endtask

endinterface
