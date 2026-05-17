# badd_test.S - test real HDC bundle-add over 4-bit saturating counters

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

    .macro BADD param
    li a0, \param
    .insn r 0x0B, 4, 2, t0, a0, zero
    .endm

main:
    # Clear acc0.
    li a0, 0
    .insn r 0x0B, 3, 2, t0, a0, zero

    # Acc1 sentinels prove acc0 badd does not touch the other accumulator.
    VWRITE 48,  0xA110000000000030
    VWRITE 117, 0xA111000000000035
    VWRITE 254, 0xA11300000000003E

    # Sparse HV0 pattern across banks/chunks/subgroups.
    VWRITE 0,   0x0000000000000001
    VWRITE 64,  0x8001000000000001
    VWRITE 128, 0x00000000FFFF0000
    VWRITE 192, 0x8000000000000000
    VWRITE 1,   0x0000000000000001
    VWRITE 131, 0x0000000000000001

    # badd: hv_slot=0, reserved=0, acc_sel=0.
    BADD 0
    bnez t0, fail

    # chunk0/subgroup0, bank0: bit0 increments counter0.
    VCHECK 32, 0x0000000000000001
    # chunk0/subgroup0, bank1: bits0 and 15 increment counters 0 and 15.
    VCHECK 96, 0x1000000000000001
    # chunk0/subgroup1, bank2: 16 set bits increment all counters once.
    VCHECK 161, 0x1111111111111111
    # chunk0/subgroup3, bank3: bit63 increments counter15.
    VCHECK 227, 0x1000000000000000
    # chunk1/subgroup0, bank0.
    VCHECK 36, 0x0000000000000001
    # chunk3/subgroup0, bank2.
    VCHECK 172, 0x0000000000000001

    # Acc1 must be isolated from acc0 badd.
    VCHECK 48,  0xA110000000000030
    VCHECK 117, 0xA111000000000035
    VCHECK 254, 0xA11300000000003E

    # Source HV entries must be preserved.
    VCHECK 64, 0x8001000000000001
    VCHECK 131, 0x0000000000000001

    # Clear acc0, then drive every counter with HV1 all ones for saturation.
    li a0, 0
    .insn r 0x0B, 3, 2, t0, a0, zero

    VWRITE 4,   0xFFFFFFFFFFFFFFFF
    VWRITE 68,  0xFFFFFFFFFFFFFFFF
    VWRITE 132, 0xFFFFFFFFFFFFFFFF
    VWRITE 196, 0xFFFFFFFFFFFFFFFF
    VWRITE 5,   0xFFFFFFFFFFFFFFFF
    VWRITE 69,  0xFFFFFFFFFFFFFFFF
    VWRITE 133, 0xFFFFFFFFFFFFFFFF
    VWRITE 197, 0xFFFFFFFFFFFFFFFF
    VWRITE 6,   0xFFFFFFFFFFFFFFFF
    VWRITE 70,  0xFFFFFFFFFFFFFFFF
    VWRITE 134, 0xFFFFFFFFFFFFFFFF
    VWRITE 198, 0xFFFFFFFFFFFFFFFF
    VWRITE 7,   0xFFFFFFFFFFFFFFFF
    VWRITE 71,  0xFFFFFFFFFFFFFFFF
    VWRITE 135, 0xFFFFFFFFFFFFFFFF
    VWRITE 199, 0xFFFFFFFFFFFFFFFF

    # One increment from 14 must reach 15, proving saturation without a long loop.
    VWRITE 32,  0xEEEEEEEEEEEEEEEE
    VWRITE 99,  0xEEEEEEEEEEEEEEEE
    VWRITE 174, 0xEEEEEEEEEEEEEEEE
    VWRITE 239, 0xEEEEEEEEEEEEEEEE
    BADD 1

    VCHECK 32,  0xFFFFFFFFFFFFFFFF
    VCHECK 99,  0xFFFFFFFFFFFFFFFF
    VCHECK 174, 0xFFFFFFFFFFFFFFFF
    VCHECK 239, 0xFFFFFFFFFFFFFFFF

    # Illegal reserved bit with acc_sel=1 must return STATUS_ERROR and keep acc1.
    VWRITE 48,  0x1111222233334444
    VWRITE 240, 0x5555666677778888
    BADD 0x18
    li t2, 2
    bne t0, t2, fail
    VCHECK 48,  0x1111222233334444
    VCHECK 240, 0x5555666677778888

    # Non-trivial HV2 pattern into acc1 checks bank/chunk/subgroup mapping.
    li a0, 1
    .insn r 0x0B, 3, 2, t0, a0, zero
    li a0, 2
    .insn r 0x0B, 2, 2, t0, a0, zero

    VWRITE 8,   0x4002900901808421
    VWRITE 73,  0x1200A00500C00003
    VWRITE 138, 0x8001040820200101
    VWRITE 203, 0x8888444422221111

    BADD 0x12
    bnez t0, fail

    # Cross-bank/chunk/subgroup checks.
    VCHECK 48, 0x1000010000100001
    # bank1 chunk1 subgroup2.
    VCHECK 118, 0x1010000000000101
    # bank2 chunk2 subgroup1.
    VCHECK 186, 0x0010000000100000
    # bank3 chunk3 subgroup3.
    VCHECK 255, 0x1000100010001000

pass:
    li a0, 0
    j _exit

fail:
    li a0, 1
    j _exit
