# V27 ECC PMUL method/area survey and HDC operator-reuse upgrade

Date: 2026-06-13
Branch: hdec-ecc-pointmul-v27

## Local reference

Current HDEC:

- Field: `GF(2^233)`, K-233 / sect233k1-style binary curve.
- Reduction polynomial: `x^233 + x^74 + 1`.
- Full scalar point multiplication: `PMUL_CYCLES=6005`.
- Current V23/V24 area comparison:
  - HDC-only strict: 4090 LUT, 3746 Logic LUT, 344 LUTRAM, 1846 FF.
  - HDC+ECC: 6258 LUT, 5786 Logic LUT, 472 LUTRAM, 2113 FF.
  - Physical ECC addition: +2168 LUT, +2040 Logic LUT, +128 LUTRAM, +267 FF.

The physical delta is real, but the previous V24 reclassification shows that not all of it is ECC-only arithmetic. The major buckets are:

| Bucket | Delta | Interpretation |
| --- | ---: | --- |
| top/control/local memory | +851 LUT | ECC job control, PMUL/INV/reduce schedule, product storage/control |
| VRF hierarchy | +1309 LUT | shared VRF access mux/control pressure, not a standalone ECC arithmetic unit |
| P2 popcount slices | -112 LUT by hierarchy | HDC popcount body did not grow; mapping moved |
| lane shift/align | +120 LUT | HPERM/shift generalized for ECC square/spread |
| lane shift + popcount combined | +8 LUT | shared compute body is almost flat |

V24 reclassification:

- strict physical overhead: +2168 LUT, +2040 Logic LUT, +128 LUTRAM, +267 FF.
- estimated ECC hard-exclusive logic: about +851 LUT, about +723 Logic LUT, +128 LUTRAM, +267 FF.
- shared-access overhead: roughly 1300 to 1500 Logic LUT, mostly VRF/routing/control.

## Binary-field ECC PMUL survey with method and area

The table focuses on full scalar point multiplication / point multiplication cycles, not single field multiplication latency.

