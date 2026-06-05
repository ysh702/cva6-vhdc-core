// HDEC VRF read/write smoke test using the current VADDR protocol.
// VADDR rs1[7:6] selects bank, rs1[5:0] selects index.
    .section ".text.init"
    .globl main
main:
    # bank0/index0
    li a0, 0
    .insn r 0x0B, 2, 3, zero, a0, zero   // VADDR
    li a0, 0xDEADBEEFCAFE0001
    .insn r 0x0B, 0, 2, t0, a0, zero     // VWR64

    li a0, 0
    .insn r 0x0B, 2, 3, zero, a0, zero   // VADDR
    .insn r 0x0B, 1, 2, t1, zero, zero   // VRD64
    li t2, 0xDEADBEEFCAFE0001
    bne t1, t2, fail

    # bank1/index1: (1 << 6) | 1 = 65
    li a0, 65
    .insn r 0x0B, 2, 3, zero, a0, zero   // VADDR
    li a0, 0x1234567890ABCDEF
    .insn r 0x0B, 0, 2, t0, a0, zero     // VWR64

    li a0, 65
    .insn r 0x0B, 2, 3, zero, a0, zero   // VADDR
    .insn r 0x0B, 1, 2, t1, zero, zero   // VRD64
    li t2, 0x1234567890ABCDEF
    bne t1, t2, fail

pass:
    li a0, 0
    j _exit
fail:
    li a0, 1
    j _exit
