# hdc_e2e_train_infer_test.S — Ladder-style HDC Train+Infer Self-Check
#
# Ladder A: sample encoding self-check (4 classes × 1 sample each)
# Ladder B: prototype build self-check (4 classes independently)
# Ladder C: full 4-class train + 8-sample inference
#
# Parameter reference:
#   HCNTCLR acc0:        a0 = 0
#   HCNTCLR acc1:        a0 = 1


#   HCNTCLIP dst=4 acc1 t=2:  0x2C  (a0[2:0]=4, a0[3]=1, a0[7:4]=2)
#   HCNTCLIP dst=0 acc0 t=2:  0x20
#   HCNTCLIP dst=1 acc0 t=2:  0x21
#   HCNTCLIP dst=2 acc0 t=2:  0x22
#   HCNTCLIP dst=3 acc0 t=2:  0x23
#   HMATCH result: min_idx=(result>>11)&0xFF, min_dist=result&0x7FF
#
# Target patterns (each HV = 16×64-bit words):
#   class0 = 0x0000000000000000 (ZERO)
#   class1 = 0xFFFFFFFFFFFFFFFF (FFFF)
#   class2 = 0xAAAAAAAAAAAAAAAA (AAAA)
#   class3 = 0x5555555555555555 (5555)
#
# 3-vs-1 majority encoding (noise position rotates across 4 samples):
#   class0: 3×ZERO + 1×FFFF  → ZERO
#   class1: 3×FFFF + 1×ZERO  → FFFF
#   class2: 3×AAAA + 1×5555  → AAAA
#   class3: 3×5555 + 1×AAAA  → 5555

    .section ".text.init"
    .globl main

# --- Macros for HDEC instructions ---
    .macro HCNTCLR acc
    li a0, \acc
    .insn r 0x0B, 3, 2, t0, a0, zero
    .endm

    .macro HCNTADD param
    li a0, \param
    .insn r 0x0B, 4, 2, t0, a0, zero
    .endm

    .macro HCNTCLIP param
    li a0, \param
    .insn r 0x0B, 0, 3, t0, a0, zero
    .endm

    .macro HMATCH param
    li a0, \param
    .insn r 0x0B, 1, 3, t0, a0, zero
    .endm

    .macro FILL_HV slot, value_reg
    li a0, \slot
    mv a1, \value_reg
    call fill_hv
    .endm


main:
    # --- Preload pattern constants into s0-s3 ---
    li s0, 0                      # ZERO = 0x0000000000000000
    li s1, -1                     # FFFF = 0xFFFFFFFFFFFFFFFF
    # s2 = AAAA, s3 = 5555 (loaded via assembler li expansion)
    li s2, 0xAAAAAAAAAAAAAAAA
    li s3, 0x5555555555555555