| # | Work | PM algorithm / curve model | Field multiplier style | Field / platform | PM cycles | Area |
| ---: | --- | --- | --- | --- | ---: | --- |
| HDEC | Current integrated HDC+ECC RTL | x-only Montgomery-style ladder over K-233-style binary curve | KPD32 diagonal/partial GF(2) multiply using HDC-friendly XOR/popcount/shift/reduce flow | `GF(2^233)`, xc7z020 OOC | 6005 | 6258 LUT, 5786 Logic LUT, 472 LUTRAM, 2113 FF for full HDC+ECC |
| 1 | Rashid et al., Electronics 2023, throughput/area ECPM | Montgomery PM, Weierstrass binary curve | bit-parallel Karatsuba modular multiplier; single adder, multiplier, square block reused for ITA | `GF(2^233)`, Virtex-7 | 7208 | 3584 slices, 13267 LUT, 1934 FF |
| 2 | Imran et al., IET CDT 2019, pipelined ECC processor | Montgomery ladder / PA-PD scheduled two-stage pipeline | digit-parallel / one-cycle modular multiplication style, higher pipeline area | `GF(2^233)`, Virtex-7 | 5634 | 5120 slices, 18953 LUT, 2764 FF |
| 3 | Optimized Flexible Accelerator over NIST Binary Fields, Applied Sciences 2023 | Montgomery ladder over NIST binary fields | digit-parallel polynomial multiplier, digit size 41, square/mul/reduction in one cycle | `GF(2^233)`, Virtex-7 | 3775 | 1998 slices, 6079 LUT, 2431 FF |
| 4 | Aljaedi et al., IEEE Access 2024, Booth polynomial multiplier | Montgomery PM, Lopez-Dahab projective flow | bit-serial Booth polynomial multiplier, about `m/2+4` cycles per multiplication | `GF(2^233)`, Virtex-7 | 174457 | 1343 slices, 3761 LUT, 1664 FF |
| 5 | Aljaedi et al., Applied Sciences 2023, area-efficient PM | Montgomery PM | bit-serial multiplier; one modular multiplier reused for square/mul | `GF(2^233)`, Virtex-7 | 716459 | 391 slices, 2346 LUT; FF not listed in main table |
| 6 | Rebeiro et al., CHES 2012, high-speed scalar multiplication | Montgomery ladder with 4-stage pipeline and data forwarding | hybrid bit-parallel Karatsuba field multiplier, one optimized full field multiplier | `GF(2^233)`, Virtex-5 | cycle count described as 1429 for `GF(2^163)`; 12.3 us reported for `GF(2^233)` at 156 MHz | 5644 slices, 18097 LUT for `GF(2^233)` |
| 7 | Khan and Benaissa, IEEE TVLSI 2017, high-speed/low-latency ECC | HPECC/LLECC variants | full-precision segmented-pipelined GF(2^m) multiplier; LLECC uses 3 multipliers, HPECC uses 1 | `GF(2^163)`/`GF(2^571)`, Virtex-7 | 1119 for `GF(2^163)` HPECC, 450 for `GF(2^163)` LLECC, 3783 for `GF(2^571)` HPECC | HPECC `GF(2^163)`: 4150 slices, 3747 LUT, 14202 FF; LLECC `GF(2^163)`: 11657 slices, 7969 LUT, 41090 FF |
| 8 | Umer et al., Electronics 2022, side-channel-resistant Binary Huff curves | unified BHC addition law | several multipliers tested: schoolbook, 2-way Karatsuba, Toom-Cook, hybrid Karatsuba, LSD-parallel | `GF(2^233)`, Virtex-7 style table | 13124 in best fast configurations | 8498 slices, 3999 LUT, 5209 FF at 88 MHz for hybrid Karatsuba; 13111 slices, 18514 LUT, 5907 FF at 164 MHz for LSD-parallel |
| 9 | Rashid et al., Applied Sciences 2023, large field-size area-constrained PM | Weierstrass PM | hybrid Karatsuba + schoolbook multiplier | `GF(2^409)`/`GF(2^571)`, Virtex-7 | 13903 / 20551 | 4439 slices, 12568 LUT, 4129 FF for `GF(2^409)`; 5683 slices, 14356 LUT, 5961 FF for `GF(2^571)` |
| 10 | Rashid et al., Electronics 2021, low-area PM | Weierstrass/Montgomery PM | shift-and-add multiplier, one low-area arithmetic path | binary field, Virtex-7 | 162673 | 491 slices, 1473 LUT, 1141 FF |

## What the survey says

The ECC-only literature has a clean area/speed trade-off:

1. Low-cycle designs use one-cycle or highly pipelined field multipliers.
   - Examples: digit-parallel, bit-parallel Karatsuba, full-precision segmented multipliers.
   - They reduce PMUL cycles, but the multiplier dominates LUT/slices and often FFs.
2. Area-first designs use bit-serial, shift-add, or Booth-style multipliers.
   - They are much smaller, but PMUL cycles rise from thousands to hundreds of thousands.
3. Several papers explicitly reuse square/multiplier hardware for Itoh-Tsujii inversion.
   - This is algorithm-level reuse inside ECC, not cross-domain HDC/ECC reuse.

HDEC sits in a different class:

- It is not trying to be an ECC-only one-cycle field-multiplier core.
- Its value is that the binary-field operations are decomposed into HDC-shaped bit-vector primitives.
- Therefore, the paper story should not imitate dedicated ECC papers by saying "we add a better ECC multiplier."
- It should say: "we expose HDC bit-vector operators as a substrate for binary-field ECC, then schedule ECC on the same foreground HDC machinery."

## ECC algorithm to HDC operator mapping

