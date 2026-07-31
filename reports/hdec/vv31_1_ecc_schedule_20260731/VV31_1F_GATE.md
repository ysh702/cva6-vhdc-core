# VV31-1F LOAD-B Elision Gate

## Snapshot and mechanism

VV31-1F retains the early B read and `LOAD_B_WAIT` capture from VV31-1E, but
does not add a new matrix issue in `LOAD_B`.  Instead, `LOAD_B_WAIT`
initializes the leaf state and enters the existing `S_ECC_DIAG_ISSUE`
directly, eliminating the otherwise separate `LOAD_B` cycle.  No RTL was
changed during this gate.

- Git HEAD: `951936a75a70d400aceacf87323f4e3a9f96187a`
- `hdec_top.sv` SHA-256:
  `2b09fa6d3fcea67744664a9c960625f7c311e25835ae45ca3ab635351a72e645`
- Quick-regression aggregate RTL SHA-256:
  `d71e115d0167bb5289633dbebb42bfd8261645b7efe926229e080ed5c3abed15`

## Candidate-level functional gate

Following the updated candidate policy, VV31-1F was checked with one newly
generated legal random K rather than four:

| Seed source | K Hamming weight | PMUL cycles | Result |
|---|---:|---:|---|
| Windows OS CSPRNG | 113 | 148539 | PASS |

The master seed was
`450a40b9bebbf9f7f3cc3ee3e85cdee0e0aab67a435da795f31be332aaa340da`.
The PMUL output matched the independent reference model.  The quick suite's
shift-align, fused-map, diagonal-map, square, and inversion checks also
passed.

An independent HDC full-flow compatibility simulation completed with:

`[HDEC_HDC_FULL_FLOW_V20] PASS`

The previously launched four-K stage run was intentionally terminated when
the candidate policy changed.  Its incomplete PMUL run is not used as
evidence.  A combined multi-K regression remains required when the ECC-only
schedule is frozen.

## Cycle result

VV31-1F preserves the 148539-cycle result of VV31-1E without adding a second
matrix producer:

| Comparison | Cycle change |
|---|---:|
| VV31-1D to VV31-1F | -1186 |
| VV31-0 to VV31-1F | -10682, approximately 6.71% |

## Matched OOC result

Vivado 2024.2 synthesized `hdec_top` out of context for
`xc7z020clg400-2` with a 5 ns clock:

| Metric | VV31-0 | VV31-1D | VV31-1E | VV31-1F |
|---|---:|---:|---:|---:|
| PMUL cycles | 159221 | 149725 | 148539 | 148539 |
| Logic LUT | 4651 | 4722 | 4866 | 4726 |
| FF | 1274 | 1273 | 1274 | 1272 |
| BRAM | 4 | 4 | 4 | 4 |
| DSP | 0 | 0 | 0 | 0 |
| WNS | 0.328 ns | 0.328 ns | 0.325 ns | 0.328 ns |
| Estimated Fmax | 214.041 MHz | 214.041 MHz | 213.904 MHz | 214.041 MHz |

VV31-1F is 24 LUT below the cumulative 4750 limit.  Relative to VV31-1D, it
adds only four Logic LUT, removes one FF, preserves the full WNS, and saves a
further 1186 cycles.

## Hierarchical localization

| Hierarchy | VV31-1D LUT | VV31-1E LUT | VV31-1F LUT | 1F versus 1D |
|---|---:|---:|---:|---:|
| Top-local `(hdec_top)` | 1791 | 1795 | 1805 | +14 |
| `i_vec` total | 2931 | 3071 | 2921 | -10 |
| Complete design | 4722 | 4866 | 4726 | +4 |

Avoiding a new matrix issue removes the 1E vector-payload expansion:
`i_vec` falls by 150 LUT relative to 1E and is 10 LUT smaller than in 1D.
The remaining mechanism cost is localized in top-level state and read
control.

## Artifacts

- Quick random-K regression:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1F_quick_20260731`
- Quick manifest:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1F_quick_20260731\run_manifest.json`
- HDC full-flow compatibility:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1F_hdc_full_flow_20260731`
- Matched OOC synthesis:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1F_ooc_20260731`
- OOC summary:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_1F_ooc_20260731\reports\run_summary.txt`

## Gate decision

`ACCEPTED`

Under the updated one-random-K candidate policy, VV31-1F passes functional,
HDC compatibility, cycle, area, and timing gates.  It becomes the cumulative
ECC-only scheduling baseline at 148539 PMUL cycles, 4726 Logic LUT, 1272 FF,
and 0.328 ns WNS.  Final ECC freeze still requires the planned combined
multi-K regression.
