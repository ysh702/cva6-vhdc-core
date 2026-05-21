// =============================================================================
// hdec_lane_clip.sv - Lane-local HDC clip comparator/packer
// =============================================================================
// HDC use: compare 16 packed 4-bit counters against a 4-bit threshold and pack
// the predicate bits into a 16-bit hypervector slice.
// =============================================================================

module hdec_lane_clip (
    input  logic [63:0] counter_i,
    input  logic [3:0]  threshold_i,
    output logic [15:0] bits_o
);

    for (genvar bit_idx = 0; bit_idx < 16; bit_idx++) begin : gen_clip_cmp
        assign bits_o[bit_idx] = counter_i[4*bit_idx +: 4] >= threshold_i;
    end

endmodule
