// =============================================================================
// hdec_lane_bmca.sv - Lane-local Bit Matrix Compression Array
// =============================================================================
// Phase 1 use: HDEC_HSIM batches up to three consecutive XOR-diff rows from the
// same query/class pair and returns popcount(row0)+popcount(row1)+popcount(row2).
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
    output logic [63:0] hi_o,
    output logic [7:0]  count3_o,
    output logic        count_valid_o
);

    logic [63:0] row0_q, row1_q, row2_q;
    logic [2:0]  row_valid_q;

    logic [63:0] row0_eff, row1_eff, row2_eff;
    logic [6:0]  lo_cnt, hi_cnt;
    logic [7:0]  count3_d, count3_q;
    logic        count_valid_q;

    assign row0_eff = row_valid_q[0] ? row0_q : 64'b0;
    assign row1_eff = row_valid_q[1] ? row1_q : 64'b0;
    assign row2_eff = row_valid_q[2] ? row2_q : 64'b0;

    for (genvar bit_idx = 0; bit_idx < 64; bit_idx++) begin : gen_bmca_cell
        hdec_bmca_cell i_cell (
            .a_i (row0_eff[bit_idx]),
            .b_i (row1_eff[bit_idx]),
            .c_i (row2_eff[bit_idx]),
            .lo_o(lo_o[bit_idx]),
            .hi_o(hi_o[bit_idx])
        );
    end

    assign lo_cnt   = 7'($countones(lo_o));
    assign hi_cnt   = 7'($countones(hi_o));
    assign count3_d = {1'b0, lo_cnt} + {hi_cnt, 1'b0};

    assign count3_o      = count3_q;
    assign count_valid_o = count_valid_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            row0_q        <= 64'b0;
            row1_q        <= 64'b0;
            row2_q        <= 64'b0;
            row_valid_q   <= 3'b000;
            count3_q      <= 8'b0;
            count_valid_q <= 1'b0;
        end else begin
            count_valid_q <= compress_valid_i;
            if (compress_valid_i)
                count3_q <= count3_d;

            if (row_clear_i) begin
                row0_q      <= 64'b0;
                row1_q      <= 64'b0;
                row2_q      <= 64'b0;
                row_valid_q <= 3'b000;
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
                    default: ;
                endcase
            end
        end
    end

endmodule
