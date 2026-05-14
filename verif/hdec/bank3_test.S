# bank3_test.S — test VRF bank 3 (address 192-255)
    .section ".text.init"
    .globl main
main:
    # vaddr(192) → bank=3, reg=0
    li a0, 192
    .insn r 0x0B, 2, 3, zero, a0, zero
    # vwr64
    li a0, 0x5555555555555555
    .insn r 0x0B, 0, 2, t0, a0, zero
    # vaddr(192)
    li a0, 192
    .insn r 0x0B, 2, 3, zero, a0, zero
    # vrd64
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0x5555555555555555
    bne t1, t2, fail

    # vaddr(255) → bank=3, reg=63
    li a0, 255
    .insn r 0x0B, 2, 3, zero, a0, zero
    # vwr64
    li a0, 0x6666666666666666
    .insn r 0x0B, 0, 2, t0, a0, zero
    # vaddr(255)
    li a0, 255
    .insn r 0x0B, 2, 3, zero, a0, zero
    # vrd64
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0x6666666666666666
    bne t1, t2, fail

pass:
    li a0, 0
    j _exit
fail:
    li a0, 1
    j _exit