# =============================================================================
# LADDER A: Sample Encoding Self-Check
#   Preload HV0-HV3 with target prototypes, then test that encoding
#   of one sample per class produces the expected query HV.
#   Fail codes: class0=0xA0, class1=0xA1, class2=0xA2, class3=0xA3
# =============================================================================

    # --- Preload HV0-HV3 with target prototypes ---
    FILL_HV 0, s0       # HV0 = ZERO  (class 0 target)
    FILL_HV 1, s1       # HV1 = FFFF  (class 1 target)
    FILL_HV 2, s2       # HV2 = AAAA  (class 2 target)
    FILL_HV 3, s3       # HV3 = 5555  (class 3 target)

    # --- class0: features (FFFF, ZERO, ZERO, ZERO), noise at pos 0, expect min_idx=0 ---
    FILL_HV 4, s1       # HV4 = FFFF
    FILL_HV 5, s0       # HV5 = ZERO
    FILL_HV 6, s0       # HV6 = ZERO
    FILL_HV 7, s0       # HV7 = ZERO
    HCNTCLR 1
    HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17       # bundle [FFFF,0,0,0] → acc1: counter=1 where FFFF=1
    HCNTCLIP 0x2C          # dst=4, acc1, t=2 → HV4 = ZERO (1 < 2)
    HMATCH 0x0404       # query=4, base=0, num=4
    srli t1, t0, 11
    andi t1, t1, 0xFF
    li   t2, 0
    bne  t1, t2, fail_a0
    andi t1, t0, 0x7FF
    bnez t1, fail_a0

    # --- class1: features (FFFF, FFFF, FFFF, ZERO), noise at pos 3, expect min_idx=1 ---
    FILL_HV 4, s1       # HV4 = FFFF
    FILL_HV 5, s1       # HV5 = FFFF
    FILL_HV 6, s1       # HV6 = FFFF
    FILL_HV 7, s0       # HV7 = ZERO
    HCNTCLR 1
    HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17       # bundle [FFFF,FFFF,FFFF,0] → counter=3 where FFFF=1
    HCNTCLIP 0x2C          # HV4 = FFFF (3 ≥ 2)
    HMATCH 0x0404
    srli t1, t0, 11
    andi t1, t1, 0xFF
    li   t2, 1
    bne  t1, t2, fail_a1
    andi t1, t0, 0x7FF
    bnez t1, fail_a1

    # --- class2: features (AAAA, AAAA, AAAA, 5555), noise at pos 3, expect min_idx=2 ---
    FILL_HV 4, s2       # HV4 = AAAA
    FILL_HV 5, s2       # HV5 = AAAA
    FILL_HV 6, s2       # HV6 = AAAA
    FILL_HV 7, s3       # HV7 = 5555
    HCNTCLR 1
    HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17       # 3×AAAA + 1×5555 → counter=3 where AAAA=1, counter=1 where AAAA=0
    HCNTCLIP 0x2C          # HV4 = AAAA (3 ≥ 2, 1 < 2)
    HMATCH 0x0404
    srli t1, t0, 11
    andi t1, t1, 0xFF
    li   t2, 2
    bne  t1, t2, fail_a2
    andi t1, t0, 0x7FF
    bnez t1, fail_a2

    # --- class3: features (5555, 5555, 5555, AAAA), noise at pos 3, expect min_idx=3 ---
    FILL_HV 4, s3       # HV4 = 5555
    FILL_HV 5, s3       # HV5 = 5555
    FILL_HV 6, s3       # HV6 = 5555
    FILL_HV 7, s2       # HV7 = AAAA
    HCNTCLR 1
    HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17       # 3×5555 + 1×AAAA → counter=3 where 5555=1, counter=1 where 5555=0
    HCNTCLIP 0x2C          # HV4 = 5555 (3 ≥ 2, 1 < 2)
    HMATCH 0x0404
    srli t1, t0, 11
    andi t1, t1, 0xFF
    li   t2, 3
    bne  t1, t2, fail_a3
    andi t1, t0, 0x7FF
    bnez t1, fail_a3


