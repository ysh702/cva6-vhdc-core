# hbind_test.S — test hbind XOR bind of two 1024-bit HV vectors
# HV0=entries 0-3, HV1=entries 4-7, HV2=entries 8-11 (dst)
# hbind encoding: funct7=2, funct3=5, rs1[3:0]=dst, [7:4]=src0, [11:8]=src1

    .section ".text.init"
    .globl main

main:
    # ── Write HV0: entries 0-3, bank 0 ────────────────────────────────

    li a0, 0
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0xAAAAAAAA00000000
    .insn r 0x0B, 0, 2, t0, a0, zero

    li a0, 1
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0xBBBBBBBB00000001
    .insn r 0x0B, 0, 2, t0, a0, zero

    li a0, 2
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0xCCCCCCCC00000002
    .insn r 0x0B, 0, 2, t0, a0, zero

    li a0, 3
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0xDDDDDDDD00000003
    .insn r 0x0B, 0, 2, t0, a0, zero

    # ── Write HV1: entries 4-7, bank 0 ────────────────────────────────

    li a0, 4
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0x1111111100000004
    .insn r 0x0B, 0, 2, t0, a0, zero

    li a0, 5
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0x2222222200000005
    .insn r 0x0B, 0, 2, t0, a0, zero

    li a0, 6
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0x3333333300000006
    .insn r 0x0B, 0, 2, t0, a0, zero

    li a0, 7
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0x4444444400000007
    .insn r 0x0B, 0, 2, t0, a0, zero

    # ── hbind: dst=HV2(2), src0=HV0(0), src1=HV1(1) ───────────────────
    # rs1 = (1<<8) | (0<<4) | 2 = 258 = 0x102

    li a0, 258
    .insn r 0x0B, 5, 2, t0, a0, zero

    # ── Verify HV2 (entries 8-11) = HV0 ^ HV1 ─────────────────────────

    # entry 8 = entry 0 ^ entry 4 = 0xAAAAAAAA00000000 ^ 0x1111111100000004 = 0xBBBBBBBB00000004
    li a0, 8
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0xBBBBBBBB00000004
    bne t1, t2, fail

    # entry 9 = entry 1 ^ entry 5 = 0xBBBBBBBB00000001 ^ 0x2222222200000005 = 0x9999999900000004
    li a0, 9
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0x9999999900000004
    bne t1, t2, fail

    # entry 10 = entry 2 ^ entry 6 = 0xCCCCCCCC00000002 ^ 0x3333333300000006 = 0xFFFFFFFF00000004
    li a0, 10
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0xFFFFFFFF00000004
    bne t1, t2, fail

    # entry 11 = entry 3 ^ entry 7 = 0xDDDDDDDD00000003 ^ 0x4444444400000007 = 0x9999999900000004
    li a0, 11
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0x9999999900000004
    bne t1, t2, fail

    # ── Verify source HV0 intact (entry 0) ─────────────────────────────

    li a0, 0
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0xAAAAAAAA00000000
    bne t1, t2, fail

    # ── Verify source HV1 intact (entry 4) ────────────────────────────

    li a0, 4
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0x1111111100000004
    bne t1, t2, fail

pass:
    li a0, 0
    j _exit

fail:
    li a0, 1
    j _exit
