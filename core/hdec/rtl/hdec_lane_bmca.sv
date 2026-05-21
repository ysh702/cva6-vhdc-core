// =============================================================================
// hdec_lane_bmca.sv - Lane-local Bit Matrix Compression Array
// =============================================================================
// HDC use: HDEC_HSIM batches up to four XOR-diff rows from the same query/class
// pair. HBundle4 uses the same four-row compressor over raw HV rows.
// Missing rows are treated as zero through row_valid_q.
// =============================================================================

module hdec_lane_bmca (
    input  logic        clk_i,
    input  logic        rst_ni,

    input  logic        row_clear_i,
    input  logic        row_load_valid_i,
    input  logic [1:0]  row_load_sel_i,
    input  logic [63:0] row_load_data_i,

    input  logic        compress_valid_i,
    output logic [63:0] lo_o,
    output logic [63:0] hi_a_o,
    output logic [63:0] hi_b_o,
    output logic [8:0]  count_o,
    output logic        count_valid_o
);

    logic [63:0] row0_q, row1_q, row2_q, row3_q;
    logic [3:0]  row_valid_q;

    logic [63:0] row0_eff, row1_eff, row2_eff, row3_eff;
    logic [63:0] lo_a;
    logic [6:0]  lo_cnt, hi_a_cnt, hi_b_cnt;
    logic [8:0]  count_d, count_q;
    logic        count_valid_q;

    assign row0_eff = row_valid_q[0] ? row0_q : 64'b0;
    assign row1_eff = row_valid_q[1] ? row1_q : 64'b0;
    assign row2_eff = row_valid_q[2] ? row2_q : 64'b0;
    assign row3_eff = row_valid_q[3] ? row3_q : 64'b0;

    for (genvar bit_idx = 0; bit_idx < 64; bit_idx++) begin : gen_bmca_cell
        hdec_bmca_cell i_cell_a (
            .a_i (row0_eff[bit_idx]),
            .b_i (row1_eff[bit_idx]),
            .c_i (row2_eff[bit_idx]),
            .lo_o(lo_a[bit_idx]),
            .hi_o(hi_a_o[bit_idx])
        );

        hdec_bmca_cell i_cell_b (
            .a_i (lo_a[bit_idx]),
            .b_i (row3_eff[bit_idx]),
            .c_i (1'b0),
            .lo_o(lo_o[bit_idx]),
            .hi_o(hi_b_o[bit_idx])
        );
    end

    assign lo_cnt   = 7'($countones(lo_o));
    assign hi_a_cnt = 7'($countones(hi_a_o));
    assign hi_b_cnt = 7'($countones(hi_b_o));
    assign count_d  = {2'b00, lo_cnt} + {1'b0, hi_a_cnt, 1'b0} + {1'b0, hi_b_cnt, 1'b0};

    assign count_o       = count_q;
    assign count_valid_o = count_valid_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            row0_q        <= 64'b0;
            row1_q        <= 64'b0;
            row2_q        <= 64'b0;
            row3_q        <= 64'b0;
            row_valid_q   <= 4'b0000;
            count_q       <= 9'b0;
            count_valid_q <= 1'b0;
        end else begin
            count_valid_q <= compress_valid_i;
            if (compress_valid_i)
                count_q <= count_d;

            if (row_clear_i) begin
                row0_q      <= 64'b0;
                row1_q      <= 64'b0;
                row2_q      <= 64'b0;
                row3_q      <= 64'b0;
                row_valid_q <= 4'b0000;
            end else if (row_load_valid_i) begin
                unique case (row_load_sel_i)
                    2'd0: begin
                        row0_q        <= row_load_data_i;
                        row_valid_q[0] <= 1'b1;
                    end
                    2'd1: begin
                        row1_q        <= row_load_data_i;
                        row_valid_q[1] <= 1'b1;
                    end
                    2'd2: begin
                        row2_q        <= row_load_data_i;
                        row_valid_q[2] <= 1'b1;
                    end
                    2'd3: begin
                        row3_q        <= row_load_data_i;
                        row_valid_q[3] <= 1'b1;
                    end
                    default: ;
                endcase
            end
        end
    end

endmodule
