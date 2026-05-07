# =============================================================================
# hdec_steal_test.S — Cycle-Stealing Evidence: ECC interleaves into HDC's gap
# =============================================================================
# Sequence:
#   1. HDEC_ECC_START → ECC state machine enters ECC_ACTIVE
#   2. HDEC_BIND (multi-cycle, 4 sends + 4 recvs) → HDC occupies lanes
#   3. 20 NOPs → let pipeline flow
#   4. HDEC_ECC_FETCH → read ECC result
#
# Goal: capture lane_owner_in flipping from OWNER_HDC to OWNER_ECC
#       during HDC's recv phase (after 4 sends complete).
# =============================================================================

#include "encoding.h"
#include "hdec_test_macros.h"

  .section ".text.init"
  .globl main

main:
  # ── Pre-load VRF with test data (2 registers, 4 banks each) ──
  li a0, 0xAA
  li a1, 0x0
  HDEC_INGEST(t0, a0, a1)
  li a0, 0xBB
  HDEC_INGEST(t0, a0, a1)
  li a0, 0xCC
  HDEC_INGEST(t0, a0, a1)
  li a0, 0xDD
  HDEC_INGEST(t0, a0, a1)

  # VRF reg 1: fill with zeros (4 more INGESTs advance counter to next sub-chunk)
  li a0, 0x0
  li a1, 0x1
  HDEC_INGEST(t0, a0, a1)
  HDEC_INGEST(t0, a0, a1)
  HDEC_INGEST(t0, a0, a1)
  HDEC_INGEST(t0, a0, a1)

  # ═══════════════════════════════════════════════════════════════
  # CRITICAL SEQUENCE: ECC_START → BIND → NOPs → ECC_FETCH
  # ═══════════════════════════════════════════════════════════════

  # Step 1: Fire ECC_START (fast path, returns immediately, ECC runs in background)
  li a0, 0xDEADBEEF
  HDEC_ECC_START(t0, a0)

  # Step 2: IMMEDIATELY fire BIND (multi-cycle, 4 sends + 4 recvs)
  #         ECC_ACTIVE should wait and then steal S1 during recv phase
  li a0, VRF_ADDR(2, 0, 1)     # vd=2, vs1=0, vs2=1
  HDEC_BIND(t0, a0)

  # Step 3: 20 NOPs to let pipeline drain + ECC run
  nop; nop; nop; nop; nop;
  nop; nop; nop; nop; nop;
  nop; nop; nop; nop; nop;
  nop; nop; nop; nop; nop;

  # Step 4: Spin-wait for ECC to finish, then fetch result
  li t0, 256
ecc_spin:
  addi t0, t0, -1
  bnez t0, ecc_spin

  HDEC_ECC_FETCH(t0)

  # ── Done ──
  li a0, 0x0
  jal exit
