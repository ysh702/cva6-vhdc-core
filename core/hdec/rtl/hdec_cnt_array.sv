// =============================================================================
// hdec_cnt_array.sv — HDCU-style CNT Array Update / Clip Unit
// =============================================================================
// Bit-plane 4-bit counter update without saturation.
//   HV bit = 1  →  counter + 1
//   HV bit = 0  →  counter unchanged
// Algorithm must keep each accumulation window within 0..15.
// No bundle, no row counting, no add/sub mode, no ECC interface.
// =============================================================================

module hdec_cnt_array (
    input  logic [63:0] old_counter_i,
    input  logic [63:0] hv_word_i,
    input  logic [1:0]  subgroup_i,
    output logic [63:0] new_counter_o
);

    logic [5:0] bit_base;
    assign bit_base = {subgroup_i, 4'b0000};

    logic [15:0] p0;
    logic [15:0] p1;
    logic [15:0] p2;
    logic [15:0] p3;
    logic [15:0] hv_slice;
    logic [15:0] carry0;
    logic [15:0] carry1;
    logic [15:0] carry2;
    logic [15:0] carry3;

    assign p0       = old_counter_i[15:0];
    assign p1       = old_counter_i[31:16];
    assign p2       = old_counter_i[47:32];
    assign p3       = old_counter_i[63:48];
    assign hv_slice = hv_word_i[bit_base +: 16];
    assign carry0 = hv_slice;
    assign carry1 = p0 & carry0;
    assign carry2 = p1 & carry1;
    assign carry3 = p2 & carry2;

    assign new_counter_o[15:0]   = p0 ^ carry0;
    assign new_counter_o[31:16]  = p1 ^ carry1;
    assign new_counter_o[47:32]  = p2 ^ carry2;
    assign new_counter_o[63:48]  = p3 ^ carry3;

endmodule
