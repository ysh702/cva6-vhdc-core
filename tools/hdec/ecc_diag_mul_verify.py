#!/usr/bin/env python3
"""
ecc_diag_mul_verify.py — Verify GF(2^256) polynomial multiplication
using diagonal popcount/parity algorithm, without RTL.

Three implementations compared:
  1. gf2_mul_shiftxor   — traditional reference
  2. gf2_mul_diagonal   — direct per-bit diagonal (k-loop)
  3. gf2_mul_lane_diag  — 4-lane × 64-bit popcount/parity (HDC-SIM model)

Author: HDEC ECC pre-design verification
Date:   2026-05-28
"""

import os
import random
import sys

LANE_WIDTH  = 64
LANE_COUNT  = 4
BIT_WIDTH   = 256
MAX_K       = 2 * BIT_WIDTH - 2   # 510


# ==============================================================================
# 1. Traditional shift-xor reference
# ==============================================================================
def gf2_mul_shiftxor(a: int, b: int) -> int:
    """Return raw GF(2) product of two 256-bit values (up to 511-bit)."""
    acc = 0
    for i in range(BIT_WIDTH):
        if (b >> i) & 1:
            acc ^= a << i
    return acc


# ==============================================================================
# 2. Direct diagonal multiplication
# ==============================================================================
def gf2_mul_diagonal(a: int, b: int) -> int:
    """Compute product by iterating k = 0..510 and XOR-ing diagonal terms."""
    product = 0
    for k in range(MAX_K + 1):
        bit = 0
        for i in range(BIT_WIDTH):
            bi = k - i
            if 0 <= bi < BIT_WIDTH:
                bit ^= ((a >> i) & 1) & ((b >> bi) & 1)
        if bit:
            product |= 1 << k
    return product


# ==============================================================================
# 3. 4-lane diagonal popcount/parity multiplication
# ==============================================================================
def popcount_parity(v: int) -> int:
    """Return popcount(v) & 1 using Python's built-in bit_count."""
    return v.bit_count() & 1


def gf2_mul_lane_diag(a: int, b: int) -> int:
    """
    Compute product using 4 lanes of 64-bit each.
    For each output bit k:
      - For each lane (base 0, 64, 128, 192):
          build a 64-bit mask v where v[t] = A[base+t] & B[k-(base+t)]
          (if bj in range 0..255, else 0)
      - lane_parity = popcount(v) & 1
      - cbit = XOR of all 4 lane_parities
    """
    # Pre-extract all bits for fast access
    A = [(a >> i) & 1 for i in range(BIT_WIDTH)]
    B = [(b >> i) & 1 for i in range(BIT_WIDTH)]

    product = 0
    lane_bases = [0, 64, 128, 192]

    for k in range(MAX_K + 1):
        cbit = 0
        for base in lane_bases:
            v = 0
            for t in range(LANE_WIDTH):
                ai = base + t
                bj = k - ai
                if 0 <= bj < BIT_WIDTH:
                    if A[ai] & B[bj]:
                        v |= 1 << t
            cbit ^= popcount_parity(v)
        if cbit:
            product |= 1 << k

    return product


