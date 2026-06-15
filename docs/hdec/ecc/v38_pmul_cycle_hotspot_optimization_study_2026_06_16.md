# V38 ECC scalar point multiplication cycle hotspot study

Date: 2026-06-16
Tool context: Vivado 2024.2, xc7z020clg400-2
Branch: `hdec-ecc-pointmul-v38`
RTL base: V37 one-inversion RTL, commit `6667c004`

V38 is created from V37. This document is an analysis note only. It does not
change RTL. The V37 RTL keeps the "one inversion instead of three final affine
inversions" optimization.

## Version anchors

| Anchor | Commit | Meaning |
|---|---|---|
| `V35-基线` | `4193f204` | V35 selected RTL: `ADD 5M cross-product + selected double XZ` |
| `V37-一次求逆` | `6667c004` | V37 selected RTL: V35 plus final affine batch inversion |
| `hdec-ecc-pointmul-v38` | `6667c004` | Analysis branch created on top of V37 |

## Short conclusion

The current full scalar point multiplication is no longer limited by the final
inversion tail. It is dominated by the per-bit point-add loop and, inside that
loop, by GF(2^233) modular multiplication.

The most important numbers from the V37 profile are:

```text
PMUL_PROFILE_WALL_CYCLES       = 333481
PMUL_PROFILE_SUB_ADD_CYCLES    = 309657   // 92.86% of wall cycles
PMUL_PROFILE_PHASE_PMUL_FIELD  = 315355   // 94.56% of wall cycles
PMUL_PROFILE_GF_MUL_STARTS_ADD = 1165     // 233 * 5
PMUL_PROFILE_SQR_STARTS_DBL    = 1165     // 233 * 5
PMUL_PROFILE_INV_STARTS        = 1
```

So V37 already reduced the final affine tail, but the main loop still performs
five field multiplications for every scalar bit:

```text
233 scalar bits * 5 field multiplications/bit = 1165 field multiplications
```

Field squaring is not the current bottleneck. The measured square/spread state
is only:

```text
PMUL_PROFILE_ST_HSPREAD_CYCLES = 3266     // 0.98% of wall cycles
```

That means optimizing squaring or Itoh-Tsujii inversion alone cannot move the
total cycle count enough. To approach 100k cycles, we need either:

1. much fewer point additions and therefore many fewer field multiplications,
2. a much faster low-area field multiplier,
3. or both.

## V35 to V37 profile comparison

| Counter | V35 selected | V37 one inversion | Delta |
|---|---:|---:|---:|
| Wall cycles | 341624 | 333481 | -8143 |
| Subop add cycles | 309657 | 309657 | 0 |
| Subop double cycles | 15608 | 15608 | 0 |
| Subop affine cycles | 16342 | 8199 | -8143 |
| GF multiply starts | 1203 | 1188 | -15 |
| GF multiply starts in add | 1165 | 1165 | 0 |
| GF multiply starts in affine | 38 | 23 | -15 |
| Inversion multiply starts | 30 | 10 | -20 |
| Square starts | 2097 | 1633 | -464 |
| Inversion square starts | 696 | 232 | -464 |
| Inversion starts | 3 | 1 | -2 |

Interpretation:

- V37 did exactly what it should do: it reduces the affine tail from three
  inversions to one inversion.
- It does not change the 233-bit main ladder loop.
- The 8143 saved cycles are real, but this path is now only about 2.46% of the
  V37 wall cycles.
- The next large win must attack the 309657-cycle add loop.

## V37 cycle breakdown

| Category | Cycles | Wall share | Meaning |
|---|---:|---:|---|
| `SUB_ADD` | 309657 | 92.86% | Per-bit point add subroutine |
| `SUB_DBL` | 15608 | 4.68% | Per-bit selected double subroutine |
| `SUB_AFFINE` | 8199 | 2.46% | Final affine recovery and inversion tail |

