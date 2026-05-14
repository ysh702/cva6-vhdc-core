# bank1_test.S — test VRF bank 1 (address 64-127)
    .section ".text.init"
    .globl main
main:
    # vaddr(64) → bank=1, reg=0
    li a0, 64
    .insn r 0x0B, 2, 3, zero, a0, zero
    # vwr64
    li a0, 0x1111111111111111
    .insn r 0x0B, 0, 2, t0, a0, zero
    # vaddr(64)
    li a0, 64
    .insn r 0x0B, 2, 3, zero, a0, zero
    # vrd64
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0x1111111111111111
    bne t1, t2, fail

    # vaddr(127) → bank=1, reg=63 (max)
    li a0, 127
    .insn r 0x0B, 2, 3, zero, a0, zero
    # vwr64
    li a0, 0x2222222222222222
    .insn r 0x0B, 0, 2, t0, a0, zero
    # vaddr(127)
    li a0, 127
    .insn r 0x0B, 2, 3, zero, a0, zero
    # vrd64
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0x2222222222222222
    bne t1, t2, fail

pass:
    li a0, 0
    j _exit
fail:
    li a0, 1
    j _exit
