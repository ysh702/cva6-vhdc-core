# hdc_inference_test.S — HDC Inference Benchmark (Cold-start + Steady-state)
#
# Data layout:
#   HV0: class 0 prototype = 0x0000000000000000 (all zeros, kept from init)
#   HV1: class 1 prototype = 0xFFFFFFFFFFFFFFFF
#   HV2: class 2 prototype = 0xAAAAAAAAAAAAAAAA  ← target class
#   HV3: class 3 prototype = 0x5555555555555555
#   HV4: query basis A = 0xAAAAAAAAAAAAAAAA
#   HV5: query basis B = 0xAAAAAAAAAAAAAAAA
#   HV6: query basis C = 0xAAAAAAAAAAAAAAAA
#   HV7: query basis D = 0xAAAAAAAAAAAAAAAA
#   acc0: bundle accumulator
#
# Flow:
#   Cold-start: init → preload prototypes → preload basis → HBUNDLE4 → HCLIP → HMATCH
#   Steady-state compute region: HBUNDLE4 + HCLIP + HMATCH (165c estimated)
#   Preload region: all VADDR+VWR64 before first compute op
#
# Expected: HMATCH(query=HV4, class_base=HV0, num_classes=4) → min_idx=2, min_dist=0

    .section ".text.init"
    .globl main

    .macro VWRITE addr, value
    li a0, \addr
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, \value
    .insn r 0x0B, 0, 2, t0, a0, zero
    .endm

    .macro HCLR slot
    li a0, \slot
    .insn r 0x0B, 2, 2, t0, a0, zero
    .endm

    .macro BCLR acc
    li a0, \acc
    .insn r 0x0B, 3, 2, t0, a0, zero
    .endm

    .macro HBUNDLE4 param
    li a0, \param
    .insn r 0x0B, 4, 3, t0, a0, zero
    .endm

    .macro HCLIP param
    li a0, \param
    .insn r 0x0B, 0, 3, t0, a0, zero
    .endm

    .macro HMATCH param
    li a0, \param
    .insn r 0x0B, 1, 3, t0, a0, zero
    .endm


main:
    # =====================================================================
    # Phase 1: Init — clear all HV slots and acc0
    # =====================================================================
    HCLR 0
    HCLR 1
    HCLR 2
    HCLR 3
    HCLR 4
    HCLR 5
    HCLR 6
    HCLR 7
    BCLR 0

    # =====================================================================
    # Phase 2: Preload class prototypes HV0-HV3
    #   HV0 stays all-zero from HCLR (class 0 = 0x0000...)
    # =====================================================================

    # --- HV1 (slot 1, entries 4-7): class 1 = all ones ---
    li t3, 0xFFFFFFFFFFFFFFFF
    li t4, 4
    jal fill_hv

    # --- HV2 (slot 2, entries 8-11): class 2 = 0xAAAA... ---
    li t3, 0xAAAAAAAAAAAAAAAA
    li t4, 8
    jal fill_hv

    # --- HV3 (slot 3, entries 12-15): class 3 = 0x5555... ---
    li t3, 0x5555555555555555
    li t4, 12
    jal fill_hv

    # =====================================================================
    # Phase 3: Preload query basis HVs HV4-HV7 (all 0xAAAA...)
    # =====================================================================

    li t3, 0xAAAAAAAAAAAAAAAA

    li t4, 16
    jal fill_hv       # HV4 (entries 16-19)

    li t4, 20
    jal fill_hv       # HV5 (entries 20-23)

    li t4, 24
    jal fill_hv       # HV6 (entries 24-27)

    li t4, 28
    jal fill_hv       # HV7 (entries 28-31)

    # =====================================================================
    # Phase 4: Encode — bundle HV4-HV7 into acc0
    #   HBUNDLE4 base=4, acc_sel=0
    #   This is the start of the steady-state compute region
    # =====================================================================
    HBUNDLE4 0x04

    # =====================================================================
    # Phase 5: Query — clip acc0 into HV4 (overwrite)
    #   HCLIP dst=4, acc_sel=0, threshold=2
    #   Since all 4 basis HVs are identical 0xAAAA..., counters are 0 or 4.
    #   threshold=2 → output=1 iff counter>=2 → query = 0xAAAA...
    # =====================================================================
    HCLIP 0x24

    # =====================================================================
    # Phase 6: Match — 4-class HMATCH
    #   Query=HV4, class_base=HV0, num_classes=4
    #   Expected: min_idx=2 (HV2 = 0xAAAA... = query), min_dist=0
    # =====================================================================
    HMATCH 0x0404

    # =====================================================================
    # Phase 7: Check result
    #   Result format: [63:19]=0, [18:11]=min_idx, [10:0]=min_dist
    #   Expected: min_idx=2, min_dist=0  →  full result = (2<<11)|0 = 0x1000
    # =====================================================================
    li t2, 0x1000
    bne t0, t2, fail

pass:
    li a0, 0
    j _exit

fail:
    li a0, 1
    j _exit


# =============================================================================
# Subroutine: fill_hv
#   Fill a 1024-bit HV slot with a constant 64-bit value.
#
#   Input:
#     t3 = 64-bit value to replicate across all banks/entries
#     t4 = base VRF entry index (slot * 4)
#
#   Writes 16 × (VADDR + VWR64):
#     4 entries × 4 banks = 16 addresses
#     address = bank*64 + base + chunk    (bank 0..3, chunk 0..3)
#
#   Clobbers: a0, t5, t6
#   Preserves: ra, t3, t4
# =============================================================================
fill_hv:
    addi sp, sp, -16
    sd   ra, 0(sp)
    sd   t3, 8(sp)

    li t5, 0               # chunk = 0..3 (entry offset within HV slot)
1:
    li t6, 0               # bank = 0..3
2:
    slli a0, t6, 6         # a0 = bank * 64
    add  a0, a0, t4        # a0 = bank*64 + base
    add  a0, a0, t5        # a0 = bank*64 + base + chunk
    .insn r 0x0B, 2, 3, zero, a0, zero   # VADDR
    mv   a0, t3
    .insn r 0x0B, 0, 2, t0, a0, zero     # VWR64
    addi t6, t6, 1
    li   a0, 4
    blt  t6, a0, 2b
    addi t5, t5, 1
    li   a0, 4
    blt  t5, a0, 1b

    ld   t3, 8(sp)
    ld   ra, 0(sp)
    addi sp, sp, 16
    ret
