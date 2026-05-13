// =============================================================================
// hdec_vrf_64x256.sv — 4-Bank Parameterized Vector Register File
// =============================================================================
// Phase 1: REG/LUTRAM (1-cycle read), write-forwarding, power-on init clear.
// NOT hardwired to BRAM; parameter VRF_IMPL selects storage type.
// =============================================================================

module hdec_vrf_64x256
    import hdec_pkg::*;
    import hdec_resource_pkg::*;
(
    input  logic        clk_i,
    input  logic        rst_ni,

    // ── Per-Bank Read Port ──────────────────────────────────────────────────
    input  logic [LANE_NUM-1:0][VRF_IDX_W-1:0]     bank_ra_addr_i,
    output logic [LANE_NUM-1:0][LANE_WIDTH-1:0]     bank_ra_data_o,

    // ── Per-Bank Write Port ─────────────────────────────────────────────────
    input  logic [LANE_NUM-1:0]                      bank_we_i,
    input  logic [LANE_NUM-1:0][VRF_IDX_W-1:0]      bank_wa_addr_i,
    input  logic [LANE_NUM-1:0][LANE_WIDTH-1:0]     bank_wdata_i,

    // ── Ready ───────────────────────────────────────────────────────────────
    output logic        vrf_ready_o
);

    // ── Parameterized Storage (Phase 1: REG) ───────────────────────────────
    localparam string VRF_IMPL = "REG";

    logic [LANE_WIDTH-1:0] vrf_b0 [0:VRF_ENTRIES-1];
    logic [LANE_WIDTH-1:0] vrf_b1 [0:VRF_ENTRIES-1];
    logic [LANE_WIDTH-1:0] vrf_b2 [0:VRF_ENTRIES-1];
    logic [LANE_WIDTH-1:0] vrf_b3 [0:VRF_ENTRIES-1];

    // ── Init FSM ────────────────────────────────────────────────────────────
    typedef enum logic [1:0] { INIT_CLEAR, INIT_DONE } init_state_t;
    init_state_t init_state_q, init_state_n;
    logic [7:0]  init_cnt_q, init_cnt_n;   // 256 total words: 4 banks × 64 entries

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

    // ── Bank Read / Write / Init Clear ──────────────────────────────────────
    always_ff @(posedge clk_i) begin
        if (rst_ni) begin
            // ── Read: 1-cycle synchronous ──────────────────────────────────
            automatic logic [VRF_IDX_W-1:0] ra0 = bank_ra_addr_i[0];
            automatic logic [VRF_IDX_W-1:0] ra1 = bank_ra_addr_i[1];
            automatic logic [VRF_IDX_W-1:0] ra2 = bank_ra_addr_i[2];
            automatic logic [VRF_IDX_W-1:0] ra3 = bank_ra_addr_i[3];

            // ── Bank 0 ─────────────────────────────────────────────────────
            if (bank_we_i[0] && (bank_wa_addr_i[0] == ra0))
                bank_ra_data_o[0] <= bank_wdata_i[0];     // write-forwarding
            else
                bank_ra_data_o[0] <= vrf_b0[ra0];

            if (bank_we_i[0])
                vrf_b0[bank_wa_addr_i[0]] <= bank_wdata_i[0];

            if (init_state_q == INIT_CLEAR && init_cnt_q[7:6] == 2'd0)
                vrf_b0[init_cnt_q[5:0]] <= '0;

            // ── Bank 1 ─────────────────────────────────────────────────────
            if (bank_we_i[1] && (bank_wa_addr_i[1] == ra1))
                bank_ra_data_o[1] <= bank_wdata_i[1];
            else
                bank_ra_data_o[1] <= vrf_b1[ra1];

            if (bank_we_i[1])
                vrf_b1[bank_wa_addr_i[1]] <= bank_wdata_i[1];

            if (init_state_q == INIT_CLEAR && init_cnt_q[7:6] == 2'd1)
                vrf_b1[init_cnt_q[5:0]] <= '0;

            // ── Bank 2 ─────────────────────────────────────────────────────
            if (bank_we_i[2] && (bank_wa_addr_i[2] == ra2))
                bank_ra_data_o[2] <= bank_wdata_i[2];
            else
                bank_ra_data_o[2] <= vrf_b2[ra2];

            if (bank_we_i[2])
                vrf_b2[bank_wa_addr_i[2]] <= bank_wdata_i[2];

            if (init_state_q == INIT_CLEAR && init_cnt_q[7:6] == 2'd2)
                vrf_b2[init_cnt_q[5:0]] <= '0;

            // ── Bank 3 ─────────────────────────────────────────────────────
            if (bank_we_i[3] && (bank_wa_addr_i[3] == ra3))
                bank_ra_data_o[3] <= bank_wdata_i[3];
            else
                bank_ra_data_o[3] <= vrf_b3[ra3];

            if (bank_we_i[3])
                vrf_b3[bank_wa_addr_i[3]] <= bank_wdata_i[3];

            if (init_state_q == INIT_CLEAR && init_cnt_q[7:6] == 2'd3)
                vrf_b3[init_cnt_q[5:0]] <= '0;

        end else begin
            for (int b = 0; b < LANE_NUM; b++)
                bank_ra_data_o[b] <= '0;
        end
    end

endmodule
