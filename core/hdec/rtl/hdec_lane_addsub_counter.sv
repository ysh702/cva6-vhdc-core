// =============================================================================
// hdec_lane_addsub_counter.sv - Lane-local Add/Sub/Counter Core
// =============================================================================
// Pure combinational static function block. No valid/ready/busy FSM.
// A single nibble-slice carry chain supports both HDC bundle counters and
// future ECC full-width add/sub. HDC mode gates carry at 4-bit boundaries.
// =============================================================================

module hdec_lane_addsub_counter (
    input  logic [63:0] src_a_i,
    input  logic [63:0] src_b_i,
    input  logic        mode_i,      // 1'b0: HDC_BUNDLE, 1'b1: ECC_FULL
    input  logic        op_i,        // 1'b0: ADD, 1'b1: SUB
    output logic [63:0] result_o,
    output logic        carry_o
);

    localparam logic MODE_HDC_BUNDLE = 1'b0;
    localparam logic MODE_ECC_FULL   = 1'b1;
    localparam logic OP_SUB          = 1'b1;

    logic [63:0] addend_b;
    logic [63:0] raw_sum;
    logic [16:0] carry;
    logic [63:0] hdc_sat_mask;
    logic        sub_active;

    assign sub_active = (mode_i == MODE_ECC_FULL) && (op_i == OP_SUB);
    assign addend_b = src_b_i ^ {64{sub_active}};
    assign carry[0] = sub_active;

    for (genvar n = 0; n < 16; n++) begin : gen_nibble_slice
        logic [4:0] slice_sum;

        assign slice_sum = {1'b0, src_a_i[4*n +: 4]} +
                           {1'b0, addend_b[4*n +: 4]} +
                           {4'b0, carry[n]};
        assign raw_sum[4*n +: 4] = slice_sum[3:0];
        assign carry[n+1] = (mode_i == MODE_ECC_FULL) ? slice_sum[4] : 1'b0;
        assign hdc_sat_mask[4*n +: 4] =
            ((mode_i == MODE_HDC_BUNDLE) && (|src_b_i[4*n +: 4]) && (&src_a_i[4*n +: 4])) ? 4'hF : raw_sum[4*n +: 4];
    end

    assign result_o = (mode_i == MODE_ECC_FULL) ? raw_sum : hdc_sat_mask;
    assign carry_o  = carry[16];

endmodule
