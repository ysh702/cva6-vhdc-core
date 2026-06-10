# HDEC ECC Pointmul V16 Report

## Scope

Branch: `hdec-ecc-pointmul-v16`

Base: `hdec-ecc-pointmul-v15` / `dca7aad1`

Round 01 adds one scheduler-friendly GF wrapper without adding a new opcode:

- `HDEC_ECC_MUL` bit 31: `GF_MUL`, raw KPD32 multiply followed by GF(2^233) reduction.
- `HDEC_ECC_MUL` bit 32: `GF_MAC`, `acc[23:18] ^= GF_MUL(src_a, src_b)`.
- Round 02 adds `GF_SQRMAC`, `acc[17:12] ^= GF_SQR(src)`, on the `HDEC_HPERM` ECC spread path.
- Round 03 adds `GF_SQRN` / `GF_SQRNMAC`: one instruction can run `1 + extra` repeated GF squares before optional accumulator XOR.
- Round 05 compresses the internal ECC diagonal slot tracking from byte-base form to 3-bit slot form.

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
| V16 round05 | compress ECC diagonal base/pipe slots to 3-bit slot IDs | 0.326 | 213.950 | 5780 | 5308 | 472 | 2054 | `group_dist_q_reg[8]/D` |

Final kept V16 delta from V15:

- LUT: -66
- Logic LUT: -66
- LUTRAM: unchanged
- FF: +14
- Fmax: unchanged at this OOC estimate

Round 03 costs more LUT than round 02, but it is kept because repeated squaring is a high-frequency operation in ITA-style inversion. One `GF_SQRN` can replace a short software-issued square loop while still using the same HSPREAD and REDUCE datapath. Round 05 then recovers the area by changing internal diagonal tracking from a 6-bit byte base to a 3-bit slot number.

Rejected variants:

| Variant | Result | Decision |
|---|---|---|
| Reuse `hperm_nibble_q` as repeat counter | 0.304 ns WNS, 6026 LUT, 2053 FF | Rejected: more LUT and slightly worse Fmax |
| Dedicated repeat write states | 0.326 ns WNS, 5951 LUT, 2060 FF | Rejected: timing recovered, but LUT/FF higher than final round03 |
| Round04 dedicated `GF_COPY` state | 0.326 ns WNS, 6149 LUT, 2066 FF | Rejected: copying can use `ECC_ADD(src, zero)` without a new VRF copy path |
| Round06 decode-based result return | 0.326 ns WNS, 5823 LUT, 2044 FF | Rejected for now: saves 10 FF versus round05 but costs 43 LUT |
| Round06b inline result return | 0.283 ns WNS, 5923 LUT, 2039 FF | Rejected: saves FF but increases LUT and worsens timing |

## Top Timing Paths

| Rank | Class | Data delay (ns) | Logic (ns) | Route (ns) | Route ratio | Endpoint |
|---:|---|---:|---:|---:|---:|---|
| 1 | ECC control CE | 4.471 | 1.085 | 3.386 | 0.757 | `ecc_leaf_b_q_reg[0]/CE` |
| 2 | ECC control CE | 4.471 | 1.085 | 3.386 | 0.757 | `ecc_leaf_b_q_reg[10]/CE` |
| 3 | ECC control CE | 4.471 | 1.085 | 3.386 | 0.757 | `ecc_leaf_b_q_reg[11]/CE` |
| 4 | ECC control CE | 4.471 | 1.085 | 3.386 | 0.757 | `ecc_leaf_b_q_reg[12]/CE` |
| 5 | ECC control CE | 4.471 | 1.085 | 3.386 | 0.757 | `ecc_leaf_b_q_reg[13]/CE` |
| 6 | ECC control CE | 4.471 | 1.085 | 3.386 | 0.757 | `ecc_leaf_b_q_reg[14]/CE` |

After round05, the top path returns to the HDC group-distance capture path:

| Rank | Class | Data delay (ns) | Logic (ns) | Route (ns) | Route ratio | Endpoint |
|---:|---|---:|---:|---:|---:|---|
| 1 | HDC group distance capture | 4.700 | 2.246 | 2.454 | 0.522 | `group_dist_q_reg[8]/D` |
| 2 | ECC control CE | 4.572 | 1.190 | 3.382 | 0.740 | ECC control endpoint |
| 3 | HDC group distance capture | 4.600 | 2.146 | 2.454 | 0.533 | HDC group-distance endpoint |

The final V16 kept version is still comfortably above 200 MHz. The remaining worst path is not a new ECC arithmetic wall; it is the same HDC-side group-distance capture class that existed before these wrappers.

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

Final V16 cycle-count smoke test:

- raw `HDEC_ECC_MUL` 256-bit polynomial multiply: 390 cycles
- `tb_hdec_ecc_mul_cycle_count`: PASS

## Conclusion

Rounds 01, 02, 03, and 05 are worth keeping. They start V16 in the intended direction: build scalar-point-multiply-friendly compound operations by sequencing existing HDC datapaths, not by adding ECC-only datapaths. Round 02 is especially good because it adds another useful compound operation while reducing LUTs and keeping FF nearly flat relative to V15. Round 03 spends a small amount of area to reduce future ITA repeated-square instruction count. Round 05 recovers LUT by making the diagonal-control representation smaller.

What changed in the final kept V16 RTL:

- added `GF_MAC` wrapper on `HDEC_ECC_MUL`
- added `GF_SQRMAC` wrapper on ECC spread-square `HDEC_HPERM`
- added repeated square `GF_SQRN` / `GF_SQRNMAC`
- compressed ECC diagonal result slot tracking to 3-bit slot IDs
- did not add a dedicated `GF_COPY` datapath, because it was too expensive

Next V16 work should continue this pattern:

1. Add more compound field-operation steps only when they remove software-visible instruction count or reduce future point-operation scheduler complexity.
2. Prefer address/role scheduling over 256-bit data muxing.
3. Keep every new ECC control path out of the P2 popcount and VRF write timing cones.
