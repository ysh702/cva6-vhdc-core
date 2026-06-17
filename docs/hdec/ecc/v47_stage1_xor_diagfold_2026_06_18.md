# V47 Stage 1 XOR Fusion Node: Diagonal Half Fold

## Baseline

V47 baseline report:

- Report: `reports/hdec/v47_ecc_area_share_2026_06_17/ooc_ecc_area_bucket/reports/run_summary.txt`
- LUT: 5796
- Logic LUT: 5668
- FF: 1714
- BRAM36: 4
- WNS: 0.247 ns
- Estimated Fmax: 210.393 MHz
- PMUL wall cycles: 190617

## What Was Tried

### Attempt A: five-input fused XOR with mode-fed inputs

This made one lane XOR expression handle both HDC two-input XOR and ECC five-input reduction XOR. Functionally it worked, but it needed wide input selection before the XOR tree.

Result:

- LUT: 6264
- Logic LUT: 6136
- FF: 1727
- Estimated Fmax: 210.393 MHz

Conclusion: bad. The saved XOR was smaller than the added 64-bit mux cost.

### Attempt B: shared-prefix XOR tree

This followed the GPT-style idea:

```text
t01 = in0 ^ in1
xor2 = t01
xor5 = t01 ^ in2 ^ in3 ^ in4
```

The idea is good only when HDC and ECC naturally use the same `in0/in1` lanes. In the current V47 datapath, HDC `A/B` and ECC reduction `A/B` are not the same natural stream. Forcing them into one prefix still creates wide input selection.

Result:

- LUT: 7003
- Logic LUT: 6875
- FF: 1736
- Estimated Fmax: 205.170 MHz

Conclusion: not suitable for the current V47 datapath.

### Attempt C: no-mux reduction cleanup

The old ECC reduction had five 64-bit terms, but the fifth term was either zero or occupied bit ranges that did not overlap with the fourth term. Lane 1 could merge `src3` and `src4` by wiring:

```text
{vrf_rd[2][61:8], 10'b0} ^ {54'b0, vrf_rd[3][17:8]}
= {vrf_rd[2][61:8], vrf_rd[3][17:8]}
```

Result:

- LUT: 5796
- Logic LUT: 5668
- FF: 1714
- Estimated Fmax: 210.393 MHz

Conclusion: functionally cleaner, but Vivado had already optimized this away, so area was unchanged.

### Attempt D: diagonal half fold

This is the selected node.

The lane diagonal unit originally computed two half ranges selected by `ecc_diag_half_i`:

```text
slot 0: diagonals 0..31
slot 1: diagonals 32..63
```

For a 32 by 32 binary polynomial product, the high-half coefficients can be produced from the low-half diagonal unit by reversing both inputs.

If:

```text
C[k] = XOR over i+j=k of A[i] & B[j]
```

then for reversed inputs:

```text
A_rev[i] = A[31-i]
B_rev[j] = B[31-j]
```

the low-half output of the reversed multiplication gives the high-half output of the original multiplication in reverse order. Therefore slot 1 no longer needs a second set of lane-local diagonal XOR trees. Top-level logic only reverses `A/B` before the lane and reverses the 31 useful parity bits afterward.

This keeps the real compute in the lane. The top-level work is only bit-order wiring and result placement.

Result:

- LUT: 5710
- Logic LUT: 5582
- FF: 1723
- BRAM36: 4
- WNS: 0.247 ns
- Estimated Fmax: 210.393 MHz
- PMUL wall cycles: 190617
- ECC diagonal cycles: 96228
- ECC reduction cycles: 11284

Delta vs V47 baseline:

- LUT: -86
- Logic LUT: -86
- FF: +9
- Timing: unchanged
- Cycles: unchanged

## Verification

All key simulations passed:

- `xsim_hdec_ecc_diag_mul_v1`: PASS
- `xsim_hdec_hdc_full_flow_v20`: PASS
- `xsim_hdec_ecc_reduce_v1`: PASS
- `xsim_hdec_ecc_pmul_profile_v27`: PASS

## Judgment On GPT Suggestions

### Method 1: shared-prefix XOR tree

This is architecturally good, but not with the current V47 operand flow. It needs the same natural `in0/in1` prefix to feed both HDC XOR and ECC reduction XOR. Otherwise the design pays for large input muxes, and the measured results are worse.

This method should be revisited in Stage 2, after HDC and ECC are put onto a more unified tagged pipeline. At that point the operands can arrive in fixed slots and the dual-tap story becomes much more realistic.

### Method 2: temporal-folded XOR accumulator

This is the true low-area option, but it trades cycles and adds accumulator registers/control. It is not the best first choice for the current Stage 1 goal because PMUL cycles should stay unchanged.

It becomes attractive if Stage 2 creates idle slots where ECC can spend extra internal cycles without extending visible HDC latency, or if we build an ultra-low-area configuration.

## Current Recommendation

Keep the selected diagonal half fold as the Stage 1 checkpoint. It is the only tried method that reduced area while keeping timing and cycles unchanged.

For the next attempt, do not force HDC and ECC into one XOR by adding mode muxes. The rule should be:

```text
fixed data slots, fixed outputs, no wide mode mux before the XOR tree
```

Shared-prefix XOR should wait until the Stage 2 unified pipeline makes the operand slots naturally common.
