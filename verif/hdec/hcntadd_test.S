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

pass:
    li a0, 0
    j _exit

fail:
    li a0, 1
    j _exit
