package hdec_vv31_vectors_pkg;

    localparam int VV31_MAX_SCALARS          = 64;
    localparam int VV31_MAX_EPISODES         = 128;
    localparam int VV31_TRAINING_PER_EPISODE = 4;
    localparam int VV31_MAX_TRAINING_VECTORS =
        VV31_MAX_EPISODES * VV31_TRAINING_PER_EPISODE;

    localparam logic [255:0] VV31_K233_N =
        256'h0000008000000000000000000000000000069d5bb915bcd46efb1ad5f173abdf;

    localparam logic [5:0] VV31_ECC_POINT_X_ROW = 6'd0;
    localparam logic [5:0] VV31_ECC_POINT_Y_ROW = 6'd1;
    localparam logic [5:0] VV31_ECC_SCALAR_ROW  = 6'd2;
    localparam logic [5:0] VV31_ECC_OUT_X_ROW   = 6'd4;
    localparam logic [5:0] VV31_ECC_OUT_Y_ROW   = 6'd5;

    // HDC slot 2 occupies rows 8..11, slot 3 occupies rows 12..15.
    localparam logic [3:0] VV31_HDC_HV2_SLOT = 4'd2;
    localparam logic [3:0] VV31_HDC_HV3_SLOT = 4'd3;

    localparam logic [5:0] VV31_HDC_ACC0_FIRST_ROW = 6'd16;
    localparam logic [5:0] VV31_HDC_ACC0_LAST_ROW  = 6'd31;
    localparam logic [5:0] VV31_ECC_INTERNAL_FIRST = 6'd32;
    localparam logic [5:0] VV31_ECC_INTERNAL_LAST  = 6'd63;

endpackage
