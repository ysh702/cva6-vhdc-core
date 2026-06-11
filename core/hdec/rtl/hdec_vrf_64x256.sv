// =============================================================================
// hdec_vrf_64x256.sv - 4-bank vector register file
// =============================================================================
// Phase 1: LUTRAM-friendly storage with 1-cycle registered reads. Four 64-bit
// banks keep read/write routing lane-local.
// =============================================================================

module hdec_vrf_64x256
    import hdec_pkg::*;
    import hdec_resource_pkg::*;
(
    input  logic        clk_i,

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

    assign vrf_ready_o = 1'b1;

    always_ff @(posedge clk_i) begin
        if (bank_we_i[0])
            vrf_b0[bank_wa_addr_i[0]] <= bank_wdata_i[0];
    end

    always_ff @(posedge clk_i) begin
        if (bank_we_i[1])
            vrf_b1[bank_wa_addr_i[1]] <= bank_wdata_i[1];
    end

    always_ff @(posedge clk_i) begin
        if (bank_we_i[2])
            vrf_b2[bank_wa_addr_i[2]] <= bank_wdata_i[2];
    end

    always_ff @(posedge clk_i) begin
        if (bank_we_i[3])
            vrf_b3[bank_wa_addr_i[3]] <= bank_wdata_i[3];
    end

    always_ff @(posedge clk_i) begin
        bank_ra_data_o[0] <= vrf_b0[bank_ra_addr_i[0]];
        bank_ra_data_o[1] <= vrf_b1[bank_ra_addr_i[1]];
        bank_ra_data_o[2] <= vrf_b2[bank_ra_addr_i[2]];
        bank_ra_data_o[3] <= vrf_b3[bank_ra_addr_i[3]];
    end

endmodule
