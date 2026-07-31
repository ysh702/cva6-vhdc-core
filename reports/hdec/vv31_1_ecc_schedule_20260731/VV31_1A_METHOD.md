# VV31-1A Cross-Leaf First-Group Preissue

## Status

`REJECTED`

## Measured entry constraint

The matched VV31-0 PMUL profile contains 1187 field multiplications. Each
field multiplication decomposes into nine 64-bit diagonal leaves. Although
the existing sub-product schedule overlaps group0 launches for the three
Karatsuba sub-products inside one leaf, every transition to the next leaf
still passes through a dedicated `S_ECC_DIAG_ISSUE` cycle.

The profile counts 10683 issue cycles:

```text
1187 field multiplications x 9 leaves = 10683 issue cycles
```

For the eight noninitial leaves of every multiplication, the current leaf's
final fold cycle already has the next A leaf in a register and the next B leaf
on the VRF return. During that cycle XOR0 merges the current contribution,
while the shared bit matrix is idle.

## Scheduling method

VV31-1A forwards the returning B half directly to the bit-matrix input and
launches the next leaf's group0 matrix in the current leaf's final fold cycle.
The state transition changes from:

```text
final fold -> dedicated diagonal issue -> capture group0
```

to:

```text
final fold plus next group0 launch -> capture group0
```

The method does not duplicate the bit matrix, XOR0, payload register, VRF
port, or field state. It uses the existing separation between contribution
folding and matrix-product generation.

## First functional result

One randomly generated legal K-233 scalar with Hamming weight 109 completed
correctly. PMUL service cycles changed from 159221 to 149725:

```text
159221 - 149725 = 9496 cycles
9496 = 1187 multiplications x 8 cross-leaf transitions
```

The 5.964% cycle reduction exactly matches the number of eliminated
noninitial-leaf issue cycles. The remaining 1187 issue cycles correspond to
the first leaf of each field multiplication and are the target of the next
separate optimization variant.

## Chapter V evidence card

1. **Computation object**  
   Consecutive 64-bit diagonal leaves inside ECC field multiplication.

2. **Direct-execution constraint**  
   A dedicated launch state separates two leaves even after both next-leaf
   operands have become available.

3. **Exploitable relation**  
   The current contribution uses XOR0 while the next group0 uses the shared
   bit matrix. The operations are data-ready and resource-compatible.

4. **Scheduling method**  
   Return-to-matrix operand forwarding and cross-leaf first-group preissue.

5. **Physical change**  
   A returned-B selection at the bit-matrix input and a final-fold transition
   directly to group0 capture.

6. **Direct evidence**  
   Four fresh random-K PMUL cases and the seven-test VV30 stage1 suite pass.
   Every PMUL requires 149725 cycles. OOC reports 4939 Logic LUT, 1281 FF,
   4 BRAM, 0 DSP, and 0.097 ns WNS.

7. **Applicability boundary**  
   The overlap applies to nonfinal transitions on the autoreduced diagonal
   path. It does not claim simultaneous use of the same matrix or XOR0 by HDC
   and ECC.

## Rejection reason and next variant

The first implementation selected the returning B value directly at the
bit-matrix input. Vivado replicated this selection into the matrix-product
fanout, increasing Logic LUT by 288 and reducing WNS from 0.328 ns to
0.097 ns. It therefore fails both the 4750-LUT and 0.20-ns stage thresholds.

The scheduling relation is still valid because the measured cycle reduction
exactly matches the eliminated states. VV31-1B retains the same schedule but
moves the operand selection away from the 256 matrix endpoints. It reads both
next-leaf operands earlier and temporarily reassigns the four existing
32-bit leaf operand registers after their current values become dead.
