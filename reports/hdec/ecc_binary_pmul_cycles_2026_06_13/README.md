# Binary-field ECC scalar point multiplication cycle survey

Date: 2026-06-13

Local HDEC reference:

- Curve/field: K-233 / sect233k1-style binary curve over `GF(2^233)`
- Reduction polynomial: `x^233 + x^74 + 1`
- One full scalar point multiplication: `PMUL_CYCLES=6005`
- At 200 MHz: about `30.0 us`

## Main takeaway

`6005` cycles is competitive for a `GF(2^233)` integrated accelerator. It is not as low as highly specialized high-speed ECC-only processors with multiple full-precision multipliers, but it is much faster than area-first bit-serial or digit-serial designs and is close to several throughput/area-optimized `GF(2^233)` FPGA implementations.

This supports the V27 story:

> Do not claim that ECC is almost free in area. Claim that HDEC integrates a competitive 233-bit PMUL engine and can hide its latency behind repeated HDC execution through foreground-HDC/background-ECC interleaving.

## Survey table

| # | Paper/design | Field / curve style | Platform | Full scalar PMUL cycles | Notes |
| ---: | --- | --- | --- | ---: | --- |
| HDEC | Current RTL | `GF(2^233)`, K-233-style | Vivado 2024.2 OOC, target 200 MHz | 6005 | One complete PMUL macro-job, including scalar loop and final recovery |
| 1 | Rashid et al., "Throughput/Area-Efficient Accelerator of ECPM over GF(2^233) on FPGA", Electronics 2023 | `GF(2^233)` | Virtex-7 | 7208 | Full ECPM; 350 MHz; 20.59 us |
| 2 | Imran et al., "Throughput/area optimised pipelined architecture for elliptic curve crypto processor", IET CDT 2019 | `GF(2^233)` | Virtex-7 | 5634 | Reported in later comparison tables; 357 MHz; 15.78 us |
| 3 | Khan and Benaissa, "Throughput/Area-efficient ECC Processor Using Montgomery Point Multiplication on FPGA", IEEE TCAS II 2015 | `GF(2^233)` | Virtex-7 | about 5920 | Reported as 16.01 us at 370 MHz; cycle count inferred from time/frequency and their cycle model |
| 4 | Aljaedi et al., "FPGA Implementation of ECC Using Additive and Multiplicative Polynomial Inverses", IEEE Access 2024 | `GF(2^233)` | Virtex-7 | 174457 | Area-oriented Booth-polynomial design; 393 MHz; 443.91 us |
| 5 | Aljaedi et al., "Area-Efficient Realization of ECC Processor Architecture over GF(2^m) on FPGA", Applied Sciences 2023 | `GF(2^233)` | Virtex-7 | 716459 | Very compact area-first design; 161 MHz; 4.45 ms |
| 6 | Rebeiro et al., "Pushing the Limits of High-Speed GF(2^m) Elliptic Curve Scalar Multiplication on FPGAs", CHES 2012 | `GF(2^163)` exact cycle table; also evaluates larger fields | Virtex-5 | 1429 for `GF(2^163)` | Extreme high-speed ECC-only design; larger-field timings imply far lower cycles than HDEC but use specialized parallel hardware |
| 7 | Khan and Benaissa, "High-Speed and Low-Latency ECC Processor Implementation over GF(2^m) on FPGA", IEEE TVLSI 2017 | `GF(2^163)` to `GF(2^571)` | Virtex-5/7 | 450 for `GF(2^163)` LLECC; 1119 for `GF(2^163)` HPECC; 3783 for `GF(2^571)` HPECC | Highly specialized low-latency designs with multiple field multipliers in the fastest variant |
| 8 | Umer et al., "Efficient Crypto Processor Architecture for Side-Channel Resistant Binary Huff Curves", Electronics 2022 | `GF(2^233)` Binary Huff curve | Virtex-7 | 13124 | Best reported proposed config; includes side-channel-resistant Binary Huff PMUL |
| 9 | Rashid et al., "A Compact 3-Stage Pipelined Hardware Accelerator for Point Multiplication on Elliptic Curves over GF(2^m)", Applied Sciences 2023 | `GF(2^409)` / `GF(2^571)` | Virtex-7 | 13903 for `GF(2^409)`; 20551 for `GF(2^571)` | Larger-field proposed 3-stage pipeline |
| 10 | Rashid et al., "A Novel Low-Area Point Multiplication Architecture for Elliptic-Curve Cryptography", Electronics 2021 | binary field, low-area PMUL | Virtex-7 | 162673 | Low-area serial architecture, much slower but small |

