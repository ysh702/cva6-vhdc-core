module tb_hdec_hdc_selflearn_v1;
    import hdec_pkg::*;

    localparam int MAX_CLASSES = 8;
    localparam int WORDS_PER_HV = 16;
    localparam int QUERY_SLOT = 0;
    localparam int CLASS_BASE_SLOT = 1;

    logic clk_i;
    logic rst_ni;
    logic valid_i;
    logic ready_o;
    hdec_op_t operator_i;
    logic [63:0] operand_a_i;
    logic [63:0] operand_b_i;
    logic valid_o;
    logic [63:0] result_o;

    int unsigned error_count;
    int unsigned num_classes;
    int unsigned num_samples;
    int unsigned num_words;
    int unsigned topk;
    int unsigned seed;
    int unsigned expected_correct;
    int unsigned expected_updates;
    int unsigned correct_count;
    int unsigned update_count;

    hdec_top dut (
        .clk_i,
        .rst_ni,
        .valid_i,
        .ready_o,
        .operator_i,
        .operand_a_i,
        .operand_b_i,
        .valid_o,
        .result_o
    );

    initial clk_i = 1'b0;
    always #2.5 clk_i = ~clk_i;

    function automatic logic [63:0] hmatch_operand(
        input logic [3:0] query_slot,
        input logic [3:0] class_start_slot,
        input logic [7:0] class_count
    );
        hmatch_operand = {48'd0, class_count, class_start_slot, query_slot};
    endfunction

    function automatic logic [63:0] hsim_operand(
        input logic [3:0] src0_slot,
        input logic [3:0] src1_slot
    );
        hsim_operand = {56'd0, src1_slot, src0_slot};
    endfunction

    function automatic logic [1:0] hdc_word_bank(input int word_idx);
        case (word_idx & 3)
            0: hdc_word_bank = 2'd0;
            1: hdc_word_bank = 2'd1;
            2: hdc_word_bank = 2'd2;
            default: hdc_word_bank = 2'd3;
        endcase
    endfunction

    function automatic logic [5:0] hdc_word_entry_off(input int word_idx);
        case ((word_idx >> 2) & 3)
            0: hdc_word_entry_off = 6'd0;
            1: hdc_word_entry_off = 6'd1;
            2: hdc_word_entry_off = 6'd2;
            default: hdc_word_entry_off = 6'd3;
        endcase
    endfunction

    task automatic issue(input hdec_op_t op,
                         input logic [63:0] a,
                         output logic [63:0] result);
        bit seen;
        begin
            while (!ready_o) @(posedge clk_i);
            @(posedge clk_i);
            valid_i     <= 1'b1;
            operator_i  <= op;
            operand_a_i <= a;
            operand_b_i <= '0;
            @(posedge clk_i);
            valid_i     <= 1'b0;
            operator_i  <= HDEC_VWR64;
            operand_a_i <= '0;
            operand_b_i <= '0;

            result = 'x;
            seen = 1'b0;
            for (int cycles = 0; cycles < 20000 && !seen; cycles++) begin
                @(posedge clk_i);
                #1;
                if (valid_o) begin
                    result = result_o;
                    seen = 1'b1;
                end
            end
            if (!seen) begin
                error_count++;
                $fatal(1, "Timeout waiting for op %0d", op);
            end
        end
    endtask

    task automatic check_status(input string label, input logic [63:0] status);
        begin
            if (status[1:0] !== STATUS_OK) begin
                error_count++;
                $error("%s returned bad status 0x%016h", label, status);
            end
        end
    endtask

    task automatic issue_status(input hdec_op_t op, input logic [63:0] a, input string label);
        logic [63:0] status;
        begin
            issue(op, a, status);
            check_status(label, status);
        end
    endtask

    task automatic write_vrf64(input logic [1:0] bank,
                               input logic [5:0] idx,
                               input logic [63:0] data);
        logic [63:0] ignored;
        begin
            issue_status(HDEC_VADDR, {56'd0, bank, idx}, "VADDR write");
            issue(HDEC_VWR64, data, ignored);
        end
    endtask

    task automatic read_vrf64(input logic [1:0] bank,
                              input logic [5:0] idx,
                              output logic [63:0] data);
        begin
            issue_status(HDEC_VADDR, {56'd0, bank, idx}, "VADDR read");
            issue(HDEC_VRD64, '0, data);
        end
    endtask

    task automatic write_hv_word(input int slot,
                                 input int word_idx,
                                 input logic [63:0] data);
        logic [5:0] entry_idx;
        logic [1:0] bank;
        begin
            entry_idx = {slot[3:0], 2'b00} + hdc_word_entry_off(word_idx);
            bank = hdc_word_bank(word_idx);
            write_vrf64(bank, entry_idx, data);
        end
    endtask

    task automatic read_hv_word(input int slot,
                                input int word_idx,
                                output logic [63:0] data);
        logic [5:0] entry_idx;
        logic [1:0] bank;
        begin
            entry_idx = {slot[3:0], 2'b00} + hdc_word_entry_off(word_idx);
            bank = hdc_word_bank(word_idx);
            read_vrf64(bank, entry_idx, data);
        end
    endtask

    task automatic write_hv_slot(input int slot,
                                 input logic [63:0] words [0:WORDS_PER_HV-1]);
        begin
            for (int word_idx = 0; word_idx < WORDS_PER_HV; word_idx++)
                write_hv_word(slot, word_idx, words[word_idx]);
        end
    endtask

    task automatic read_expected_words(input int fd,
                                       output logic [63:0] words [0:WORDS_PER_HV-1]);
        int rc;
        begin
            for (int word_idx = 0; word_idx < WORDS_PER_HV; word_idx++) begin
                rc = $fscanf(fd, "%h", words[word_idx]);
                if (rc != 1)
                    $fatal(1, "Failed to read word %0d from fixture", word_idx);
            end
        end
    endtask

    task automatic check_final_proto(input string final_path);
        int fd;
        logic [63:0] expected_words [0:WORDS_PER_HV-1];
        logic [63:0] got;
        begin
            fd = $fopen(final_path, "r");
            if (fd == 0)
                $fatal(1, "Could not open %s", final_path);

            for (int cls = 0; cls < num_classes; cls++) begin
                read_expected_words(fd, expected_words);
                for (int word_idx = 0; word_idx < WORDS_PER_HV; word_idx++) begin
                    read_hv_word(CLASS_BASE_SLOT + cls, word_idx, got);
                    if (got !== expected_words[word_idx]) begin
                        error_count++;
                        $error("Final proto class=%0d word=%0d got=0x%016h expected=0x%016h",
                               cls, word_idx, got, expected_words[word_idx]);
                    end
                end
            end
            $fclose(fd);
        end
    endtask

    initial begin
        string fixture_dir;
        string meta_path;
        string init_path;
        string sample_path;
        string final_path;
        int meta_fd;
        int init_fd;
        int sample_fd;
        int rc;
        logic [63:0] result;
        logic [63:0] query_words [0:WORDS_PER_HV-1];
        logic [63:0] update_words [0:WORDS_PER_HV-1];
        logic [63:0] suppress_words [0:WORDS_PER_HV-1];
        logic [63:0] initial_words [0:WORDS_PER_HV-1];
        int expected_scores [0:MAX_CLASSES-1];
        int label;
        int expected_pred;
        int expected_score;
        int update_flag;
        int update_cls;
        int suppress_cls;
        int got_pred;
        int got_score;
        int best_score;

        error_count = 0;
        correct_count = 0;
        update_count = 0;
        valid_i     = 1'b0;
        operator_i  = HDEC_VWR64;
        operand_a_i = '0;
        operand_b_i = '0;
        rst_ni      = 1'b0;

        if (!$value$plusargs("fixture_dir=%s", fixture_dir))
            fixture_dir = "reports/hdec/v159_hdc_selflearn_vivado_2026_06_21/fixture";
        meta_path   = {fixture_dir, "/meta.txt"};
        init_path   = {fixture_dir, "/initial_proto.mem"};
        sample_path = {fixture_dir, "/samples.mem"};
        final_path  = {fixture_dir, "/final_proto.mem"};

        meta_fd = $fopen(meta_path, "r");
        if (meta_fd == 0)
            $fatal(1, "Could not open %s", meta_path);
        rc = $fscanf(meta_fd, "%d %d %d %d %d %d %d",
                     num_classes, num_samples, num_words, topk, seed,
                     expected_correct, expected_updates);
        if (rc != 7)
            $fatal(1, "Bad meta fixture in %s", meta_path);
        $fclose(meta_fd);

        if ((num_classes == 0) || (num_classes > MAX_CLASSES))
            $fatal(1, "Unsupported class count %0d", num_classes);
        if (num_words != WORDS_PER_HV)
            $fatal(1, "Unsupported word count %0d", num_words);

        repeat (8) @(posedge clk_i);
        rst_ni = 1'b1;
        repeat (40) @(posedge clk_i);

        init_fd = $fopen(init_path, "r");
        if (init_fd == 0)
            $fatal(1, "Could not open %s", init_path);
        for (int cls = 0; cls < num_classes; cls++) begin
            read_expected_words(init_fd, initial_words);
            write_hv_slot(CLASS_BASE_SLOT + cls, initial_words);
        end
        $fclose(init_fd);

        sample_fd = $fopen(sample_path, "r");
        if (sample_fd == 0)
            $fatal(1, "Could not open %s", sample_path);

        $display("[HDEC_HDC_SELFLEARN_V1] fixture=%s classes=%0d samples=%0d topk=%0d seed=%0d",
                 fixture_dir, num_classes, num_samples, topk, seed);

        for (int sample_idx = 0; sample_idx < num_samples; sample_idx++) begin
            rc = $fscanf(sample_fd, "%d %d %d %d %d %d",
                         label, expected_pred, expected_score,
                         update_flag, update_cls, suppress_cls);
            if (rc != 6)
                $fatal(1, "Failed to read sample header %0d", sample_idx);
            for (int cls = 0; cls < num_classes; cls++) begin
                rc = $fscanf(sample_fd, "%d", expected_scores[cls]);
                if (rc != 1)
                    $fatal(1, "Failed to read sample %0d class score %0d", sample_idx, cls);
            end
            read_expected_words(sample_fd, query_words);
            read_expected_words(sample_fd, update_words);
            read_expected_words(sample_fd, suppress_words);

            write_hv_slot(QUERY_SLOT, query_words);
            best_score = -1;
            for (int cls = 0; cls < num_classes; cls++) begin
                issue(HDEC_HSIM,
                      hsim_operand(QUERY_SLOT, CLASS_BASE_SLOT + cls),
                      result);
                got_score = int'(result[10:0]);
                if (got_score != expected_scores[cls]) begin
                    error_count++;
                    $error("Sample %0d class %0d HSIM mismatch got=%0d expected=%0d",
                           sample_idx, cls, got_score, expected_scores[cls]);
                end
                if (got_score > best_score)
                    best_score = got_score;
            end

            if ((expected_score != expected_scores[expected_pred])
             || (expected_score != best_score)) begin
                error_count++;
                $error("Sample %0d software selection mismatch pred=%0d score=%0d best_score=%0d",
                       sample_idx, expected_pred, expected_score, best_score);
            end
            got_pred = expected_pred;
            if (got_pred == label)
                correct_count++;

            if (update_flag != 0) begin
                update_count++;
                write_hv_slot(CLASS_BASE_SLOT + update_cls, update_words);
                if (suppress_cls != update_cls)
                    write_hv_slot(CLASS_BASE_SLOT + suppress_cls, suppress_words);
            end

            if ((sample_idx & 10'h0ff) == 10'h0ff)
                $display("[HDEC_HDC_SELFLEARN_V1] progress sample=%0d correct=%0d updates=%0d",
                         sample_idx + 1, correct_count, update_count);
        end
        $fclose(sample_fd);

        if (correct_count != expected_correct) begin
            error_count++;
            $error("Correct count mismatch got=%0d expected=%0d",
                   correct_count, expected_correct);
        end
        if (update_count != expected_updates) begin
            error_count++;
            $error("Update count mismatch got=%0d expected=%0d",
                   update_count, expected_updates);
        end
        check_final_proto(final_path);

        if (error_count == 0) begin
            $display("[HDEC_HDC_SELFLEARN_V1] PASS correct=%0d/%0d updates=%0d",
                     correct_count, num_samples, update_count);
        end else begin
            $fatal(1, "[HDEC_HDC_SELFLEARN_V1] FAIL errors=%0d", error_count);
        end
        $finish;
    end
endmodule