| Phase/state group | Cycles | Wall share | Meaning |
|---|---:|---:|---|
| `PHASE_PMUL_FIELD` | 315355 | 94.56% | Field multiply/square/reduce work under point multiplication |
| `PHASE_INV_SQR` | 2099 | 0.63% | Squares inside the one remaining inversion |
| `PHASE_INV_MUL` | 2580 | 0.77% | Multiplications inside the one remaining inversion |
| `PHASE_PMUL_ADD` | 4949 | 1.48% | 256-bit XOR/uop add work |
| `PHASE_PMUL_COPY` | 470 | 0.14% | Copy work |

| ECC datapath state | Cycles | Wall share | Per GF multiply rough average |
|---|---:|---:|---:|
| `ST_ECC_DIAG` | 160380 | 48.09% | 135.00 |
| `ST_ECC_LEAF_FOLD` | 128304 | 38.47% | 108.00 |
| `ST_ECC_REDUCE` | 11284 | 3.38% | 9.50 |
| `ST_ECC_WRITE_DRAIN` | 5642 | 1.69% | 4.75 |
| `ST_ECC_LOAD` | 4752 | 1.42% | 4.00 |
| `ST_ECC_WRITE_PAIR` | 4752 | 1.42% | 4.00 |
| `ST_HSPREAD` | 3266 | 0.98% | n/a |
| `ST_ECC_UOP` | 4949 | 1.48% | n/a |

The field multiplier still spends most of its time in two places:

```text
diagonal partial product calculation
leaf fold into the raw product accumulator
```

For the current KPD32 multiplier, the rough shape per normal field
multiplication is:

```text
~135 cycles diagonal calculation
~108 cycles leaf fold
~20 cycles load/write/reduce/drain overhead
```

That matches the earlier observation: the multiplier is not only limited by
how many diagonal bits are computed per cycle. The leaf fold and handoff cost
are almost as important.

## RTL mapping

Relevant RTL and testbench anchors:

| File | Lines | Meaning |
|---|---:|---|
| `core/hdec/rtl/hdec_top.sv` | 427-444 | GF(2^233) reduction for `x^233 + x^74 + 1` |
| `core/hdec/rtl/hdec_top.sv` | 513 | 32-bit leaf diagonal partial product helper |
| `core/hdec/rtl/hdec_top.sv` | 1127-1305 | KPD32 field multiplication, writeback, and reduction states |
| `core/hdec/rtl/hdec_top.sv` | 1309-1390 | Current inversion chain controller |
| `core/hdec/rtl/hdec_top.sv` | 1466-1674 | V37 final affine one-inversion path |
| `core/hdec/rtl/hdec_top.sv` | 1676-1684 | Point double subop: five squares and one XOR/uop bind |
| `core/hdec/rtl/hdec_top.sv` | 1686-1697 | Point add subop: five field multiplications, one square, two XOR/uop binds |
| `verif/hdec/tb_hdec_ecc_pmul_profile_v27.sv` | 373-397 | Profile counter display |

The current add subop has five normal field multiplication starts:

```text
step 0: R0X * R1Z
step 1: R1X * R0Z
step 4: selected RX * selected RZ
step 5: T0 * T1
step 6: base_x * T5
```

The current double subop has no normal GF multiply starts. It is mostly
squares:

```text
5 square/spread starts per scalar bit
```

That is why reducing one field multiplication in every point add is worth far
more than optimizing the double path. One removed field multiplication per bit
is:

```text
233 fewer field multiplications
roughly 233 * 265 cycles = about 61745 cycles
```

## ITA status

The current inverter is already an Itoh-Tsujii-style fixed square/multiply
chain, not an Extended Euclidean inverter. The V37 profile proves one inversion
costs:

```text
232 field squares + 10 field multiplications
```

This is visible in RTL through:

```text
ecc_inv_step_has_mul(step)
ecc_inv_step_sqr_repeat(step)
```