| ECC operation | Mathematical form | Current / natural HDC resource | Current extra area meaning | V27 upgrade direction |
| --- | --- | --- | --- | --- |
| Field add/sub | bitwise XOR in `GF(2)` | HBIND / boolean XOR lane path | mostly mux/control to let ECC enter XOR path | make `BV_XOR` a named shared primitive used by HBIND, HSIM diff, ECC add |
| Field square | bit interleave plus modular reduction | HPERM/shift-align/spread path plus XOR fold | lane shift/align only +120 LUT by hierarchy | turn bit-granular spread/align into HDC-visible bit-permute primitive |
| Field multiply | diagonal partial products, no carry, XOR/parity accumulation | P2 boolean + popcount parity, VRF rows, reduction fold | popcount/shift combined net +8 LUT; product storage/control remains ECC-heavy | define `BV_AND_POP_PARITY` or masked-popcount primitive that also benefits HDC masked similarity/search |
| Modular reduction | fixed linear XOR fold for `x^233+x^74+1` | XOR fold + shift/align | currently buried in top ECC control | expose as generic linear-fold primitive or microcoded XOR-fold stage |
| Inversion | Itoh-Tsujii chain of squares and multiplies | same square/multiply resources | mostly schedule/temp/control | represent as microcoded shared field-op sequence, not special datapath |
| Point add/double | fixed formula over add/square/mul | shared field-op sequence | PMUL FSM and VRF temp routing dominate | micro-op scheduler with HDC-priority/background-ECC arbitration |

## Why this helps the story

The old story:

> ECC reuses HDC hardware, so area should be small.

This is fragile because the measured physical delta is still about one third of the full HDC+ECC LUT count.

The stronger V27 story:

> HDEC upgrades HDC's bit-vector substrate into a set of reusable primitives. These primitives are useful for HDC itself, and binary-field ECC is expressed as a background program over the same primitives. The ECC-only physical addition is then mostly scheduling, VRF access, and temporary storage rather than standalone arithmetic units.

This lets us count the upgraded primitives as HDC infrastructure when they improve HDC operations:

- generalized boolean input mode: HDC masked similarity/search, ECC diagonal multiply.
- bit-granular shift/align: HDC HPERM extension, ECC square/spread/reduction.
- unified VRF uop access: HDC timing and scheduling cleanup, ECC background scheduling.
- popcount/parity primitive: HDC HSIM/HMATCH, ECC diagonal parity.
- microcoded operation sequencing: HDC multi-cycle op cleanup, ECC PMUL/ITA schedule.

## Specific optimization targets

### 1. Replace ECC-specific VRF muxes with a shared uop broker

Current issue:

- V24 hierarchy shows VRF delta +1309 LUT.
- This is the biggest shared-access tax.

Target:

- one foreground HDC request path.
- one background ECC request path.
- one shared arbitration point producing the existing VRF command bundle.
- resource mask says whether ECC may issue this cycle.

Paper benefit:

- VRF access becomes HDC scheduler infrastructure, not ECC-only mux sprawl.

### 2. Make boolean-popcount a shared primitive, not an ECC feature

Current issue:

- HDC popcount exists, but ECC diagonal multiply needs `AND -> parity`, while HDC currently uses `XOR -> popcount`.

Target:

- add a mode at the boolean front-end: XOR, AND, maybe MASKED_XOR.
- keep the popcount tree shared.
- ECC consumes parity bit; HDC consumes full count.

HDC benefit:

- masked similarity.
- sparse hypervector density/count operations.
- masked HMATCH.

Paper benefit:

- ECC multiplication maps to a HDC masked-popcount extension.

### 3. Promote square/reduction to a linear transform primitive

Current issue:

- ECC square/reduction currently looks ECC-specific.
- But binary square is a fixed bit spread, and reduction is a fixed XOR fold.

Target:

- implement `BV_LINEAR_FOLD` or `BV_SPREAD_FOLD` primitive.
- HPERM uses it for bit/nibble permutation.
- ECC uses it for square and reduction.

HDC benefit:

- richer permutation and projection operations.
- less special-case HPERM code.

### 4. Move product/reduction temporary storage into shared scratch policy

Current issue:

- ECC product bank is a clean +128 LUTRAM delta.

Target options:

