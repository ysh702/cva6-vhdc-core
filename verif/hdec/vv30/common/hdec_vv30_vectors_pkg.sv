package hdec_vv30_vectors_pkg;

    localparam int VV30_SHIFT_BASIS_COVERAGE = 16 * 128;
    localparam int VV30_FUSED_MAP_COVERAGE   = 16 * 3 * 3 * 31;
    localparam int VV30_SQUARE_BASIS_COVERAGE = 233;
    localparam int VV30_SQUARE_DIRECTED_COVERAGE = 10;
    localparam int VV30_MAX_RANDOM_FIELDS    = 8192;

    // SEC 2 sect233k1 base-point order, left-padded to the 256-bit VRF row.
    localparam logic [255:0] VV30_K233_N =
        256'h000000800000000000000000000000000069d5bb915bcd46efb1ad5f173abdf;

endpackage