# =============================================================================
# LADDER B: Prototype Build Self-Check
#   For each class: train 4 samples into acc0, HCNTCLIP to produce prototype,
#   then verify prototype matches expected target via HMATCH.
#   Fail codes: class0=0xB0, class1=0xB1, class2=0xB2, class3=0xB3
# =============================================================================

    # --- Class 0: train 4 samples, prototype into HV0, verify vs HV4=ZERO ---
    HCNTCLR 0
    # sample 0: noise at pos 0 → (FFFF, ZERO, ZERO, ZERO)
    FILL_HV 4, s1; FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0
    HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    # sample 1: noise at pos 1 → (ZERO, FFFF, ZERO, ZERO)
    FILL_HV 4, s0; FILL_HV 5, s1; FILL_HV 6, s0; FILL_HV 7, s0
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0
    HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    # sample 2: noise at pos 2 → (ZERO, ZERO, FFFF, ZERO)
    FILL_HV 4, s0; FILL_HV 5, s0; FILL_HV 6, s1; FILL_HV 7, s0
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0
    HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    # sample 3: noise at pos 3 → (ZERO, ZERO, ZERO, FFFF)
    FILL_HV 4, s0; FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s1
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0
    HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    HCNTCLIP 0x20         # HV0 = clip(acc0, t=2)
    FILL_HV 4, s0      # HV4 = ZERO (ref)
    HMATCH 0x0140      # query=0, base=4, num=1
    andi t1, t0, 0x7FF
    bnez t1, fail_b0

    # --- Class 1: train 4 samples, prototype into HV1, verify vs HV4=FFFF ---
    HCNTCLR 0
    # sample 0: noise at pos 0 → (ZERO, FFFF, FFFF, FFFF)
    FILL_HV 4, s0; FILL_HV 5, s1; FILL_HV 6, s1; FILL_HV 7, s1
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0
    HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    # sample 1: noise at pos 1 → (FFFF, ZERO, FFFF, FFFF)
    FILL_HV 4, s1; FILL_HV 5, s0; FILL_HV 6, s1; FILL_HV 7, s1
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0
    HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    # sample 2: noise at pos 2 → (FFFF, FFFF, ZERO, FFFF)
    FILL_HV 4, s1; FILL_HV 5, s1; FILL_HV 6, s0; FILL_HV 7, s1
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0
    HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    # sample 3: noise at pos 3 → (FFFF, FFFF, FFFF, ZERO)
    FILL_HV 4, s1; FILL_HV 5, s1; FILL_HV 6, s1; FILL_HV 7, s0
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0
    HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    HCNTCLIP 0x21         # HV1 = clip(acc0, t=2)
    FILL_HV 4, s1      # HV4 = FFFF (ref)
    HMATCH 0x0141      # query=1, base=4, num=1
    andi t1, t0, 0x7FF
    bnez t1, fail_b1

    # --- Class 2: train 4 samples, prototype into HV2, verify vs HV4=AAAA ---
    HCNTCLR 0
    # sample 0: noise at pos 0 → (5555, AAAA, AAAA, AAAA)
    FILL_HV 4, s3; FILL_HV 5, s2; FILL_HV 6, s2; FILL_HV 7, s2
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0
    HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    # sample 1: noise at pos 1 → (AAAA, 5555, AAAA, AAAA)
    FILL_HV 4, s2; FILL_HV 5, s3; FILL_HV 6, s2; FILL_HV 7, s2
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0
    HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    # sample 2: noise at pos 2 → (AAAA, AAAA, 5555, AAAA)
    FILL_HV 4, s2; FILL_HV 5, s2; FILL_HV 6, s3; FILL_HV 7, s2
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0
    HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    # sample 3: noise at pos 3 → (AAAA, AAAA, AAAA, 5555)
    FILL_HV 4, s2; FILL_HV 5, s2; FILL_HV 6, s2; FILL_HV 7, s3
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0
    HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    HCNTCLIP 0x22         # HV2 = clip(acc0, t=2)
    FILL_HV 4, s2      # HV4 = AAAA (ref)
    HMATCH 0x0142      # query=2, base=4, num=1
    andi t1, t0, 0x7FF
    bnez t1, fail_b2

    # --- Class 3: train 4 samples, prototype into HV3, verify vs HV4=5555 ---
    HCNTCLR 0
    # sample 0: noise at pos 0 → (AAAA, 5555, 5555, 5555)
    FILL_HV 4, s2; FILL_HV 5, s3; FILL_HV 6, s3; FILL_HV 7, s3
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0
    HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    # sample 1: noise at pos 1 → (5555, AAAA, 5555, 5555)
    FILL_HV 4, s3; FILL_HV 5, s2; FILL_HV 6, s3; FILL_HV 7, s3
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0
    HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    # sample 2: noise at pos 2 → (5555, 5555, AAAA, 5555)
    FILL_HV 4, s3; FILL_HV 5, s3; FILL_HV 6, s2; FILL_HV 7, s3
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0
    HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    # sample 3: noise at pos 3 → (5555, 5555, 5555, AAAA)
    FILL_HV 4, s3; FILL_HV 5, s3; FILL_HV 6, s3; FILL_HV 7, s2
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0
    HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    HCNTCLIP 0x23         # HV3 = clip(acc0, t=2)
    FILL_HV 4, s3      # HV4 = 5555 (ref)
    HMATCH 0x0143      # query=3, base=4, num=1
    andi t1, t0, 0x7FF
    bnez t1, fail_b3


