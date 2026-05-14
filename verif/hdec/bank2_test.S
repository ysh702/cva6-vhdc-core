# bank2_test.S — test VRF bank 2 (address 128-191)
    .section ".text.init"
    .globl main
main:
    # vaddr(128) → bank=2, reg=0
    li a0, 128
    .insn r 0x0B, 2, 3, zero, a0, zero
    # vwr64
    li a0, 0x3333333333333333
    .insn r 0x0B, 0, 2, t0, a0, zero
    # vaddr(128)
    li a0, 128
    .insn r 0x0B, 2, 3, zero, a0, zero
    # vrd64
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0x3333333333333333
    bne t1, t2, fail

    # vaddr(191) → bank=2, reg=63
    li a0, 191
    .insn r 0x0B, 2, 3, zero, a0, zero
    # vwr64
    li a0, 0x4444444444444444
    .insn r 0x0B, 0, 2, t0, a0, zero
    # vaddr(191)
    li a0, 191
    .insn r 0x0B, 2, 3, zero, a0, zero
    # vrd64
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0x4444444444444444
    bne t1, t2, fail

pass:
    li a0, 0
    j _exit
fail:
    li a0, 1
    j _exit
