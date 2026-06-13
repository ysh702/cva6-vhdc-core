# V27 fixed-window W=4 PMUL feasibility

Date: 2026-06-13
Branch: `hdec-ecc-pointmul-v27`

This note checks whether a fixed-base `W=4` scalar multiplication path can be
added on top of the current RTL, and whether it helps the cycle story without
breaking the HDC/ECC resource-sharing story.

## Current baseline

Current RTL implements a Lopez-Dahab/Montgomery-ladder style x-only PMUL over
`GF(2^233)` with reduction polynomial:

`f(x) = x^233 + x^74 + 1`

Measured after the accepted direct diagonal-parity bypass:

| Item | Value |
|---|---:|
| PMUL wall cycles | 518287 |
| PMUL ADD subop cycles | 483242 |
| PMUL DBL subop cycles | 15608 |
| affine/recovery cycles | 19420 |
| GF_MUL starts | 1436 |
| GF_MUL starts in ADD | 1398 |
| SQR starts | 2097 |

Important derived numbers:

- The ADD part is exactly `233 * 2074` cycles.
- The ADD part uses exactly `233 * 6 = 1398` GF multiplications.
- The DBL part is about `67` cycles per scalar bit.
- Therefore the dominant cost is not scalar-bit scanning itself; it is doing a
  full differential ADD for every one of the 233 scalar bits.

## What W=4 changes

For a fixed-base signing path, a width-4 table can pre-store:

`T[d] = d * G`, for `d = 1..15`

Then a 233-bit scalar can be scanned as `ceil(233 / 4) = 59` windows:

1. double the accumulator 4 times;
2. add the selected affine table point `T[d]`;
3. repeat for all windows.

This keeps the lower-level GF operations. The Karatsuba-plus-diagonal GF_MUL is
still needed. W=4 is a top-level point-multiplication reduction: it reduces how
many point additions call the multiplier.

## VRF capacity check

The VRF has 64 entries. Current PMUL reserves the upper half as scratch:

| Range | Current use |
|---|---|
| `0..31` | software-visible HDC/ECC inputs, scalar, result, HDC data |
| `32..63` | PMUL internal workspace: `R0/R1/T0..T9` |

Each affine table point needs two VRF entries: one `x` row and one `y` row.
The table `T[1]..T[15]` therefore needs `15 * 2 = 30` entries.

| Layout | Entries needed in lower VRF | Fits? | Notes |
|---|---:|---|---|
| W=4 table only, `T[1]..T[15]` | 30 | yes | leaves only 2 lower entries |
| W=4 table + scalar | 31 | yes | leaves only 1 lower entry |
| W=4 table + scalar + X/Y result | 33 | no | cannot fit entirely in `0..31` |
| W=4 table + scalar, result written to PMUL scratch after finish | 31 | barely | would need a new command/layout rule |
| W=3 table `T[1]..T[7]` + scalar + X/Y result | 17 | yes | much safer VRF coexistence |
| W=4 odd/signed table `T[1],T[3],...,T[15]` + scalar + result | 19 | yes | needs signed recoding and side-channel policy |
| W=4 table in ROM/BRAM + scalar/result in VRF | 3 | yes | better for fixed `G`, but adds separate storage |

Conclusion: plain unsigned W=4 can only fit in the current VRF if the result is
allowed to land in the scratch region or if the table is not kept in lower VRF.
It is not a good fit for the HDC/ECC interleaving story because occupying
`0..29` with ECC table rows leaves almost no room for live HDC vectors.

For the paper story, the cleanest W=4 option is a fixed-base `G` table outside
the shared VRF, or a W=3/odd-W=4 table in VRF.

## Why current ADD cannot be reused directly

The existing `ECC_PMUL_SUB_ADD` is a differential x-only add used by the
Montgomery ladder. It assumes:

- two ladder points `R0` and `R1`;
- a known difference point `P`;
- output selection controlled by the current scalar bit.

Fixed-window multiplication needs a normal/mixed point addition:

