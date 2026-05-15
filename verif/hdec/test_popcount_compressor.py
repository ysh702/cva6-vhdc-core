#!/usr/bin/env python3
"""Golden checks for hdec_lane_popcount_compressor modes."""
import random

MASK64 = (1 << 64) - 1


def hdc_popcount(diff):
    return (diff & MASK64).bit_count()


def ecc_compress(a, b, c):
    a &= MASK64
    b &= MASK64
    c &= MASK64
    maj = (a & b) | (a & c) | (b & c)
    csa_sum = a ^ b ^ c
    csa_carry = ((maj & ((1 << 63) - 1)) << 1) & MASK64
    csa_cout = (maj >> 63) & 1
    return csa_sum, csa_carry, csa_cout


def test_hdc_popcount(n=1000):
    vectors = [
        (0, 0),
        (MASK64, 64),
        (0xAAAAAAAAAAAAAAAA, 32),
        (0x5555555555555555, 32),
        (0x8000000000000001, 2),
    ]
    for diff, expected in vectors:
        assert hdc_popcount(diff) == expected

    for _ in range(n):
        diff = random.getrandbits(64)
        assert hdc_popcount(diff) == bin(diff).count("1")
    print(f"  HDC_POPCOUNT: {n + len(vectors)} vectors PASS")


def test_ecc_compress(n=1000):
    vectors = [
        (0, 0, 0),
        (MASK64, 0, 0),
        (MASK64, MASK64, 0),
        (MASK64, MASK64, MASK64),
        (0xAAAAAAAAAAAAAAAA, 0x5555555555555555, MASK64),
        (1 << 63, 1 << 63, 0),
    ]
    for a, b, c in vectors:
        csa_sum, csa_carry, csa_cout = ecc_compress(a, b, c)
        maj = (a & b) | (a & c) | (b & c)
        assert csa_sum == ((a ^ b ^ c) & MASK64)
        assert csa_carry == (((maj & ((1 << 63) - 1)) << 1) & MASK64)
        assert csa_cout == ((maj >> 63) & 1)

    for _ in range(n):
        a = random.getrandbits(64)
        b = random.getrandbits(64)
        c = random.getrandbits(64)
        csa_sum, csa_carry, csa_cout = ecc_compress(a, b, c)
        maj = (a & b) | (a & c) | (b & c)
        assert csa_sum == ((a ^ b ^ c) & MASK64)
        assert csa_carry == (((maj & ((1 << 63) - 1)) << 1) & MASK64)
        assert csa_cout == ((maj >> 63) & 1)
    print(f"  ECC_COMPRESS: {n + len(vectors)} vectors PASS")


def main():
    print("Popcount/Compressor Golden Model Tests:")
    random.seed(42)
    test_hdc_popcount()
    test_ecc_compress()
    print("All tests PASSED")


if __name__ == "__main__":
    main()
