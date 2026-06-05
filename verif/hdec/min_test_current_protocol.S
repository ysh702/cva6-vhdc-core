// VRF write/read round-trip using the current VADDR protocol.
// Current RTL protocol:
//   VADDR rs1[7:6] = bank, rs1[5:0] = index
//   VWR64 writes rs1 data to the internally selected VADDR
//   VRD64 reads from the internally selected VADDR
    .section ".text.init"
    .globl main
main:
    # bank0, index0: VADDR = {bank=0, idx=0} = 0
    li a0, 0
    .insn r 0x0B, 2, 3, zero, a0, zero   // VADDR

    li a0, 0xCAFE0001
    .insn r 0x0B, 0, 2, t0, a0, zero     // VWR64

    # bank1, index1: VADDR = {bank=1, idx=1} = 65
    li a0, 65
    .insn r 0x0B, 2, 3, zero, a0, zero   // VADDR

    li a0, 0xDEADBEEF
    .insn r 0x0B, 0, 2, t0, a0, zero     // VWR64

    # Read back bank0/index0
    li a0, 0
    .insn r 0x0B, 2, 3, zero, a0, zero   // VADDR

    .insn r 0x0B, 1, 2, t1, zero, zero   // VRD64
    li t2, 0xCAFE0001
    bne t1, t2, fail

    # Read back bank1/index1
    li a0, 65
    .insn r 0x0B, 2, 3, zero, a0, zero   // VADDR

    .insn r 0x0B, 1, 2, t1, zero, zero   // VRD64
    li t2, 0xDEADBEEF
    bne t1, t2, fail

pass:
    li a0, 0
    j _exit
fail:
    li a0, 1
    j _exit