# ==============================================================================
# 4. 8-bit small-scale example for human understanding
# ==============================================================================
def print_8bit_example():
    """Print a small 8-bit example showing diagonal terms per k."""
    N = 8
    a = 0b10110011   # 8-bit
    b = 0b01001110   # 8-bit

    def shiftxor_n(a, b, n):
        acc = 0
        for i in range(n):
            if (b >> i) & 1:
                acc ^= a << i
        return acc

    def diagonal_n(a, b, n):
        max_k = 2 * n - 2
        prod = 0
        for k in range(max_k + 1):
            bit = 0
            for i in range(n):
                bi = k - i
                if 0 <= bi < n:
                    bit ^= ((a >> i) & 1) & ((b >> bi) & 1)
            if bit:
                prod |= 1 << k
        return prod

    def lane_diag_n(a, b, n, lane_w=4):
        A = [(a >> i) & 1 for i in range(n)]
        B = [(b >> i) & 1 for i in range(n)]
        max_k = 2 * n - 2
        prod = 0
        lane_count = n // lane_w
        for k in range(max_k + 1):
            cbit = 0
            for ln in range(lane_count):
                base = ln * lane_w
                v = 0
                for t in range(lane_w):
                    ai = base + t
                    bj = k - ai
                    if 0 <= bj < n:
                        if A[ai] & B[bj]:
                            v |= 1 << t
                cbit ^= v.bit_count() & 1
            if cbit:
                prod |= 1 << k
        return prod

    ref    = shiftxor_n(a, b, N)
    diag   = diagonal_n(a, b, N)
    lanediag = lane_diag_n(a, b, N, lane_w=4)

    print("=" * 72)
    print("8-BIT SMALL-SCALE EXAMPLE")
    print("=" * 72)
    print(f"  a = 0x{a:02x}  ({a:08b})")
    print(f"  b = 0x{b:02x}  ({b:08b})")
    print()

    max_k = 2 * N - 2
    print(f"  Diagonal term decomposition (k = 0..{max_k}):")
    print(f"  {'k':>3s}  {'term':<34s}  bit")
    print(f"  {'-'*3}  {'-'*34}  {'-'*3}")

    for k in range(max_k + 1):
        terms = []
        for i in range(N):
            bi = k - i
            if 0 <= bi < N:
                terms.append(f"a{i}b{bi}")
        term_str = " ^ ".join(terms)
        bit = (ref >> k) & 1
        print(f"  {k:3d}  {term_str:<34s}  {bit}")

    print()
    print(f"  shift-xor result: 0x{ref:04x} ({ref:015b})")
    print(f"  diagonal  result: 0x{diag:04x} ({diag:015b})")
    print(f"  lane-diag result: 0x{lanediag:04x} ({lanediag:015b})")
    print()
    ok = (ref == diag == lanediag)
    print(f"  8-bit match: {'PASS' if ok else 'FAIL'}")

    # Print P[3] specifically
    k = 3
    terms = []
    for i in range(N):
        bi = k - i
        if 0 <= bi < N:
            terms.append(f"a{i}b{bi}")
    print(f"  P[3] = {' ^ '.join(terms)}")
    print()


# ==============================================================================
# 5. Boundary tests
# ==============================================================================
def run_boundary_tests():
    print("=" * 72)
    print("BOUNDARY TESTS")
    print("=" * 72)

    tests = []

    # Individual fixed tests
    rng = random.Random(42)

    a_zero   = 0
    b_rand   = rng.getrandbits(BIT_WIDTH)
    tests.append(("a=0, b=random", a_zero, b_rand))

    a_rand   = rng.getrandbits(BIT_WIDTH)
    b_zero   = 0
    tests.append(("b=0, a=random", a_rand, b_zero))

    a_one    = 1
    b_rand2  = rng.getrandbits(BIT_WIDTH)
    tests.append(("a=1, b=random", a_one, b_rand2))

    a_rand2  = rng.getrandbits(BIT_WIDTH)
    b_one    = 1
    tests.append(("b=1, a=random", a_rand2, b_one))

    all_ones = (1 << BIT_WIDTH) - 1
    tests.append(("a=all-ones, b=all-ones", all_ones, all_ones))

    msb_only = 1 << 255
    tests.append(("a=1<<255, b=1<<255", msb_only, msb_only))

    lsb_only = 1
    tests.append(("a=1<<0, b=1<<255", lsb_only, msb_only))
    tests.append(("a=1<<255, b=1<<0", msb_only, lsb_only))

    all_pass = True
    for name, a, b in tests:
        r1 = gf2_mul_shiftxor(a, b)
        r2 = gf2_mul_diagonal(a, b)
        r3 = gf2_mul_lane_diag(a, b)
        ok = (r1 == r2 == r3)
        status = "PASS" if ok else "FAIL"
        if not ok:
            all_pass = False
        print(f"  [{status}] {name}")
        if not ok:
            print(f"         shiftxor = {r1:#018x}")
            print(f"         diagonal = {r2:#018x}")
            print(f"         lane_diag = {r3:#018x}")

    print()
    return all_pass


