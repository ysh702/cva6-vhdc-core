# VV5 Vector Payload Fabric Result

## Baseline

- Baseline branch: `hdec-vv4-hdcu-hperm64`
- Baseline commit: `2ce0637b`
- Baseline OOC: `reports/hdec/vv4_hdcu_hperm64_2026_06_24/try2_lane64_2stage_ooc`
- VV5 branch: `hdec-vv5-vector-fabric`
- Final accepted try: `try11_no_hperm_clear`

## What Changed

VV5 finally takes the aggressive direction discussed in the design review:

- Top no longer sees four independent lane result paths.
- A new `hdec_vector_payload_4x64` module exposes one 256-bit vector payload interface.
- The physical computation is still four 64-bit slices, so the datapath does not become one large 256-bit ALU.
- The old P2/P3 split result paths are collapsed into one payload register:
  - HBIND writes 4x64 XOR result into `vec_payload_q`.
  - HSIM/HMATCH write packed overlap counts into `vec_payload_q`.
  - HCNTADD writes 4x64 counter update into `vec_payload_q`.
  - HCNTCLIP writes packed 16-bit clip result into `vec_payload_q`.
  - HPERM writes each 64-bit slot into `vec_payload_q`.

The important final optimization is that HPERM no longer clears the whole 256-bit payload before writing four 64-bit slots. All four slots are overwritten before P3 writeback, so the clear branch was a redundant 256-bit mux input.

## Area And Timing

Vivado OOC:

- Vivado: 2024.2
- Part: `xc7z020clg400-2`
- Constraint: 5ns
- Final OOC directory: `reports/hdec/vv5_vector_fabric_2026_06_24/try11_no_hperm_clear_ooc`

| Version | Total LUT | Logic LUT | LUTRAM | FF | BRAM | DSP | Fmax |
|---|---:|---:|---:|---:|---:|---:|---:|
| VV4 baseline | 4722 | 4722 | 0 | 1747 | 4 | 0 | 207.684 MHz |
| VV5 early boundary try5 | 4688 | 4688 | 0 | 1748 | 4 | 0 | 207.684 MHz |
| VV5 final try11 | 4675 | 4675 | 0 | 1382 | 4 | 0 | 207.727 MHz |

Delta against VV4:

| Metric | Delta |
|---|---:|
| Total LUT | -47 |
| Logic LUT | -47 |
| FF | -365 |
| Fmax | +0.043 MHz |
| PMUL cycles | 0 |

Delta against the earlier VV5 try5:

| Metric | Delta |
|---|---:|
| Total LUT | -13 |
| Logic LUT | -13 |
| FF | -366 |

## Hierarchy Interpretation

| Version | Top body LUT | Vector/lane LUT | Top body FF | Vector/lane FF |
|---|---:|---:|---:|---:|
| VV4 baseline | 3351 | 1371 | 1442 | 305 |
| VV5 early try5 | 3318 | 1370 | 1444 | 304 |
| VV5 final try11 | 2143 | 2532 | 1126 | 256 |

This explains the result:

- The aggressive merge really cuts top-level control: top body LUT drops from 3318 to 2143.
- The new vector payload fabric absorbs more local selection logic, so `i_vec` becomes larger than the old four lane instances.
- After removing the redundant HPERM clear path, the total still improves: final total is 4675 LUT.
- The biggest win is FF: one shared payload register replaces several semantic boundary registers.

## Functional Tests

| Test | Result |
|---|---|
| `xsim_hdec_hdc_full_flow_v20` | PASS |
| `xsim_hdec_hmatch_compare_split` | PASS |
| `xsim_hdec_hperm_bit_align` | PASS |
| `xsim_hdec_ecc_reduce_v1` | PASS |
| `xsim_hdec_ecc_pmul_profile_v27` | PASS, `PMUL_PROFILE_WALL_CYCLES=135952` |

## Attempts

| Try | Idea | Result | Decision |
|---|---|---:|---|
| try5 | Only remove top `lane_result_n/lane_clip_n` and share pop enable | 4688 LUT, 1748 FF | Good but conservative |
| try6/7/8 | One vector module, but still separate bool/pop/cnt/clip outputs | 4755 LUT, 1748 FF | Rejected, vector boundary got wider |
| try9 | One shared vector payload for all HDC lane results | 4698 LUT, 1380 FF | Good FF drop, LUT still +10 vs try5 |
| try10 | Only update low payload bits for pop/clip | 4708 LUT, 1380 FF | Rejected, CE/mux split hurt LUT |
| try11 | Remove redundant HPERM payload clear | 4675 LUT, 1382 FF | Accepted |

## Conclusion

The useful VV5 idea is not "merge four lanes into one 256-bit ALU". The useful idea is:

> one vector-level control and payload boundary, implemented internally as four 64-bit compute slices.

This keeps the 4x64 physical datapath, but removes several semantic result registers and reduces top-level control pressure. The final effect is modest LUT reduction and large FF reduction without changing ISA, HDC algorithm, ECC algorithm, PMUL cycles, BRAM, DSP, or the 200 MHz timing target.
