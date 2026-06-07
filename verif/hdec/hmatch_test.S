# hmatch_test.S - test HMatch semantics through HDEC_HSEARCH encoding
# hsearch/hmatch encoding: funct7=3, funct3=1
# rs1[3:0]=query_hv_slot, rs1[7:4]=class_base_slot, rs1[15:8]=num_classes
# result[10:0]=min_distance, result[18:11]=min_index, result[63:19]=0

    .section ".text.init"
    .globl main

    .macro VWRITE addr, value
    li a0, \addr
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, \value
    .insn r 0x0B, 0, 2, t0, a0, zero
    .endm

    .macro VCHECK addr, value
    li a0, \addr
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, \value
    bne t1, t2, fail
    .endm

    .macro HCLR slot
    li a0, \slot
    .insn r 0x0B, 2, 2, t0, a0, zero
    .endm

    .macro HMATCH param
    li a0, \param
    .insn r 0x0B, 1, 3, t0, a0, zero
    .endm

main:
    # Query HV0 = all zero. Classes HV1/HV2/HV3 are all-one, all-zero, mixed.
    HCLR 0
    HCLR 1
    HCLR 2
    HCLR 3

    li a2, 0
class_fill_loop:
    li a3, 0
class_fill_bank_loop:
    # HV1 all ones.
    addi t4, a2, 4
    add a0, t4, a3
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, -1
    .insn r 0x0B, 0, 2, t0, a0, zero

    # HV2 all zeros.
    addi t4, a2, 8
    add a0, t4, a3
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0
    .insn r 0x0B, 0, 2, t0, a0, zero

    # HV3 half-set alternating pattern.
    addi t4, a2, 12
    add a0, t4, a3
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0xAAAAAAAAAAAAAAAA
    .insn r 0x0B, 0, 2, t0, a0, zero

    addi a3, a3, 64
    li t4, 256
    blt a3, t4, class_fill_bank_loop

    addi a2, a2, 1
    li t3, 4
    blt a2, t3, class_fill_loop

    # base=HV1, num_classes=3, query=HV0. Best is HV2 at relative index 1.
    HMATCH 0x0310
    li t2, 0x800
    bne t0, t2, fail

    # Tie case: HV4 and HV5 both equal query; first relative index must win.
    HCLR 4
    HCLR 5
    HMATCH 0x0240
    bnez t0, fail

    # Non-zero best distance: query HV0 vs only HV3 gives distance 512.
    HMATCH 0x0130
    li t2, 512
    bne t0, t2, fail

    # Illegal num_classes=0 returns STATUS_ERROR.
    HMATCH 0x0010
    li t2, 2
    bne t0, t2, fail

    # Illegal class range base=6,num=3 would exceed HV7 and must not corrupt VRF.
    VWRITE 28, 0x0123456789ABCDEF
    HMATCH 0x0360
    li t2, 2
    bne t0, t2, fail
    VCHECK 28, 0x0123456789ABCDEF

    # Query source remains intact.
    VCHECK 0, 0x0000000000000000

    # ═══════════════════════════════════════════════════════════════
    # V1 budget countdown directed cases
    # Query = HV0 (all zeros), baseline at slot 4 (VRF 16-19).
    # Baseline: 4 chunks × popcount 25 = total distance 100.
    # Candidate at slot 5 (VRF 20-23) varies per case.
    # HMATCH 0x0240: num=2, base=4, query=0.
    # ═══════════════════════════════════════════════════════════════

    # --- Setup baseline class (slot 4) once ---
    # Each chunk: bank 0 carries popcount 25, banks 1-3 stay zero from HCLR.
    HCLR 4
    VWRITE 16, 0x0000000001FFFFFF   # chunk 0
    VWRITE 17, 0x0000000001FFFFFF   # chunk 1
    VWRITE 18, 0x0000000001FFFFFF   # chunk 2
    VWRITE 19, 0x0000000001FFFFFF   # chunk 3

    # --- Case 1: candidate 120/10/10/10, total=150 > 100, baseline wins ---
    HCLR 5
    # Chunk 0: 4 banks × 30 = 120
    VWRITE 20,  0x000000003FFFFFFF
    VWRITE 84,  0x000000003FFFFFFF
    VWRITE 148, 0x000000003FFFFFFF
    VWRITE 212, 0x000000003FFFFFFF
    # Chunks 1-3: bank 0 popcount 10
    VWRITE 21, 0x00000000000003FF
    VWRITE 22, 0x00000000000003FF
    VWRITE 23, 0x00000000000003FF
    HMATCH 0x0240
    li t2, 0x64
    bne t0, t2, fail

    # --- Case 2: candidate 50/50/0/0, total=100, tie, baseline wins ---
    HCLR 5
    # Chunk 0: bank 0 + bank 1 = 25+25 = 50
    VWRITE 20, 0x0000000001FFFFFF
    VWRITE 84, 0x0000000001FFFFFF
    # Chunk 1: same
    VWRITE 21, 0x0000000001FFFFFF
    VWRITE 85, 0x0000000001FFFFFF
    # Chunks 2-3 stay zero from HCLR
    HMATCH 0x0240
    li t2, 0x64
    bne t0, t2, fail

    # --- Case 3: candidate 30/30/30/9, total=99 < 100, candidate wins ---
    HCLR 5
    VWRITE 20, 0x000000003FFFFFFF   # chunk 0: pop30
    VWRITE 21, 0x000000003FFFFFFF   # chunk 1: pop30
    VWRITE 22, 0x000000003FFFFFFF   # chunk 2: pop30
    VWRITE 23, 0x00000000000001FF   # chunk 3: pop9
    HMATCH 0x0240
    li t2, 0x863                     # idx=1 (0x800) | dist=99 (0x63)
    bne t0, t2, fail

    # --- Case 4: candidate 30/30/30/10, total=100, tie, baseline wins ---
    HCLR 5
    VWRITE 20, 0x000000003FFFFFFF
    VWRITE 21, 0x000000003FFFFFFF
    VWRITE 22, 0x000000003FFFFFFF
    VWRITE 23, 0x00000000000003FF   # pop10
    HMATCH 0x0240
    li t2, 0x64
    bne t0, t2, fail

    # --- Case 5: candidate 30/30/30/11, total=101 > 100, baseline wins ---
    HCLR 5
    VWRITE 20, 0x000000003FFFFFFF
    VWRITE 21, 0x000000003FFFFFFF
    VWRITE 22, 0x000000003FFFFFFF
    VWRITE 23, 0x00000000000007FF   # pop11
    HMATCH 0x0240
    li t2, 0x64
    bne t0, t2, fail

    # --- Case 6: first-class-is-best ---
    # Single class at slot 4, no candidate. First class distance 100 < 1025.
    HMATCH 0x0140                     # num=1, base=4, query=0
    li t2, 0x64                       # idx=0, dist=100
    bne t0, t2, fail

pass:
    li a0, 0
    j _exit

fail:
    li a0, 1
    j _exit
