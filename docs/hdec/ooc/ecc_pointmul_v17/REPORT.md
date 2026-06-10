# HDEC ECC Pointmul V17 Report

## Scope

Branch: `hdec-ecc-pointmul-v17`

Base: `hdec-ecc-pointmul-v16` final.

Vivado: 2024.2

Part: `xc7z020clg400-2`

Top: `hdec_top`

Target: OOC 200 MHz, 5.000 ns.

V17 adds the first long ECC macro-job in the HDEC top controller: `GF_INV` over GF(2^233), using the field polynomial `x^233 + x^74 + 1`. It is started through `HDEC_ECC_STATUS` operand bit 31:

```text
[31]    = GF_INV start
[17:12] = dst
[5:0]   = src
```

`dst+1` is reserved as the existing 512-bit product/square scratch row, and `dst+2` is reserved as the ITA temporary row. The start checker rejects `dst > 61` and rejects `src == dst`, `src == dst+1`, or `src == dst+2`.

Bit 30 remains reserved for a future full point-multiply controller and currently returns `STATUS_NOT_IMPLEMENTED`. This V17 RTL therefore completes the reusable ITA inversion macro needed by scalar point multiplication, but it does not yet implement the full Montgomery LD scalar scheduler.

## What Changed

- Added a small ECC macro-job state layer around the existing GF datapaths.
- Implemented `GF_INV` with an ITA-style addition chain:
  - build `A_232 = a^(2^232 - 1)`;
  - final square gives `a^(2^233 - 2) = a^-1`.
- Reused existing HDEC/ECC resources:
  - GF square still uses HPERM spread plus GF reduce;
  - GF multiply still uses KPD32 diagonal multiply plus GF reduce;
  - copy uses the existing VRF read/write path;
  - no DSP, BRAM, or dedicated ECC multiplier was added.
- Widened the internal repeated-square counter to support long ITA square runs.
- Cleaned the `HDEC_ECC_MUL` start path so the GF_MAC operand bit no longer gates the leaf scratch register CE.
- Updated the instruction metadata for `HDEC_ECC_STATUS` to read `rs1`, matching the macro-job operand encoding.
- Added `tb_hdec_ecc_inv_v17.sv` and `xsim_hdec_ecc_inv_v17.tcl`.

## PPA Comparison

| Version | Main change | WNS (ns) | Est. Fmax (MHz) | LUT | Logic LUT | LUTRAM | FF | BRAM | DSP | Worst endpoint |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| V16 final | GF_MAC / GF_SQRMAC / GF_SQRNMAC wrappers | 0.326 | 213.950 | 5780 | 5308 | 472 | 2054 | 0 | 0 | `group_dist_q_reg[8]/D` |
| V17 final | ITA `GF_INV` macro-job | 0.255 | 210.748 | 6105 | 5633 | 472 | 2104 | 0 | 0 | `ecc_inv_step_q_reg[0]/CE` |

Delta from V16 final:

- LUT: +325
- Logic LUT: +325
- LUTRAM: unchanged
- FF: +50
- BRAM/DSP: unchanged at 0
- Estimated Fmax: -3.202 MHz, still above 200 MHz

## Timing Notes

Top paths after V17 are still control paths, not ECC arithmetic datapaths.

| Rank | Simple class | Data delay (ns) | Logic (ns) | Route (ns) | Route ratio | Endpoint |
|---:|---|---:|---:|---:|---:|---|
| 1-4 | GF_INV start/control CE | 4.534 | 1.190 | 3.344 | 0.738 | `ecc_inv_step_q_reg[*]/CE` |
| 5 | HDC popcount accumulation | 4.700 | 2.246 | 2.454 | 0.522 | `group_dist_q_reg[8]/D` |
| 6-11 | ECC destination control CE | 4.450 | 1.190 | 3.260 | 0.733 | `ecc_dst_q_reg[*]/CE` |

The final OOC still clears 200 MHz with 0.255 ns slack. The remaining risk is control routing fanout around macro-job start and ECC destination registers, not KPD32, reduction, or HDC popcount arithmetic.

## Verification

Vivado xsim:

- `tb_hdec_ecc_inv_v17`: PASS
- `GF_INV_CYCLES=6066`
- Tested input:
  - `a = 0x00000000000000000000000000000123456789abcdef0fedcba9876543210`
- Expected inverse:
  - `0x000000cd19db029a4f01607e5b121223031381bf41f0aebb3ecfa6a9ff47ea51`
- Existing `tb_hdec_ecc_reduce_v1`: PASS

Raw logs are under `xsim/`.

## Decision

Keep this V17 direction.

It is not area-free: the ITA macro-job costs about +325 logic LUT and +50 FF over V16. But it removes a very large software-visible inversion loop while still reusing HDEC's existing square, multiply, reduce, and VRF paths. The cost is mostly control and repeated-square sequencing, not a new ECC compute array.

## Next Step

The next version should add the Montgomery LD scalar scheduler on top of these field macros. The scheduler should stay microcoded/address-driven and should avoid adding a wide ECC-only datapath. Priority is to reuse:

1. `GF_ADD` for field XOR/copy;
2. `GF_MUL` and `GF_MAC` for product terms;
3. `GF_SQRN` and V17 `GF_INV` for ITA and affine recovery;
4. existing VRF slots for point/state storage.
