// VRF write/read round-trip: vwr64 → vrd64
    .section ".text.init"
    .globl main
main:
    # vwr64: write 0xCAFE0001 to VRF[0], bank=0
    li a0, 0xCAFE0001
    li a1, 0              # bank=0, reg=0
    .insn r 0x0B, 0, 2, t0, a0, a1   // VWR64

    # vwr64: write 0xDEADBEEF to VRF[1], bank=1
    li a0, 0xDEADBEEF
    li a1, 64             # bank=1, reg=1
    .insn r 0x0B, 0, 2, t0, a0, a1

    # vrd64: read back VRF[0], bank=0
    li a1, 0
    .insn r 0x0B, 1, 2, t1, a1, zero  // VRD64
    li t2, 0xCAFE0001
    bne t1, t2, fail

    # vrd64: read back VRF[1], bank=1
    li a1, 64
    .insn r 0x0B, 1, 2, t1, a1, zero
    li t2, 0xDEADBEEF
    bne t1, t2, fail

pass:
    li a0, 0
    j _exit
fail:
    li a0, 1
    j _exit
