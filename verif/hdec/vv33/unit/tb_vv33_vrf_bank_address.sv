module tb_vv33_vrf_bank_address;
    import hdec_pkg::*;
    import hdec_resource_pkg::*;

    logic clk_i;
    logic [LANE_NUM-1:0][VRF_IDX_W-1:0] bank_ra_addr_i;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] bank_ra_data_o;
    logic [LANE_NUM-1:0] bank_we_i;
    logic [VRF_IDX_W-1:0] row_wa_addr_i;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] bank_wdata_i;
    logic vrf_ready_o;
    int unsigned errors;

    hdec_vrf_64x256 dut (.*);

    always #2.5 clk_i = ~clk_i;

    function automatic logic [63:0] pattern(input int bank, input int row);
        pattern = 64'h5a00_0000_0000_0000
                ^ (64'(bank) << 48)
                ^ 64'(row);
    endfunction

    task automatic write_row(input int row);
        @(negedge clk_i);
        row_wa_addr_i = VRF_IDX_W'(row);
        bank_we_i = '1;
        for (int bank = 0; bank < LANE_NUM; bank++)
            bank_wdata_i[bank] = pattern(bank, row);
        @(negedge clk_i);
        bank_we_i = '0;
    endtask

    task automatic check_packet(
        input int row0,
        input int row1,
        input int row2,
        input int row3
    );
        int rows [0:3];
        rows[0] = row0;
        rows[1] = row1;
        rows[2] = row2;
        rows[3] = row3;
        @(negedge clk_i);
        for (int bank = 0; bank < LANE_NUM; bank++)
            bank_ra_addr_i[bank] = VRF_IDX_W'(rows[bank]);
        @(posedge clk_i);
        @(posedge clk_i);
        #1;
        for (int bank = 0; bank < LANE_NUM; bank++) begin
            if (bank_ra_data_o[bank] !== pattern(bank, rows[bank])) begin
                errors++;
                $error("bank=%0d row=%0d got=%016h expected=%016h",
                       bank, rows[bank], bank_ra_data_o[bank],
                       pattern(bank, rows[bank]));
            end
        end
    endtask

    initial begin
        clk_i = 1'b0;
        bank_ra_addr_i = '0;
        bank_we_i = '0;
        row_wa_addr_i = '0;
        bank_wdata_i = '0;
        errors = 0;

        repeat (2) @(posedge clk_i);
        for (int row = 0; row < 64; row++)
            write_row(row);

        check_packet(0, 0, 0, 0);
        check_packet(0, 17, 42, 63);
        check_packet(63, 42, 17, 0);

        for (int iter = 0; iter < 256; iter++)
            check_packet($urandom_range(63, 0),
                         $urandom_range(63, 0),
                         $urandom_range(63, 0),
                         $urandom_range(63, 0));

        if (errors == 0)
            $display("[VV33:vrf_bank_address] PASS checks=%0d", 259 * 4);
        else
            $fatal(1, "[VV33:vrf_bank_address] FAIL errors=%0d", errors);
        $finish;
    end
endmodule
