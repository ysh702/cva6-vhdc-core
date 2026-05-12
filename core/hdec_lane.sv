// =========================================================================
// hdec_lane.sv — HDEC compatible Lane for HDC + ECC computation
// =========================================================================
// Uses hdec_xif_pkg for operation type definitions.
// ECC mode: carry chain suppressed, XOR reduction falls to LSB naturally.
// =========================================================================

import hdec_xif_pkg::*;

// ── Polymorphic Adder (ECC-aware, carry-suppressible) ──
module poly_adder #(
    parameter WIDTH = 1
)(
    input  logic             i_ecc_mode,
    input  logic [WIDTH-1:0] a,
    input  logic [WIDTH-1:0] b,
    output logic [WIDTH:0]   sum
);
    logic [WIDTH:0] carry;
    assign carry[0] = 1'b0;

    genvar i;
    generate
        for (i = 0; i < WIDTH; i++) begin : gen_adders
            ecc_full_adder u_efa (
                .ecc_mode ( i_ecc_mode ),
                .a        ( a[i]       ),
                .b        ( b[i]       ),
                .cin      ( carry[i]   ),
                .sum      ( sum[i]     ),
                .cout     ( carry[i+1] )
            );
        end
    endgenerate
    assign sum[WIDTH] = carry[WIDTH];
endmodule

