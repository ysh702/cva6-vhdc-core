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
    .macro HCNTCLR acc
    li a0, \acc
    .insn r 0x0B, 3, 2, t0, a0, zero
    .endm
    .macro HCNTADD param
    li a0, \param
    .insn r 0x0B, 4, 2, t0, a0, zero
    .endm
    .macro HCNTCLIP param
    li a0, \param
    .insn r 0x0B, 0, 3, t0, a0, zero
    .endm
main:
    # Case 1
    HCNTCLR 0
    HCNTCLIP 0
    VCHECK 0, -1

    # Case 2
    HCLR 0
    HCNTCLR 0
    VWRITE 0, -1
    VWRITE 4, -1
    VWRITE 8, -1
    VWRITE 12,-1
    HCNTADD 0
    HCNTCLIP 0x11
    VCHECK 4, -1

    # Case 3
    HCLR 0
    HCNTCLR 0
    VWRITE 0, -1
    VWRITE 4, -1
    VWRITE 8, -1
    VWRITE 12,-1
    HCNTADD 0
    HCNTCLIP 0x22
    VCHECK 8, 0

    # Case 4
    HCLR 0
    HCNTCLR 0
    VWRITE 0, -1
    VWRITE 4, -1
    VWRITE 8, -1
    VWRITE 12,-1
    li a5, 0
1:
    HCNTADD 0
    addi a5, a5, 1
    li t3, 15
    blt a5, t3, 1b
    HCNTCLIP 0x83
    VCHECK 12, -1

pass:
    li a0, 0
    j _exit
fail:
    li a0, 1
    j _exit
