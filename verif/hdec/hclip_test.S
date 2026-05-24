# hclip_test.S - test HClip thresholding over packed 4-bit counters
# hclip encoding: funct7=3, funct3=0
# rs1[2:0]=dst_hv_slot, rs1[3]=acc_sel, rs1[7:4]=threshold

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

    .macro BCLR acc
    li a0, \acc
    .insn r 0x0B, 3, 2, t0, a0, zero
    .endm

    .macro HCLIP param
    li a0, \param
    .insn r 0x0B, 0, 3, t0, a0, zero
    .endm

main:
    # Pre-implementation guard: HClip is decoded but returns NOT_IMPLEMENTED
    # until the RTL path exists.
    BCLR 0
    HCLR 2
    HCLIP 0x42
    bnez t0, fail

    # Case 1: threshold 8 over a nibble ramp writes low 16 output bits.
    HCLR 2
    VWRITE 32, 0xFEDCBA9876543210
    HCLIP 0x82
    bnez t0, fail
    VCHECK 8, 0x000000000000FF00

    # Case 2: threshold 0 is legal and emits all ones for each packed word.
    HCLR 3
    VWRITE 33, 0x0000000000000000
    VWRITE 97, 0x1111111111111111
    HCLIP 0x03
    bnez t0, fail
    VCHECK 12, 0xFFFFFFFFFFFFFFFF
    VCHECK 76, 0xFFFFFFFFFFFFFFFF
    VCHECK 13, 0xFFFFFFFFFFFFFFFF
    VCHECK 77, 0xFFFFFFFFFFFFFFFF

    # Case 3: threshold 15 only selects saturated counters.
    HCLR 4
    VWRITE 34,  0xFFFFFFFFFFFFFFFF
    VWRITE 98,  0xEEEEEEEEEEEEEEEE
    VWRITE 162, 0x0000FFFF0000FFFF
    VWRITE 226, 0x0123456789ABCDEF
    HCLIP 0xF4
    bnez t0, fail
    VCHECK 16,  0x0000FFFF00008000
    VCHECK 80,  0x0000000000000000
    VCHECK 144, 0x00000F0F00000000
    VCHECK 208, 0x0000000100000000

    # Case 4: acc1 source and destination isolation from acc0.
    HCLR 5
    VWRITE 32, 0xFFFFFFFFFFFFFFFF
    BCLR 1
    VWRITE 48, 0x777788889999AAAA
    HCLIP 0x8D
    bnez t0, fail
    VCHECK 20, 0x0000000000000FFF
    VCHECK 32, 0xFFFFFFFFFFFFFFFF

pass:
    li a0, 0
    j _exit

fail:
    li a0, 1
    j _exit
