// =============================================================================
// hdec_lane_popcount_compressor.sv — Lane-local Popcount / CSA Compressor
// =============================================================================
// Pure combinational static function block. No valid/ready/busy FSM.
// Mode 0: HDC_POPCOUNT  - count ones in diff_i[63:0].
// Mode 1: ECC_COMPRESS  - 3:2 carry-save compressor for future ECC use.
// =============================================================================

module hdec_lane_popcount_compressor (
    input  logic        mode_i,
    input  logic [63:0] diff_i,
    input  logic [63:0] a_i,
    input  logic [63:0] b_i,
    input  logic [63:0] c_i,
    output logic [6:0]  count_o,
    output logic [63:0] csa_sum_o,
    output logic [63:0] csa_carry_o,
    output logic        csa_cout_o
);

    localparam logic HDC_POPCOUNT = 1'b0;
    localparam logic ECC_COMPRESS = 1'b1;

    logic [63:0] diff_iso;
    logic [63:0] a_iso, b_iso, c_iso;
    logic [63:0] maj;

    assign diff_iso = (mode_i == HDC_POPCOUNT) ? diff_i : 64'b0;
    assign a_iso    = (mode_i == ECC_COMPRESS) ? a_i    : 64'b0;
    assign b_iso    = (mode_i == ECC_COMPRESS) ? b_i    : 64'b0;
    assign c_iso    = (mode_i == ECC_COMPRESS) ? c_i    : 64'b0;

    assign maj = (a_iso & b_iso) | (a_iso & c_iso) | (b_iso & c_iso);

    always_comb begin
        count_o     = 7'($countones(diff_iso));
        csa_sum_o   = a_iso ^ b_iso ^ c_iso;
        csa_carry_o = {maj[62:0], 1'b0};
        csa_cout_o  = maj[63];
    end

endmodule
