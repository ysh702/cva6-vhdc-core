# VV2 try9: ECC diagonal direct leaf capture

Baseline: VV1 `f9326951`

Change:
- Removed the ECC diagonal parity pipe registers.
- Captured each 32-bit diagonal parity result directly into the 64-bit leaf product register.
- Kept KPD64, Montgomery LD, ITA, HDC AND-overlap self-learning, ISA, VRF layout, and PMUL schedule unchanged.

Result:

| Metric | VV1 | try9 | Delta |
|---|---:|---:|---:|
| Total LUT | 5195 | 5150 | -45 |
| Logic LUT | 5067 | 5022 | -45 |
| LUTRAM | 128 | 128 | 0 |
| FF | 1877 | 1839 | -38 |
| Fmax | 210.393 MHz | 210.393 MHz | 0 |
| PMUL wall cycles | 190151 | 190151 | 0 |

Functional checks:
- Quick xsim regression: PASS
- ECC PMUL profile: PASS, `190151` cycles
- ECC background idle: PASS, `190152` cycles
- ECC background + HDC loop: PASS, `191217` cycles
- HDC self-learning UCI HAR: PASS, `2598/2947`, `updates=349`
- HDC self-learning WISDM: PASS, `1078/1643`, `updates=565`

Strict ECC-only proxy:

| Bucket | VV1 LUT cells | try9 LUT cells | Delta | VV1 FF | try9 FF | Delta |
|---|---:|---:|---:|---:|---:|---:|
| ECC inv/PMUL schedule | 128 | 129 | +1 | 55 | 55 | 0 |
| ECC mul/reduce datapath | 1007 | 878 | -129 | 390 | 356 | -34 |
| ECC product scratch | 134 | 134 | 0 | 128 | 128 | 0 |
| Strict ECC-only proxy total | 1269 | 1141 | -128 | 573 | 539 | -34 |

Interpretation:
- This is a structural ECC datapath optimization, not an ECC algorithm change.
- The diagonal parity product remains product-local and is still computed by the same GF(2) diagonal parity math.
- The saving comes from removing an unnecessary local pipe stage and its control, then folding the result into the leaf product at the issue point.
