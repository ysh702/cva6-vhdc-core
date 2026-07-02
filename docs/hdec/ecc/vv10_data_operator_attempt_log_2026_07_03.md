# VV10 data-operator co-design attempt log

Baseline: `hdec-vv5-vector-fabric` / `93341f77`

Goal: rebuild HDEC reuse around a common data form and a matching operator form, rather than forcing ECC data through the old HDC-only operators. The lane principle from VV5 is kept: four 64-bit slices are compute slices only, without per-lane algorithm control.

## try1: 8x32 bit-matrix tile for HDC overlap and ECC diagonal parity

RTL change:

- Data structure: map the existing 4x64 payload shape into eight 32-bit rows.
- HDC mapping: HSIM/HMATCH uses row-wise bit overlap count from the matrix tile.
- ECC mapping: each 32x32 diagonal window is encoded as row masks. The same row-wise AND result provides parity for diagonal coefficients.
- Operator structure: add `hdec_bitmatrix_tile_8x32`, which computes row product, row count, full parity, low-half parity and edge parity.
- Lane control policy: no per-lane independent controller is added. ECC only changes the row data layout and group schedule.

True reuse evidence:

- HDC overlap and ECC diagonal multiplication share the same physical row-wise AND/count/parity tile.
- The old ECC local diagonal line parity functions are removed from the payload fabric.
- ECC no longer owns a separate diagonal AND/parity array in this path.

Verification:

- `xsim_hdec_ecc_diag_mul_v1`: PASS
- `xsim_hdec_hdc_full_flow_v20`: PASS
- `xsim_hdec_ecc_pmul_profile_v27`: PASS

Metrics:

| Candidate | Logic LUT | FF | Fmax MHz | PMUL cycles | ST_ECC_DIAG cycles | ST_ECC_LEAF_FOLD cycles |
|---|---:|---:|---:|---:|---:|---:|
| VV5 reference | 4675 | 1382 | ~207 | 135952 | / | / |
| try1 bit-matrix tile | 4477 | 1426 | 207.684 | 296332 | 33264 | 160380 |

Decision:

- Keep as the first VV10 checkpoint.
- It proves the target direction is feasible: a changed data form plus a matching operator can achieve real hardware reuse and still meet 200 MHz.
- The next bottleneck is no longer diagonal product generation. The dominant cost is leaf fold/writeback around the produced 32x32 leaf result.

Next direction:

- Build a fold data path that consumes bit-matrix leaf results more naturally.
- Avoid late routing through HBIND-style input muxes; previous VV9 attempts showed that this creates large control/select cones.
- Prefer small pairwise fold operators or early prefetch over full 233-bit contribution packet generation.
