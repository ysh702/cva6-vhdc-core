# hsim_test.S — test hsim Hamming distance over 1024-bit HV vectors
# hsim encoding: funct7=2, funct3=7, rs1[3:0]=src0_hv_id, rs1[7:4]=src1_hv_id

    .section ".text.init"
    .globl main

main:
    # ── Case 1: HV0 == HV1, expect distance 0 ─────────────────────────
    # Fill HV0 entries 0-3 and HV1 entries 4-7 with identical all-bank data.

    li a2, 0
case1_loop:
    li a3, 0
case1_bank_loop:
    # HV0 entry = a2
    add a0, a2, a3
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0x0123456789ABCDEF
    .insn r 0x0B, 0, 2, t0, a0, zero

    # HV1 entry = a2 + 4
    addi t4, a2, 4
    add a0, t4, a3
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0x0123456789ABCDEF
    .insn r 0x0B, 0, 2, t0, a0, zero

    addi a3, a3, 64
    li t4, 256
    blt a3, t4, case1_bank_loop

    addi a2, a2, 1
    li t3, 4
    blt a2, t3, case1_loop

    li a0, 0x10       # src0=HV0, src1=HV1
    .insn r 0x0B, 7, 2, t1, a0, zero
    bnez t1, fail

    # ── Case 2: HV2 is all-zero, HV3 is all-one, expect 1024 ──────────

    li a2, 0
case2_loop:
    li a3, 0
case2_bank_loop:
    # HV2 entry = a2 + 8
    addi t4, a2, 8
    add a0, t4, a3
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0
    .insn r 0x0B, 0, 2, t0, a0, zero

    # HV3 entry = a2 + 12
    addi t4, a2, 12
    add a0, t4, a3
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, -1
    .insn r 0x0B, 0, 2, t0, a0, zero

    addi a3, a3, 64
    li t4, 256
    blt a3, t4, case2_bank_loop

    addi a2, a2, 1
    li t3, 4
    blt a2, t3, case2_loop

    li a0, 0x32       # src0=HV2, src1=HV3
    .insn r 0x0B, 7, 2, t1, a0, zero
    li t2, 1024
    bne t1, t2, fail

    # ── Case 3: complementary mixed pattern, expect 1024 ──────────────
    # HV4 = 0xAAAAAAAA..., HV5 = 0x55555555... in all 16 lane words.

    li a2, 0
case3_loop:
    li a3, 0
case3_bank_loop:
    # HV4 entry = a2 + 16
    addi t4, a2, 16
    add a0, t4, a3
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0xAAAAAAAAAAAAAAAA
    .insn r 0x0B, 0, 2, t0, a0, zero

    # HV5 entry = a2 + 20
    addi t4, a2, 20
    add a0, t4, a3
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0x5555555555555555
    .insn r 0x0B, 0, 2, t0, a0, zero

    addi a3, a3, 64
    li t4, 256
    blt a3, t4, case3_bank_loop

    addi a2, a2, 1
    li t3, 4
    blt a2, t3, case3_loop

    li a0, 0x54       # src0=HV4, src1=HV5
    .insn r 0x0B, 7, 2, t1, a0, zero
    li t2, 1024
    bne t1, t2, fail

pass:
    li a0, 0
    j _exit

fail:
    li a0, 1
    j _exit
