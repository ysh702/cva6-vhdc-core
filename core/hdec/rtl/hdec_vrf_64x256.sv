// =============================================================================
// hdec_vrf_64x256.sv - 4-bank vector register file
// =============================================================================
// Phase 2 trial: BRAM/SRAM-friendly storage with 1-cycle registered reads and
// sequential power-on init clear. Four 64-bit banks keep read/write routing
// lane-local while allowing Vivado to map the storage into block RAM.
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

    localparam int unsigned VRF_BANK_MEMORY_SIZE = LANE_WIDTH * VRF_ENTRIES;

    typedef enum logic [1:0] { INIT_CLEAR, INIT_DONE } init_state_t;
    init_state_t init_state_q, init_state_n;
    logic [7:0] init_cnt_q, init_cnt_n;

    logic [LANE_NUM-1:0] init_bank_we;
    logic [VRF_IDX_W-1:0] init_addr;
    logic [LANE_NUM-1:0][LANE_WIDTH-1:0] bank_rd_data;

    assign init_addr       = init_cnt_q[5:0];
    assign init_bank_we[0] = (init_state_q == INIT_CLEAR) && (init_cnt_q[7:6] == 2'd0);
    assign init_bank_we[1] = (init_state_q == INIT_CLEAR) && (init_cnt_q[7:6] == 2'd1);
    assign init_bank_we[2] = (init_state_q == INIT_CLEAR) && (init_cnt_q[7:6] == 2'd2);
    assign init_bank_we[3] = (init_state_q == INIT_CLEAR) && (init_cnt_q[7:6] == 2'd3);
    assign bank_ra_data_o  = bank_rd_data;

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

    for (genvar bank = 0; bank < LANE_NUM; bank++) begin : gen_vrf_bram
        logic write_en;
        logic [0:0] write_we;
        logic [VRF_IDX_W-1:0] write_addr;
        logic [LANE_WIDTH-1:0] write_data;
        logic sbiterr_unused;
        logic dbiterr_unused;

        assign write_en   = init_bank_we[bank] || bank_we_i[bank];
        assign write_we   = write_en;
        assign write_addr = init_bank_we[bank] ? init_addr : bank_wa_addr_i[bank];
        assign write_data = init_bank_we[bank] ? '0 : bank_wdata_i[bank];

        xpm_memory_sdpram #(
            .MEMORY_SIZE(VRF_BANK_MEMORY_SIZE),
            .MEMORY_PRIMITIVE("block"),
            .CLOCKING_MODE("common_clock"),
            .ECC_MODE("no_ecc"),
            .MEMORY_INIT_FILE("none"),
            .MEMORY_INIT_PARAM("0"),
            .USE_MEM_INIT(0),
            .WAKEUP_TIME("disable_sleep"),
            .AUTO_SLEEP_TIME(0),
            .MESSAGE_CONTROL(0),
            .USE_EMBEDDED_CONSTRAINT(0),
            .MEMORY_OPTIMIZATION("true"),
            .CASCADE_HEIGHT(0),
            .SIM_ASSERT_CHK(0),
            .WRITE_PROTECT(1),
            .WRITE_DATA_WIDTH_A(LANE_WIDTH),
            .BYTE_WRITE_WIDTH_A(LANE_WIDTH),
            .ADDR_WIDTH_A(VRF_IDX_W),
            .RST_MODE_A("SYNC"),
            .READ_DATA_WIDTH_B(LANE_WIDTH),
            .ADDR_WIDTH_B(VRF_IDX_W),
            .READ_RESET_VALUE_B("0"),
            .READ_LATENCY_B(1),
            .WRITE_MODE_B("read_first"),
            .RST_MODE_B("SYNC")
        ) i_vrf_bank (
            .sleep(1'b0),
            .clka(clk_i),
            .ena(1'b1),
            .wea(write_we),
            .addra(write_addr),
            .dina(write_data),
            .injectsbiterra(1'b0),
            .injectdbiterra(1'b0),
            .clkb(clk_i),
            .rstb(!rst_ni),
            .enb(1'b1),
            .regceb(1'b1),
            .addrb(bank_ra_addr_i[bank]),
            .doutb(bank_rd_data[bank]),
            .sbiterrb(sbiterr_unused),
            .dbiterrb(dbiterr_unused)
        );
    end

endmodule
