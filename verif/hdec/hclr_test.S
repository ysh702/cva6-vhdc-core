# hclr_test.S — test hclr clears 4-entry HV slot, preserves other entries
# HV slot 0 = entries 0,1,2,3.  HV slot 1 = entries 4,5,6,7 (for isolation check).

    .section ".text.init"
    .globl main

main:
    # ── Phase 1: write non-zero to HV slot 0 (entries 0-3, bank 0) ─────

    # entry 0, bank 0
    li a0, 0
    .insn r 0x0B, 2, 3, zero, a0, zero      # vaddr(0)
    li a0, 0xCAFE000100000000
    .insn r 0x0B, 0, 2, t0, a0, zero         # vwr64

    # entry 1, bank 0
    li a0, 1
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0xCAFE000200000000
    .insn r 0x0B, 0, 2, t0, a0, zero

    # entry 2, bank 0
    li a0, 2
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0xCAFE000300000000
    .insn r 0x0B, 0, 2, t0, a0, zero

    # entry 3, bank 0
    li a0, 3
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0xCAFE000400000000
    .insn r 0x0B, 0, 2, t0, a0, zero

    # ── Verify writes succeeded ─────────────────────────────────────────

    li a0, 0
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0xCAFE000100000000
    bne t1, t2, fail

    li a0, 1
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0xCAFE000200000000
    bne t1, t2, fail

    # ── Phase 2: write non-zero to HV slot 1 (entries 4-7, bank 0) ─────

    # entry 4
    li a0, 4
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0xDEAD000100000000
    .insn r 0x0B, 0, 2, t0, a0, zero

    # entry 5
    li a0, 5
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0xDEAD000200000000
    .insn r 0x0B, 0, 2, t0, a0, zero

    # ── Phase 3: hclr hv_id=0 ───────────────────────────────────────────
    # rs1 = hv_id = 0 → clear entries 0-3

    li a0, 0
    .insn r 0x0B, 2, 2, t0, a0, zero        # hclr (funct3=2, funct7=2)

    # ── Phase 4: verify HV slot 0 entries are ALL zero ──────────────────

    li a0, 0
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    bnez t1, fail

    li a0, 1
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    bnez t1, fail

    li a0, 2
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    bnez t1, fail

    li a0, 3
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    bnez t1, fail

    # ── Phase 5: verify HV slot 1 entries are PRESERVED ─────────────────

    li a0, 4
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0xDEAD000100000000
    bne t1, t2, fail

    li a0, 5
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0xDEAD000200000000
    bne t1, t2, fail

pass:
    li a0, 0
    j _exit

fail:
    li a0, 1
    j _exit
