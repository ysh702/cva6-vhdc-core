# va_test.S — single-bank VRF r/w via vaddr protocol
# vaddr: funct7=3, funct3=2  → set internal VRF address from rs1[7:0]
# vwr64: funct7=2, funct3=0  → write rs1 to VRF[stored_addr]
# vrd64: funct7=2, funct3=1  → read VRF[stored_addr] → rd

    .section ".text.init"
    .globl main

main:
    # 1. vaddr(0) → bank=0, reg=0
    li a0, 0
    .insn r 0x0B, 2, 3, zero, a0, zero

    # 2. vwr64: write 0xCAFE0001 to VRF[0][0]
    li a0, 0xCAFE0001
    .insn r 0x0B, 0, 2, t0, a0, zero

    # 3. vaddr(0) again to re-set for read
    li a0, 0
    .insn r 0x0B, 2, 3, zero, a0, zero

    # 4. vrd64: read from VRF[0][0]
    .insn r 0x0B, 1, 2, t1, zero, zero

    # 5. check
    li t2, 0xCAFE0001
    bne t1, t2, fail

    # 6. vaddr(63) → bank=0, reg=63 (max index)
    li a0, 63
    .insn r 0x0B, 2, 3, zero, a0, zero

    # 7. vwr64: write 0x42 to VRF[0][63]
    li a0, 0x42
    .insn r 0x0B, 0, 2, t0, a0, zero

    # 8. vaddr(63)
    li a0, 63
    .insn r 0x0B, 2, 3, zero, a0, zero

    # 9. vrd64: read VRF[0][63]
    .insn r 0x0B, 1, 2, t1, zero, zero

    # 10. check
    li t2, 0x42
    bne t1, t2, fail

pass:
    li a0, 0
    j _exit

fail:
    li a0, 1
    j _exit
