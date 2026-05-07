# =============================================================================
# hdec_full_test.S — Full HDEC test: HDC + ECC, bare-metal via CV-X-IF
# =============================================================================

#include "encoding.h"
#include "hdec_test_macros.h"

  .section ".text.init"
  .globl main

main:
  # ===========================================================================
  # Phase 1: INGEST data into VRF
  # ===========================================================================
  # VRF reg 0: 4 banks with test pattern (0xAA,0xBB,0xCC,0xDD)
  li a0, 0xAA
  li a1, 0x0
  HDEC_INGEST(t0, a0, a1)

  li a0, 0xBB
  HDEC_INGEST(t0, a0, a1)

  li a0, 0xCC
  HDEC_INGEST(t0, a0, a1)

  li a0, 0xDD
  HDEC_INGEST(t0, a0, a1)

  # ===========================================================================
  # Phase 2: ECC — start, run HDC while ECC computes, then fetch
  # ===========================================================================
  # Start ECC with private key
  li a0, 0xDEADBEEF
  HDEC_ECC_START(t0, a0)

  # While ECC runs in background, do HDC operations
  # BIND: VRF[2] = VRF[0] XOR VRF[1]
  li a0, VRF_ADDR(2, 0, 1)
  HDEC_BIND(t0, a0)

  # PERMUTE: VRF[3] = rotate VRF[0]
  li a0, VRF_ADDR(3, 0, 0)
  HDEC_PERMUTE(t0, a0)

  # MATCH: popcnt of VRF[0] XOR VRF[1]
  li a0, VRF_ADDR(0, 0, 1)
  HDEC_MATCH(t0, a0)

  # BUNDLE
  HDEC_CLEAR_CNT(t0)
  li a0, VRF_ADDR(5, 0, 0)
  HDEC_BUNDLE(t0, a0)

  # BINARIZE (threshold=3)
  li a0, (3 << 15) | VRF_ADDR(6, 0, 0)
  HDEC_BINARIZE(t0, a0)

  # BUNDLE_ACCUM
  HDEC_CLEAR_CNT(t0)
  li a0, VRF_ADDR(7, 0, 0)
  HDEC_BUNDLE_ACCUM(t0, a0)

  # ===========================================================================
  # Phase 3: Fetch ECC result
  #   By now, ECC should have completed (256 iterations * parallel)
  # ===========================================================================
  li t0, 2048
ecc_spin:
  addi t0, t0, -1
  bnez t0, ecc_spin

  HDEC_ECC_FETCH(t0)

  # ===========================================================================
  # Done
  # ===========================================================================
  li a0, 0x0
  jal exit
