# multi_index_test.S — VRF multi-index across 4 banks via vaddr protocol
# bank0 idx0, bank1 idx7, bank2 idx15, bank3 idx63

    .section ".text.init"
    .globl main

main:
    # ── bank0, index 0 ─────────────────────────────────────────────────
    li a0, 0                  # bank=0, idx=0
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0xAAAAAAAA00000000
    .insn r 0x0B, 0, 2, t0, a0, zero

    li a0, 0
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0xAAAAAAAA00000000
    bne t1, t2, fail

    # ── bank1, index 7 ─────────────────────────────────────────────────
    li a0, 71                 # bank=1, idx=7 → 1*64 + 7 = 71
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0xBBBBBBBB00000007
    .insn r 0x0B, 0, 2, t0, a0, zero

    li a0, 71
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0xBBBBBBBB00000007
    bne t1, t2, fail

    # ── bank2, index 15 ────────────────────────────────────────────────
    li a0, 143                # bank=2, idx=15 → 2*64 + 15 = 143
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0xCCCCCCCC0000000F
    .insn r 0x0B, 0, 2, t0, a0, zero

    li a0, 143
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0xCCCCCCCC0000000F
    bne t1, t2, fail

    # ── bank3, index 63 ────────────────────────────────────────────────
    li a0, 255                # bank=3, idx=63 → 3*64 + 63 = 255
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0xDDDDDDDD0000003F
    .insn r 0x0B, 0, 2, t0, a0, zero

    li a0, 255
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0xDDDDDDDD0000003F
    bne t1, t2, fail

    # ── cross-check: bank0 idx0 still holds original value ─────────────
    li a0, 0
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0xAAAAAAAA00000000
    bne t1, t2, fail

pass:
    li a0, 0
    j _exit

fail:
    li a0, 1
    j _exit
