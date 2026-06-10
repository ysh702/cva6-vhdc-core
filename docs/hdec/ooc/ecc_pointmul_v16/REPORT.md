# HDEC ECC Pointmul V16 Round 01

## Scope

Branch: `hdec-ecc-pointmul-v16`

Base: `hdec-ecc-pointmul-v15` / `dca7aad1`

Round 01 adds one scheduler-friendly GF wrapper without adding a new opcode:

- `HDEC_ECC_MUL` bit 31: `GF_MUL`, raw KPD32 multiply followed by GF(2^233) reduction.
- `HDEC_ECC_MUL` bit 32: `GF_MAC`, `acc[23:18] ^= GF_MUL(src_a, src_b)`.

`GF_MAC` intentionally reuses the existing HBIND/XOR lane after reduction instead of adding a dedicated 256-bit ECC XOR datapath. This keeps the V16 direction aligned with the HDC/ECC resource-reuse story.

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

## Vivado OOC Result

Vivado: 2024.2

Part: `xc7z020clg400-2`

Top: `hdec_top`

Clock: 5.000 ns / 200 MHz

| Version | Change | WNS (ns) | Est. Fmax (MHz) | LUT | Logic LUT | LUTRAM | FF | Worst endpoint |
|---|---|---:|---:|---:|---:|---:|---:|---|
| V15 round02 | auto `GF_MUL` / `GF_SQR` | 0.326 | 213.950 | 5846 | 5374 | 472 | 2040 | `group_dist_q_reg[8]/D` |
| V16 round01 | add reusable `GF_MAC` wrapper | 0.326 | 213.950 | 5806 | 5334 | 472 | 2056 | `group_dist_q_reg[8]/D` |

Delta from V15:

- LUT: -40
- Logic LUT: -40
- LUTRAM: unchanged
- FF: +16
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

## Conclusion

Round 01 is worth keeping. It starts V16 in the intended direction: build scalar-point-multiply-friendly compound operations by sequencing existing HDC datapaths, not by adding ECC-only datapaths. Timing still clears 200 MHz with the same estimated Fmax as V15, LUTs slightly decrease, and the only visible area cost is a small FF increase for accumulator address and mode tracking.

Next V16 work should continue this pattern:

1. Add more compound field-operation steps only when they remove software-visible instruction count or reduce future point-operation scheduler complexity.
2. Prefer address/role scheduling over 256-bit data muxing.
3. Keep every new ECC control path out of the P2 popcount and VRF write timing cones.
