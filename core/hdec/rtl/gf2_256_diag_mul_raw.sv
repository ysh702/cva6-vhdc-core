// =============================================================================
// gf2_256_diag_mul_raw.sv — GF(2^256) Diagonal Popcount/Parity Raw Multiplier
// =============================================================================
// Standalone prototype: computes raw 511-bit GF(2) polynomial product of two
// 256-bit operands using 4-lane × 64-bit diagonal popcount/parity.
//
// Algorithm: P[k] = XOR over all valid i of A[i] & B[k-i]
//   - 4 lanes, each 64-bit wide
//   - One product bit per cycle (k = 0..510)
//   - Per-lane parity via XOR reduction (^v)
//   - No GF(2^256) reduction (raw product only)
//
// Latency: 512 cycles (511 compute + 1 done pulse), plus 1 start cycle
// =============================================================================

module gf2_256_diag_mul_raw (
    input  logic         clk_i,
    input  logic         rst_ni,

    input  logic         start_i,
    input  logic [255:0] a_i,
    input  logic [255:0] b_i,

    output logic         busy_o,
    output logic         done_o,
    output logic [510:0] product_o
);

    // ── FSM ──────────────────────────────────────────────────────────────────
    typedef enum logic [1:0] { IDLE, RUN, DONE_S } state_t;
    state_t state_q, state_n;

    logic [8:0]  k_q, k_n;           // product bit index: 0..510
    logic [255:0] a_reg, b_reg;
    logic [510:0] prod_q, prod_n;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            state_q <= IDLE;
            k_q     <= '0;
            a_reg   <= '0;
            b_reg   <= '0;
            prod_q  <= '0;
        end else begin
            state_q <= state_n;
            k_q     <= k_n;
            prod_q  <= prod_n;
            if (start_i && (state_q == IDLE || state_q == DONE_S)) begin
                a_reg  <= a_i;
                b_reg  <= b_i;
            end
        end
    end

    always_comb begin
        state_n = state_q;
        k_n     = k_q;
        prod_n  = prod_q;
        busy_o  = (state_q == RUN);
        done_o  = 1'b0;

        case (state_q)
            IDLE: begin
                if (start_i) begin
                    state_n = RUN;
                    k_n     = '0;
                    prod_n  = '0;
                end
            end
            RUN: begin
                prod_n[k_q] = product_bit;
                if (k_q == 9'd510) begin
                    state_n = DONE_S;
                end else begin
                    k_n = k_q + 9'd1;
                end
            end
            DONE_S: begin
                done_o = 1'b1;
                if (start_i) begin
                    state_n = RUN;
                    k_n     = '0;
                    prod_n  = '0;
                end
            end
            default: begin
                state_n = IDLE;
            end
        endcase
    end

    // ── Per-Lane Diagonal Parity Computation ─────────────────────────────────
    //
    // For product bit k, compute four 64-bit lane parities in parallel.
    // Each lane covers a 64-bit slice of A; the corresponding B indices are
    // determined by k:  bj = k - ai, valid when 0 <= bj < 256.
    //
    // lane parity = XOR-reduce (A_slice[i] & B[k - base - i])
    // product_bit = lane0 ^ lane1 ^ lane2 ^ lane3
    // =========================================================================

    function automatic logic lane_diag_parity(
        input logic [255:0] a,
        input logic [255:0] b,
        input int           base,
        input int           k
    );
        logic [63:0] v;
        int ai, bj;
        for (int t = 0; t < 64; t++) begin
            ai = base + t;
            bj = k - ai;
            if (bj >= 0 && bj < 256)
                v[t] = a[ai] & b[bj];
            else
                v[t] = 1'b0;
        end
        return ^v;
    endfunction

    wire [3:0] lane_parity;
    wire       product_bit;

    assign lane_parity[0] = lane_diag_parity(a_reg, b_reg,   0, int'(k_q));
    assign lane_parity[1] = lane_diag_parity(a_reg, b_reg,  64, int'(k_q));
    assign lane_parity[2] = lane_diag_parity(a_reg, b_reg, 128, int'(k_q));
    assign lane_parity[3] = lane_diag_parity(a_reg, b_reg, 192, int'(k_q));

    assign product_bit = ^lane_parity;
    assign product_o   = prod_q;

endmodule
