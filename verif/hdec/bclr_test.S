# bclr_test.S — test bclr clears 16-entry accumulator, preserves non-target entries
# acc0 = entries 32-47, acc1 = entries 48-63

    .section ".text.init"
    .globl main

main:
    # ── Phase 1: write non-zero to acc0 entries 32, 39, 47 (bank 0) ──

    # entry 32
    li a0, 32
    .insn r 0x0B, 2, 3, zero, a0, zero      # vaddr(32)
    li a0, 0xBC00002000000000
    .insn r 0x0B, 0, 2, t0, a0, zero         # vwr64

    # entry 39
    li a0, 39
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0xBC00002700000000
    .insn r 0x0B, 0, 2, t0, a0, zero

    # entry 47
    li a0, 47
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0xBC00002F00000000
    .insn r 0x0B, 0, 2, t0, a0, zero

    # ── Verify writes ───────────────────────────────────────────────────

    li a0, 32
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0xBC00002000000000
    bne t1, t2, fail

    # ── Phase 2: write non-zero to non-target entry 0 (HV slot 0) ──────

    li a0, 0
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0xCAFE000100000000
    .insn r 0x0B, 0, 2, t0, a0, zero

    # ── Phase 3: bclr acc0 (rs1=0) ──────────────────────────────────────
    # bclr: funct3=3, funct7=2

    li a0, 0
    .insn r 0x0B, 3, 2, t0, a0, zero

    # ── Phase 4: verify acc0 entries are ALL zero ────────────────────────

    li a0, 32
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    bnez t1, fail

    li a0, 39
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    bnez t1, fail

    li a0, 47
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    bnez t1, fail

    # ── Phase 5: verify non-target entry 0 is PRESERVED ─────────────────

    li a0, 0
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0xCAFE000100000000
    bne t1, t2, fail

pass:
    li a0, 0
    j _exit

fail:
    li a0, 1
    j _exit