So "use ITA" is not a new optimization direction for this RTL. It is already
the current shape. The useful V37 change was instead to reduce the number of
inversions from three to one.

Further ITA work can still be checked, but it is not the first priority:

1. Search for a shorter proven addition chain for GF(2^233) inversion.
2. Keep the one-inversion batching.
3. Do not spend large RTL area accelerating inversion squares unless a later
   algorithm makes many more squares appear in the main path.

## Literature alignment

### Binary-field formula level

The Explicit Formulas Database lists Lopez-Dahab binary-field projective
formula costs for curves of the form:

```text
y^2 + x*y = x^3 + a*x^2 + b
```

Its operation tables show a wide spread of costs depending on whether both
inputs are general projective points or one input has `Z = 1`. The important
lesson for this design is not that one formula should be copied directly. The
lesson is that multiplication count is the first-order cost driver.

Our V35/V37 add formula is already a very low-multiplication special formula:

```text
5M per scalar bit point-add path
```

The failed 4M experiment confirms the local risk: removing one multiplication
also removed a value needed by the following selected double. This means the
next formula-level win is more likely to come from reducing the number of point
additions, not just squeezing the existing 5M add into 4M.

### Multiplier architecture level

Recent FPGA ECC work still treats modular multiplication as the dominant
hardware cost. The usual tradeoff is:

```text
bit-serial:     small area, about m cycles
digit-serial:   area/cycle tradeoff, about ceil(m / digit_size) cycles
parallel:       low cycles, much larger area
Karatsuba:      lower multiplication complexity, more wiring/control pressure
```

That matches our Vivado 2024.2 trials:

| Trial | PMUL cycles | Logic LUT delta | FF delta | Status |
|---|---:|---:|---:|---|
| Leaf compute/fold overlap | 252627 | +348 | +152 | Fast but too large for current target |
| KPD64 64-bit leaf | 221035 | +1059 | +158 | Fast, but area large and timing failed 200 MHz |
| D4 digit-serial modular multiplier | 126259 | +1911 | +735 | Fastest isolated trial, but area far above target |
| KPD64 sub32 direct accumulation | 255008 | +198 | +138 | Interesting middle ground, not retained |
| V37 Plan2 tail bypass | 309143 | +130 | +4 | Good small-area candidate, not in current V37 RTL |
| Popcount/parity `popxor24_lsb` | 309143 | +253 | +13 | Functionally useful, area worse than Plan2 |

The data says: simply making the multiplier wider works, but area rises faster
than the current target allows. The better direction is to either reduce the
number of multiplications or reuse existing storage/control more aggressively.

### K-233 and Koblitz structure

The local testbench base point matches NIST K-233, also known as sect233k1:

```text
field polynomial: x^233 + x^74 + 1
curve:            y^2 + x*y = x^3 + 1
base point Gx:    017232ba853a7e731af129f22ff4149563a419c26bf50a4c9d6eefad6126
base point Gy:    01db537dece819b7f70f555a67c427a8cd9bf18aeb9b56e0c11056fae6a3
```

This is important because Koblitz curves have a cheap Frobenius map:

```text
tau(P) = (x^2, y^2)
```

In binary fields, squaring is linear and much cheaper than multiplication. The
Koblitz `tau` representation can replace many double-and-add operations with
Frobenius steps plus fewer point additions. A width-w tau-adic NAF method
usually has a nonzero digit density close to:

```text
1 / (w + 1)
```

For `w = 4`, the rough add count is:

```text
233 / 5 = about 47 point additions
```

That is the first method in this study that plausibly changes the order of the
cycle count. If each remaining addition costs about the current 1329 cycles,
then:

```text
47 * 1329 = about 62463 cycles
```

There will be scalar recoding, precomputation, table selection, final
normalization, and tau/square costs, so the real number will be higher. Still,
this is the most plausible path toward sub-100k cycles without adding a large
parallel multiplier.

