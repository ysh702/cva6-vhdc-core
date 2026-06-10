# HDEC ECC Shared Ops V12 Summary

Date: 2026-06-10

Branch: `hdec-ecc-shared-ops-v12`

Base commit: `2d23b592 hdec: add shared HSPREAD square layout primitive`

Vivado: 2024.2

Part: `xc7z020clg400-2`

Clock target: 5.000 ns / 200 MHz

## RTL intent

V12 keeps the V11 shared square-layout primitive and adds two small ECC field operations that reuse existing HDEC datapaths.

| Operation | Implementation | New datapath |
|---|---|---|
| `HDEC_ECC_ADD` | One 256-bit GF(2) add/sub using the existing HBIND/XOR lane path | No |
| `HDEC_ECC_ALIGN` | One 256-bit row align/copy using the existing HPERM shift-align lane path | No |

`ECC_ALIGN` is intentionally more general than a pure move. A move is encoded as `src0=src1=src`, `lane_base=0`, `bit_shift=0`. Non-zero `lane_base` and `bit_shift` can later support reduction/square folding windows without adding a separate ECC shifter.

## Encoding notes

`HDEC_ECC_ADD` operand layout:

`{dst[17:12], src_a[11:6], src_b[5:0]}`

`HDEC_ECC_ALIGN` operand layout:

`{lane_base[25:24], bit_shift[23:18], dst[17:12], src1[11:6], src0[5:0]}`

## OOC result comparison

| Version | Added shared op | WNS ns | Fmax est MHz | Slice LUT | Logic LUT | LUTRAM | FF | BRAM | DSP | Worst endpoint |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| V11 round06 | HSPREAD square layout | 0.177 | 207.340 | 5531 | 5059 | 472 | 2024 | 0 | 0 | lane result |
| V12 round01 | ECC_ADD | 0.190 | 207.900 | 5573 | 5101 | 472 | 2045 | 0 | 0 | lane result |
| V12 round02 | ECC_ADD + ECC_ALIGN | 0.324 | 213.858 | 5511 | 5039 | 472 | 2032 | 0 | 0 | lane result |

Round02 is the kept candidate. Compared with V11, it adds two useful ECC shared operations while the final OOC point is slightly smaller in LUT and remains comfortably above 200 MHz. The apparent improvement is synthesis-shape dependent, so the key conclusion is not that the ops are free in all implementations, but that they did not create a new timing or area wall in Vivado 2024.2 OOC.

## Validation

Vivado xsim PASS:

| Test | Result |
|---|---|
| `tb_hdec_ecc_add_v1` | PASS |
| `tb_hdec_ecc_align_v1` | PASS |
| `tb_hdec_hperm_bit_align` | PASS |
| `tb_hdec_ecc_diag_mul_v1` | PASS |

## Conclusion

Keep `ECC_ADD` and `ECC_ALIGN` for V12. They fit the HDEC/ECC reuse story better than adding standalone ECC add/copy/shifter hardware:

- GF(2) add/sub maps directly to existing HBIND/XOR.
- Field copy and shift-window extraction map to existing HPERM shift-align.
- No LUTRAM, BRAM, DSP, or CARRY increase was introduced.
- 200 MHz timing remains positive in OOC.

The next ECC steps should use these two shared primitives before adding any dedicated ECC reduction or ladder-control hardware.