# =============================================================================
# LADDER C: Full 4-Class Train + 8-Sample Inference
#   Build prototypes into HV0-HV3, then run 8 inference samples.
#   Expected labels: 0,1,2,3,0,1,2,3
#   Fail codes: 0xC0..0xC7 for samples 0..7
# =============================================================================

    # --- Clear working area ---
    FILL_HV 0, s0; FILL_HV 1, s0; FILL_HV 2, s0; FILL_HV 3, s0
    FILL_HV 4, s0; FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0
    HCNTCLR 0; HCNTCLR 1

    # --- Train class 0 → HV0 (same as Ladder B class 0) ---
    HCNTCLR 0
    FILL_HV 4, s1; FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0; HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    FILL_HV 4, s0; FILL_HV 5, s1; FILL_HV 6, s0; FILL_HV 7, s0
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0; HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    FILL_HV 4, s0; FILL_HV 5, s0; FILL_HV 6, s1; FILL_HV 7, s0
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0; HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    FILL_HV 4, s0; FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s1
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0; HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    HCNTCLIP 0x20

    # --- Train class 1 → HV1 ---
    HCNTCLR 0
    FILL_HV 4, s0; FILL_HV 5, s1; FILL_HV 6, s1; FILL_HV 7, s1
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0; HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    FILL_HV 4, s1; FILL_HV 5, s0; FILL_HV 6, s1; FILL_HV 7, s1
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0; HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    FILL_HV 4, s1; FILL_HV 5, s1; FILL_HV 6, s0; FILL_HV 7, s1
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0; HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    FILL_HV 4, s1; FILL_HV 5, s1; FILL_HV 6, s1; FILL_HV 7, s0
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0; HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    HCNTCLIP 0x21

    # --- Train class 2 → HV2 ---
    HCNTCLR 0
    FILL_HV 4, s3; FILL_HV 5, s2; FILL_HV 6, s2; FILL_HV 7, s2
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0; HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    FILL_HV 4, s2; FILL_HV 5, s3; FILL_HV 6, s2; FILL_HV 7, s2
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0; HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    FILL_HV 4, s2; FILL_HV 5, s2; FILL_HV 6, s3; FILL_HV 7, s2
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0; HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    FILL_HV 4, s2; FILL_HV 5, s2; FILL_HV 6, s2; FILL_HV 7, s3
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0; HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    HCNTCLIP 0x22

    # --- Train class 3 → HV3 ---
    HCNTCLR 0
    FILL_HV 4, s2; FILL_HV 5, s3; FILL_HV 6, s3; FILL_HV 7, s3
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0; HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    FILL_HV 4, s3; FILL_HV 5, s2; FILL_HV 6, s3; FILL_HV 7, s3
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0; HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    FILL_HV 4, s3; FILL_HV 5, s3; FILL_HV 6, s2; FILL_HV 7, s3
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0; HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    FILL_HV 4, s3; FILL_HV 5, s3; FILL_HV 6, s3; FILL_HV 7, s2
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C
    FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0; HCNTADD 4; HCNTADD 5; HCNTADD 6; HCNTADD 7
    HCNTCLIP 0x23

    # --- Inference: 8 test samples ---
    # expected labels: 0, 0, 1, 1, 2, 2, 3, 3

    # sample 0: class 0, noise at pos 0 → (FFFF, ZERO, ZERO, ZERO)
    FILL_HV 4, s1; FILL_HV 5, s0; FILL_HV 6, s0; FILL_HV 7, s0
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C; HMATCH 0x0404
    srli t1, t0, 11; andi t1, t1, 0xFF
    bnez t1, fail_c0
    andi t1, t0, 0x7FF; bnez t1, fail_c0

    # sample 1: class 0, noise at pos 2 → (ZERO, ZERO, FFFF, ZERO)
    FILL_HV 4, s0; FILL_HV 5, s0; FILL_HV 6, s1; FILL_HV 7, s0
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C; HMATCH 0x0404
    srli t1, t0, 11; andi t1, t1, 0xFF
    bnez t1, fail_c1
    andi t1, t0, 0x7FF; bnez t1, fail_c1

    # sample 2: class 1, noise at pos 0 → (ZERO, FFFF, FFFF, FFFF)
    FILL_HV 4, s0; FILL_HV 5, s1; FILL_HV 6, s1; FILL_HV 7, s1
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C; HMATCH 0x0404
    srli t1, t0, 11; andi t1, t1, 0xFF
    li   t2, 1; bne t1, t2, fail_c2
    andi t1, t0, 0x7FF; bnez t1, fail_c2

    # sample 3: class 1, noise at pos 3 → (FFFF, FFFF, FFFF, ZERO)
    FILL_HV 4, s1; FILL_HV 5, s1; FILL_HV 6, s1; FILL_HV 7, s0
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C; HMATCH 0x0404
    srli t1, t0, 11; andi t1, t1, 0xFF
    li   t2, 1; bne t1, t2, fail_c3
    andi t1, t0, 0x7FF; bnez t1, fail_c3

    # sample 4: class 2, noise at pos 0 → (5555, AAAA, AAAA, AAAA)
    FILL_HV 4, s3; FILL_HV 5, s2; FILL_HV 6, s2; FILL_HV 7, s2
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C; HMATCH 0x0404
    srli t1, t0, 11; andi t1, t1, 0xFF
    li   t2, 2; bne t1, t2, fail_c4
    andi t1, t0, 0x7FF; bnez t1, fail_c4

    # sample 5: class 2, noise at pos 3 → (AAAA, AAAA, AAAA, 5555)
    FILL_HV 4, s2; FILL_HV 5, s2; FILL_HV 6, s2; FILL_HV 7, s3
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C; HMATCH 0x0404
    srli t1, t0, 11; andi t1, t1, 0xFF
    li   t2, 2; bne t1, t2, fail_c5
    andi t1, t0, 0x7FF; bnez t1, fail_c5

    # sample 6: class 3, noise at pos 0 → (AAAA, 5555, 5555, 5555)
    FILL_HV 4, s2; FILL_HV 5, s3; FILL_HV 6, s3; FILL_HV 7, s3
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C; HMATCH 0x0404
    srli t1, t0, 11; andi t1, t1, 0xFF
    li   t2, 3; bne t1, t2, fail_c6
    andi t1, t0, 0x7FF; bnez t1, fail_c6

    # sample 7: class 3, noise at pos 1 → (5555, AAAA, 5555, 5555)
    FILL_HV 4, s3; FILL_HV 5, s2; FILL_HV 6, s3; FILL_HV 7, s3
    HCNTCLR 1; HCNTADD 0x14; HCNTADD 0x15; HCNTADD 0x16; HCNTADD 0x17; HCNTCLIP 0x2C; HMATCH 0x0404
    srli t1, t0, 11; andi t1, t1, 0xFF
    li   t2, 3; bne t1, t2, fail_c7
    andi t1, t0, 0x7FF; bnez t1, fail_c7

    # All passed
    j pass


