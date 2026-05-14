# =============================================================================
# test_vrw.S — HDEC Phase 1 VRF Read/Write Test (raw .insn encoding)
# VWR64: funct7=2, funct3=0,  opcode=0x0B
# VRD64: funct7=2, funct3=1,  opcode=0x0B
# HCLR:  funct7=2, funct3=2,  opcode=0x0B
# BCLR:  funct7=2, funct3=3,  opcode=0x0B
# HBIND: funct7=2, funct3=5,  opcode=0x0B
# =============================================================================

    .section ".text.init"
    .globl main

main:
    # Test 1: vwr64 + vrd64 round-trip — all 4 banks
    # Write pattern to VRF[0] across 4 banks
    li a0, 0xDEADBEEFCAFE0001
    li a1, 0      # bank=0, reg=0
    .insn r 0x0B, 0, 2, t0, a0, a1   # HDEC_VWR64(t0,a0,a1)

    li a0, 0x1234567890ABCDEF
    li a1, 64     # bank=1, reg=0
    .insn r 0x0B, 0, 2, t0, a0, a1

    li a0, 0xAABBCCDD11223344
    li a1, 128    # bank=2, reg=0
    .insn r 0x0B, 0, 2, t0, a0, a1

    li a0, 0x5566778899AABBCC
    li a1, 192    # bank=3, reg=0
    .insn r 0x0B, 0, 2, t0, a0, a1

    # Read back and verify each bank
    li a1, 0
    .insn r 0x0B, 1, 2, t1, a1, zero  # HDEC_VRD64(t1,a1)
    li t2, 0xDEADBEEFCAFE0001
    bne t1, t2, fail

    li a1, 64
    .insn r 0x0B, 1, 2, t1, a1, zero
    li t2, 0x1234567890ABCDEF
    bne t1, t2, fail

    li a1, 128
    .insn r 0x0B, 1, 2, t1, a1, zero
    li t2, 0xAABBCCDD11223344
    bne t1, t2, fail

    li a1, 192
    .insn r 0x0B, 1, 2, t1, a1, zero
    li t2, 0x5566778899AABBCC
    bne t1, t2, fail

    # Test 2: vwr64/vrd64 at max index (reg=63, bank=0)
    li a0, 0x42
    li a1, 63     # bank=0, reg=63
    .insn r 0x0B, 0, 2, t0, a0, a1
    li a1, 63
    .insn r 0x0B, 1, 2, t1, a1, zero
    li t2, 0x42
    bne t1, t2, fail

    # Test 3: hclr
    .insn r 0x0B, 2, 2, t0, zero, zero

    # Test 4: bclr
    .insn r 0x0B, 3, 2, t0, zero, zero

    # Test 5: HDC placeholder (hbind)
    li a0, ((5<<12)|(0<<6)|0)   # vd=5, vs1=0, vs2=0
    .insn r 0x0B, 5, 2, t0, a0, zero

pass:
    li a0, 0
    j _exit

fail:
    li a0, 1
    j _exit
