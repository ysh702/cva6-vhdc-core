# V43 ECC/HDC area co-optimization checkpoint

Date: 2026-06-17
Branch: `hdec-ecc-pointmul-v43`

## Goal

V43 continues from V42 with the rule that cycle count must not increase and the 200 MHz OOC target must still pass. The main target is area: reduce LUTs by using algorithm knowledge to remove duplicated hardware control, instead of only rewriting RTL syntax.

## Current ECC math model

The ECC field is the binary field GF(2^233), with reduction polynomial:

`f(x) = x^233 + x^74 + 1`

In this field:

- Addition/subtraction is bitwise XOR.
- Multiplication is polynomial multiplication over GF(2), then reduction by `f(x)`.
- Squaring is a spread operation: insert zeros between source bits, then reduce.
- Reduction folds high terms back because `x^233 = x^74 + 1`, so every high bit contributes to two lower positions by XOR.

The current RTL implements multiplication as a low-area diagonal/Karatsuba-style flow:

1. Load 64-bit lane words from the VRF.
2. Compute 32-bit diagonal parity pieces in the shared lane XOR/parity path.
3. Accumulate leaf products and fold them into four product-pair slots.
4. Run the shared lane reduction XOR path for GF(2^233) modular reduction.
5. Use the same VRF/lane resources for HDC operations when ECC is not occupying them.

This means the important hardware story is still: XOR is the common math operator for HDC bind/similarity/diff and binary-field ECC add/multiply/reduce.

## Accepted V43 RTL changes

### 1. Narrow diagonal lane output

Algorithm view:
Each ECC diagonal issue produces two 16-bit halves over two slots. The old lane interface exposed `diag_parity` and `diag_pair_parity` separately, even though the caller only needs the packed 32-bit result.

Hardware change:
Each lane now emits one 8-bit diagonal parity bundle controlled by one half tag. Top-level packing builds the 32-bit diagonal result from four lanes.

Effect:
This reduces interface/control noise and makes the lane output match the algorithm's "two halves, one packed result" model. OOC is area-neutral by itself, but it simplifies the later control story.

### 2. Remove dead lane valid and dead counter clip comparator

Algorithm view:
The lane datapaths are combinational resources selected by the uop tag. The per-lane `cnt_valid`, `shift_valid`, and `clip_valid` signals did not gate the arithmetic result. The counter array also computed an unused clip comparison.

Hardware change:
Removed those valid ports/signals and the unused comparator from `hdec_cnt_array`.

Effect:
This is mostly RTL hygiene. Vivado already optimized most of it, so OOC is neutral, but the design now better reflects the real lane contract: top chooses which result to capture; the lane just computes candidate results.

### 3. ECC square/spread destination alias

Algorithm view:
For ECC macro jobs, the square/spread destination is already `ecc_dst`. The previous RTL also wrote the same value into `hperm_dst_base`, then later used `hperm_dst_base` to write the spread result and start reduction. That is the same address carried twice.

Hardware change:
For ECC macro-job spread, writeback now uses `ecc_dst` through `hspread_dst_base`. `hperm_dst_base` remains the owner for normal HDC HPERM and standalone spread operations.

Effect:
This removes several ECC-only assignment sources from the `hperm_dst_base` control mux. This is the V43 change that actually reduced area.

## Rejected candidates

| Candidate | Algorithm idea | Result | Decision |
|---|---|---:|---|
| `fold_first_mux` | First fold can write contribution directly instead of `0 XOR contribution`. | 6341 LUT, 2016 FF | Rejected; +5 LUT vs V42. |
| `hperm_window` | Convert 8 repeated HPERM word picks into one 5-word sliding window. | 6483 LUT, 2013 FF | Rejected; centralized window increased top/VRF muxing. |
| `hspread_src_late` | Delay `ecc_src_a` assignment until spread completes. | 6354 LUT, 2015 FF | Rejected; less source code assignment produced worse synthesized mux sharing. |
| `shift_two_stage` | Split lane dynamic shift into smaller stages. | 7516 LUT | Rejected; barrel shift got much larger. |
| `reduce_share_bool` | Route ECC reduce through the normal bool/XOR sources. | 6548 LUT | Rejected; added control mux cost exceeded reuse benefit. |
| `pair_regs` | Implement product-pair buffer as registers instead of distributed RAM. | 6470 LUT, 2538 FF | Rejected; FF cost too high. |

The main lesson is that "algorithmically fewer assignments" only helps when it removes a real hardware mux input. If it forces an earlier global selection or breaks Vivado's local sharing, area can rise.

## Final V43 OOC data

OOC command:

```powershell
& E:\Vivado\Vivado\2024.2\bin\vivado.bat -mode batch `
  -source scripts/hdec/ooc_hdec_p2_popcount_local_keep_v1.tcl `
  -tclargs E:\HDEC\cva6-vhdc-core\tmp\hdec_v15_pointmul_worktree `
  reports/hdec/v43_final_2026_06_17/ooc_v43_final 5.0 main
```

Final OOC result:

| Version | Slice LUT | Logic LUT | LUTRAM | FF | WNS | Estimated Fmax |
|---|---:|---:|---:|---:|---:|---:|
| V42 checkpoint | 6336 | 5864 | 472 | 2012 | 0.250 ns | 210.526 MHz |
| V43 final | 6330 | 5858 | 472 | 2009 | 0.250 ns | 210.526 MHz |

The gain is small but real: -6 Slice LUT, -6 Logic LUT, -3 FF, with unchanged PMUL cycles and unchanged 200 MHz timing margin.

## Final functional checks

All checks passed under `reports/hdec/v43_final_2026_06_17`:

- `xsim_hdec_ecc_pmul_profile_v27`: PASS, `PMUL_PROFILE_WALL_CYCLES=183793`
- `xsim_hdec_ecc_diag_mul_v1`: PASS
- `xsim_hdec_ecc_reduce_v1`: PASS
- `xsim_hdec_hdc_full_flow_v20`: PASS

PMUL cycle split:

| Stage | Cycles |
|---|---:|
| ECC diagonal | 96228 |
| ECC leaf fold | 42768 |
| ECC reduce | 11284 |
| HSPREAD | 3266 |
| ECC uop | 4949 |

## Next useful direction

The biggest remaining areas are not the accepted V43 cleanup itself:

- VRF/read/writeback remains about 2967 LUT.
- Lane dynamic shift-align remains about 763 LUT across four lanes.
- Top control remains about 1808 LUT.

Future optimization should keep using the same algorithm-to-hardware rule:

1. Only merge signals when the algorithm proves they are the same live value.
2. Avoid centralizing a local lane choice unless it removes more muxes than it creates.
3. Treat Vivado OOC as the judge; several apparently cleaner algorithm rewrites were worse after synthesis.
