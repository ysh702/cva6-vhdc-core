// =============================================================================
// hdec_cnt_array.sv — HDCU-style CNT Array Update / Clip Unit
// =============================================================================
// Single-HV packed 4-bit counter update with saturation.
//   HV bit = 1  →  counter + 1 (saturate at 15)
//   HV bit = 0  →  counter unchanged
// Clip comparator: counter >= threshold → prototype bit = 1
// No bundle, no row counting, no add/sub mode, no ECC interface.
// =============================================================================

module hdec_cnt_array (
    input  logic        clear_i,
    input  logic        update_i,
    input  logic [63:0] old_counter_i,
    input  logic [63:0] hv_word_i,
    input  logic [1:0]  subgroup_i,
    input  logic [3:0]  clip_threshold_i,
    output logic [63:0] new_counter_o,
    output logic [15:0] clip_bits_o
);

    logic [5:0] bit_base;
    assign bit_base = {subgroup_i, 4'b0000};

    for (genvar ni = 0; ni < 16; ni++) begin : gen_cnt_nibble
        logic [3:0] old_cnt;
        logic       hv_bit;
        logic [3:0] inc_one;

        assign old_cnt = old_counter_i[4*ni +: 4];
        assign hv_bit  = hv_word_i[bit_base + ni];

        // 4-bit saturating increment by 1 (LUT-style, no arithmetic +)
        always_comb unique case (old_cnt)
            4'h0:    inc_one = 4'h1;
            4'h1:    inc_one = 4'h2;
            4'h2:    inc_one = 4'h3;
            4'h3:    inc_one = 4'h4;
            4'h4:    inc_one = 4'h5;
            4'h5:    inc_one = 4'h6;
            4'h6:    inc_one = 4'h7;
            4'h7:    inc_one = 4'h8;
            4'h8:    inc_one = 4'h9;
            4'h9:    inc_one = 4'hA;
            4'hA:    inc_one = 4'hB;
            4'hB:    inc_one = 4'hC;
            4'hC:    inc_one = 4'hD;
            4'hD:    inc_one = 4'hE;
            4'hE:    inc_one = 4'hF;
            4'hF:    inc_one = 4'hF;   // saturated
            default: inc_one = 4'h0;
        endcase

        always_comb begin
            new_counter_o[4*ni +: 4] = hv_bit ? inc_one : old_cnt;

            clip_bits_o[ni] = (old_cnt >= clip_threshold_i);
        end
    end

endmodule
