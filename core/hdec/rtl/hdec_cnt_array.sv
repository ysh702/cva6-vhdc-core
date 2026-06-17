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
    input  logic [63:0] old_counter_i,
    input  logic [63:0] hv_word_i,
    input  logic [1:0]  subgroup_i,
    output logic [63:0] new_counter_o
);

    logic [5:0] bit_base;
    assign bit_base = {subgroup_i, 4'b0000};

    for (genvar ni = 0; ni < 16; ni++) begin : gen_cnt_nibble
        logic [3:0] old_cnt;
        logic       hv_bit;
        logic       inc_en;
        logic [4:0] inc_sum;

        assign old_cnt = old_counter_i[4*ni +: 4];
        assign hv_bit  = hv_word_i[bit_base + ni];
        assign inc_en  = hv_bit & ~&old_cnt;
        assign inc_sum = {1'b0, old_cnt} + {4'b0, inc_en};

        always_comb begin
            new_counter_o[4*ni +: 4] = inc_sum[3:0];
        end
    end

endmodule
