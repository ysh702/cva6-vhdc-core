# HDEC ECC pointmul V15 OOC summary

## Scope

Branch: `hdec-ecc-pointmul-v15`

Base: `origin/hdec-ecc-reduce-v13` / `dfa1607f`

Vivado: 2024.2

Part: `xc7z020clg400-2`

Top: `hdec_top`

Clock: 5.000 ns / 200 MHz OOC

## Field and curve target

The current RTL implements the field arithmetic base for `GF(2^233)`.

- Preferred curve family: `sect233k1 / NIST K-233`
- Compatible curve family at field-arithmetic level: `sect233r1 / NIST B-233`
- Irreducible polynomial: `f(x) = x^233 + x^74 + 1`
- KPD32 raw multiply remains 256-bit slot based: `256 -> 128 -> 64 -> 32`

The RTL currently fixes only the field reduction polynomial. Curve constants
such as `a`, `b`, base point, order, and cofactor are not hardcoded yet.

## RTL changes

1. Added a registered P2 lane-compute enable so the wide lane-result capture
   path is no longer driven directly by the main FSM state bit.
2. Added low-disturbance GF wrapper modes without adding opcodes or FSM states:
   - `HDEC_ECC_MUL` with operand bit 31 set performs raw KPD32 multiply and
     then automatically reuses `ECC_REDUCE`.
   - `HDEC_HPERM` HSPREAD mode with operand bit 19 set performs square layout
     and then automatically reuses `ECC_REDUCE`.
3. Updated `tb_hdec_ecc_reduce_v1` to cover automatic `GF_MUL` and `GF_SQR`.

## OOC results

| Run | Change | WNS (ns) | Est. Fmax (MHz) | LUT | Logic LUT | LUTRAM | FF | Worst endpoint |
|---|---|---:|---:|---:|---:|---:|---:|---|
| round00 | V13 baseline | 0.106 | 204.332 | 5889 | 5417 | 472 | 2030 | `lane_result_q_reg[0][27]/D` |
| round01 | P2 lane-compute enable | 0.326 | 213.950 | 5861 | 5389 | 472 | 2040 | `group_dist_q_reg[8]/D` |
| round02 | auto GF_MUL/GF_SQR modes | 0.326 | 213.950 | 5846 | 5374 | 472 | 2040 | `group_dist_q_reg[8]/D` |

## Verification

Vivado xsim 2024.2:

- `tb_hdec_ecc_reduce_v1`: PASS, including direct REDUCE, raw MUL->REDUCE,
  SQR->REDUCE, automatic GF_MUL, and automatic GF_SQR.
- `tb_hdec_hmatch_compare_split`: PASS.
- `tb_hdec_hperm_bit_align`: PASS.

## Conclusion

V15 restores and improves the 200 MHz margin. The original fragile path was
the HDC wide lane-result capture path controlled directly by the main FSM. The
new local P2 compute enable moves the worst path to the popcount accumulation
side, while the automatic GF wrapper modes do not reduce Fmax.

This version is a good base for V16 ITA/point-operation scheduling.