# =============================================================================
# FAIL labels with distinct exit codes
# =============================================================================
fail_a0:  li a0, 0xA0; j _exit
fail_a1:  li a0, 0xA1; j _exit
fail_a2:  li a0, 0xA2; j _exit
fail_a3:  li a0, 0xA3; j _exit
fail_b0:  li a0, 0xB0; j _exit
fail_b1:  li a0, 0xB1; j _exit
fail_b2:  li a0, 0xB2; j _exit
fail_b3:  li a0, 0xB3; j _exit
fail_c0:  li a0, 0xC0; j _exit
fail_c1:  li a0, 0xC1; j _exit
fail_c2:  li a0, 0xC2; j _exit
fail_c3:  li a0, 0xC3; j _exit
fail_c4:  li a0, 0xC4; j _exit
fail_c5:  li a0, 0xC5; j _exit
fail_c6:  li a0, 0xC6; j _exit
fail_c7:  li a0, 0xC7; j _exit

pass:
    li a0, 0
    j _exit


# =============================================================================
# Subroutine: fill_hv
#   Fill one 1024-bit HV slot with a constant 64-bit value.
#   ALWAYS explicitly writes all 16 VADDR+VWR64 pairs — no skip for ZERO.
#
#   Input:
#     a0 = HV slot number (0-7)
#     a1 = 64-bit value to replicate
#
#   Writes: 16 × (VADDR + VWR64) = 4 chunks × 4 banks
#   Clobbers: a0, t3, t4, t5, t6
#   Preserves: a1 (value), ra, s-registers
# =============================================================================
fill_hv:
    addi sp, sp, -16
    sd   ra, 0(sp)
    sd   a1, 8(sp)        # save value

    slli t4, a0, 2         # t4 = slot * 4 = base entry index

    li t5, 0               # chunk = 0..3
1:
    li t6, 0               # bank = 0..3
2:
    slli a0, t6, 6         # a0 = bank * 64
    add  a0, a0, t4        # a0 = bank*64 + base
    add  a0, a0, t5        # a0 = bank*64 + base + chunk
    .insn r 0x0B, 2, 3, zero, a0, zero   # VADDR
    mv   a0, a1            # value
    .insn r 0x0B, 0, 2, t0, a0, zero     # VWR64
    addi t6, t6, 1
    li   a0, 4
    blt  t6, a0, 2b
    addi t5, t5, 1
    li   a0, 4
    blt  t5, a0, 1b

    ld   a1, 8(sp)         # restore value
    ld   ra, 0(sp)
    addi sp, sp, 16
    ret
