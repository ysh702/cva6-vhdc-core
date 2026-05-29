# hdc_pipeline_test.S - end-to-end HDC primitive pipeline smoke test
# Pipeline: HBind -> HBundle4 -> HClip -> HSim -> HMatch

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

    .macro HBIND param
    li a0, \param
    .insn r 0x0B, 5, 2, t0, a0, zero
    .endm

    .macro HCNTADD param
    li a0, \param
    .insn r 0x0B, 4, 2, t0, a0, zero
    .endm

    .macro HCNTCLIP param
    li a0, \param
    .insn r 0x0B, 0, 3, t0, a0, zero
    .endm

    .macro HSIM param
    li a0, \param
    .insn r 0x0B, 7, 2, t0, a0, zero
    .endm

    .macro HMATCH param
    li a0, \param
    .insn r 0x0B, 1, 3, t0, a0, zero
    .endm

main:
    HCLR 0
    HCLR 1
    HCLR 2
    HCLR 3
    HCLR 4
    HCLR 5
    HCLR 6
    HCNTCLR 0

    # HV1 and HV3 are all ones. HV0, HV4, HV5 stay zero.
    li a2, 0
fill_loop:
    li a3, 0
fill_bank_loop:
    addi t4, a2, 4
    add a0, t4, a3
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, -1
    .insn r 0x0B, 0, 2, t0, a0, zero

    addi t4, a2, 12
    add a0, t4, a3
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, -1
    .insn r 0x0B, 0, 2, t0, a0, zero

    addi a3, a3, 64
    li t4, 256
    blt a3, t4, fill_bank_loop

    addi a2, a2, 1
    li t3, 4
    blt a2, t3, fill_loop

    # HBind: HV2 = HV0 XOR HV1 = all ones.
    HBIND 0x102
    bnez t0, fail
    VCHECK 8, 0xFFFFFFFFFFFFFFFF

    # HBundle4 base=HV2 accumulates HV2/HV3/HV4/HV5, so every counter becomes 2.
    HCNTADD 2; HCNTADD 3; HCNTADD 4; HCNTADD 5
    bnez t0, fail
    VCHECK 32, 0x2222222222222222
    VCHECK 47, 0x2222222222222222

    # HClip threshold=2 writes HV6 = all ones.
    HCNTCLIP 0x26
    bnez t0, fail
    VCHECK 24, 0xFFFFFFFFFFFFFFFF
    VCHECK 27, 0xFFFFFFFFFFFFFFFF

    # HSim confirms clipped HV6 matches HV1.
    HSIM 0x16
    bnez t0, fail

    # HMatch query=HV6 against HV0..HV4. HV1 and HV2 tie at distance 0;
    # relative index 1 must win.
    HMATCH 0x0506
    li t2, 0x800
    bne t0, t2, fail

pass:
    li a0, 0
    j _exit

fail:
    li a0, 1
    j _exit
