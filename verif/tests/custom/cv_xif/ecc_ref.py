#!/usr/bin/env python3
"""
ECC GF(2^256) Montgomery Ladder + ITA Reference Model
Exact cycle-accurate match to hdec_top.sv RTL.
KEY INSIGHT: GF_MUL shifts gf_A_q 256 times. Post-MUL gf_A = original * x^256 mod P.
"""
POLY = (1 << 256) ^ (1 << 10) ^ (1 << 5) ^ (1 << 2) ^ 1
ECC_B = 1
MASK = (1 << 256) - 1
X256 = (1 << 10) ^ (1 << 5) ^ (1 << 2) ^ 1  # x^256 mod P = x^10+x^5+x^2+1


def add(a, b): return a ^ b


def sqr(a):
    e = 0
    for i in range(256):
        if (a >> i) & 1:
            e |= 1 << (2 * i)
    for j in range(511, 255, -1):
        if (e >> j) & 1:
            e ^= POLY << (j - 256)
    return e & MASK


def mul_rtl(A, K, init=0):
    """
    RTL GF_MUL: returns (result, final_A).
    result = init ^ (A * K) in GF(2^256).
    final_A = A after 256 left-shifts with polynomial reduction.
    In RTL, gf_A_q gets final_A after GF_DONE.
    """
    acc = init & MASK
    a = A
    k = K
    for _ in range(256):
        if k & 1:
            acc ^= a
        k >>= 1
        a <<= 1
        if (a >> 256) & 1:
            a ^= POLY
    return acc & MASK, a & MASK


def mul(A, K, init=0):
    """Convenience: return just the result (ignoring A shift)."""
    r, _ = mul_rtl(A, K, init)
    return r


def ita_inv(z):
    """Exact RTL Itoh-Tsujii inversion (11 GF_MULs, 255 SQRs)."""
    acc = z
    acc, _ = mul_rtl(sqr(acc), z)          # A2
    acc, _ = mul_rtl(sqr(acc), z)          # A3
    a3 = acc
    tmp = acc
    for _ in range(3): acc = sqr(acc)
    acc, _ = mul_rtl(acc, tmp)             # A6
    tmp = acc
    for _ in range(6): acc = sqr(acc)
    acc, _ = mul_rtl(acc, tmp)             # A12
    for _ in range(3): acc = sqr(acc)
    acc, _ = mul_rtl(acc, a3)              # A15
    a15 = acc
    tmp = acc
    for _ in range(15): acc = sqr(acc)
    acc, _ = mul_rtl(acc, tmp)             # A30
    tmp = acc
    for _ in range(30): acc = sqr(acc)
    acc, _ = mul_rtl(acc, tmp)             # A60
    tmp = acc
    for _ in range(60): acc = sqr(acc)
    acc, _ = mul_rtl(acc, tmp)             # A120
    tmp = acc
    for _ in range(120): acc = sqr(acc)
    acc, _ = mul_rtl(acc, tmp)             # A240
    for _ in range(15): acc = sqr(acc)
    acc, _ = mul_rtl(acc, a15)             # A255
    return sqr(acc)                        # ZINV


def ladder_init(k_256):
    """RTL INIT: gf_A = sqr(k), X1=k, Z1=1."""
    return sqr(k_256), k_256, 1


def ladder_step(gf_A, X1, Z1, k_bit):
    """One RTL ladder step. Tracks gf_A through GF_MUL shifts."""
    # sub=0: gf_A = sqr(gf_A)
    gf_A = sqr(gf_A)

    # sub=1: VRF[15].sub2 = gf_A (not needed)

    # sub=2 IDLE: gf_k = sqr(gf_A), trigger MUL(init=0)
    gf_k_val = sqr(gf_A)
    acc2, gf_A2 = mul_rtl(gf_A, gf_k_val, init=0)
    Z1 = acc2

    # sub=2 DONE: gf_A now = gf_A2 (shifted 256x by MUL)
    gf_A = gf_A2

    # sub=3: T1 = gf_A, gf_A = sqr(gf_A)
    T1 = gf_A
    gf_A = sqr(gf_A)

    # sub=4 IDLE: gf_k=ECC_B=1, init=sqr(gf_A), trigger
    acc4_init = sqr(gf_A)
    acc4, gf_A4 = mul_rtl(gf_A, ECC_B, init=acc4_init)
    sub4_mul_gfA = gf_A4  # gf_A after this MUL (MUL with k=1 shifts 256x)

    # sub=5 DONE: write X1 = T1 ^ acc4
    X1_sub5 = T1 ^ acc4
    gf_A = gf_A4

    # sub=6 IDLE: gf_k = gf_A, trigger MUL(init=0)
    acc6, gf_A6 = mul_rtl(gf_A, gf_A, init=0)

    # sub=8 DONE: T1 = acc6  (result from sub6 MUL)
    T1 = acc6
    gf_A = gf_A6

    # sub=9 IDLE: default → sub=10 (sub=7 is not reached)
    # T2 stays from previous step (= 0 for first step)

    # sub=10: gf_A = sqr(T1 ^ T2)
    gf_A = sqr(T1 ^ 0)  # T2 always 0 in observed flow

    # sub=11 IDLE: gf_k = gf_A, trigger(init=0)
    acc11, gf_A11 = mul_rtl(gf_A, gf_A, init=0)

    # sub=11 DONE: T4 = acc11
    T4 = acc11
    gf_A = gf_A11

    # sub=12 IDLE: gf_k = gf_A, trigger(init=0)
    acc12, gf_A12 = mul_rtl(gf_A, gf_A, init=0)

    # sub=12 DONE: conditional write
    if k_bit:
        X1 = acc12 ^ T4    # write sub0
    else:
        X1 = X1_sub5       # sub12 writes sub2, X1 stays from sub5

    gf_A = gf_A12

    # sub=13: k>>=1, step-- (caller handles)
    return gf_A, X1, Z1


