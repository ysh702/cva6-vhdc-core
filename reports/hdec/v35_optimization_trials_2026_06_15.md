# V35 ECC PMUL Optimization Trials

Baseline is commit `5244c56f hdec: add V33 load-read sidecar` on branch
`hdec-ecc-pointmul-v35`.

## Baseline

| Metric | Value |
| --- | ---: |
| PMUL wall cycles | 401971 |
| Logic LUT | 5887 |
| Slice LUT | 6359 |
| LUTRAM | 472 |
| FF | 1801 |
| WNS | 0.243 ns |
| Fmax | 210.217 MHz |

## Completed Trials

| Trial | Result | PMUL cycles | Cycle delta | Logic LUT | LUT delta | FF | Fmax MHz | Decision |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Diagonal tail bypass v1 | PASS | 363199 | -38772 | 6006 | +119 | 1810 | 210.393 | Reverted: good speed, area above small-increase target |
| Diagonal tail bypass direct | PASS | 363199 | -38772 | 6032 | +145 | 1814 | 210.393 | Reverted: worse area than v1 |
| Leaf prefetch + dual fold | PASS | 324427 | -77544 | 7192 | +1305 | 2392 | 210.393 | Reverted: product accumulator became register-heavy |
| Autoreduce entry bypass | PASS | 398438 | -3533 | 6018 | +131 | 1808 | 210.393 | Reverted: small cycle win, area too high |
| Square reduce entry bypass | PASS | 399874 | -2097 | 6059 | +172 | 1813 | 210.393 | Reverted: narrower version still too large |
| PMUL add tail GF_MAC reuse | PASS | 401272 | -699 | 5932 | +45 | 1813 | 210.393 | Reverted by request: cycle/area tradeoff weaker than tail bypass |
| ADD 4M cross-product formula | FAIL | 281277 | -120694 | n/a | n/a | n/a | n/a | Reverted/continued: `GF_MUL_STARTS_ADD=932`, but removed `X*Z` value needed by following double |
| ADD 5M cross-product + selected double XZ | PASS | 341624 | -60347 | 5921 | +34 | 1802 | 210.217 | Selected for V35 RTL: `GF_MUL_STARTS_ADD=1165`, strong cycle/area tradeoff |
| Leaf compute/fold overlap | PASS | 252627 | -149344 | 6235 | +348 | 1954 | 210.393 | Reverted: strong speed, area above target; profile sub-counters invalid after enum insertion |
| Direct reduced accumulation | PASS | 391919 | -10052 | 6656 | +769 | 1811 | 206.143 | Reverted: direct per-leaf modular fold saves tail cycles but adds large XOR/mux network |
| KPD64 64-bit leaf | PASS | 221035 | -180936 | 6946 | +1059 | 1960 | 193.761 | Reverted: fastest isolated multiplier trial, but area large and 200 MHz timing fails |
| D4 digit-serial modular multiplier | PASS | 126259 | -275712 | 7798 | +1911 | 2537 | 202.224 | Reverted: best cycle count and timing passes, but register/logic area far above target |

## Notes

- Results are OOC measurements from Vivado 2024.2 using `scripts/hdec/run_ooc_200.ps1`.
- Functional checks use `scripts/hdec/xsim_hdec_ecc_pmul_profile_v27.tcl`.
- Each rejected trial was reverted before the next trial; the selected 5M point-add RTL is retained in V35.
- The best small-area candidate so far is `ADD 5M cross-product + selected double XZ`: `-60347` cycles for `+34` Logic LUT.
- The largest cycle reductions (`KPD64`, `D4`, compute/fold overlap) are useful performance references but exceed the current small-area target.
