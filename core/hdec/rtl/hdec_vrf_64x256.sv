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

    input  logic [VRF_IDX_W-1:0]                row_ra_addr_i,
    output logic [LANE_NUM-1:0][LANE_WIDTH-1:0] bank_ra_data_o,

    input  logic [LANE_NUM-1:0]                 bank_we_i,
    input  logic [VRF_IDX_W-1:0]                row_wa_addr_i,
    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0] bank_wdata_i,

    output logic        vrf_ready_o
);

    assign vrf_ready_o = 1'b1;

    for (genvar bid = 0; bid < LANE_NUM; bid++) begin : gen_bank
        (* ram_style = "distributed" *) logic [LANE_WIDTH-1:0] vrf_mem [0:VRF_ENTRIES-1];

        always_ff @(posedge clk_i) begin
            if (bank_we_i[bid])
                vrf_mem[row_wa_addr_i] <= bank_wdata_i[bid];

            bank_ra_data_o[bid] <= vrf_mem[row_ra_addr_i];
        end
    end

endmodule
