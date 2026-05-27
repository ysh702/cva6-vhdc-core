// =============================================================================
// hdec_vrf_64x256.sv - 4-bank vector register file
// =============================================================================
// Phase 1: LUTRAM-friendly storage with 1-cycle registered reads,
// same-cycle normal write forwarding, and sequential power-on init clear.
// =============================================================================

module hdec_vrf_64x256
    import hdec_pkg::*;
    import hdec_resource_pkg::*;
(
    input  logic        clk_i,
    input  logic        rst_ni,

    input  logic [LANE_NUM-1:0][VRF_IDX_W-1:0]  bank_ra_addr_i,
    output logic [LANE_NUM-1:0][LANE_WIDTH-1:0] bank_ra_data_o,

    input  logic [LANE_NUM-1:0]                 bank_we_i,
    input  logic [LANE_NUM-1:0][VRF_IDX_W-1:0]  bank_wa_addr_i,
    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0] bank_wdata_i,

    output logic        vrf_ready_o
);

    (* ram_style = "distributed" *) logic [LANE_WIDTH-1:0] vrf_b0 [0:VRF_ENTRIES-1];
    (* ram_style = "distributed" *) logic [LANE_WIDTH-1:0] vrf_b1 [0:VRF_ENTRIES-1];
    (* ram_style = "distributed" *) logic [LANE_WIDTH-1:0] vrf_b2 [0:VRF_ENTRIES-1];
    (* ram_style = "distributed" *) logic [LANE_WIDTH-1:0] vrf_b3 [0:VRF_ENTRIES-1];

    typedef enum logic [1:0] { INIT_CLEAR, INIT_DONE } init_state_t;
    init_state_t init_state_q, init_state_n;
    logic [7:0] init_cnt_q, init_cnt_n;

    logic init_b0_we, init_b1_we, init_b2_we, init_b3_we;
    logic [VRF_IDX_W-1:0] init_addr;

    assign init_addr  = init_cnt_q[5:0];
    assign init_b0_we = (init_state_q == INIT_CLEAR) && (init_cnt_q[7:6] == 2'd0);
    assign init_b1_we = (init_state_q == INIT_CLEAR) && (init_cnt_q[7:6] == 2'd1);
    assign init_b2_we = (init_state_q == INIT_CLEAR) && (init_cnt_q[7:6] == 2'd2);
    assign init_b3_we = (init_state_q == INIT_CLEAR) && (init_cnt_q[7:6] == 2'd3);

    always_comb begin
        init_state_n = init_state_q;
        init_cnt_n   = init_cnt_q;
        vrf_ready_o  = (init_state_q == INIT_DONE);

        if (init_state_q == INIT_CLEAR) begin
            if (init_cnt_q == 8'd255)
                init_state_n = INIT_DONE;
            else
                init_cnt_n = init_cnt_q + 8'd1;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            init_state_q <= INIT_CLEAR;
            init_cnt_q   <= '0;
        end else begin
            init_state_q <= init_state_n;
            init_cnt_q   <= init_cnt_n;
        end
    end

    // One write port per bank. During init, the sequential clear owns the write
    // port; normal HDEC traffic is expected after reset/init.
    always_ff @(posedge clk_i) begin
        if (init_b0_we)
            vrf_b0[init_addr] <= '0;
        else if (bank_we_i[0])
            vrf_b0[bank_wa_addr_i[0]] <= bank_wdata_i[0];
    end

    always_ff @(posedge clk_i) begin
        if (init_b1_we)
            vrf_b1[init_addr] <= '0;
        else if (bank_we_i[1])
            vrf_b1[bank_wa_addr_i[1]] <= bank_wdata_i[1];
    end

    always_ff @(posedge clk_i) begin
        if (init_b2_we)
            vrf_b2[init_addr] <= '0;
        else if (bank_we_i[2])
            vrf_b2[bank_wa_addr_i[2]] <= bank_wdata_i[2];
    end

    always_ff @(posedge clk_i) begin
        if (init_b3_we)
            vrf_b3[init_addr] <= '0;
        else if (bank_we_i[3])
            vrf_b3[bank_wa_addr_i[3]] <= bank_wdata_i[3];
    end

    // Keep the existing 1-cycle registered read behavior seen by hdec_top.
    // Same-cycle normal write/read to the same bank/address forwards write data.
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            bank_ra_data_o <= '0;
        end else begin
            if (bank_we_i[0] && (bank_wa_addr_i[0] == bank_ra_addr_i[0]))
                bank_ra_data_o[0] <= bank_wdata_i[0];
            else
                bank_ra_data_o[0] <= vrf_b0[bank_ra_addr_i[0]];

            if (bank_we_i[1] && (bank_wa_addr_i[1] == bank_ra_addr_i[1]))
                bank_ra_data_o[1] <= bank_wdata_i[1];
            else
                bank_ra_data_o[1] <= vrf_b1[bank_ra_addr_i[1]];

            if (bank_we_i[2] && (bank_wa_addr_i[2] == bank_ra_addr_i[2]))
                bank_ra_data_o[2] <= bank_wdata_i[2];
            else
                bank_ra_data_o[2] <= vrf_b2[bank_ra_addr_i[2]];

            if (bank_we_i[3] && (bank_wa_addr_i[3] == bank_ra_addr_i[3]))
                bank_ra_data_o[3] <= bank_wdata_i[3];
            else
                bank_ra_data_o[3] <= vrf_b3[bank_ra_addr_i[3]];
        end
    end

endmodule
