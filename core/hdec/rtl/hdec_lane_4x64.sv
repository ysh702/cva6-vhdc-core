// =============================================================================
// hdec_lane_4x64.sv — 64-bit Lane Shell, 4-Stage Pipeline, Zero Datapath Compute
// =============================================================================
// Phase 1: P0(read/decode)→P1(bool/shift)→P2(count/add)→P3(compare/writeback)
//          Every stage is a simple register passthrough. No compute.
// Future:  P1 gets XOR/rotate/shift; P2 gets popcount/adder/counter;
//          P3 gets comparator/threshold.
// =============================================================================

module hdec_lane_4x64
    import hdec_pkg::*;
    import hdec_resource_pkg::*;
#(
    parameter int LANE_ID = 0   // 0, 1, 2, or 3
) (
    input  logic        clk_i,
    input  logic        rst_ni,

    // ── VRF Bank Connection (this lane ↔ its bank) ──────────────────────────
    output logic [VRF_IDX_W-1:0]              vrf_ra_addr_o,
    input  logic [LANE_WIDTH-1:0]             vrf_ra_data_i,
    output logic                              vrf_we_o,
    output logic [VRF_IDX_W-1:0]              vrf_wa_addr_o,
    output logic [LANE_WIDTH-1:0]             vrf_wdata_o,

    // ── Control Interface (from engine / cmd_decode) ────────────────────────
    input  logic                              ctrl_valid_i,
    output logic                              ctrl_ready_o,
    input  logic [1:0]                        ctrl_owner_i,
    input  hdec_op_t                          ctrl_op_i,
    input  logic [VRF_IDX_W-1:0]              ctrl_rd_reg_i,
    input  logic [VRF_IDX_W-1:0]              ctrl_wr_reg_i,
    input  logic [LANE_WIDTH-1:0]             ctrl_wr_data_i,
    input  logic                              ctrl_is_write_i,
    input  logic                              ctrl_is_read_i,

    // ── Result Interface (to engine) ────────────────────────────────────────
    output logic                              res_valid_o,
    input  logic                              res_ready_i,
    output logic [LANE_WIDTH-1:0]             res_data_o,
    output logic [1:0]                        res_owner_o,

    // ── Neighbor Lane Interface (P1 permute/shift, future) ──────────────────
    input  logic [LANE_WIDTH-1:0]             neighbor_in_i,
    output logic [LANE_WIDTH-1:0]             neighbor_out_o,

    // ── Carry / Borrow / Count / Flag (P2, future) ──────────────────────────
    input  logic                              carry_in_i,
    output logic                              carry_out_o,
    input  logic                              borrow_in_i,
    output logic                              borrow_out_o,
    input  logic [6:0]                        count_in_i,
    output logic [6:0]                        count_out_o,
    input  logic                              flag_in_i,
    output logic                              flag_out_o,

    // ── Local Writeback (P3, future) ────────────────────────────────────────
    output logic [LANE_WIDTH-1:0]             local_wb_data_o,
    output logic [VRF_IDX_W-1:0]              local_wb_addr_o,
    output logic                              local_wb_we_o,

    // ── Boolean/Mask Compute Path (transitional: will be unified under engine) ─
    input  logic                              bool_valid_i,
    input  logic [LANE_WIDTH-1:0]             bool_src_a_i,
    input  logic [LANE_WIDTH-1:0]             bool_src_b_i,
    input  logic [LANE_WIDTH-1:0]             bool_mask_i,
    input  logic [1:0]                        bool_mode_i,
    output logic [LANE_WIDTH-1:0]             bool_result_o
);

    // ── Operand Isolation: gate all bool inputs to 0 when inactive ─────────
    // Prevents dynamic power from spurious toggling on unused bool path.
    logic [LANE_WIDTH-1:0] bool_src_a, bool_src_b, bool_mask;
    logic [1:0]            bool_mode;
    assign bool_src_a = bool_valid_i ? bool_src_a_i : '0;
    assign bool_src_b = bool_valid_i ? bool_src_b_i : '0;
    assign bool_mask  = bool_valid_i ? bool_mask_i  : '0;
    assign bool_mode  = bool_valid_i ? bool_mode_i  : 2'b0;

    // ── Boolean/Mask Core (combinational, no pipeline delay) ───────────────
    // Transitional: bool path sits alongside ctrl path.  Final target is
    // engine-level arbiter + unified Lane compute request.
    hdec_lane_boolean_mask i_boolean_mask (
        .src_a_i (bool_src_a),
        .src_b_i (bool_src_b),
        .mask_i  (bool_mask),
        .mode_i  (bool_mode),
        .result_o(bool_result_o)
    );

    // ── Pipeline Stage Registers ────────────────────────────────────────────
    typedef enum logic [2:0] { LS_IDLE, LS_P0, LS_P1, LS_P2, LS_P3 } lane_state_t;
    lane_state_t lane_state_q, lane_state_n;

    // P0: read/decode
    logic [LANE_WIDTH-1:0] p0_data_q, p0_data_d;
    hdec_op_t              p0_op_q,   p0_op_d;
    logic [1:0]            p0_owner_q, p0_owner_d;

    // P1: bool/shift
    logic [LANE_WIDTH-1:0] p1_data_q, p1_data_d;
    hdec_op_t              p1_op_q,   p1_op_d;
    logic [1:0]            p1_owner_q, p1_owner_d;

    // P2: count/add
    logic [LANE_WIDTH-1:0] p2_data_q, p2_data_d;
    hdec_op_t              p2_op_q,   p2_op_d;
    logic [1:0]            p2_owner_q, p2_owner_d;

    // P3: compare/writeback
    logic [LANE_WIDTH-1:0] p3_data_q, p3_data_d;
    logic [1:0]            p3_owner_q, p3_owner_d;

    // ── Combinational ───────────────────────────────────────────────────────
    always_comb begin
        lane_state_n = lane_state_q;
        ctrl_ready_o = 1'b0;
        res_valid_o  = 1'b0;

        // Pipeline defaults: hold
        p0_data_d  = p0_data_q;   p0_op_d    = p0_op_q;   p0_owner_d  = p0_owner_q;
        p1_data_d  = p1_data_q;   p1_op_d    = p1_op_q;   p1_owner_d  = p1_owner_q;
        p2_data_d  = p2_data_q;   p2_op_d    = p2_op_q;   p2_owner_d  = p2_owner_q;
        p3_data_d  = p3_data_q;   p3_owner_d = p3_owner_q;

        // VRF defaults
        vrf_ra_addr_o = '0;  vrf_we_o = 1'b0;  vrf_wa_addr_o = '0;  vrf_wdata_o = '0;

        // Reserved port defaults
        neighbor_out_o = neighbor_in_i;   // passthrough
        carry_out_o    = '0;  borrow_out_o = '0;  count_out_o = '0;  flag_out_o = '0;
        local_wb_data_o = '0; local_wb_addr_o = '0; local_wb_we_o = '0;

        // ── FSM ────────────────────────────────────────────────────────────
        case (lane_state_q)
            LS_IDLE: begin
                ctrl_ready_o = 1'b1;
                if (ctrl_valid_i) begin
                    if (ctrl_is_write_i) begin
                        // Write: latch data, drive VRF immediately
                        vrf_we_o      = 1'b1;
                        vrf_wa_addr_o = ctrl_wr_reg_i;
                        vrf_wdata_o   = ctrl_wr_data_i;
                    end
                    if (ctrl_is_read_i) begin
                        // Read: launch VRF address
                        vrf_ra_addr_o = ctrl_rd_reg_i;
                    end
                    // Passthrough: op + owner go straight to pipeline
                    p0_data_d   = ctrl_is_read_i ? vrf_ra_data_i : ctrl_wr_data_i;
                    p0_op_d     = ctrl_op_i;
                    p0_owner_d  = ctrl_owner_i;
                    lane_state_n = LS_P0;
                end
            end

            LS_P0: begin  // registered → P1
                p1_data_d   = p0_data_q;
                p1_op_d     = p0_op_q;
                p1_owner_d  = p0_owner_q;
                lane_state_n = LS_P1;
            end

            LS_P1: begin  // registered → P2
                p2_data_d   = p1_data_q;
                p2_op_d     = p1_op_q;
                p2_owner_d  = p1_owner_q;
                lane_state_n = LS_P2;
            end

            LS_P2: begin  // registered → P3
                p3_data_d   = p2_data_q;
                p3_owner_d  = p2_owner_q;
                lane_state_n = LS_P3;
            end

            LS_P3: begin  // drive result
                res_valid_o  = 1'b1;
                res_data_o   = p3_data_q;
                res_owner_o  = p3_owner_q;
                if (res_ready_i)
                    lane_state_n = LS_IDLE;
            end

            default: lane_state_n = LS_IDLE;
        endcase
    end

    // ── Sequential ──────────────────────────────────────────────────────────
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            lane_state_q <= LS_IDLE;
            p0_data_q  <= '0;  p0_op_q  <= HDEC_VWR64;  p0_owner_q  <= OWNER_NONE;
            p1_data_q  <= '0;  p1_op_q  <= HDEC_VWR64;  p1_owner_q  <= OWNER_NONE;
            p2_data_q  <= '0;  p2_op_q  <= HDEC_VWR64;  p2_owner_q  <= OWNER_NONE;
            p3_data_q  <= '0;                        p3_owner_q  <= OWNER_NONE;
        end else begin
            lane_state_q <= lane_state_n;
            p0_data_q  <= p0_data_d;   p0_op_q   <= p0_op_d;   p0_owner_q  <= p0_owner_d;
            p1_data_q  <= p1_data_d;   p1_op_q   <= p1_op_d;   p1_owner_q  <= p1_owner_d;
            p2_data_q  <= p2_data_d;   p2_op_q   <= p2_op_d;   p2_owner_q  <= p2_owner_d;
            p3_data_q  <= p3_data_d;                             p3_owner_q  <= p3_owner_d;
        end
    end

endmodule
