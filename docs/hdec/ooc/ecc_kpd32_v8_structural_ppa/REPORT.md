# HDEC ECC KPD32 V8 structural PPA report

Vivado: 2024.2  
Part: xc7z020clg400-2  
Clock: 5.000 ns, 200 MHz OOC  
Branch: hdec-ecc-kpd32-v8-structural-ppa

## Final result

V8 final keeps 200 MHz and cuts area hard. Relative to V7 final:

| Version | Fmax est MHz | WNS ns | LUT | Logic LUT | LUTRAM | FF | BRAM | DSP | CARRY4 | ECC_MUL cycles |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| V7 final | 210.704 | 0.254 | 6458 | 5770 | 688 | 3864 | 0 | 0 | 16 | 421 |
| V8 final round11 | 202.470 | 0.061 | 5172 | 4572 | 600 | 2011 | 0 | 0 | 16 | 394 |
| Delta | -8.234 | -0.193 | -1286 | -1198 | -88 | -1853 | 0 | 0 | 0 | -27 |

The final timing wall is still the P2 popcount part register path:

| Rank | Simple path name | Data delay ns | Logic ns | Route ns | Route ratio | Slack ns |
|---:|---|---:|---:|---:|---:|---:|
| 1-8 | lane local XOR result register -> lane local 32-bit popcount part register | 4.936 | 1.105 | 3.831 | 0.776 | 0.061 |

This means the design is just over 200 MHz. The final version deliberately spends most remaining slack to reduce LUT/FF.

## Retained rounds

| Round | Main change | Fmax est MHz | WNS ns | LUT | Logic LUT | LUTRAM | FF | ECC_MUL cycles | Keep |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| V7 | Previous baseline | 210.704 | 0.254 | 6458 | 5770 | 688 | 3864 | 421 | baseline |
| 01 | Stream ECC operands through KPD32 leaves, remove 512-bit A/B shadow regs | 213.950 | 0.326 | 6398 | 5710 | 688 | 3368 | 394 | yes |
| 02 | Store ECC product in local word banks instead of 512-bit FF product | 202.470 | 0.061 | 6296 | 5352 | 944 | 2830 | 394 | yes |
| 03 | Remove unused VRF reset clear path | 202.634 | 0.065 | 5766 | 5166 | 600 | 2809 | 394 | yes |
| 04 | Share lane staging registers across HDC ops | 202.470 | 0.061 | 5587 | 4987 | 600 | 2026 | 394 | yes |
| 06 | Remove redundant lane operand gating | 202.470 | 0.061 | 5402 | 4802 | 600 | 2041 | 394 | yes |
| 07 | Use staged HPERM nibble shifter | 202.470 | 0.061 | 5393 | 4793 | 600 | 2039 | 394 | yes |
| 08 | Compact counter saturating increment logic | 202.470 | 0.061 | 5312 | 4712 | 600 | 2034 | 394 | yes |
| 11 | Use one result register for scalar responses | 202.470 | 0.061 | 5172 | 4572 | 600 | 2011 | 394 | final |

## Rejected rounds

| Round | Main change | Result | Reason |
|---|---|---|---|
| 05 | Hand-balanced popcount with explicit 4-bit groups | LUT 5810, FF 2034, Fmax 213.950 MHz | Timing improved, but LUT increased too much for this V8 goal |
| 09 | Directly instantiate lane counter/shift/clip in top | LUT 5424, FF 2029, Fmax 202.470 MHz | FF slightly fell, but LUT increased versus round08 |
| 10 | Replace ECC leaf-path ROM with path counter | LUT 5330, FF 2041, Fmax 202.470 MHz | Removed ROM report, but total LUT/FF worsened |
| 12 | Remove P4 op register and use op_q directly | LUT 5423, FF 2012, Fmax 202.470 MHz | Control muxing got worse; MUXF7 rose sharply |

## Verification

Final round11 xsim:

| Test | Result |
|---|---|
| HMATCH compare-split | PASS |
| ECC_MUL cycle count | PASS, ECC_MUL_CYCLES=394 |

The final round did not increase ECC polynomial multiplication cycles. It keeps the V8 round01 throughput improvement from 421 cycles to 394 cycles.

## Design notes

- VRF reset auto-clear was removed. Software or HDEC instructions must explicitly clear regions that require known zero contents.
- LUTRAM is 600 in the final report: 344 from VRF distributed RAM plus 256 from the ECC product word banks.
- BRAM and DSP remain 0.
- CARRY4 remains 16, so the counter rewrite did not spend extra carry resources.
- The current hard wall is still P2 popcount routing, not HMATCH, VRF writeback, ECC fold, or scalar response.

## Recommendation

Keep round11 as V8. It gives a large area reduction while preserving the 200 MHz target and improving ECC_MUL cycles. Further reductions are likely possible, but the next major tradeoff should be deliberate: either reduce LUTRAM by changing where the ECC product lives, or revisit the P2 popcount layout if we want more timing margin above 200 MHz.