## Optimization directions ranked for V38+

### 1. Best algorithmic target: Koblitz tau-adic scalar multiplication

Why it is attractive:

- The curve is K-233, so the Frobenius map is naturally available.
- Squaring is cheap in the current RTL.
- It reduces the number of point additions instead of only making each
  multiplication faster.
- It is the only path here that looks capable of reaching below 100k cycles
  with small or moderate area increase.

Expected effect:

```text
Current main loop: 233 point-add paths * 5M = 1165 add multiplications
Tau-adic w=4 rough estimate: about 47 additions
If mixed add is 5M to 8M: about 235 to 376 main-loop multiplications
```

Risk:

- This is not a small FSM tweak.
- It needs scalar recoding into tau-adic digits.
- It needs point precomputation and sign handling.
- Constant-time table selection may add cycles and control area.
- If arbitrary base points are required, precomputation must be done at runtime.
- If only fixed-base K-233 `G` is required, the table can be fixed or loaded
  once, which is much easier.
- The current result-recovery and exceptional-case assumptions need a new
  correctness proof and many more tests.

Recommended first step:

Do not modify RTL immediately. First build a reference model that uses the same
K-233 parameters as the testbench and verifies tau-adic multiplication against
the current ladder for many scalars. After the algebra is stable, implement the
minimal RTL path.

### 2. Best low-risk RTL candidate: combine V37 one inversion with Plan2 tail bypass

V37 does not include the earlier Plan2 tail bypass. The measured Plan2 result
on the V37 investigation path was:

```text
PMUL cycles: 309143
Logic LUT:   6051
FF:          1806
WNS:         0.247 ns
```

This likely combines well with the one-inversion tail, because Plan2 attacks
field-multiply tail/transition cycles while V37 attacks affine inversion count.
It will not reach 100k cycles, but it is the best known small-area RTL
candidate.

Recommended next trial:

Apply Plan2 on top of V38 and run the same xsim plus OOC flow. Accept only if
the combined area remains close to the V37 small-increase range and timing is
still above 200 MHz.

### 3. Multiplier target: D2/D3 streaming digit-serial modular multiplier

The full D4 digit-serial multiplier proved the performance direction:

```text
126259 cycles
```

But it added too much LUT and FF. The next version should not repeat the full
D4 local-state structure. It should be redesigned around existing HDC/ECC
storage:

- keep field state in the existing VRF/lane registers where possible,
- avoid large duplicate 233/256-bit local accumulators,
- try digit sizes 2, 3, and maybe 7, not only 4,
- use static reduction for `x^233 = x^74 + 1`,
- make the per-cycle work lane-local before any global fold.

Why D3 is worth checking:

Some digit-serial literature notes that digit sizes of the form `2^l - 1` can
have favorable time-area behavior. For us, `d = 3` may be a better compromise
than D4:

```text
D2: ceil(233 / 2) = 117 digit rounds per multiplication
D3: ceil(233 / 3) = 78 digit rounds per multiplication
D4: ceil(233 / 4) = 59 digit rounds per multiplication
```

D3 by itself probably will not guarantee sub-100k cycles with the current 1165
point-add multiplications, but D3 plus tau-adic scalar multiplication could be
very strong.

### 4. Middle-ground datapath target: KPD64 sub32 direct accumulation

The previous KPD64 full leaf was too large. The more interesting measured
middle-ground was:

```text
KPD64 sub32 direct accumulation
PMUL cycles: 255008
Logic LUT delta: +198
FF delta: +138
```

This is not as area-clean as the V35 5M formula or V37 one-inversion change,
but it is much more realistic than full KPD64 or full D4. It should be revisited
only after the tau-adic path is understood, because reducing multiplication
count changes how much multiplier acceleration is still needed.

### 5. Small fold-overlap target: one-entry leaf handoff instead of full overlap

Full leaf compute/fold overlap was fast but area-heavy:

