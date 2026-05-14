# bank0_test.S — test VRF bank 0 (address 0-63)
    .section ".text.init"
    .globl main
main:
    # vaddr(0) → bank=0, reg=0
    li a0, 0
    .insn r 0x0B, 2, 3, zero, a0, zero
    # vwr64: write pattern to VRF[0][0]
    li a0, 0xDEADBEEF00000000
    .insn r 0x0B, 0, 2, t0, a0, zero
    # vaddr(0) → re-set
    li a0, 0
    .insn r 0x0B, 2, 3, zero, a0, zero
    # vrd64: read back
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0xDEADBEEF00000000
    bne t1, t2, fail

    # vaddr(63) → bank=0, reg=63 (max for this bank)
    li a0, 63
    .insn r 0x0B, 2, 3, zero, a0, zero
    # vwr64: write to VRF[0][63]
    li a0, 0x00000000B0B00000
    .insn r 0x0B, 0, 2, t0, a0, zero
    # vaddr(63)
    li a0, 63
    .insn r 0x0B, 2, 3, zero, a0, zero
    # vrd64
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0x00000000B0B00000
    bne t1, t2, fail

pass:
    li a0, 0
    j _exit
fail:
    li a0, 1
    j _exit
