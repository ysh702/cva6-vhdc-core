// =============================================================================
// hdec_cnt_array.sv - HDC lane-local packed counter update/prototype block
// =============================================================================
// Unsigned 4-bit counters, saturated at 15.  A set input bit increments the
// corresponding counter by one; a clear input forces the output word to zero.
// Input bit 0 leaves the counter unchanged.  Clip emits a prototype bit when
// counter >= threshold.
// =============================================================================

module hdec_cnt_array (
    input  logic        clear_i,
    input  logic        update_i,
    input  logic [63:0] old_counter_i,
    input  logic [63:0] row0_i,
    input  logic [63:0] row1_i,
    input  logic [63:0] row2_i,
    input  logic [63:0] row3_i,
    input  logic [2:0]  row_count_i,
    input  logic [1:0]  subgroup_i,
    input  logic [3:0]  clip_threshold_i,
    output logic [63:0] new_counter_o,
    output logic [15:0] clip_bits_o
);

    logic [5:0] bit_base;
    assign bit_base = {subgroup_i, 4'b0000};

    for (genvar bit_idx = 0; bit_idx < 16; bit_idx++) begin : gen_cnt
        logic [3:0] old_cnt;
        logic [2:0] inc;
        logic [4:0] sum;

        assign old_cnt = old_counter_i[4*bit_idx +: 4];
        assign inc = {2'b00, row0_i[bit_base + bit_idx]} +
                     {2'b00, row1_i[bit_base + bit_idx]} +
                     {2'b00, row2_i[bit_base + bit_idx]} +
                     ((row_count_i >= 3'd4) ? {2'b00, row3_i[bit_base + bit_idx]} : 3'b000);
        assign sum = {1'b0, old_cnt} + {2'b00, inc};

        always_comb begin
            if (clear_i)
                new_counter_o[4*bit_idx +: 4] = 4'h0;
            else if (update_i)
                new_counter_o[4*bit_idx +: 4] = sum[4] ? 4'hF : sum[3:0];
            else
                new_counter_o[4*bit_idx +: 4] = old_cnt;

            clip_bits_o[bit_idx] = (old_cnt >= clip_threshold_i);
        end
    end

endmodule
