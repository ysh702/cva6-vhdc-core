# HDEC ECC PMUL V19 Fast Non-Constant-Time Snapshot

## Scope

Branch: `hdec-ecc-pointmul-v19`

Base: `hdec-ecc-pointmul-v18` / `92d38de5`

Purpose: preserve the fast PMUL experiment that reduces cycles by caching scalar words and skipping no-effect ladder work.

Important security note: this snapshot is **not constant-time**. It skips leading-zero scalar bits and can therefore leak scalar shape through timing. Keep it as a performance/architecture reference, not as the secure scalar-multiply baseline.

## Changes

- Reused the existing `b_q` register as a 64-bit scalar-word cache.
- Changed PMUL scalar handling from "read scalar VRF row every bit" to "read scalar row only when crossing a 64-bit word boundary".
- Skipped leading-zero ladder work while `R0` is still point-at-infinity.
- Skipped the final unused double when the last scalar bit already placed the result in `R0`.

## Results

| Version | PMUL cycles | WNS | Estimated Fmax | Slice LUT | Logic LUT | LUTRAM | FF | BRAM | DSP |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| V18 baseline | 18414 | 0.219 ns | 209.161 MHz | 6714 | 6242 | 472 | 2158 | 0 | 0 |
| V19 round04 | 13676 | 0.326 ns | 213.950 MHz | 6727 | 6255 | 472 | 2216 | 0 | 0 |
| Delta | -4738 | +0.107 ns | +4.789 MHz | +13 | +13 | 0 | +58 | 0 | 0 |

Cycle reduction:

```text
18414 - 13676 = 4738 cycles
4738 / 18414 = 25.7%
```

## Validation

Vivado xsim PMUL test:

```text
PMUL_CYCLES=13676
[HDEC_ECC_PMUL_V18] PASS
```

Vivado OOC 200 MHz:

```text
wns=0.326
worst_data_delay_ns=4.700
fmax_est_mhz=213.950
top_endpoint=group_dist_q_reg[8]/D
```

## Raw Artifacts

Raw reports and logs are under:

```text
docs/hdec/ooc/ecc_pointmul_v19_fast_nonconstant/raw/
```

