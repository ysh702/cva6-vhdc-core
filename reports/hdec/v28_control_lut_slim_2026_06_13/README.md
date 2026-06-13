# V28 control LUT slim checkpoint

## Objective

Reduce ECC-specific/shared VRF control cost without changing the V27 2x point-multiply datapath behavior. The target is to preserve the 401971-cycle point-multiply wall time and 200 MHz timing while converting replicated ECC VRF address control into a shared HDC/ECC row-scheduling primitive.

## Kept change

- Replace per-bank VRF read/write addresses with one row read address and one row write address.
- Keep the per-bank write mask and per-bank write data, so HDC single-bank VWR/VRD and full-row HDC/ECC accesses still share the same VRF.
- Remove the dead `pipe1` / `S_ECC_DIAG_ACCUM` path left after the V27 2x diagonal pipeline.

## Rejected experiment

`pipe0free` derived the diagonal pack slot directly from the current slot register. It passed REDUCE, PMUL, and HDC full-flow simulation, but worsened OOC area to 6114 Logic LUT and 2095 FF. It is not kept.

## Validation

| Check | Result |
| --- | --- |
| ECC reduce xsim | PASS |
| ECC point-multiply wall xsim | PASS, 401971 cycles |
| HDC full-flow xsim | PASS |

## OOC comparison

| Version | Slice LUT | Logic LUT | LUTRAM | FF | WNS ns | Fmax MHz |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| V27 diag2 pipeline | 6754 | 6282 | 472 | 2128 | 0.082 | 203.335 |
| V28 row-VRF slim | 6521 | 6049 | 472 | 2093 | 0.243 | 210.217 |
| Delta | -233 | -233 | 0 | -35 | +0.161 | +6.882 |

Hierarchy highlights:

- `i_vrf` Logic LUT: 2911 -> 2821, delta -90.
- Top Logic LUT: 1653 -> 1500, delta -153.

## Story note

The row-address VRF interface is a shared scheduling infrastructure for HDC and ECC. ECC no longer carries replicated bank-address muxing for operations that are naturally full-row, while HDC keeps bank-select behavior through the write mask and read-bank selection.
