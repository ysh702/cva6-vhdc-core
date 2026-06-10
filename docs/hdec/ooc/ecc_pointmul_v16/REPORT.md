# HDEC ECC Pointmul V16 Round 01

## Scope

Branch: `hdec-ecc-pointmul-v16`

Base: `hdec-ecc-pointmul-v15` / `dca7aad1`

Round 01 adds one scheduler-friendly GF wrapper without adding a new opcode:

- `HDEC_ECC_MUL` bit 31: `GF_MUL`, raw KPD32 multiply followed by GF(2^233) reduction.
- `HDEC_ECC_MUL` bit 32: `GF_MAC`, `acc[23:18] ^= GF_MUL(src_a, src_b)`.
- Round 02 adds `GF_SQRMAC`, `acc[17:12] ^= GF_SQR(src)`, on the `HDEC_HPERM` ECC spread path.

`GF_MAC` and `GF_SQRMAC` intentionally reuse the existing HBIND/XOR lane after reduction instead of adding a dedicated 256-bit ECC XOR datapath. This keeps the V16 direction aligned with the HDC/ECC resource-reuse story.

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

Round 02 delta from V15:

- LUT: -93
- Logic LUT: -93
- LUTRAM: unchanged
- FF: +6
- Fmax: unchanged

## Top Timing Paths

| Rank | Class | Data delay (ns) | Logic (ns) | Route (ns) | Route ratio | Endpoint |
|---:|---|---:|---:|---:|---:|---|
| 1 | P2 popcount capture | 4.700 | 2.246 | 2.454 | 0.522 | `group_dist_q_reg[8]/D` |
| 2 | P2 popcount capture | 4.600 | 2.146 | 2.454 | 0.533 | `group_dist_q_reg[7]/D` |
| 3 | TOP control | 4.566 | 1.882 | 2.684 | 0.588 | `st_q_reg[2]/D` |
| 4 | TOP control | 4.566 | 1.882 | 2.684 | 0.588 | `st_q_reg[2]_rep/D` |
| 5 | TOP control | 4.566 | 1.882 | 2.684 | 0.588 | `st_q_reg[2]_rep__0/D` |
| 6 | TOP control | 4.559 | 1.882 | 2.677 | 0.587 | `st_q_reg[3]/D` |

## Verification

`tb_hdec_ecc_reduce_v1` passed in Vivado xsim. The test now covers:

- direct `ECC_REDUCE`
- raw `ECC_MUL` followed by `ECC_REDUCE`
- `HSPREAD` followed by `ECC_REDUCE`
- automatic `GF_MUL`
- automatic `GF_SQR`
- automatic `GF_MAC`
- automatic `GF_SQRMAC`

## Conclusion

Round 01 and round 02 are worth keeping. They start V16 in the intended direction: build scalar-point-multiply-friendly compound operations by sequencing existing HDC datapaths, not by adding ECC-only datapaths. Timing still clears 200 MHz with the same estimated Fmax as V15. Round 02 is especially good because it adds another useful compound operation while reducing LUTs and keeping FF nearly flat relative to V15.

Next V16 work should continue this pattern:

1. Add more compound field-operation steps only when they remove software-visible instruction count or reduce future point-operation scheduler complexity.
2. Prefer address/role scheduling over 256-bit data muxing.
3. Keep every new ECC control path out of the P2 popcount and VRF write timing cones.