# ==============================================================================
# 6. Random tests
# ==============================================================================
def run_random_tests(count: int = 1000, seed: int = 12345):
    print("=" * 72)
    print(f"RANDOM TESTS ({count} pairs)")
    print("=" * 72)

    rng = random.Random(seed)
    failed = 0

    for i in range(count):
        a = rng.getrandbits(BIT_WIDTH)
        b = rng.getrandbits(BIT_WIDTH)

        r1 = gf2_mul_shiftxor(a, b)
        r2 = gf2_mul_diagonal(a, b)
        r3 = gf2_mul_lane_diag(a, b)

        if not (r1 == r2 == r3):
            failed += 1
            print(f"\n  FAIL #{failed}: test index {i}")
            print(f"    a = 0x{a:064x}")
            print(f"    b = 0x{b:064x}")
            print(f"    shiftxor  = 0x{r1:0128x}")
            print(f"    diagonal  = 0x{r2:0128x}")
            print(f"    lane_diag = 0x{r3:0128x}")
            # find first differing bit
            diff = r1 ^ r2
            first_bit = diff.bit_length() - 1 if diff > 0 else -1
            print(f"    first diff bit (shiftxor vs diagonal): {first_bit}")
            if r2 != r3:
                diff2 = r2 ^ r3
                first_bit2 = diff2.bit_length() - 1 if diff2 > 0 else -1
                print(f"    first diff bit (diagonal vs lane_diag): {first_bit2}")

    if failed == 0:
        print(f"  PASS: {count} random GF(2) raw multiplication tests")
    else:
        print(f"  FAIL: {failed}/{count} tests failed")
        return False

    print()
    return True


# ==============================================================================
# 7. Statistics
# ==============================================================================
def print_statistics():
    print("=" * 72)
    print("STATISTICS")
    print("=" * 72)
    print(f"  Product bit range:   0..{MAX_K}")
    print(f"  Lane width:          {LANE_WIDTH}")
    print(f"  Number of lanes:     {LANE_COUNT}")
    bits_per_cycle = LANE_WIDTH * LANE_COUNT
    print(f"  Bits processed/cycle:{bits_per_cycle} ({LANE_COUNT}×{LANE_WIDTH})")
    print(f"  Cycles (1 bit/cycle output): {MAX_K + 1}")
    print(f"  Per-cycle per-lane operation: {LANE_WIDTH} ANDs + popcount parity")
    print(f"  Total ANDs per full multiply: {(MAX_K + 1) * bits_per_cycle}")
    print(f"  Total popcounts per full multiply: {(MAX_K + 1) * LANE_COUNT}")
    print()


