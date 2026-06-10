# HDEC ECC Pointmul V16 Round 01

## Scope

Branch: `hdec-ecc-pointmul-v16`

Base: `hdec-ecc-pointmul-v15` / `dca7aad1`

Round 01 adds one scheduler-friendly GF wrapper without adding a new opcode:

- `HDEC_ECC_MUL` bit 31: `GF_MUL`, raw KPD32 multiply followed by GF(2^233) reduction.
- `HDEC_ECC_MUL` bit 32: `GF_MAC`, `acc[23:18] ^= GF_MUL(src_a, src_b)`.
- Round 02 adds `GF_SQRMAC`, `acc[17:12] ^= GF_SQR(src)`, on the `HDEC_HPERM` ECC spread path.
- Round 03 adds `GF_SQRN` / `GF_SQRNMAC`: one instruction can run `1 + extra` repeated GF squares before optional accumulator XOR.

`GF_MAC`, `GF_SQRMAC`, and `GF_SQRNMAC` intentionally reuse the existing HBIND/XOR lane after reduction instead of adding a dedicated 256-bit ECC XOR datapath. This keeps the V16 direction aligned with the HDC/ECC resource-reuse story.

## Operand Format

For `HDEC_ECC_MUL`:

| Field | Meaning |
|---|---|
| `[5:0]` | `src_b` row |
| `[11:6]` | `src_a` row |
| `[17:12]` | temporary/raw product destination row |
| `[23:18]` | accumulator destination row for `GF_MAC` |
| `[31]` | auto reduce, produces `GF_MUL` in temporary destination |
| `[32]` | auto reduce plus accumulator XOR, produces `GF_MAC` |

For `GF_MAC`, the temporary destination must not be row 63 and the accumulator row must not overlap the temporary low/high product rows.

For `HDEC_HPERM` ECC spread mode:

| Field | Meaning |
|---|---|
| `[5:0]` | temporary square destination row |
| `[11:6]` | source row |
| `[17:12]` | accumulator destination row for `GF_SQRMAC` |
| `[18]` | spread-square layout mode |
| `[19]` | auto reduce, produces `GF_SQR` in temporary destination |
| `[20]` | auto reduce plus accumulator XOR, produces `GF_SQRMAC` |
| `[27:24]` | extra repeated squares for `GF_SQRN` / `GF_SQRNMAC`; total squares = `1 + extra` |

For `GF_SQRMAC`, the accumulator row must not overlap the temporary low/high square rows.

## Vivado OOC Result

Vivado: 2024.2

Part: `xc7z020clg400-2`

Top: `hdec_top`

Clock: 5.000 ns / 200 MHz

| Version | Change | WNS (ns) | Est. Fmax (MHz) | LUT | Logic LUT | LUTRAM | FF | Worst endpoint |
|---|---|---:|---:|---:|---:|---:|---:|---|
| V15 round02 | auto `GF_MUL` / `GF_SQR` | 0.326 | 213.950 | 5846 | 5374 | 472 | 2040 | `group_dist_q_reg[8]/D` |
| V16 round01 | add reusable `GF_MAC` wrapper | 0.326 | 213.950 | 5806 | 5334 | 472 | 2056 | `group_dist_q_reg[8]/D` |
| V16 round02 | add reusable `GF_SQRMAC` wrapper | 0.326 | 213.950 | 5753 | 5281 | 472 | 2046 | `group_dist_q_reg[8]/D` |
| V16 round03 | add `GF_SQRN` / `GF_SQRNMAC` repeated-square wrapper | 0.318 | 213.584 | 5898 | 5426 | 472 | 2050 | `ecc_leaf_b_q_reg[0]/CE` |

Round 03 delta from V15:

- LUT: +52
- Logic LUT: +52
- LUTRAM: unchanged
- FF: +10
- Fmax: -0.366 MHz, still comfortably above 200 MHz

Round 03 costs more LUT than round 02, but it is kept because repeated squaring is a high-frequency operation in ITA-style inversion. One `GF_SQRN` can replace a short software-issued square loop while still using the same HSPREAD and REDUCE datapath.

Two round03 implementation variants were tried and rejected:

| Variant | Result | Decision |
|---|---|---|
| Reuse `hperm_nibble_q` as repeat counter | 0.304 ns WNS, 6026 LUT, 2053 FF | Rejected: more LUT and slightly worse Fmax |
| Dedicated repeat write states | 0.326 ns WNS, 5951 LUT, 2060 FF | Rejected: timing recovered, but LUT/FF higher than final round03 |

## Top Timing Paths

| Rank | Class | Data delay (ns) | Logic (ns) | Route (ns) | Route ratio | Endpoint |
|---:|---|---:|---:|---:|---:|---|
| 1 | ECC control CE | 4.471 | 1.085 | 3.386 | 0.757 | `ecc_leaf_b_q_reg[0]/CE` |
| 2 | ECC control CE | 4.471 | 1.085 | 3.386 | 0.757 | `ecc_leaf_b_q_reg[10]/CE` |
| 3 | ECC control CE | 4.471 | 1.085 | 3.386 | 0.757 | `ecc_leaf_b_q_reg[11]/CE` |
| 4 | ECC control CE | 4.471 | 1.085 | 3.386 | 0.757 | `ecc_leaf_b_q_reg[12]/CE` |
| 5 | ECC control CE | 4.471 | 1.085 | 3.386 | 0.757 | `ecc_leaf_b_q_reg[13]/CE` |
| 6 | ECC control CE | 4.471 | 1.085 | 3.386 | 0.757 | `ecc_leaf_b_q_reg[14]/CE` |

The round03 top path changes from HDC popcount accumulation to an ECC control-enable path, but the data delay is still below 5 ns and the design remains above 200 MHz.

## Verification

`tb_hdec_ecc_reduce_v1` passed in Vivado xsim. The test now covers:

- direct `ECC_REDUCE`
- raw `ECC_MUL` followed by `ECC_REDUCE`
- `HSPREAD` followed by `ECC_REDUCE`
- automatic `GF_MUL`
- automatic `GF_SQR`
- automatic `GF_MAC`
- automatic `GF_SQRMAC`
- automatic `GF_SQRN`
- automatic `GF_SQRNMAC`

The testbench was also hardened so a row mismatch increments an error counter; `PASS` is printed only when the counter remains zero. This avoids a Vivado xsim quirk where `$fatal` did not stop the final display path during one failed reference-model experiment.

## Conclusion

Rounds 01, 02, and 03 are worth keeping. They start V16 in the intended direction: build scalar-point-multiply-friendly compound operations by sequencing existing HDC datapaths, not by adding ECC-only datapaths. Round 02 is especially good because it adds another useful compound operation while reducing LUTs and keeping FF nearly flat relative to V15. Round 03 spends a small amount of area to reduce future ITA repeated-square instruction count, while still clearing 200 MHz.

Next V16 work should continue this pattern:

1. Add more compound field-operation steps only when they remove software-visible instruction count or reduce future point-operation scheduler complexity.
2. Prefer address/role scheduling over 256-bit data muxing.
3. Keep every new ECC control path out of the P2 popcount and VRF write timing cones.
