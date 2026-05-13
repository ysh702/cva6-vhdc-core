// =============================================================================
// hdec_cmd_decode.sv — Instruction Field Parser & Command Dispatcher
// =============================================================================
// Phase 1: parses 10 instructions, extracts VRF address fields,
// routes vwr64/vrd64 directly, dispatches HDC ops to engine.
// =============================================================================

module hdec_cmd_decode
    import hdec_pkg::*;
    import hdec_resource_pkg::*;
(
    input  logic        clk_i,
    input  logic        rst_ni,

    // ── Command Input ───────────────────────────────────────────────────────
    input  logic        cmd_valid_i,
    output logic        cmd_ready_o,
    input  hdec_op_t    cmd_op_i,
    input  logic [63:0] cmd_rs1_i,
    input  logic [63:0] cmd_rs2_i,

    // ── Decoded Output ───────────────────────────────────────────────────────
    output logic                     decode_valid_o,
    input  logic                     decode_ready_i,
    output hdec_op_t                 decode_op_o,
    output logic [VRF_BNK_W-1:0]     decode_bank_o,
    output logic [VRF_IDX_W-1:0]     decode_vrf_reg_o,
    output logic [VRF_IDX_W-1:0]     decode_rd_reg_o,
    output logic [VRF_IDX_W-1:0]     decode_wr_reg_o,
    output logic [LANE_WIDTH-1:0]    decode_wr_data_o,
    output logic                     decode_is_write_o,
    output logic                     decode_is_read_o,
    output logic [LANE_NUM-1:0]      decode_lane_en_o
);

    // ── Field Extraction ────────────────────────────────────────────────────
    typedef enum logic [1:0] { DEC_IDLE, DEC_DISPATCH } dec_state_t;
    dec_state_t dec_state_q, dec_state_n;

    always_comb begin
        dec_state_n   = dec_state_q;
        cmd_ready_o   = 1'b0;
        decode_valid_o = 1'b0;
        decode_op_o    = cmd_op_i;
        decode_bank_o  = '0;
        decode_vrf_reg_o = '0;
        decode_rd_reg_o  = '0;
        decode_wr_reg_o  = '0;
        decode_wr_data_o = '0;
        decode_is_write_o = 1'b0;
        decode_is_read_o  = 1'b0;
        decode_lane_en_o  = '0;

        case (dec_state_q)
            DEC_IDLE: begin
                cmd_ready_o = 1'b1;
                if (cmd_valid_i) begin
                    decode_valid_o = 1'b1;

                    unique case (cmd_op_i)
                        // ── vwr64: bank = rs2[7:6], reg = rs2[5:0], data = rs1 ──
                        HDEC_VWR64: begin
                            decode_bank_o     = get_vrf_bank(cmd_rs2_i);
                            decode_wr_reg_o   = get_vrf_entry(cmd_rs2_i);
                            decode_wr_data_o  = cmd_rs1_i;
                            decode_is_write_o = 1'b1;
                            decode_lane_en_o  = (1 << get_vrf_bank(cmd_rs2_i));
                        end

                        // ── vrd64: bank = rs1[7:6], reg = rs1[5:0] ──
                        HDEC_VRD64: begin
                            decode_bank_o    = get_vrf_bank(cmd_rs1_i);
                            decode_rd_reg_o  = get_vrf_entry(cmd_rs1_i);
                            decode_is_read_o = 1'b1;
                            decode_lane_en_o = (1 << get_vrf_bank(cmd_rs1_i));
                        end

                        // ── HDC ops: pass through to engine ──
                        default: begin
                            // HDC ops encode fields in rs1:
                            //   rs1[17:12] = vd (dst VRF slot base index)
                            //   rs1[11:6]  = vs1 (src VRF slot base index)
                            //   rs1[5:0]   = vs2 (second src slot)
                            decode_wr_reg_o = cmd_rs1_i[17:12];
                            decode_rd_reg_o = cmd_rs1_i[11:6];
                            decode_vrf_reg_o = cmd_rs1_i[5:0];
                            // HDC ops use all 4 lanes
                            decode_lane_en_o = '1;
                        end
                    endcase

                    if (decode_ready_i)
                        dec_state_n = DEC_DISPATCH;
                end
            end

            DEC_DISPATCH: begin
                decode_valid_o = 1'b0;
                dec_state_n    = DEC_IDLE;
            end

            default: dec_state_n = DEC_IDLE;
        endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni)
            dec_state_q <= DEC_IDLE;
        else
            dec_state_q <= dec_state_n;
    end

endmodule
