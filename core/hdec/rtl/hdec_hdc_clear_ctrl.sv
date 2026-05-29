// =============================================================================
// hdec_hdc_clear_ctrl.sv — hclr / hcntclr Controller
// =============================================================================
// hclr:    zeroes 4 contiguous VRF entries (one 1024-bit HDC vector slot)
// hcntclr: zeroes 16 contiguous VRF entries (one CNT accumulator bank)
// Asserts busy while iterating, returns OK on completion.
// =============================================================================

module hdec_hdc_clear_ctrl
    import hdec_pkg::*;
    import hdec_resource_pkg::*;
(
    input  logic        clk_i,
    input  logic        rst_ni,

    // ── Command ─────────────────────────────────────────────────────────────
    input  logic                    start_i,        // single-cycle pulse
    output logic                    busy_o,
    output logic                    done_o,         // 1-cycle pulse
    output logic [1:0]              status_o,       // OK / ERROR
    input  hdec_op_t                opcode_i,       // HDEC_HCLR or HDEC_HCNTCLR
    input  logic [VRF_IDX_W-1:0]    base_slot_i,    // first VRF entry to clear

    // ── VRF Write Interface (to engine / VRF) ───────────────────────────────
    output logic [VRF_IDX_W-1:0]    vrf_wr_addr_o,
    output logic                    vrf_wr_en_o,
    output logic [LANE_NUM-1:0]     vrf_wr_bank_en_o,  // all 4 banks active
    output logic                    vrf_wr_req_o
);
    typedef enum logic [1:0] { CLR_IDLE, CLR_BUSY, CLR_DONE } clr_state_t;
    clr_state_t clr_state_q, clr_state_n;

    logic [7:0]  clr_cnt_q, clr_cnt_n;           // entry counter
    logic [7:0]  clr_total;                       // total entries to clear

    always_comb begin
        // Determine clear count from opcode
        clr_total = (opcode_i == HDEC_HCNTCLR) ? 8'(HCNTCLR_CLEAR_ENTRIES) : 8'(HCLR_CLEAR_ENTRIES);
    end

    always_comb begin
        clr_state_n  = clr_state_q;
        clr_cnt_n    = clr_cnt_q;
        busy_o       = 1'b0;
        done_o       = 1'b0;
        status_o     = STATUS_OK;
        vrf_wr_addr_o  = '0;
        vrf_wr_en_o     = 1'b0;
        vrf_wr_bank_en_o = '0;
        vrf_wr_req_o    = 1'b0;

        case (clr_state_q)
            CLR_IDLE: begin
                if (start_i) begin
                    clr_cnt_n   = '0;
                    clr_state_n = CLR_BUSY;
                end
            end

            CLR_BUSY: begin
                busy_o          = 1'b1;
                vrf_wr_addr_o   = base_slot_i + VRF_IDX_W'(clr_cnt_q);
                vrf_wr_en_o     = 1'b1;
                vrf_wr_bank_en_o = '1;    // clear all 4 banks (256-bit write)
                vrf_wr_req_o    = 1'b1;

                if (clr_cnt_q == (clr_total - 1)) begin
                    clr_cnt_n   = '0;
                    clr_state_n = CLR_DONE;
                end else begin
                    clr_cnt_n = clr_cnt_q + 8'd1;
                end
            end

            CLR_DONE: begin
                done_o      = 1'b1;
                status_o    = STATUS_OK;
                clr_state_n = CLR_IDLE;
            end

            default: clr_state_n = CLR_IDLE;
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            clr_state_q <= CLR_IDLE;
            clr_cnt_q   <= '0;
        end else begin
            clr_state_q <= clr_state_n;
            clr_cnt_q   <= clr_cnt_n;
        end
    end

endmodule