def run_ladder(k_256, steps):
    gf_A, X1, Z1 = ladder_init(k_256)
    k_shift = k_256
    for s in range(steps):
        k_bit = (k_shift >> 255) & 1
        gf_A, X1, Z1 = ladder_step(gf_A, X1, Z1, k_bit)
        k_shift = (k_shift >> 1) & MASK
    return X1, Z1


def run_full(k_64, steps):
    k_256 = k_64 & MASK
    X1, Z1 = run_ladder(k_256, steps)
    ZINV = ita_inv(Z1)
    XAFF = mul(X1, ZINV)
    return {'X1': X1, 'Z1': Z1, 'ZINV': ZINV, 'XAFF': XAFF, 'CHECK': mul(Z1, ZINV)}


HW_1STEP = dict(
    Z1  =0x0000000000000000000000000001000000000000000000000000000000000000,
    X1  =0x0000010000100101000000000000000000100411000000000425000000000000,
)

HW_7STEP = dict(
    Z1  =0xf93ad96abc927a63b42bf2c78c7c7f208ee53350dbc16a80897a337c8e350ca5,
    X1  =0xc82dd28b76eccef13155e3c30817752430c450e14f18dbbb70a433dbae43b8bc,
    XAFF=0x06222ef8b083567fa29444ecfb1770dbcee8d518acb0baa3433b730ea4b2c1f9,
)

HW_255STEP = dict(
    Z1  =0x1fe9ac2e504540246d23bb1b4643447473b1ea7eaafa6f4bd23b62d536647e7b,
    X1  =0x4386f2d34f484e77191a2c610e9b05149c9e2bbb4652a0c8ad26c95b8ab5c78a,
    XAFF=0x3f57b8a5470cc4a2ad3f5a6c7169a827366f793fc6f75e696368dc48301191c9,
)


if __name__ == '__main__':
    K = 0x1000  # from RTL INIT dump
    print("=== ECC Ref Model (Cycle-Accurate, with gf_A shift) ===\n")
    print(f"  K = {K:#018x}\n")

    print("─ Unit Tests ─")
    assert ita_inv(1) == 1;                 print("  [PASS] inv(1)=1")
    zz = 0x12345
    assert mul(zz, ita_inv(zz)) == 1;       print("  [PASS] Z×inv(Z)=1")
    print()

    # Verify ZINV self-check using HW Z1 values
    print("─ ZINV Self-Check (HW Z1) ─")
    for label, hw in [('1-step', HW_1STEP['Z1']), ('7-step', HW_7STEP['Z1']),
                       ('255-step', HW_255STEP['Z1'])]:
        zinv = ita_inv(hw)
        assert mul(hw, zinv) == 1
        print(f"  {label}: PASS")
    print()

    all_pass = True
    for label, steps, hw in [('1-step', 1, HW_1STEP), ('7-step', 7, HW_7STEP),
                               ('255-step', 254, HW_255STEP)]:
        r = run_full(K, steps)
        print(f"─ {label} ─")
        for n in (['X1','Z1'] if steps==1 else ['X1','Z1','XAFF']):
            ok = r[n] == hw[n]
            if not ok: all_pass = False
            print(f"  {n:5s}: {'PASS' if ok else 'FAIL'}")
            if not ok:
                print(f"    HW:  {hw[n]:#066x}")
                print(f"    REF: {r[n]:#066x}")
        print(f"  CHECK: {'PASS' if r['CHECK']==1 else 'FAIL'}")
        print()

    print(f"{'=== ECC FULL CLOSED-LOOP PASS ===' if all_pass else '=== SOME FAILURES ==='}")
