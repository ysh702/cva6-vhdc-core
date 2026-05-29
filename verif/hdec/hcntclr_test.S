# hcntclr_test.S - test HCNTCLR clear CNT accumulator bank
# HCNTCLR encoding: funct7=000_0010, funct3=011
# rs1[0] = acc bank select (0=acc0 VRF[32:47], 1=acc1 VRF[48:55])

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

    .macro HCNTCLR acc
    li a0, \acc
    .insn r 0x0B, 3, 2, t0, a0, zero
    .endm

main:
    # Case 1: clear acc0, verify all 16 entries zero
    VWRITE 32, 0xDEADBEEF12345678
    VWRITE 33, 0xCAFEBABEDEADBEEF
    VWRITE 47, 0xAAAAAAAAAAAAAAA5
    HCNTCLR 0
    VCHECK 32, 0x0000000000000000
    VCHECK 33, 0x0000000000000000
    VCHECK 47, 0x0000000000000000

    # Case 2: clear acc1, verify all 16 entries zero
    VWRITE 48, 0x5555555555555555
    VWRITE 55, 0xFFFFFFFFFFFFFFFF
    HCNTCLR 1
    VCHECK 48, 0x0000000000000000
    VCHECK 55, 0x0000000000000000

    # Case 3: acc0 clear does not touch acc1
    VWRITE 48, 0x1234567890ABCDEF
    HCNTCLR 0
    VCHECK 48, 0x1234567890ABCDEF

    # Case 4: acc1 clear does not touch acc0
    VWRITE 32, 0xFEDCBA0987654321
    HCNTCLR 1
    VCHECK 32, 0xFEDCBA0987654321

pass:
    li a0, 0
    j _exit

fail:
    li a0, 1
    j _exit
