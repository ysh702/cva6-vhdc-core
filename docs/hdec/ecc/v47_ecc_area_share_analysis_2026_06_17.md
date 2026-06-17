# V47 ECC-exclusive area share analysis

Date: 2026-06-17

Base branch: `hdec-ecc-pointmul-v46`

Purpose: after the V46 BRAM VRF change, estimate how much area is still ECC-exclusive, and how much is now shared HDC/ECC fabric.

## Method

The analysis uses a strict name-based lower-bound classification after OOC synthesis:

`reports/hdec/v47_ecc_area_share_2026_06_17/ooc_ecc_area_bucket`

Rules:

- Count obvious `ecc_*` logic as ECC-exclusive.
- Count `ecc_product_pair` as ECC-exclusive scratch storage.
- Count `i_vrf` as shared VRF storage/fabric.
- Count `gen_lane[*].i_lane` as shared lane operators.
- Count popcount, shift/spread, and VRF top write/read control as shared or non-ECC-exclusive.
- Leave generic state-machine and host register logic in `unattributed_top_control` unless its cell name clearly proves ECC ownership.

This is intentionally conservative. It does not charge shared lane/VRF resources to ECC just because ECC uses them. It also does not claim generic FSM decode as ECC-exclusive unless Vivado kept an ECC name on the cell.

## OOC check

The V47 area-bucket synth reproduces the V46 selected OOC result:

| Metric | Value |
| --- | ---: |
| WNS | 0.247 ns |
| Fmax estimate | 210.393 MHz |
| Total LUT | 5796 |
| Logic LUT | 5668 |
| LUTRAM | 128 |
| FF | 1714 |
| BRAM36 | 4 |

Hierarchy:

| Bucket | Total LUT | Logic LUT | LUTRAM | FF | BRAM36 | Meaning |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `hdec_top` total | 5796 | 5668 | 128 | 1714 | 4 | whole OOC design |
| top-level bucket | 1806 | 1678 | 128 | 1409 | 0 | control, ECC scratch, scalar/front-end state |
| four lanes | 767 | 767 | 0 | 305 | 0 | shared HDC/ECC operators |
| `i_vrf` | 3223 | 3223 | 0 | 0 | 4 | shared BRAM VRF implementation |

## Strict ECC-exclusive result

Raw cell-bucket count:

| Strict ECC bucket | LUT cells | FF cells | LUTRAM cells | Notes |
| --- | ---: | ---: | ---: | --- |
| ECC inverse / point-multiply schedule | 148 | 74 | 0 | point-multiply, inverse, ECC job state |
| ECC multiply / reduce datapath | 1000 | 382 | 0 | diagonal/leaf/fold/reduce named logic |
| ECC product scratch | 195 | 0 | 256 | `ecc_product_pair` distributed scratch |
| Strict ECC total | 1343 | 456 | 256 | name-proven ECC-only logic |

Because Vivado logical LUT cells do not map one-to-one to final physical LUT utilization, the useful normalized estimate is:

- ECC named logic is `1343 / 2015 = 66.65%` of the top-level logical LUT-cell bucket after excluding lane and VRF hierarchy.
- Top-level physical logic LUT is `1678`, so strict ECC named logic is about `1118` physical logic LUT.
- `ecc_product_pair` accounts for the top-level `128` physical LUTRAM.
- Therefore strict ECC-exclusive LUT area is about `1118 + 128 = 1246` LUT-equivalent resources.

Final ratio:

| Quantity | Estimate | Ratio |
| --- | ---: | ---: |
| strict ECC-exclusive LUT-equivalent | about 1246 | about 21.5% of total LUT 5796 |
| strict ECC-exclusive logic LUT only | about 1118 | about 19.7% of logic LUT 5668 |
| strict ECC-exclusive FF | 456 | 26.6% of FF 1714 |
| ECC-exclusive BRAM | 0 | 0% |
| shared VRF BRAM | 4 RAMB36 | shared, not ECC-exclusive |

## What this means

The V46/V47 structure has already moved the largest memory resource out of the ECC-only story:

- The 4 BRAM36 VRF is shared HDC/ECC storage.
- The lane operators are shared HDC/ECC compute.
- ECC no longer owns a large standalone reduction XOR outside the shared lane story.

The remaining ECC-exclusive cost is concentrated in three places:

1. `ecc_product_pair`: a small distributed scratch RAM for partial products.
2. ECC diagonal/leaf/fold/reduce named datapath.
3. ECC point-multiply and inverse schedule/control registers.

So the next high-value area work should not target BRAM or lane sharing first. It should target:

- replacing or shrinking `ecc_product_pair`;
- reducing the named ECC fold/reduce datapath;
- compressing ECC schedule/control state without exploding mux decode;
- moving more deterministic ECC bookkeeping into compact table/tag encodings only if the resulting decode is smaller than the current named logic.

The current strict conclusion is:

> In the BRAM-native V46 design, ECC-exclusive LUT-equivalent area is roughly one fifth of the total design, while the largest blocks, VRF and lanes, are now shared infrastructure rather than ECC-only area.

This is a good architectural position: future reductions should focus on ECC control/product scratch, not on arguing that the shared VRF/lane cost belongs to ECC.
