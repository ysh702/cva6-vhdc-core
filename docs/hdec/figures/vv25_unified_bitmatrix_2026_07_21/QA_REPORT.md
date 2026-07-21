# Figure 3 v8 final QA report

Date: 2026-07-21
Status: **PASS / frozen for review**

## Mathematical verification

- Figure layout is identical, entry by entry, to `scripts/hdec/vv25_byte_equation_model.py` in the VV25 worktree.
- The fixed layout contains 256 slots and 256 unique \((i,j)\) pairs.
- Every \(a_i\) occurs exactly 16 times in \(\mathbf X_A^{(E)}\); every \(b_j\) occurs exactly 16 times in \(\mathbf X_B^{(E)}\).
- For each \(i\), its 16 packed copies occupy 16 unique coordinates, with two copies in each of the eight matrix rows.
- All 256 one-hot operand pairs were tested. Each pair produced exactly one partial product in the reference slot.
- 10,000 seeded random 16-bit operand pairs were compared bit for bit with the independent VV25 model.
- The highlighted \(a_3\) coordinates are the exact 16 coordinates returned by the frozen VV25 layout.
- \(\mathbf Q^{(H)}\) and \(\mathbf Q^{(E)}\) appear only after the single pointwise AND.

Verification command:

```powershell
python verify_fig3_v8.py
```

Final result:

```text
[FIG3_V8_QA] PASS layout=8x32 unique_pairs=256 copies_per_operand_bit=16 onehot=256 random16=10000 svg_live_text=78 svg_images=0 pdf_raster_xobjects=0 tiff=RGB@600dpi text_outside=0 text_collisions=0
```

## Export verification

| Artifact | Result |
|---|---|
| SVG | 507.109 × 283.680 pt; 78 live text nodes; zero embedded images |
| PDF | One page; vector-only; zero raster XObjects |
| TIFF | 4225 × 2364 px; RGB; 600 dpi; LZW compression |
| PNG | 2112 × 1182 px; 300 dpi |
| Review PNG | 1056 × 591 px; 150 dpi |
| Grayscale PNG | 2112 × 1182 px; the information hierarchy remains legible without color |
| Physical size | Approximately 178.9 × 100.1 mm; intended for a two-column figure |

## Layout and reviewer audit

- Zero text objects lie outside the canvas.
- Zero text-to-text collisions remain at the rendered size.
- A 150-dpi review verifies that the 16-copy \(a_3\) trace remains visible.
- The black/open bit glyphs preserve binary value semantics; the indigo halo marks position only.
- White background and the restrained steel-blue/indigo/ochre accents remain distinguishable in grayscale through geometry and line style.
- Two independent final audits found no mathematical or reviewer-facing blocking issue.

## Scope boundary

The figure verifies only data normalization, fixed packing, and the shared pointwise AND. POPCOUNT, XOR1, diagonal reduction, modular reduction, and scheduling are intentionally excluded and belong to the subsequent architecture figure.
