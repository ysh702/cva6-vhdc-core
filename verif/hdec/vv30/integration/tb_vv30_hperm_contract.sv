module tb_vv30_hperm_contract;
    import hdec_pkg::*;

    localparam int HV_SLOTS = 16;
    localparam int HV_WORDS = 16;

    logic clk_i;
    logic rst_ni;
    logic valid_i;
    logic ready_o;
    hdec_op_t operator_i;
    logic [63:0] operand_a_i;
    logic [63:0] operand_b_i;
    logic valid_o;
    logic [63:0] result_o;

    logic [63:0] model [0:HV_SLOTS-1][0:HV_WORDS-1];
    int legal_cycle_reference;

    hdec_top #(.ECC_DEBUG_FIELD_OPS(1'b1)) dut (
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

    function automatic logic [63:0] hperm_operand(
        input logic [3:0] dst_slot,
        input logic [3:0] src_slot,
        input logic [9:0] rot_amt
    );
        begin
            hperm_operand = {46'd0, rot_amt, src_slot, dst_slot};
        end
    endfunction

    function automatic logic [63:0] pattern_word(
        input int slot,
        input int word_idx
    );
        logic [63:0] mixed;
        begin
            mixed = 64'h9e37_79b9_7f4a_7c15
                  ^ (64'(slot + 1) * 64'h1000_0001_0000_01b3)
                  ^ (64'(word_idx + 3) * 64'h0001_0000_01b3_1001);
            pattern_word = {mixed[31:0] ^ mixed[63:32], mixed[63:32]};
        end
    endfunction

    function automatic logic [63:0] peek_vrf(
        input int bank,
        input int row
    );
        begin
            case (bank)
                0: peek_vrf = dut.i_vrf.gen_bank[0].vrf_mem[row];
                1: peek_vrf = dut.i_vrf.gen_bank[1].vrf_mem[row];
                2: peek_vrf = dut.i_vrf.gen_bank[2].vrf_mem[row];
                default: peek_vrf = dut.i_vrf.gen_bank[3].vrf_mem[row];
            endcase
        end
    endfunction

    task automatic poke_vrf(
        input int bank,
        input int row,
        input logic [63:0] value
    );
        begin
            case (bank)
                0: dut.i_vrf.gen_bank[0].vrf_mem[row] = value;
                1: dut.i_vrf.gen_bank[1].vrf_mem[row] = value;
                2: dut.i_vrf.gen_bank[2].vrf_mem[row] = value;
                default: dut.i_vrf.gen_bank[3].vrf_mem[row] = value;
            endcase
        end
    endtask

    task automatic initialize_vrf;
        int slot;
        int word_idx;
        int bank;
        int row;
        begin
            @(negedge clk_i);
            for (slot = 0; slot < HV_SLOTS; slot++) begin
                for (word_idx = 0; word_idx < HV_WORDS; word_idx++) begin
                    bank = word_idx & 3;
                    row = (slot << 2) + (word_idx >> 2);
                    model[slot][word_idx] = pattern_word(slot, word_idx);
                    poke_vrf(bank, row, model[slot][word_idx]);
                end
            end
            @(posedge clk_i);
            #1;
        end
    endtask

    task automatic issue_hperm(
        input logic [3:0] dst_slot,
        input logic [3:0] src_slot,
        input logic [9:0] rot_amt,
        input logic       require_no_write,
        output logic [63:0] status,
        output int          cycles
    );
        begin
            while (!ready_o)
                @(posedge clk_i);
            @(negedge clk_i);
            operator_i  = HDEC_HPERM;
            operand_a_i = hperm_operand(dst_slot, src_slot, rot_amt);
            operand_b_i = '0;
            valid_i     = 1'b1;
            @(posedge clk_i);
            #1;
            @(negedge clk_i);
            valid_i     = 1'b0;
            operator_i  = HDEC_VWR64;
            operand_a_i = '0;
            operand_b_i = '0;

            cycles = 0;
            status = 'x;
            while (cycles < 1000) begin
                @(posedge clk_i);
                #1;
                cycles++;
                if (require_no_write && (dut.vrf_we !== 4'b0000))
                    $fatal(1,
                           "Illegal HPERM wrote VRF: rot=%0d src=%0d dst=%0d we=%b wa=%0d",
                           rot_amt, src_slot, dst_slot, dut.vrf_we, dut.vrf_wa);
                if (valid_o) begin
                    status = result_o;
                    return;
                end
            end
            $fatal(1, "Timeout: rot=%0d src=%0d dst=%0d", rot_amt, src_slot, dst_slot);
        end
    endtask

    task automatic compute_rotation(
        input int src_slot,
        input int rot_amt,
        output logic [63:0] rotated [0:HV_WORDS-1]
    );
        int word_off;
        int bit_off;
        int word_idx;
        logic [63:0] lo_word;
        logic [63:0] hi_word;
        begin
            word_off = rot_amt >> 6;
            bit_off = rot_amt & 63;
            for (word_idx = 0; word_idx < HV_WORDS; word_idx++) begin
                lo_word = model[src_slot][(word_idx + word_off) & 15];
                hi_word = model[src_slot][(word_idx + word_off + 1) & 15];
                if (bit_off == 0)
                    rotated[word_idx] = lo_word;
                else
                    rotated[word_idx] = (lo_word >> bit_off)
                                      | (hi_word << (64 - bit_off));
            end
        end
    endtask

    task automatic check_model(input string check_label);
        int slot;
        int word_idx;
        int bank;
        int row;
        logic [63:0] got;
        begin
            for (slot = 0; slot < HV_SLOTS; slot++) begin
                for (word_idx = 0; word_idx < HV_WORDS; word_idx++) begin
                    bank = word_idx & 3;
                    row = (slot << 2) + (word_idx >> 2);
                    got = peek_vrf(bank, row);
                    if (got !== model[slot][word_idx])
                        $fatal(1,
                               "%s slot=%0d word=%0d got=%016h expected=%016h",
                               check_label, slot, word_idx, got, model[slot][word_idx]);
                end
            end
        end
    endtask

    task automatic run_case(
        input int dst_slot,
        input int src_slot,
        input int rot_amt
    );
        logic [63:0] status;
        logic [63:0] rotated [0:HV_WORDS-1];
        int cycles;
        int word_idx;
        bit legal;
        begin
            legal = ((rot_amt & 3) == 0) && (dst_slot != src_slot);
            if (legal)
                compute_rotation(src_slot, rot_amt, rotated);

            issue_hperm(4'(dst_slot), 4'(src_slot), 10'(rot_amt),
                        !legal, status, cycles);

            if (legal) begin
                if (status[1:0] !== STATUS_OK)
                    $fatal(1,
                           "Legal HPERM returned %0d: rot=%0d src=%0d dst=%0d",
                           status[1:0], rot_amt, src_slot, dst_slot);
                if (legal_cycle_reference < 0)
                    legal_cycle_reference = cycles;
                else if (cycles != legal_cycle_reference)
                    $fatal(1,
                           "Legal HPERM cycle mismatch: rot=%0d cycles=%0d expected=%0d",
                           rot_amt, cycles, legal_cycle_reference);
                for (word_idx = 0; word_idx < HV_WORDS; word_idx++)
                    model[dst_slot][word_idx] = rotated[word_idx];
            end else if (status[1:0] !== STATUS_ERROR) begin
                $fatal(1,
                       "Illegal HPERM returned %0d: rot=%0d src=%0d dst=%0d",
                       status[1:0], rot_amt, src_slot, dst_slot);
            end

            check_model($sformatf("HPERM rot=%0d src=%0d dst=%0d",
                                  rot_amt, src_slot, dst_slot));
        end
    endtask

    task automatic run_baseline_probe;
        logic [63:0] status;
        logic [63:0] rotated [0:HV_WORDS-1];
        logic [63:0] before_invalid [0:HV_WORDS-1];
        int cycles;
        int word_idx;
        int failures;
        begin
            failures = 0;
            initialize_vrf();

            compute_rotation(2, 4, rotated);
            issue_hperm(4'd3, 4'd2, 10'd4, 1'b0, status, cycles);
            $display("[VV30:HPERM_BASELINE] LEGAL_CYCLES=%0d", cycles);
            for (word_idx = 0; word_idx < HV_WORDS; word_idx++) begin
                if (peek_vrf(word_idx & 3, (3 << 2) + (word_idx >> 2))
                        !== rotated[word_idx]) begin
                    failures++;
                    $display("[VV30:HPERM_BASELINE] captured HV-boundary failure at word %0d",
                             word_idx);
                    break;
                end
            end

            for (word_idx = 0; word_idx < HV_WORDS; word_idx++)
                before_invalid[word_idx] =
                    peek_vrf(word_idx & 3, (3 << 2) + (word_idx >> 2));
            issue_hperm(4'd3, 4'd2, 10'd1, 1'b0, status, cycles);
            if (status[1:0] !== STATUS_ERROR) begin
                failures++;
                $display("[VV30:HPERM_BASELINE] captured unaligned status=%0d",
                         status[1:0]);
            end
            for (word_idx = 0; word_idx < HV_WORDS; word_idx++) begin
                if (peek_vrf(word_idx & 3, (3 << 2) + (word_idx >> 2))
                        !== before_invalid[word_idx]) begin
                    failures++;
                    $display("[VV30:HPERM_BASELINE] captured illegal-write failure at word %0d",
                             word_idx);
                    break;
                end
            end

            if (failures == 0)
                $fatal(1, "[VV30:HPERM_BASELINE] probe unexpectedly found no failure");
            $fatal(1, "[VV30:HPERM_BASELINE] expected failures captured=%0d", failures);
        end
    endtask

    initial begin
        int rot_amt;
        int src_slot;
        int dst_slot;

        valid_i = 1'b0;
        operator_i = HDEC_VWR64;
        operand_a_i = '0;
        operand_b_i = '0;
        rst_ni = 1'b0;
        legal_cycle_reference = -1;
        repeat (8) @(posedge clk_i);
        rst_ni = 1'b1;
        repeat (4) @(posedge clk_i);

        if ($test$plusargs("BASELINE_PROBE"))
            run_baseline_probe();

        initialize_vrf();

        // Exhaust every 10-bit rotation encoding. Legal rotations check all
        // 1024 result bits; illegal rotations must not assert any VRF write.
        for (rot_amt = 0; rot_amt < 1024; rot_amt++)
            run_case(3, 2, rot_amt);

        // Cover the complete source/destination slot cross-product.
        for (src_slot = 0; src_slot < HV_SLOTS; src_slot++) begin
            for (dst_slot = 0; dst_slot < HV_SLOTS; dst_slot++) begin
                run_case(dst_slot, src_slot,
                         ((src_slot * HV_SLOTS + dst_slot) * 4) & 1020);
            end
        end

        // Invalid-followed-by-valid and back-to-back legal requests.
        run_case(7, 6, 1023);
        run_case(7, 6, 508);
        run_case(9, 8, 252);
        run_case(10, 8, 256);

        $display("[VV30:hperm_contract] LEGAL_CYCLES=%0d", legal_cycle_reference);
        $display("[VV30:hperm_contract] ROTATION_ENCODINGS=1024 LEGAL=256 ILLEGAL=768");
        $display("[VV30:hperm_contract] SLOT_PAIRS=256");
        $display("[VV30:hperm_contract] PASS");
        $finish;
    end
endmodule