```text
252627 cycles, +348 Logic LUT, +152 FF
```

The small-area variant should not duplicate the whole product path. A better
trial is a one-entry narrow leaf handoff:

- keep only enough latched data to hide one or two fold cycles,
- do not add a full ping-pong product accumulator,
- keep the leaf fold writeback path mostly unchanged,
- accept a partial win if it stays under roughly +80 to +120 Logic LUT.

This is not enough for sub-100k by itself, but it can combine with formula-level
changes.

### 6. Popcount plus reduction-XOR sharing

Using popcount's lowest bit as parity is functionally valid:

```text
parity(bits) = popcount(bits)[0]
```

But the measured `popxor24_lsb` trial was not area-competitive:

```text
same cycle count as Plan2, but +253 Logic LUT instead of +130
```

So the rule for this direction should be strict:

- It is useful only if it reuses existing HDC popcount trees with little extra
  partial-product/control logic.
- If it needs a duplicate AND array plus control muxing, it is worse than the
  existing dedicated ECC reduction-XOR path.
- It may still help HDC throughput and ECC together, but it should be evaluated
  as a shared datapath scheduling problem, not as an ECC-only multiplier widen.

## What can realistically reach below 100k cycles

These are rough estimates, not measured RTL results:

| Direction | Alone below 100k? | Why |
|---|---|---|
| V37 one inversion | No | Only saves affine tail cycles |
| Plan2 tail bypass | No | Good small-area win, but main loop remains |
| KPD64 sub32 | No | Still about 255k measured |
| Full D4 digit-serial | Close but no | 126k measured, area too high |
| D2/D3 low-area digit-serial | Probably no alone | Multiplier faster, but 1165 add multiplications remain |
| Koblitz tau-adic method | Plausibly yes | Reduces point additions from 233 to roughly 40 to 60 |
| Tau-adic plus D2/D3 multiplier | Best candidate | Reduces both multiplication count and multiplication cost |

My current recommendation is:

1. Keep V37 one-inversion RTL as the current stable optimization.
2. Use V38 to prototype tau-adic scalar multiplication at the reference-model
   level first.
3. In parallel, trial Plan2 on V38 as the next low-risk RTL measurement.
4. After tau-adic correctness is proven, choose whether D2/D3 streaming
   multiplier is still needed.

## References

- Explicit Formulas Database, Lopez-Dahab binary formulas:
  https://www.hyperelliptic.org/EFD/g12o/auto-shortw-lopezdahab.html
- MDPI Electronics 2023, throughput/area ECC accelerator discussion:
  https://www.mdpi.com/2079-9292/12/17/3611
- IEEE Access / Queen's University Belfast PDF, GF(2^233) area-sensitive
  point multiplication:
  https://pureadmin.qub.ac.uk/ws/portalfiles/portal/628046952/FPGA_Implementation_of_Elliptic-Curve_Point-Multiplication_Over_GF2233_Using_Booth_Polynomial_Multiplier_for_Area-Sensitive_Applications.pdf
- Kumar, Wollinger, Paar, digit-serial GF(2^m) multipliers:
  https://informatik.rub.de/veroeffentlichungenbkp/emsec/veroeffentlichungen/2006/pdfs/2006_Optimum_Digit_Serial_GF_2%5Em__Multipliers_for_Curve_Based_Cryptography.pdf
- Springer Encyclopedia, Itoh-Tsujii inversion:
  https://link.springer.com/rwe/10.1007/978-3-030-71522-9_34
- Standard curve database, NIST K-233:
  https://std.neuromancer.sk/nist/K-233/
- IACR ePrint 2021/171, window tau-NAF on Koblitz curves:
  https://eprint.iacr.org/2021/171
- Waterloo CACR 2007-18, parallel scalar multiplication on Koblitz curves:
  https://cacr.uwaterloo.ca/techreports/2007/cacr2007-18.pdf