## Relative interpretation

Against `GF(2^233)` throughput/area designs:

- HDEC vs 7208 cycles: HDEC uses about `16.7%` fewer cycles.
- HDEC vs 5634 cycles: HDEC uses about `6.6%` more cycles.
- HDEC vs about 5920 cycles: HDEC is essentially the same cycle class.

Against area-first designs:

- HDEC vs 174457 cycles: HDEC is about `29x` fewer cycles.
- HDEC vs 716459 cycles: HDEC is about `119x` fewer cycles.
- HDEC vs 162673 cycles: HDEC is about `27x` fewer cycles.

Against high-speed ECC-only designs:

- HDEC is slower in cycles than the most aggressive dedicated ECC processors.
- This is expected because those designs use specialized parallel multipliers and are not trying to share a HDC-oriented datapath.

## Suggested wording for the paper

Strong wording:

> The proposed integrated HDC/ECC datapath completes one 233-bit binary-field scalar point multiplication in 6005 cycles, placing it in the same cycle class as throughput/area-optimized GF(2^233) ECC accelerators while retaining the HDC execution substrate. V27 further exploits temporal compatibility by scheduling ECC as a background job behind foreground HDC operations.

Avoid:

> Our ECC PMUL is the fastest.

Avoid:

> ECC area is almost free.

Better:

> The area overhead buys a competitive ECC PMUL engine whose latency can be partially or fully hidden under repeated HDC execution.

## Sources

- Rashid et al., Electronics 2023, Throughput/Area-Efficient Accelerator of ECPM over GF(2^233): https://www.mdpi.com/2079-9292/12/17/3611
- Aljaedi et al., Applied Sciences 2023, Area-Efficient Realization of ECC Processor Architecture over GF(2^m): https://www.mdpi.com/2076-3417/13/12/7018
- Aljaedi et al., IEEE Access 2024, FPGA Implementation of ECC Using Additive and Multiplicative Polynomial Inverses: https://pureadmin.qub.ac.uk/ws/portalfiles/portal/628046952/FPGA_Implementation_of_ECC_Using_Additive_and_Multiplicative_Polynomial_Inverses.pdf
- Khan and Benaissa, IEEE TCAS II 2015, Throughput/Area-efficient ECC Processor Using Montgomery PM on FPGA: https://eprints.whiterose.ac.uk/id/eprint/92952/9/WRRO_92952.pdf
- Rebeiro et al., CHES 2012, Pushing the Limits of High-Speed GF(2^m) ECC Scalar Multiplication on FPGAs: https://scispace.com/pdf/pushing-the-limits-of-high-speed-gf-2-m-elliptic-curve-4dkhu96f2r.pdf
- Khan and Benaissa, IEEE TVLSI 2017, High-Speed and Low-Latency ECC Processor Implementation over GF(2^m): https://eprints.whiterose.ac.uk/id/eprint/99476/1/Final_1Revised_TVLSI_00793_2015.pdf
- Umer et al., Electronics 2022, Efficient Crypto Processor Architecture for Side-Channel Resistant Binary Huff Curves: https://www.mdpi.com/2079-9292/11/7/1131
- Rashid et al., Applied Sciences 2023, Compact 3-Stage Pipelined Hardware Accelerator: https://www.mdpi.com/2076-3417/13/3/1240
- Rashid et al., Electronics 2021, Low-Area Point Multiplication Architecture: https://www.mdpi.com/2079-9292/10/21/2698

