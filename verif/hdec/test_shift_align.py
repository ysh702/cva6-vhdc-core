#!/usr/bin/env python3
"""Golden checks for bit-granular hdec_lane_shift_align."""
import random

MASK64 = (1 << 64) - 1


def shift_align_bit(src_a, src_b, bit_shift):
    src_a &= MASK64
    src_b &= MASK64
    bit_shift &= 0x3F
    if bit_shift == 0:
        return src_a
    return ((src_a >> bit_shift) | (src_b << (64 - bit_shift))) & MASK64


def shift_align_hdc_nibble(src_a, src_b, nibble_shift):
    return shift_align_bit(src_a, src_b, (nibble_shift & 0xF) * 4)


def test_directed():
    a = 0x0123456789ABCDEF
    b = 0xF0E1D2C3B4A59687
    assert shift_align_bit(a, b, 0) == a
    assert shift_align_bit(a, b, 1) == 0x8091A2B3C4D5E6F7
    assert shift_align_bit(a, b, 63) == 0xE1C3A587694B2D0E
    assert shift_align_hdc_nibble(a, b, 1) == 0x70123456789ABCDE
    assert shift_align_hdc_nibble(a, b, 15) == 0x0E1D2C3B4A596870
    print("  directed: PASS")


def test_random(n=1000):
    for _ in range(n):
        a = random.getrandbits(64)
        b = random.getrandbits(64)
        for bit_shift in range(64):
            r = shift_align_bit(a, b, bit_shift)
            if bit_shift == 0:
                expected = a & MASK64
            else:
                expected = ((a >> bit_shift) | (b << (64 - bit_shift))) & MASK64
            assert r == expected
        for nibble_shift in range(16):
            assert shift_align_hdc_nibble(a, b, nibble_shift) == shift_align_bit(a, b, nibble_shift * 4)
    print(f"  random: {n * 64} bit-shift vectors PASS")
    print(f"  random: {n * 16} HDC nibble-compat vectors PASS")


def main():
    print("Shift-Align Golden Model Tests:")
    random.seed(42)
    test_directed()
    test_random()
    print("All tests PASSED")


if __name__ == "__main__":
    main()
