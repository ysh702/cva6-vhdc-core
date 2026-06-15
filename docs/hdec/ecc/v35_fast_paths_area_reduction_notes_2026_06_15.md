# V35 Fast ECC Paths: Area-Reduction Notes

This note records follow-up ideas for the three high-speed V35 trials that
reduced scalar-multiplication cycles strongly but exceeded the current
small-area target.

## Current Selected V35 RTL

V35 selects the point-add formula change:

```text
ADD 5M cross-product + selected double XZ
```

The point-add path now keeps `T0 = X0*Z1` and `T1 = X1*Z0`, computes the
add cross product as `T6 = T0*T1`, and computes only the one `X*Z` value that
the following point-double step still needs. This keeps the next double valid
while reducing point-add field multiplications from 6 to 5.

Measured result:

| Item | Value |
| --- | ---: |
| PMUL cycles | 341624 |
| Cycle delta vs baseline | -60347 |
| Logic LUT | 5921 |
| Logic LUT delta | +34 |
| FF | 1802 |
| Fmax | 210.217 MHz |

This is currently the best small-area tradeoff.

## High-Speed Trials That Need Area Reduction

| Trial | PMUL cycles | Cycle delta | Logic LUT | LUT delta | FF | Fmax MHz | Main issue |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Leaf compute/fold overlap | 252627 | -149344 | 6235 | +348 | 1954 | 210.393 | Extra buffering/control is too large |
| KPD64 64-bit leaf | 221035 | -180936 | 6946 | +1059 | 1960 | 193.761 | 64-bit diagonal logic is too wide and timing fails |
| D4 digit-serial modular multiplier | 126259 | -275712 | 7798 | +1911 | 2537 | 202.224 | 256-bit local state and wide masked XOR network are too large |

## 1. Leaf Compute/Fold Overlap

The measured overlap version is fast because it reduces the leaf initiation
interval from roughly 9 cycles toward 4 cycles. The area increase comes from
making the leaf boundary more independent: extra leaf product storage, fold
valid bookkeeping, and wider control around the product accumulator.

Lower-area directions:

1. Try a one-entry fold latch instead of ping-pong storage.
   The goal is to hold only the completed 64-bit leaf product and its path mask,
   not a full second leaf context. This may recover part of the overlap benefit
   with much less FF cost.

2. Fold only into the existing `ecc_product_pair` RAM write port.
   The rejected dual-fold/prefetch variants grew because they made the product
   accumulator too register-heavy. A viable version should keep one physical
   write path and overlap only control/operand-load bubbles.

3. Add partial overlap first.
   Full overlap gives the best cycle count but costs +348 LUT. A smaller target
   is to hide one or two of the four fold cycles under next-leaf operand reads.
   That would not reach the 252k-cycle result, but it may beat the diagonal tail
   bypass with less area.

4. Avoid inserting enum states in the middle of the state list.
   Appending states preserves profile counters and keeps the verification
   story cleaner.

Expected useful target:

```text
PMUL cycles: 300k to 330k
Logic LUT delta: under +80 if the fold latch is kept narrow
```

## 2. KPD64 64-Bit Leaf

KPD64 is attractive because it changes the multiplication structure from
27 leaves to 9 leaves. The failed area/timing point comes from computing
16 diagonals per cycle over 64-bit operands. That doubles the local AND/XOR
width and creates the worst endpoint at the diagonal parity register.

Lower-area directions:

1. Use KPD64 with 8 diagonals per cycle instead of 16.
   This doubles the per-leaf diagonal loop from 8 to 16 cycles, but still keeps
   the leaf count at 9. It may reduce logic pressure and fix timing because the
   diagonal parity cone is smaller.

2. Use asymmetric leaf width, for example 48-bit or 40-bit leaves.
   This is less clean mathematically than 32 or 64, but it may be a better
   FPGA point: fewer leaves than KPD32 and shorter parity cones than KPD64.

3. Split the 64-bit diagonal parity into two registered halves.
   This is a timing fix first, not an area fix. If it allows LUT packing to
   improve, it may also reduce effective area. It needs careful cycle accounting.

4. Keep KPD64 only for internal autoreduced field multiply.
   The raw 512-bit product path can stay KPD32. That lets KPD64 specialize its
   fold/reduce path and may remove some muxing.

Expected useful target:

```text
PMUL cycles: 260k to 310k
Logic LUT delta: under +150 only if the diagonal cone is narrowed
```

## 3. D4 Digit-Serial Modular Multiplier

D4 is the fastest trial. It bypasses raw product generation and updates the
field product directly modulo `x^233 + x^74 + 1`. The current trial is too big
because it adds large local state:

```text
Awork[255:0]
Bwork[255:0]
Acc[255:0]
wide masked XOR for {A, xA, x^2A, x^3A}
```

Lower-area directions:

1. Store `Bwork` in VRF instead of a 256-bit local register.
   The multiplier only needs the low digit each round. If scheduling can read
   one lane/digit without duplicating the whole operand locally, FF drops.

2. Reuse `hdc_src0_q`, `lane_result_q`, or `ecc_product_pair` as D4 state.
   This turns D4 from a new local multiplier into a user of the existing lane
   datapath. The cycle count will rise, but area may fall sharply.

3. Build a D2 version as the small-area sibling.
   D2 needs only `{A, xA}` contribution instead of `{A, xA, x^2A, x^3A}`.
   It will not hit 126k cycles, but it may land between KPD32 and D4 with much
   less logic.

4. Pipeline the D4 contribution over two cycles.
   Compute `{A, xA}` in one cycle and `{x^2A, x^3A}` in the next. This halves
   the wide XOR/mask cone and may make a D4-like design practical at moderate
   area.

5. Combine D4-lite with the selected 5M point-add formula.
   The measured D4 result still used the 6M point-add schedule. Combining a
   smaller D4/D2 multiplier with 5M point-add should reduce the multiplication
   count and the field-multiply latency at the same time.

Expected useful target:

```text
D4 full local-state trial: 126k cycles, but too large
D4-lite or D2 target: 150k to 220k cycles with much lower LUT/FF
Sub-100k likely requires both a fast modular multiplier and another formula-level reduction
```

## Route Toward Sub-100k Cycles

The current selected 5M point-add version gets a strong area-efficient win, but
it does not change the field multiplier latency. To approach 100k cycles, we
probably need two independent reductions:

```text
1. Formula-level: 6M point add -> 5M point add, and maybe a safer 4M/5M double-aware variant.
2. Multiplier-level: KPD32 field multiply -> D4-lite, D2, or narrowed KPD64.
```

A realistic next exploration order:

1. Keep V35 selected 5M RTL as the baseline.
2. Try partial compute/fold overlap with one narrow fold latch.
3. Try KPD64 with 8 diagonals per cycle.
4. Try D2 digit-serial using existing VRF/lane state instead of local 256-bit registers.
5. Only after those pass individually, measure combinations with the 5M point-add RTL.

The important constraint is that any high-speed path must first prove it can
avoid new full-width local state. Otherwise cycle count improves, but the area
story stops matching the HDEC reuse goal.
