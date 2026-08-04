// ASIC logic-core boundary for VV35.
//
// The four memory banks are black boxes, but the second public return stage is
// retained. Each black box represents one 64-entry x 64-bit 1R1W SRAM with a
// registered read output. Area, power and timing inside the black boxes are
// excluded until a real macro .db is linked.

(* black_box = "true" *)
module hdec_sram64x64_1r1w_bb (
    input  logic        clk_i,
    input  logic [5:0]  raddr_i,
    output logic [63:0] rdata_o,
    input  logic        we_i,
    input  logic [5:0]  waddr_i,
    input  logic [63:0] wdata_i
);
    /* synopsys syn_black_box */
endmodule

module hdec_vrf_64x256
    import hdec_pkg::*;
    import hdec_resource_pkg::*;
(
    input  logic clk_i,
    input  logic [LANE_NUM-1:0][VRF_IDX_W-1:0] bank_ra_addr_i,
    output logic [LANE_NUM-1:0][LANE_WIDTH-1:0] bank_ra_data_o,
    output logic [LANE_NUM-1:0][LANE_WIDTH-1:0] bank_ra_early_o,
    input  logic [LANE_NUM-1:0] bank_we_i,
    input  logic [VRF_IDX_W-1:0] row_wa_addr_i,
    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0] bank_wdata_i,
    output logic vrf_ready_o
);
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] macro_rdata;

    assign vrf_ready_o = 1'b1;
    assign bank_ra_early_o = macro_rdata;

    for (genvar bank = 0; bank < LANE_NUM; bank++) begin : gen_bank
        hdec_sram64x64_1r1w_bb i_sram (
            .clk_i,
            .raddr_i (bank_ra_addr_i[bank]),
            .rdata_o (macro_rdata[bank]),
            .we_i    (bank_we_i[bank]),
            .waddr_i (row_wa_addr_i),
            .wdata_i (bank_wdata_i[bank])
        );

        always_ff @(posedge clk_i)
            bank_ra_data_o[bank] <= macro_rdata[bank];
    end
endmodule
