# hbundle4_test.S - test BMCA-backed HDC Bundle4 over packed 4-bit counters
# hbundle4 encoding: funct7=3, funct3=4, rs1[2:0]=base_hv_slot, rs1[3]=acc_sel

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

    .macro HCLR slot
    li a0, \slot
    .insn r 0x0B, 2, 2, t0, a0, zero
    .endm

    .macro BCLR acc
    li a0, \acc
    .insn r 0x0B, 3, 2, t0, a0, zero
    .endm

    .macro HBUNDLE4 param
    li a0, \param
    .insn r 0x0B, 4, 3, t0, a0, zero
    .endm

main:
    # Pre-implementation guard: before HBUNDLE4 decode exists, F7=3/F3=4 falls
    # through to the wrapper default op and clobbers the current vaddr.
    HCLR 0
    HCLR 1
    HCLR 2
    HCLR 3
    VWRITE 32, 0xDEADBEEF12345678
    li a0, 32
    .insn r 0x0B, 2, 3, zero, a0, zero
    HBUNDLE4 0
    bnez t0, fail
    VCHECK 32, 0xDEADBEEF12345678

    # Case 1: all-zero HV0..HV3 leaves acc0 at zero.
    HCLR 0
    HCLR 1
    HCLR 2
    HCLR 3
    BCLR 0
    HBUNDLE4 0
    bnez t0, fail
    VCHECK 32, 0x0000000000000000
    VCHECK 47, 0x0000000000000000
    VCHECK 99, 0x0000000000000000

    # Case 2: all-one HV0..HV3 increments every selected counter by 4.
    HCLR 0
    HCLR 1
    HCLR 2
    HCLR 3
    BCLR 0
    li a2, 0
all_ones_entry_loop:
    li a3, 0
all_ones_bank_loop:
    add a0, a2, a3
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, -1
    .insn r 0x0B, 0, 2, t0, a0, zero
    addi a3, a3, 64
    li t4, 256
    blt a3, t4, all_ones_bank_loop
    addi a2, a2, 1
    li t3, 16
    blt a2, t3, all_ones_entry_loop
    HBUNDLE4 0
    bnez t0, fail
    VCHECK 32,  0x4444444444444444
    VCHECK 47,  0x4444444444444444
    VCHECK 111, 0x4444444444444444
    VCHECK 175, 0x4444444444444444

    # Case 3: HV0/HV1 alternating plus HV2 all-one and HV3 zero gives inc=2.
    HCLR 0
    HCLR 1
    HCLR 2
    HCLR 3
    BCLR 0
    VWRITE 0,  0xAAAAAAAAAAAAAAAA
    VWRITE 4,  0x5555555555555555
    VWRITE 8,  0xFFFFFFFFFFFFFFFF
    VWRITE 12, 0x0000000000000000
    HBUNDLE4 0
    bnez t0, fail
    VCHECK 32, 0x2222222222222222
    VCHECK 33, 0x0000000000000000

    # Case 4: saturation coverage and acc1 isolation while updating acc0.
    HCLR 0
    HCLR 1
    HCLR 2
    HCLR 3
    BCLR 0
    VWRITE 48,  0xA110000000000040
    VWRITE 255, 0xA11400000000004F
    VWRITE 32,  0xEEEEEEEEEEEEEEEE
    VWRITE 33,  0xEEEEEEEEEEEEEEEE
    VWRITE 35,  0xFFFFFFFFFFFFFFFF
    VWRITE 96,  0xFFFFFFFFFFFFFFFF
    VWRITE 160, 0xCCCCCCCCCCCCCCCC
    VWRITE 224, 0x0000000000000000
    VWRITE 0,   0xFFFFFFFFFFFFFFFF
    VWRITE 4,   0x0000FFFFFFFFFFFF
    VWRITE 8,   0x0000FFFFFFFF0000
    VWRITE 12,  0x0000FFFF00000000
    VWRITE 64,  0x000000000000FFFF
    VWRITE 68,  0x000000000000FFFF
    VWRITE 128, 0x000000000000FFFF
    VWRITE 132, 0x000000000000FFFF
    VWRITE 136, 0x000000000000FFFF
    HBUNDLE4 0
    bnez t0, fail
    VCHECK 32,  0xFFFFFFFFFFFFFFFF
    VCHECK 33,  0xFFFFFFFFFFFFFFFF
    VCHECK 34,  0x4444444444444444
    VCHECK 35,  0xFFFFFFFFFFFFFFFF
    VCHECK 96,  0xFFFFFFFFFFFFFFFF
    VCHECK 160, 0xFFFFFFFFFFFFFFFF
    VCHECK 224, 0x0000000000000000
    VCHECK 48,  0xA110000000000040
    VCHECK 255, 0xA11400000000004F

    # Case 5: acc1 update uses base+4-HV semantics and does not touch acc0.
    HCLR 0
    HCLR 1
    HCLR 2
    HCLR 3
    BCLR 0
    BCLR 1
    VWRITE 32, 0x123456789ABCDEF0
    VWRITE 0,  0x000000000000FFFF
    VWRITE 4,  0x000000000000FFFF
    VWRITE 8,  0x000000000000FFFF
    VWRITE 12, 0x000000000000FFFF
    HBUNDLE4 8
    bnez t0, fail
    VCHECK 48, 0x4444444444444444
    VCHECK 32, 0x123456789ABCDEF0

    # Case 6: illegal base_hv_slot > 4 returns STATUS_ERROR and preserves acc0.
    VWRITE 32, 0x0123456789ABCDEF
    HBUNDLE4 5
    li t2, 2
    bne t0, t2, fail
    VCHECK 32, 0x0123456789ABCDEF

pass:
    li a0, 0
    j _exit

fail:
    li a0, 1
    j _exit
