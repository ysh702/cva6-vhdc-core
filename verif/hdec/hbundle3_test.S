# hbundle3_test.S - test BMCA-backed HDC Bundle3 over packed 4-bit counters
# hbundle3 encoding: funct7=3, funct3=3, rs1[2:0]=base_hv_slot, rs1[3]=acc_sel

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

    .macro HBUNDLE3 param
    li a0, \param
    .insn r 0x0B, 3, 3, t0, a0, zero
    .endm

main:
    # Pre-implementation guard: an unknown F7=3/F3=3 instruction must not behave
    # like the wrapper's default VWR64 path and clobber the current vaddr.
    HCLR 0
    HCLR 1
    HCLR 2
    VWRITE 32, 0xDEADBEEF12345678
    li a0, 32
    .insn r 0x0B, 2, 3, zero, a0, zero
    HBUNDLE3 0
    bnez t0, fail
    VCHECK 32, 0xDEADBEEF12345678

    # Case 1: all-zero HV0/HV1/HV2 leaves acc0 at zero.
    HCLR 0
    HCLR 1
    HCLR 2
    BCLR 0
    HBUNDLE3 0
    bnez t0, fail
    VCHECK 32, 0x0000000000000000
    VCHECK 99, 0x0000000000000000

    # Case 2: all-one HV0/HV1/HV2 increments every selected counter by 3.
    HCLR 0
    HCLR 1
    HCLR 2
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
    li t3, 12
    blt a2, t3, all_ones_entry_loop
    HBUNDLE3 0
    bnez t0, fail
    VCHECK 32,  0x3333333333333333
    VCHECK 107, 0x3333333333333333
    VCHECK 175, 0x3333333333333333

    # Case 3: alternating HV0/HV1 plus all-one HV2 gives increment 2.
    HCLR 0
    HCLR 1
    HCLR 2
    BCLR 0
    VWRITE 0, 0xAAAAAAAAAAAAAAAA
    VWRITE 4, 0x5555555555555555
    VWRITE 8, 0xFFFFFFFFFFFFFFFF
    HBUNDLE3 0
    bnez t0, fail
    VCHECK 32, 0x2222222222222222
    VCHECK 33, 0x0000000000000000

    # Case 4: saturation coverage and acc1 isolation while updating acc0.
    HCLR 0
    HCLR 1
    HCLR 2
    BCLR 0
    VWRITE 48,  0xA110000000000030
    VWRITE 255, 0xA11300000000003F
    VWRITE 32,  0xEEEEEEEEEEEEEEEE
    VWRITE 33,  0xEEEEEEEEEEEEEEEE
    VWRITE 35,  0xFFFFFFFFFFFFFFFF
    VWRITE 96,  0xFFFFFFFFFFFFFFFF
    VWRITE 160, 0xDDDDDDDDDDDDDDDD
    VWRITE 0,   0xFFFFFFFFFFFFFFFF
    VWRITE 4,   0x0000FFFFFFFFFFFF
    VWRITE 8,   0x0000FFFFFFFF0000
    VWRITE 64,  0x000000000000FFFF
    VWRITE 68,  0x000000000000FFFF
    VWRITE 128, 0x000000000000FFFF
    VWRITE 132, 0x000000000000FFFF
    VWRITE 136, 0x000000000000FFFF
    HBUNDLE3 0
    bnez t0, fail
    VCHECK 32,  0xFFFFFFFFFFFFFFFF
    VCHECK 33,  0xFFFFFFFFFFFFFFFF
    VCHECK 34,  0x3333333333333333
    VCHECK 35,  0xFFFFFFFFFFFFFFFF
    VCHECK 96,  0xFFFFFFFFFFFFFFFF
    VCHECK 160, 0xFFFFFFFFFFFFFFFF
    VCHECK 48,  0xA110000000000030
    VCHECK 255, 0xA11300000000003F

    # Case 5: acc1 update uses the same base+3-HV semantics and does not touch acc0.
    HCLR 0
    HCLR 1
    HCLR 2
    BCLR 0
    BCLR 1
    VWRITE 32, 0x123456789ABCDEF0
    VWRITE 0,  0x000000000000FFFF
    VWRITE 4,  0x000000000000FFFF
    VWRITE 8,  0x000000000000FFFF
    HBUNDLE3 8
    bnez t0, fail
    VCHECK 48, 0x3333333333333333
    VCHECK 32, 0x123456789ABCDEF0

    # Case 6: illegal base_hv_slot > 5 returns STATUS_ERROR and preserves acc0.
    VWRITE 32, 0x0123456789ABCDEF
    HBUNDLE3 6
    li t2, 2
    bne t0, t2, fail
    VCHECK 32, 0x0123456789ABCDEF

pass:
    li a0, 0
    j _exit

fail:
    li a0, 1
    j _exit