`Q <- Q + T[d]`

where `Q` is the running accumulator and `T[d]` is an affine table point. This
needs a new PMUL subop. Reusing `ECC_PMUL_SUB_ADD` as-is would be algorithmically
wrong, even if it synthesizes.

## Cycle estimate

Use the current measured costs as a conservative model:

- ladder differential ADD proxy: `2074` cycles;
- ladder DBL proxy: `67` cycles;
- final affine/recovery proxy: about `19000..20000` cycles.

For unsigned W=4:

- windows: `59`;
- doublings: `58 * 4 = 232` if the first window initializes the accumulator;
- point additions: fixed-schedule `59`.

Estimated cycles:

| Assumption for mixed/window add | Estimate |
|---|---:|
| optimistic, 6 GF_MUL-like add | `~158k` cycles |
| moderate, 8 GF_MUL-like add | `~199k` cycles |
| pessimistic, 10 GF_MUL-like add | `~240k` cycles |

Against the current `518287` cycles, W=4 should save about `278k..360k` cycles,
or roughly `54%..69%`, if the mixed-add FSM is implemented correctly.

W=3 is less aggressive but easier to store:

- windows: `ceil(233 / 3) = 78`;
- estimated with the 6-GF_MUL add proxy: about `197k..210k` cycles.

This is still a large reduction while keeping enough lower VRF space for HDC
state.

## Karatsuba-plus-diagonal GF_MUL parallelism

W=4 reduces the number of point additions. GF_MUL remains the hot primitive
inside every point addition, so the current Karatsuba-plus-diagonal multiplier
is still important.

Current multiplier shape:

- three-level Karatsuba decomposition, `3^3 = 27` KPD32 leaf products;
- after parity bypass, each leaf emits 8 diagonal parity groups directly;
- each GF_MUL still spends many cycles traversing all 27 leaves and folding the
  product.

Candidate next experiments:

| Experiment | Expected cycle effect | Area/story risk |
|---|---:|---|
| issue 2 diagonal slots per leaf cycle | save about `4 * 27 = 108` cycles per GF_MUL | moderate LUT increase, likely measurable |
| fold/write two product word pairs per cycle | save about `2 * 27 = 54` cycles per GF_MUL | moderate; touches product RAM/writeback |
| process 2 KPD32 leaves in parallel | potentially save about half of leaf traversal | higher LUT/FF, less reuse-friendly |
| fully unroll larger multiplier | largest speedup | probably too much area for this paper story |

On the current ladder profile, a 108-cycle GF_MUL reduction would save up to
`1436 * 108 = 155088` cycles. Under W=4 the GF_MUL count would be much lower,
but it would still improve the final number.

Recommended order:

1. Add a true fixed-base window PMUL command and mixed-add subop.
2. Prefer ROM/BRAM table or W=3/odd-W=4 if HDC interleaving must stay active.
3. After the algorithmic reduction is correct, try 2-diagonal-slot GF_MUL issue
   as the first low-risk multiplier parallelism experiment.

## Implementation sketch

New command/mode:

- Keep existing arbitrary-point PMUL ladder unchanged for correctness and
  constant-time fallback.
- Add a fixed-base `PMUL_G_W4` mode for signing/non-secret-base acceleration.

New state:

- window index: `0..58`;
- current 4-bit digit;
- accumulator infinity flag;
- table source `T[d]`;
- new subops: `WINDOW_DBL4`, `WINDOW_SELECT`, `WINDOW_MIXED_ADD`,
  `WINDOW_FINAL_AFFINE`.

Storage options:

- fixed `G` table in constant ROM: best for VRF/HDC coexistence;
- external preload into lower VRF: simplest to prototype but bad for
  interleaving;
- W=3 lower-VRF table: safer prototype if ROM is postponed.

The existing field multiply, square/spread, reduction, inversion, and HBIND/XOR
paths should be reused. W=4 should not replace the Karatsuba-plus-diagonal
multiplier; it should call it fewer times.
