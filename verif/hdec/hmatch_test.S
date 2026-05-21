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

pass:
    li a0, 0
    j _exit

fail:
    li a0, 1
    j _exit