// ── Main HDEC Lane ──
module hdec_lane (
    input  logic         clk,
    input  logic         rst_n,
    input  logic         i_valid,
    output logic         o_valid,
    input  hdec_op       i_op_mode,
    input  logic         i_ecc_mode,
    input  logic         i_cnt_clear,
    input  logic [1:0]   i_owner,
    output logic [1:0]   o_owner,
    input  logic [6:0]   i_threshold,
    input  logic [63:0]  i_rs1_data,
    input  logic [63:0]  i_rs2_data,
    output logic [63:0]  o_lane_data,
    output logic [6:0]   o_popcnt_val,
    output logic [63:0]  o_ecc_data
);

    // =========================================================================
    // Stage 1: XOR computation + control latching
    // =========================================================================
    logic [63:0] s1_xor_result;
    hdec_op      s1_op_mode;
    logic        s1_valid;
    logic        s1_ecc_mode_q;  // ecc_mode tracked per pipeline stage

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid   <= 1'b0;
            s1_op_mode <= HDEC_BIND;
            s1_xor_result <= 64'b0;
            s1_ecc_mode_q <= 1'b0;
        end else begin
            s1_valid <= i_valid;
            if (i_valid) begin
                s1_op_mode <= i_op_mode;
                s1_xor_result <= i_rs1_data ^ i_rs2_data;
                s1_ecc_mode_q <= i_ecc_mode;
            end
        end
    end

    // =========================================================================
    // BUNDLE accumulator array (CNT Array, time-multiplexed)
    // =========================================================================
    logic [6:0] cnt_array [63:0];
    logic [63:0] updated_binarized;

    always_comb begin
        for (int i = 0; i < 64; i++) begin
            updated_binarized[i] = ((cnt_array[i] + {6'd0, s1_xor_result[i]}) > i_threshold) ? 1'b1 : 1'b0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 64; i++) cnt_array[i] <= 6'd0;
        end else if (i_cnt_clear) begin
            for (int i = 0; i < 64; i++) cnt_array[i] <= 6'd0;
        end else if (s1_valid && s1_op_mode == HDEC_BUNDLE) begin
            for (int i = 0; i < 64; i++) begin
                cnt_array[i] <= cnt_array[i] + {6'd0, s1_xor_result[i]};
            end
        end
    end

    logic [63:0] binarized_result;
    always_comb begin
        for (int i = 0; i < 64; i++) begin
            binarized_result[i] = (cnt_array[i] > i_threshold) ? 1'b1 : 1'b0;
        end
    end

    // =========================================================================
    // Level 1.5: Combinational 64-level binary polymorphic adder tree
    // =========================================================================
    // Level 1: 64 → 32 (2-bit)
    logic [1:0] lvl1_out [31:0];
    genvar g1;
    generate for (g1 = 0; g1 < 32; g1++) begin : L1
        poly_adder #(1) u1 (.i_ecc_mode(s1_ecc_mode_q), .a(s1_xor_result[g1*2]), .b(s1_xor_result[g1*2+1]), .sum(lvl1_out[g1]));
    end endgenerate

    // Level 2: 32 → 16 (3-bit)
    logic [2:0] lvl2_out [15:0];
    genvar g2;
    generate for (g2 = 0; g2 < 16; g2++) begin : L2
        poly_adder #(2) u2 (.i_ecc_mode(s1_ecc_mode_q), .a(lvl1_out[g2*2]), .b(lvl1_out[g2*2+1]), .sum(lvl2_out[g2]));
    end endgenerate

    // Level 3: 16 → 8 (4-bit)
    logic [3:0] lvl3_out [7:0];
    genvar g3;
    generate for (g3 = 0; g3 < 8; g3++) begin : L3
        poly_adder #(3) u3 (.i_ecc_mode(s1_ecc_mode_q), .a(lvl2_out[g3*2]), .b(lvl2_out[g3*2+1]), .sum(lvl3_out[g3]));
    end endgenerate

    // Mid-Pipe (L3→L4 equator cut, ecc_mode travels with data)
    logic [3:0] lvl3_out_mid [7:0];
    logic       mid_ecc_mode_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 8; i++) lvl3_out_mid[i] <= 4'd0;
            mid_ecc_mode_q <= 1'b0;
        end else begin
            for (int i = 0; i < 8; i++) lvl3_out_mid[i] <= lvl3_out[i];
            mid_ecc_mode_q <= s1_ecc_mode_q;
        end
    end

    // 2-cycle rigid pipeline: ECC and HDC share the same mid-pipe register.
    // No bypass — ECC data takes the same 2 cycles as HDC through S1→mid→S2.
    logic [3:0] lvl4_src [7:0];
    assign lvl4_src = lvl3_out_mid;  // always from mid-pipe register
    // ecc_mode also travels through mid_ecc_mode_q for S2 carry suppression
    logic ecc_mode_l4;
    assign ecc_mode_l4 = mid_ecc_mode_q;

    // Level 4-6: use pipelined ecc_mode_l4
    logic [4:0] lvl4_out [3:0];
    genvar g4;
    generate for (g4 = 0; g4 < 4; g4++) begin : L4
        poly_adder #(4) u4 (.i_ecc_mode(ecc_mode_l4), .a(lvl4_src[g4*2]), .b(lvl4_src[g4*2+1]), .sum(lvl4_out[g4]));
    end endgenerate

    logic [5:0] lvl5_out [1:0];
    genvar g5;
    generate for (g5 = 0; g5 < 2; g5++) begin : L5
        poly_adder #(5) u5 (.i_ecc_mode(ecc_mode_l4), .a(lvl4_out[g5*2]), .b(lvl4_out[g5*2+1]), .sum(lvl5_out[g5]));
    end endgenerate

    logic [6:0] tree_final_out;
    poly_adder #(6) u6 (.i_ecc_mode(ecc_mode_l4), .a(lvl5_out[0]), .b(lvl5_out[1]), .sum(tree_final_out));

    // =========================================================================
    // Stage 2: Registered output routing
    // =========================================================================
    logic [6:0]  s2_popcnt_val;
    logic [63:0] s2_lane_data;
    logic        s2_valid;
    logic        mid_valid;
    logic [1:0]  s1_owner_q, mid_owner_q, s2_owner_q;
    hdec_op      mid_op_mode_q;     // op_mode follows pipeline
    logic [63:0] mid_xor_result_q;  // data follows pipeline

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid      <= 1'b0; mid_valid <= 1'b0;
            s2_popcnt_val <= '0; s2_lane_data  <= '0;
            s1_owner_q <= 2'd0; mid_owner_q <= 2'd0; s2_owner_q <= 2'd0;
        end else begin
            // Owner + op_mode tag tracking: s1 → mid → s2
            if (i_valid) s1_owner_q <= i_owner;
            mid_owner_q <= s1_owner_q;
            s2_owner_q <= mid_owner_q;
            mid_op_mode_q    <= s1_op_mode;
            mid_xor_result_q <= s1_xor_result;  // data follows pipeline

            mid_valid <= s1_valid;
            s2_valid <= mid_valid;
            if (mid_valid) begin
                s2_popcnt_val <= tree_final_out;
                if (mid_op_mode_q == HDEC_BIND) s2_lane_data <= mid_xor_result_q;
                else if (mid_op_mode_q == HDEC_BUNDLE) s2_lane_data <= updated_binarized;
                else s2_lane_data <= 64'b0;
            end
        end
    end

    // =========================================================================
    // Output wiring
    // =========================================================================
    assign o_valid      = s2_valid;
    assign o_owner      = s2_owner_q;
    assign o_popcnt_val = s2_popcnt_val;
    assign o_lane_data  = s2_lane_data;
    assign o_ecc_data   = (s2_owner_q == OWNER_ECC) ? s2_lane_data : {57'b0, s2_popcnt_val};

endmodule