- keep product LUTRAM if cycle count matters.
- or use reserved VRF scratch rows and accept more cycles.
- or make the product bank a general HDC scratchpad used by long HDC ops too.

Paper benefit:

- if it remains ECC-only, report it honestly.
- if generalized, it becomes shared long-op scratch storage.

### 5. Microcode PMUL/ITA and reuse the same sequencer style for HDC long ops

Current issue:

- PMUL control lives in wide top-level case logic.
- Previous optimization rounds showed direct RTL cleanup often remaps worse.

Target:

- encode point-add, point-double, affine-recovery, ITA steps as compact micro-ops.
- use same sequencer framework for long HDC ops or HMATCH variants.

Paper benefit:

- control is a shared long-operation engine, not ECC-only FSM bloat.

## Recommended V27 experiment order

1. Measurement-only resource mask counters.
   - no behavior change.
   - quantify HDC/ECC use of VRF_R, VRF_W, BOOL, POP, SHIFT, CNT, CLIP, RESP.
2. Shared VRF uop broker prototype.
   - goal: reduce or at least stop growing the +1309 LUT VRF access tax.
3. Boolean-popcount mode extension.
   - add AND/masked mode only if HDC tests also use it.
   - validate HDC HSIM/HMATCH timing.
4. Linear fold primitive.
   - make square/reduce look like HDC bit-permute/fold.
5. PMUL micro-op scheduler and background interleaving.
   - then measure `HDC-only`, `PMUL-only=6005`, sequential, interleaved.

## Paper wording

Use:

> Unlike ECC-only accelerators that reduce scalar-multiplication latency by instantiating one-cycle digit-parallel or bit-parallel field multipliers, HDEC decomposes binary-field arithmetic into HDC-native bit-vector primitives: XOR binding, masked boolean-popcount, bit permutation, and linear XOR folding. These primitives serve foreground HDC workloads and also execute background ECC scalar multiplication.

Avoid:

> ECC costs only 700 LUT.

Better:

> The strict physical overhead of ECC integration is +2168 LUT and +267 FF. After reclassifying HDC-native storage and compute resources, the ECC-hard-exclusive control/storage portion is about +723 Logic LUT plus +128 LUTRAM, while the largest remaining cost is shared VRF access control. V27 targets this access-control tax by replacing ECC-specific muxing with a unified HDC/ECC uop broker.

## Sources

- Rashid et al., Electronics 2023, Throughput/Area-Efficient Accelerator of ECPM over GF(2^233): https://www.mdpi.com/2079-9292/12/17/3611
- Optimized Flexible Accelerator over NIST Binary Fields, Applied Sciences 2023: https://www.mdpi.com/2076-3417/13/19/10882
- Aljaedi et al., IEEE Access 2024, Booth polynomial multiplier for GF(2^233) PM: https://pureadmin.qub.ac.uk/ws/portalfiles/portal/628046952/FPGA_Implementation_of_Elliptic-Curve_Point_Multiplication_Over_GF2233_Using_Booth_Polynomial_Multiplier_for_Area-Sensitive_Applications.pdf
- Aljaedi et al., Applied Sciences 2023, area-efficient binary ECC PM: https://www.mdpi.com/2076-3417/13/12/7018
- Rebeiro et al., CHES 2012, high-speed GF(2^m) scalar multiplication: https://scispace.com/pdf/pushing-the-limits-of-high-speed-gf-2-m-elliptic-curve-4dkhu96f2r.pdf
- Khan and Benaissa, IEEE TVLSI 2017, high-speed and low-latency ECC over GF(2^m): https://eprints.whiterose.ac.uk/id/eprint/99476/1/Final_1Revised_TVLSI_00793_2015.pdf
- Umer et al., Electronics 2022, side-channel-resistant Binary Huff curves: https://www.mdpi.com/2079-9292/11/7/1131
- Rashid et al., Applied Sciences 2023, large field-size ECC processor: https://www.mdpi.com/2076-3417/13/3/1240
- Rashid et al., Electronics 2021, low-area PM architecture: https://www.mdpi.com/2079-9292/10/21/2698

