# V27 2X Diagonal Pipeline Experiment

Date: 2026-06-13
Branch: `hdec-ecc-pointmul-v27`
Tool: Vivado 2024.2
Part: `xc7z020clg400-2`
Target: 200 MHz OOC, 5.000 ns

## RTL change kept

The kept RTL version makes the KPD32 leaf diagonal stage issue two adjacent 8-bit diagonal groups per issue cycle:

- old kept V27 direct-parity path: 8 diagonal product bits per cycle, 8 issue cycles per 32x32 leaf;
- new kept V27 diag2 pipeline path: 16 diagonal product bits per issue cycle, with one pipeline drain cycle, 5 cycles per 32x32 leaf.

The implementation does not skip scalar-zero bits and does not change the Montgomery/Lopez-Dahab ladder schedule. It also does not add DSPs or a standalone GF multiplier. The acceleration comes only from duplicating the diagonal XOR/parity logic and pipelining the leaf-product pack.

## Validation

Functional regressions:

- `xsim_hdec_ecc_pmul_wall_v27`: PASS.
- `xsim_hdec_ecc_pmul_profile_v27`: PASS.
- `xsim_hdec_hdc_full_flow_v20`: PASS.

Final kept results:

| Item | V27 direct parity baseline | V27 diag2 pipeline | Delta |
|---|---:|---:|---:|
| PMUL wall cycles | 518287 | 401971 | -116316 |
| PMUL wall reduction | - | -22.44% | - |
| PMUL ADD subop cycles | 483242 | 370004 | -113238 |
| PMUL field-phase cycles | 487837 | 373951 | -113886 |
| GF multiply starts | 1436 | 1436 | 0 |
| GF multiply starts inside ADD | 1398 | 1398 | 0 |

The cycle reduction matches the intended model:

`1436 GF_MUL * 27 KPD32 leaves * 3 saved cycles/leaf = 116316 cycles saved`

## OOC comparison

| Design point | PMUL wall cycles | Slice LUT | Logic LUT | LUTRAM | FF | DSP | CARRY4 | WNS | Fmax est. | Keep? |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| V27 direct parity baseline | 518287 | 6394 | 5922 | 472 | 2118 | 0 | 20 | 0.247 ns | 210.393 MHz | Previous baseline |
| V27 unpipelined diag2 | 363199 | 6710 | 6238 | 472 | 2106 | 0 | 20 | -0.230 ns | 191.205 MHz | Reject: fails 200 MHz |
| V27 diag2 timingfix attempt | 363199 | 6719 | 6247 | 472 | 2112 | 0 | 20 | -0.196 ns | 192.456 MHz | Reject: still fails 200 MHz |
| V27 diag2 pack16 attempt | 363199 | 7539 | 7067 | 472 | 2106 | 0 | 140 | -0.262 ns | 190.042 MHz | Reject: Vivado mapped dynamic pack to carry-heavy logic |
| V27 diag2 pipeline | 401971 | 6754 | 6282 | 472 | 2128 | 0 | 20 | 0.082 ns | 203.335 MHz | Keep |

Final kept area delta versus V27 direct parity baseline:

- `+360` Slice LUT.
- `+360` Logic LUT.
- `+0` LUTRAM.
- `+10` FF.
- `+0` DSP.
- `+0` CARRY4.

## Interpretation

This is a useful microarchitecture result:

- The KPD32/diagonal algorithm really is parallelizable.
- Pure unpipelined 2X gives the best cycle count but loses the 200 MHz target.
- One-stage pipelining recovers timing while preserving most of the cycle benefit.
- The result is still HDEC-style parity/XOR hardware, not a separate ECC multiplier.

For the paper story, use the kept result as:

> A 2X pipelined diagonal-parity issue path reduces full scalar point multiplication from 518287 to 401971 cycles, a 22.44% reduction, while preserving 200 MHz timing and adding +360 Logic LUT, +10 FF, no DSP, and no extra LUTRAM.

## Next candidates

1. Try 2X diagonal pipeline plus 2X fold.
   - Current leaf still spends 4 cycles in `S_ECC_LEAF_FOLD`.
   - Reducing fold from 4 cycles to 2 cycles would save another `1436 * 27 * 2 = 77544` cycles if timing holds.

2. Try a staged 4X diagonal path.
   - A naive unpipelined 4X is likely too hard for 200 MHz.
   - A two-stage 4X could target 3 cycles per leaf diagonal stage.

3. Reduce control-path pressure.
   - Worst endpoint in the kept run is still `ecc_src_a_q_reg[0]/CE`, not the diagonal data path.
   - A future microcode/control split may recover more timing headroom for wider diagonal issue.
