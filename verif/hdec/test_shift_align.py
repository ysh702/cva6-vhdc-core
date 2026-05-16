#!/usr/bin/env python3
"""Golden checks for 4-bit-granular hdec_lane_shift_align."""
import random

MASK64 = (1 << 64) - 1


def shift_align(src_a, src_b, nibble_shift):
    src_a &= MASK64
    src_b &= MASK64
    nibble_shift &= 0xF
    if nibble_shift == 0:
        return src_a
    shift_bits = nibble_shift * 4
    return ((src_a >> shift_bits) | (src_b << (64 - shift_bits))) & MASK64


def test_directed():
    a = 0x0123456789ABCDEF
    b = 0xF0E1D2C3B4A59687
    assert shift_align(a, b, 0) == a
    assert shift_align(a, b, 1) == 0x70123456789ABCDE
    assert shift_align(a, b, 15) == 0x0E1D2C3B4A596870
    print("  directed: PASS")


def test_random(n=1000):
    for _ in range(n):
        a = random.getrandbits(64)
        b = random.getrandbits(64)
        for nibble_shift in range(16):
            r = shift_align(a, b, nibble_shift)
            if nibble_shift == 0:
                expected = a & MASK64
            else:
                s = nibble_shift * 4
                expected = ((a >> s) | (b << (64 - s))) & MASK64
            assert r == expected
    print(f"  random: {n * 16} vectors PASS")


def main():
    print("Shift-Align Golden Model Tests:")
    random.seed(42)
    test_directed()
    test_random()
    print("All tests PASSED")


if __name__ == "__main__":
    main()
