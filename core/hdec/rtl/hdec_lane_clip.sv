// =============================================================================
// hdec_lane_clip.sv - Lane-local HDC clip comparator/packer
// =============================================================================
// HDC use: pack the non-zero predicate of 16 bit-plane 4-bit counters into a
// 16-bit hypervector slice. Current low-area bit-plane mode fixes clip
// semantics to threshold 1; the ISA threshold field is ignored in hdec_top.
// =============================================================================

module hdec_lane_clip (
    input  logic [63:0] counter_i,
    output logic [15:0] bits_o
);

    logic [15:0] p0;
    logic [15:0] p1;
    logic [15:0] p2;
    logic [15:0] p3;

    assign p0 = counter_i[15:0];
    assign p1 = counter_i[31:16];
    assign p2 = counter_i[47:32];
    assign p3 = counter_i[63:48];

    assign bits_o = p0 | p1 | p2 | p3;

endmodule
