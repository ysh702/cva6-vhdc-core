// =========================================================================
// ecc_full_adder.sv — 1-bit full adder with ECC mode control
// When ecc_mode = 1, carry_out is forced to 0 (GF(2) polynomial arithmetic).
// =========================================================================

module ecc_full_adder (
    input  logic ecc_mode,
    input  logic a,
    input  logic b,
    input  logic cin,
    output logic sum,
    output logic cout
);
    logic half_sum;
    logic half_carry;

    assign half_sum   = a ^ b;
    assign half_carry = a & b;

    assign sum = half_sum ^ cin;

    // ECC mode: suppress carry propagation (GF(2) addition = XOR)
    assign cout = ecc_mode ? 1'b0 : (half_carry | (half_sum & cin));
endmodule