# ==============================================================================
# 8. Vector export for Verilator testbench
# ==============================================================================
def export_vectors(filepath: str, boundary_count: int = 8, random_count: int = 100):
    """Export test vectors to a text file for Verilator consumption."""
    rng_boundary = random.Random(42)
    rng_random   = random.Random(99999)

    vectors = []

    # Boundary vectors (matching run_boundary_tests)
    b_rand   = rng_boundary.getrandbits(BIT_WIDTH)
    vectors.append(("a=0,b=rand", 0, b_rand))

    a_rand   = rng_boundary.getrandbits(BIT_WIDTH)
    vectors.append(("b=0,a=rand", a_rand, 0))

    b_rand2  = rng_boundary.getrandbits(BIT_WIDTH)
    vectors.append(("a=1,b=rand", 1, b_rand2))

    a_rand2  = rng_boundary.getrandbits(BIT_WIDTH)
    vectors.append(("b=1,a=rand", a_rand2, 1))

    all_ones = (1 << BIT_WIDTH) - 1
    vectors.append(("a=all-ones,b=all-ones", all_ones, all_ones))

    msb_only = 1 << 255
    vectors.append(("a=1<<255,b=1<<255", msb_only, msb_only))

    lsb_only = 1
    vectors.append(("a=1<<0,b=1<<255", lsb_only, msb_only))
    vectors.append(("a=1<<255,b=1<<0", msb_only, lsb_only))

    # Random vectors
    for i in range(random_count):
        a = rng_random.getrandbits(BIT_WIDTH)
        b = rng_random.getrandbits(BIT_WIDTH)
        vectors.append((f"random_{i}", a, b))

    # Compute golden products and write
    with open(filepath, 'w') as f:
        f.write(f"# GF(2^256) diagonal popcount/parity raw multiplication test vectors\n")
        f.write(f"# Format: INDEX COMMENT A_HEX B_HEX PRODUCT_HEX\n")
        f.write(f"# A: 256-bit operand\n")
        f.write(f"# B: 256-bit operand\n")
        f.write(f"# PRODUCT: 511-bit raw GF(2) product (no reduction)\n")
        f.write(f"# Total vectors: {len(vectors)}\n")
        f.write(f"#\n")

        for idx, (comment, a, b) in enumerate(vectors):
            prod = gf2_mul_lane_diag(a, b)
            # Verify against reference
            ref = gf2_mul_shiftxor(a, b)
            assert prod == ref, f"Vector {idx} ({comment}): lane_diag != shiftxor"
            f.write(f"{idx:4d} {comment:<30s} {a:064x} {b:064x} {prod:0128x}\n")

    print(f"  Exported {len(vectors)} vectors to {filepath}")

    # Also export a C header for Verilator testbench
    tool_dir = os.path.dirname(os.path.abspath(filepath))
    header_path = os.path.join(tool_dir, "ecc_diag_mul_vectors.h")
    with open(header_path, 'w') as f:
        f.write("// Auto-generated GF(2^256) diagonal multiplier test vectors\n")
        f.write(f"// {len(vectors)} vectors total\n\n")
        f.write("#ifndef ECC_DIAG_MUL_VECTORS_H\n")
        f.write("#define ECC_DIAG_MUL_VECTORS_H\n\n")
        f.write(f"#define NUM_VECTORS {len(vectors)}\n\n")
        f.write("struct TestVector {\n")
        f.write("    int index;\n")
        f.write("    const char* comment;\n")
        f.write("    unsigned long long a[4];\n")
        f.write("    unsigned long long b[4];\n")
        f.write("    unsigned long long prod[8];\n")
        f.write("};\n\n")
        f.write("static const TestVector vectors[NUM_VECTORS] = {\n")
        for idx, (comment, a, b) in enumerate(vectors):
            prod = gf2_mul_lane_diag(a, b)
            a_words = [(a >> (i*64)) & 0xFFFFFFFFFFFFFFFF for i in range(4)]
            b_words = [(b >> (i*64)) & 0xFFFFFFFFFFFFFFFF for i in range(4)]
            p_words = [(prod >> (i*64)) & 0xFFFFFFFFFFFFFFFF for i in range(8)]
            f.write(f'    {{{idx}, "{comment}", ')
            f.write('{' + ', '.join(f'0x{w:016x}ULL' for w in a_words) + '}, ')
            f.write('{' + ', '.join(f'0x{w:016x}ULL' for w in b_words) + '}, ')
            f.write('{' + ', '.join(f'0x{w:016x}ULL' for w in p_words) + '}}},\n')
        f.write("};\n\n")
        f.write("#endif\n")
    print(f"  Exported C header to {header_path}")
    return len(vectors)


# ==============================================================================
# main
# ==============================================================================
def main():
    print_8bit_example()

    boundary_ok = run_boundary_tests()
    random_ok   = run_random_tests(1000)

    print_statistics()

    # Export vectors for Verilator
    print("=" * 72)
    print("VECTOR EXPORT")
    print("=" * 72)
    script_dir = os.path.dirname(os.path.abspath(__file__))
    vector_path = os.path.join(script_dir, "ecc_diag_mul_vectors.txt")
    n_vectors = export_vectors(vector_path, boundary_count=8, random_count=100)
    print()

    if boundary_ok and random_ok:
        print("OVERALL: PASS")
    else:
        print("OVERALL: FAIL")
        sys.exit(1)


if __name__ == "__main__":
    main()
