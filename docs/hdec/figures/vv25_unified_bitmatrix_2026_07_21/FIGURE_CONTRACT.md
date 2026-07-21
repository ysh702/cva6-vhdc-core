# Figure 3 contract — unified bit-matrix construction

## Single conclusion

HDC and a 16×16 GF(2) ECC leaf can be normalized into the same pair of 8×32 operand matrices and therefore presented to one task-agnostic pointwise AND operation.

## Evidence path

1. HDC partitions its two 256-bit operands directly into 8×32 layouts.
2. ECC starts from ordinary 16-bit operands. The second operand is reversed once:
   \[
   b_{\mathrm{rev},t}=b_{15-t}.
   \]
3. Each bit \(a_i\) is copied to 16 pair coordinates. Pair \((a_i,b_{\mathrm{rev},t})\) belongs to diagonal
   \[
   k=i+j=15+i-t.
   \]
4. A fixed bijection packs all 256 unique \((i,j)\) pairs into the two 8×32 matrices \(\mathbf X_A^{(E)}\) and \(\mathbf X_B^{(E)}\). No pair is dropped or duplicated.
5. With \(\tau\in\{H,E\}\), both modes use the same data type and operator:
   \[
   \mathbf X_A^{(\tau)},\mathbf X_B^{(\tau)},\mathbf Q^{(\tau)}\in\{0,1\}^{8\times32},
   \qquad
   \mathbf Q^{(\tau)}=\mathbf X_A^{(\tau)}\odot\mathbf X_B^{(\tau)}.
   \]

## Visual semantics

- Black square: bit 1; open circle: bit 0.
- Steel blue: ECC index reversal and diagonal alignment.
- Muted indigo: fixed packing and the traced copies of \(a_3\).
- Muted ochre: the single shared pointwise AND and its outputs.
- The sixteen highlighted copies of \(a_3\) are position traces; their black/open bit glyphs remain the value encoding.

## Boundary with the next architecture figure

This figure ends at the 256-bit pointwise-AND result \(\mathbf Q^{(\tau)}\). It does not show POPCOUNT, XOR1, diagonal reduction, modular reduction, scheduling, or cycle timing. Those belong to the following hardware-architecture figure.
