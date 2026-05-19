// =============================================================================
// hdec_lane_4x64.sv — 64-bit Lane Shell with Lane-Local Static Function Blocks
// =============================================================================
// Phase 1: transitional control ports plus independent combinational XOR Front-End
//          and Popcount/Compressor blocks. Complex operators can later add local
//          thin register shells around these blocks without changing top-level
//          CV-X-IF or VRF protocols.
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

    // ── Neighbor Lane Interface (reserved for future lane-local operators) ──
    input  logic [LANE_WIDTH-1:0]             neighbor_in_i,
    output logic [LANE_WIDTH-1:0]             neighbor_out_o,

    // ── Carry / Borrow / Count / Flag (reserved for future local operators) ─
    input  logic                              carry_in_i,
    output logic                              carry_out_o,
    input  logic                              borrow_in_i,
    output logic                              borrow_out_o,
    input  logic [6:0]                        count_in_i,
    output logic [6:0]                        count_out_o,
    input  logic                              flag_in_i,
    output logic                              flag_out_o,

    // ── Local Writeback (reserved for future local operators) ───────────────
    output logic [LANE_WIDTH-1:0]             local_wb_data_o,
    output logic [VRF_IDX_W-1:0]              local_wb_addr_o,
    output logic                              local_wb_we_o,

    // ── XOR Front-End Compute Path (transitional: will be unified under engine) ─
    input  logic                              bool_valid_i,
    input  logic [LANE_WIDTH-1:0]             bool_src_a_i,
    input  logic [LANE_WIDTH-1:0]             bool_src_b_i,
    output logic [LANE_WIDTH-1:0]             bool_result_o,
    output logic [6:0]                        popcount_count_o,

    // -- BMCA hvsim batch path --------------------------------------------
    input  logic                              bmca_row_clear_i,
    input  logic                              bmca_row_load_valid_i,
    input  logic [1:0]                        bmca_row_load_sel_i,
    input  logic                              bmca_compress_valid_i,
    output logic [LANE_WIDTH-1:0]             bmca_lo_o,
    output logic [LANE_WIDTH-1:0]             bmca_hi_o,
    output logic [7:0]                        bmca_count3_o,
    output logic                              bmca_count_valid_o,

    // ── Shift-Align Compute Path (4-bit granular, lane-local) ───────────────
    input  logic                              shift_valid_i,
    input  logic [LANE_WIDTH-1:0]             shift_src_a_i,
    input  logic [LANE_WIDTH-1:0]             shift_src_b_i,
    input  logic [3:0]                        shift_nibble_i,
    output logic [LANE_WIDTH-1:0]             shift_result_o,

    // -- Add/Sub/Counter Compute Path (HDC badd system path) ---------------
    input  logic                              addsub_valid_i,
    input  logic [LANE_WIDTH-1:0]             addsub_old_counter_i,
    input  logic [15:0]                       addsub_hv_bits_i,
    output logic [LANE_WIDTH-1:0]             addsub_result_o
);

    // ── Operand Isolation: gate all XOR inputs to 0 when inactive ──────────
    // Prevents dynamic power from spurious toggling on unused XOR path.
    logic [LANE_WIDTH-1:0] bool_src_a, bool_src_b;
    assign bool_src_a = bool_valid_i ? bool_src_a_i : '0;
    assign bool_src_b = bool_valid_i ? bool_src_b_i : '0;

    // ── XOR Front-End Core (combinational, no pipeline delay) ──────────────
    // Transitional: bool path sits alongside ctrl path.  Final target is
    // engine-level arbiter + unified Lane compute request.
    logic [LANE_WIDTH-1:0] bool_result;

    hdec_lane_boolean_mask i_boolean_mask (
        .src_a_i (bool_src_a),
        .src_b_i (bool_src_b),
        .result_o(bool_result)
    );

    assign bool_result_o = bool_result;

    // ── Popcount/Compressor Core (combinational static block) ──────────────
    // HDC hsim uses the popcount path over the XOR Front-End diff.  The ECC
    // compressor path is structurally present but intentionally unconnected to
    // any ECC controller in this phase.
    hdec_lane_popcount_compressor i_popcount_compressor (
        .mode_i     (1'b0),
        .diff_i     (bool_result),
        .a_i        ('0),
        .b_i        ('0),
        .c_i        ('0),
        .count_o    (popcount_count_o),
        .csa_sum_o  (),
        .csa_carry_o(),
        .csa_cout_o ()
    );

    // -- BMCA hvsim batch compressor --------------------------------------
    hdec_lane_bmca i_bmca (
        .clk_i,
        .rst_ni,
        .row_clear_i      (bmca_row_clear_i),
        .row_load_valid_i (bmca_row_load_valid_i),
        .row_load_sel_i   (bmca_row_load_sel_i),
        .row_load_data_i  (bool_result),
        .compress_valid_i (bmca_compress_valid_i),
        .lo_o             (bmca_lo_o),
        .hi_o             (bmca_hi_o),
        .count3_o         (bmca_count3_o),
        .count_valid_o    (bmca_count_valid_o)
    );

    // ── Shift-Align Core (combinational static block) ──────────────────────
    // Gate all shift inputs to 0 when inactive to avoid unused-path toggling.
    logic [LANE_WIDTH-1:0] shift_src_a, shift_src_b;
    logic [3:0]            shift_nibble;
    assign shift_src_a  = shift_valid_i ? shift_src_a_i  : '0;
    assign shift_src_b  = shift_valid_i ? shift_src_b_i  : '0;
    assign shift_nibble = shift_valid_i ? shift_nibble_i : '0;

    hdec_lane_shift_align i_shift_align (
        .src_a_i       (shift_src_a),
        .src_b_i       (shift_src_b),
        .nibble_shift_i(shift_nibble),
        .result_o      (shift_result_o)
    );

    // -- Add/Sub/Counter Core (combinational static block) ------------------
    // Current system path uses HDC_BUNDLE ADD only. Future ECC_FULL control is
    // intentionally not routed through hdec_top in this phase.
    logic [LANE_WIDTH-1:0] addsub_old_counter, addsub_hv_addend;
    logic [15:0]           addsub_hv_bits;
    assign addsub_old_counter = addsub_valid_i ? addsub_old_counter_i : '0;
    assign addsub_hv_bits     = addsub_valid_i ? addsub_hv_bits_i     : '0;

    for (genvar addsub_bit = 0; addsub_bit < 16; addsub_bit++) begin : gen_addsub_hv_expand
        assign addsub_hv_addend[4*addsub_bit +: 4] = addsub_hv_bits[addsub_bit] ? 4'b0001 : 4'b0000;
    end

    hdec_lane_addsub_counter i_addsub_counter (
        .src_a_i (addsub_old_counter),
        .src_b_i (addsub_hv_addend),
        .mode_i  (1'b0),
        .op_i    (1'b0),
        .result_o(addsub_result_o),
        .carry_o ()
    );

    // ── Legacy Passthrough Shell Registers ──────────────────────────────────
    typedef enum logic [2:0] { LS_IDLE, LS_P0, LS_P1, LS_P2, LS_P3 } lane_state_t;
    lane_state_t lane_state_q, lane_state_n;

    // Passthrough slot 0
    logic [LANE_WIDTH-1:0] p0_data_q, p0_data_d;
    hdec_op_t              p0_op_q,   p0_op_d;
    logic [1:0]            p0_owner_q, p0_owner_d;

    // Passthrough slot 1
    logic [LANE_WIDTH-1:0] p1_data_q, p1_data_d;
    hdec_op_t              p1_op_q,   p1_op_d;
    logic [1:0]            p1_owner_q, p1_owner_d;

    // Passthrough slot 2
    logic [LANE_WIDTH-1:0] p2_data_q, p2_data_d;
    hdec_op_t              p2_op_q,   p2_op_d;
    logic [1:0]            p2_owner_q, p2_owner_d;

    // Passthrough slot 3
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
