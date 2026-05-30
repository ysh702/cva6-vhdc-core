# hcntadd_test.S - test HCNTADD single-HV accumulate into CNT array
# HCNTADD encoding: funct7=000_0010, funct3=100
# rs1[2:0] = HV slot base, rs1[4] = acc bank select (0=acc0, 1=acc1)

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

    .macro HCNTCLR acc
    li a0, \acc
    .insn r 0x0B, 3, 2, t0, a0, zero
    .endm

    .macro HCNTADD param
    li a0, \param
    .insn r 0x0B, 4, 2, t0, a0, zero
    .endm

main:
    # Case 1: all-zero HV added to clean acc0 → all counters stay 0
    HCLR 0
    HCNTCLR 0
    HCNTADD 0
    VCHECK 32, 0x0000000000000000
    VCHECK 33, 0x0000000000000000
    VCHECK 47, 0x0000000000000000

    # Case 2: all-ones HV (slot 0) added once → every 4-bit counter = 1
    HCLR 0
    HCNTCLR 0
    VWRITE 0,  -1
    VWRITE 4,  -1
    VWRITE 8,  -1
    VWRITE 12, -1
    HCNTADD 0
    VCHECK 32, 0x1111111111111111
    VCHECK 33, 0x1111111111111111
    VCHECK 34, 0x1111111111111111
    VCHECK 35, 0x1111111111111111

    # Case 3: accumulate twice → counters double (0→1→2 for all-ones)
    HCLR 0
    HCNTCLR 0
    VWRITE 0, -1
    VWRITE 4, -1
    VWRITE 8, -1
    VWRITE 12,-1
    HCNTADD 0
    HCNTADD 0
    VCHECK 32, 0x2222222222222222
    VCHECK 35, 0x2222222222222222

    # Case 4: saturation test — add all-ones 20 times → all counters saturate at 15
    HCLR 0
    HCNTCLR 0
    VWRITE 0, -1
    VWRITE 4, -1
    VWRITE 8, -1
    VWRITE 12,-1
    li a5, 0
sat_loop:
    HCNTADD 0
    addi a5, a5, 1
    li t3, 20
    blt a5, t3, sat_loop
    VCHECK 32, 0xFFFFFFFFFFFFFFFF
    VCHECK 33, 0xFFFFFFFFFFFFFFFF
    VCHECK 35, 0xFFFFFFFFFFFFFFFF

    # Case 5: acc1 independence — add to acc1 does not touch acc0
    HCLR 0
    HCNTCLR 0
    HCNTCLR 1
    VWRITE 0, -1
    VWRITE 4, -1
    VWRITE 8, -1
    VWRITE 12,-1
    HCNTADD 16    # acc_sel=1 (bit4=1), HV slot=0
    VCHECK 32, 0x0000000000000000
    VCHECK 48, 0x1111111111111111

    # Case 6: mixed-quarter patterns catch subgroup 0/1/2/3 misalignment.
    # Each 64-bit HV word has four distinct 16-bit quarters; each bank also
    # uses a distinct pattern so bank/chunk addressing errors are visible.
    HCLR 0
    HCNTCLR 0
    VWRITE 0,   0x800000F000030001
    VWRITE 64,  0xF0000F0F5555AAAA
    VWRITE 128, 0xFF0000FFCCCC3333
    VWRITE 192, 0x1008200440028001
    HCNTADD 0

    # bank0, chunk0
    VCHECK 32, 0x0000000000000001
    VCHECK 33, 0x0000000000000011
    VCHECK 34, 0x0000000011110000
    VCHECK 35, 0x1000000000000000

    # bank1, chunk0
    VCHECK 96, 0x1010101010101010
    VCHECK 97, 0x0101010101010101
    VCHECK 98, 0x0000111100001111
    VCHECK 99, 0x1111000000000000

    # bank2, chunk0
    VCHECK 160, 0x0011001100110011
    VCHECK 161, 0x1100110011001100
    VCHECK 162, 0x0000000011111111
    VCHECK 163, 0x1111111100000000

    # bank3, chunk0
    VCHECK 224, 0x1000000000000001
    VCHECK 225, 0x0100000000000010
    VCHECK 226, 0x0010000000000100
    VCHECK 227, 0x0001000000001000

pass:
    li a0, 0
    j _exit

fail:
    li a0, 1
    j _exit
