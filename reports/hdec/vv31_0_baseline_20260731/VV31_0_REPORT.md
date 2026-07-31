# VV31-0 Verification and Resource-Trace Baseline

## Stage status

`ACCEPTED`

The entry RTL is the unmodified `VV31` branch at commit
`951936a75a70d400aceacf87323f4e3a9f96187a`. Simulation-only named resource
events were then added under `ifndef SYNTHESIS`. A matched post-probe OOC run
reproduced every entry PPA value exactly. The complete compatibility gate has
now finished. Historical background-loop tests are not used as acceptance
evidence.

## Reproduced entry metrics

| Item | Reproduced result |
|---|---:|
| Logic LUT | 4651 |
| FF | 1274 |
| BRAM | 4 |
| DSP | 0 |
| WNS at 5 ns | 0.328 ns |
| Estimated Fmax | 214.041 MHz |
| Blocking PMUL cycles | 159221 |

Vivado OOC synthesis used Vivado 2024.2, `xc7z020clg400-2`, and a 5 ns
clock.  The PMUL regression used four newly generated legal K-233 scalars.
Their Hamming weights were 103, 118, 118, and 112.  Every scalar completed in
159221 cycles and matched the independent K-233 reference model.

The matched OOC run after adding the simulation probes also reported 4651
Logic LUT, 1274 FF, 4 BRAM, 0 DSP, and 0.328 ns WNS. Therefore, the probes did
not alter the synthesized design.

## New VV31 baseline tests

The new standalone HDC episode test completed two randomly generated training
and inference episodes. Each episode required 3178 cycles and executed 16 HDC
compute operations. Measured accepted-request service cycles were 19 for
HCNTCLR, 59 for HPERM, 31 for HBIND, 79 for HCNTADD, 83 for HCNTCLIP, and 40
for both HSIM and HMATCH. The standalone maximum acceptance wait was one
cycle.

The held-valid background-gap test started one random PMUL with scalar Hamming
weight 109 and presented an HSIM request as soon as the background start
response was returned. At the entry design:

- the HSIM request waited 155427 cycles before acceptance;
- the accepted HSIM retained its 40-cycle service time;
- the PMUL result matched the independent K-233 model;
- no HDC/ECC product or XOR0 conflict was observed;
- no compatible resource-pair event was observed, as expected before VV31
  scheduling is implemented.

The diagnostic ECC state profile independently reproduced the 159221-cycle
PMUL and counted 1187 field multiplications, 1167 square-write operations, 233
scalar reads, and 10683 `S_ECC_DIAG_ISSUE` cycles. These counts define the
measured optimization space for VV31-1 rather than assuming an opportunity
from the state names alone.

## Reproducible artifacts

- Entry random regression:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_0_entry_stage1`
- Entry OOC synthesis:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_0_entry_ooc`
- Post-probe matched OOC synthesis:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_0_gate_ooc_after_probes_20260731`
- Runner vector-only probe:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\runner_vectors_probe`
- New HDC episode:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_0_hdc_episode_fix2`
- New held-valid background gap:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_0_new_baseline_gap_fix2`
- ECC state profile:
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv31\vv31_0_ecc_state_profile`

The VV31 generator obtains a new 256-bit seed from the Windows operating
system CSPRNG for normal runs, expands it with a specified SHA-256 counter
construction, excludes K=3 from the primary random set, and records all
vectors and hashes for exact replay.

## Compatibility observation

The historical
`tb_hdec_ecc_pmul_bg_hdc_loop_v31.sv` test is not an admissible VV31
baseline.  On the entry RTL it reports 34 HDC data mismatches even though the
background PMUL reaches its completion point.  Its fixed K=3 workload,
status polling, and legacy VRF assumptions also violate the VV31 test
contract.  It is retained only as diagnostic history.

## Compatibility gate conclusion

All nine VV30 functional tests produced their required PASS signatures,
including 16 fresh random-K PMUL cases, the HDC full flow, and the complete
HPERM contract. Every random scalar produced the correct point and required
exactly 159221 cycles.

The legacy VV30 runner reported an overall FAIL only because its dedicated
HPERM path concatenated the same PASS signature from both the driver log and
the XSim result log. The resulting `pass_marker_count=2` violates that
runner's bookkeeping rule requiring exactly one marker. The tool exit was
zero, no failure marker was present, and the HPERM XSim log explicitly
reported all 1024 rotation encodings, all 256 slot pairs, and PASS. This is a
runner accounting defect rather than an RTL failure.

VV31-0 therefore passes the engineering gate and becomes the frozen
incremental baseline for ECC-only scheduling.
