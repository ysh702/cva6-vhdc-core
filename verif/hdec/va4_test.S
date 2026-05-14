# va4_test.S — continuous 4-bank VRF r/w via vaddr protocol
# Sequence: vaddr→vwr64 for 4 banks, then vaddr→vrd64→check for 4 banks

    .section ".text.init"
    .globl main

main:
    # ── Write phase: 4 banks ──────────────────────────────────────────

    # Bank 0 (addr 0): write 0xDEADBEEF11111111
    li a0, 0
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0xDEADBEEF11111111
    .insn r 0x0B, 0, 2, t0, a0, zero

    # Bank 1 (addr 64): write 0x2222222222222222
    li a0, 64
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0x2222222222222222
    .insn r 0x0B, 0, 2, t0, a0, zero

    # Bank 2 (addr 128): write 0x3333333333333333
    li a0, 128
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0x3333333333333333
    .insn r 0x0B, 0, 2, t0, a0, zero

    # Bank 3 (addr 192): write 0x4444444444444444
    li a0, 192
    .insn r 0x0B, 2, 3, zero, a0, zero
    li a0, 0x4444444444444444
    .insn r 0x0B, 0, 2, t0, a0, zero

    # ── Read + verify phase: 4 banks ──────────────────────────────────

    # Bank 0: expect 0xDEADBEEF11111111
    li a0, 0
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0xDEADBEEF11111111
    bne t1, t2, fail

    # Bank 1: expect 0x2222222222222222
    li a0, 64
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0x2222222222222222
    bne t1, t2, fail

    # Bank 2: expect 0x3333333333333333
    li a0, 128
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0x3333333333333333
    bne t1, t2, fail

    # Bank 3: expect 0x4444444444444444
    li a0, 192
    .insn r 0x0B, 2, 3, zero, a0, zero
    .insn r 0x0B, 1, 2, t1, zero, zero
    li t2, 0x4444444444444444
    bne t1, t2, fail

pass:
    li a0, 0
    j _exit

fail:
    li a0, 1
    j _exit
