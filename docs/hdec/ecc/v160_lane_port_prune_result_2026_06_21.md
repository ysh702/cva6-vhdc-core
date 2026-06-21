# V160 Lane Port Prune Result

## Change

`hdec_lane_4x64` no longer exposes the old per-lane command shell ports:

- unused VRF bank ports
- unused ctrl/result ports
- unused neighbor/carry/borrow/count/flag ports
- unused local writeback ports

The top-level HDEC pipeline already drives the lane only through static compute
ports: bool/AND-XOR front end, counter update, shift-align, clip, ECC reduce,
and ECC diagonal parity. This change removes the dead shell interface and the
constant tie-offs in `hdec_top`.

## Verification

Vivado xsim:

| Test | Result |
| --- | --- |
| `xsim_hdec_hdc_full_flow_v20` | PASS |
| `xsim_hdec_hdc_selflearn_v1`, UCI-HAR seed 7 fixture | PASS, 2598/2947, updates 349 |
| `xsim_hdec_ecc_reduce_v1` | PASS |
| `xsim_hdec_ecc_pmul_profile_v27` | PASS, `PMUL_PROFILE_WALL_CYCLES=190151` |

OOC synthesis, Vivado 2024.2, `xc7z020clg400-2`, 5 ns:

| Metric | V160 |
| --- | ---: |
| Slice LUT / Total LUT | 5195 |
| Logic LUT | 5067 |
| LUTRAM | 128 |
| FF | 1877 |
| BRAM | 4 |
| DSP | 0 |
| CARRY4 | 12 |
| WNS | 0.247 ns |
| Fmax estimate | 210.393 MHz |

## Decision

Keep as a structural cleanup. It does not reduce LUT/FF, but it also does not
increase area or affect timing/cycles, and it cuts synthesis warnings from 759
to 119 by removing the dead lane command shell.
