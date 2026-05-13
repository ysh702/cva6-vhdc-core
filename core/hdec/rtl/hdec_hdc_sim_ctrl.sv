// =============================================================================
// hdec_hdc_sim_ctrl.sv — sim Controller Placeholder (Phase 1: NOT_IMPLEMENTED)
// =============================================================================

module hdec_hdc_sim_ctrl
    import hdec_pkg::*;
    import hdec_resource_pkg::*;
(
    input  logic        clk_i,
    input  logic        rst_ni,

    input  logic                    start_i,
    output logic                    busy_o,
    output logic                    done_o,
    output logic [1:0]              status_o,
    input  hdec_op_t                opcode_i,
    input  logic [VRF_IDX_W-1:0]    src_slot_i,
    input  logic [VRF_IDX_W-1:0]    dst_slot_i,
    input  logic [1:0]              chunk_idx_i,

    output logic                    vrf_rd_req_o,
    output logic                    vrf_wr_req_o
);
    typedef enum logic [1:0] { ST_IDLE, ST_DONE } state_t;
    state_t state_q, state_n;

    always_comb begin
        state_n = state_q;
        busy_o  = 1'b0;
        done_o  = 1'b0;
        status_o = STATUS_NOT_IMPLEMENTED;
        vrf_rd_req_o = 1'b0;
        vrf_wr_req_o = 1'b0;

        case (state_q)
            ST_IDLE: if (start_i) state_n = ST_DONE;
            ST_DONE: begin
                done_o = 1'b1;
                state_n = ST_IDLE;
            end
            default: state_n = ST_IDLE;
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) state_q <= ST_IDLE;
        else         state_q <= state_n;
    end
endmodule
