#!/usr/bin/env python3
"""Golden checks for hdec_lane_addsub_counter."""
import random

MASK64 = (1 << 64) - 1


def expand_hv16(hv16):
    result = 0
    for i in range(16):
        if (hv16 >> i) & 1:
            result |= 1 << (4 * i)
    return result & MASK64


def hdc_bundle(src_a, src_b):
    result = 0
    for i in range(16):
        nibble_a = (src_a >> (4 * i)) & 0xF
        nibble_b = (src_b >> (4 * i)) & 0xF
        nibble = (nibble_a + nibble_b) & 0xF
        if nibble_b and nibble_a == 0xF:
            nibble = 0xF
        result |= nibble << (4 * i)
    return result & MASK64


def ecc_full(src_a, src_b, op_sub):
    if op_sub:
        return (src_a + ((~src_b) & MASK64) + 1) & MASK64
    return (src_a + src_b) & MASK64


def test_hdc_directed():
    assert hdc_bundle(0, expand_hv16(0)) == 0
    assert hdc_bundle(0, expand_hv16(0x0001)) == 0x1
    assert hdc_bundle(0, expand_hv16(0xFFFF)) == 0x1111111111111111
    assert hdc_bundle(0xEEEEEEEEEEEEEEEE, expand_hv16(0xFFFF)) == 0xFFFFFFFFFFFFFFFF
    assert hdc_bundle(0xFFFFFFFFFFFFFFFF, expand_hv16(0xFFFF)) == 0xFFFFFFFFFFFFFFFF
    assert hdc_bundle(0x123456789ABCDEF0, expand_hv16(0x00FF)) == 0x12345678ABCDEFF1
    print("  hdc directed: PASS")


def test_hdc_random(n=10000):
    for _ in range(n):
        counter = random.getrandbits(64)
        hv16 = random.getrandbits(16)
        src_b = expand_hv16(hv16)
        expected = 0
        for i in range(16):
            nibble = (counter >> (4 * i)) & 0xF
            if (hv16 >> i) & 1 and nibble < 0xF:
                nibble += 1
            expected |= nibble << (4 * i)
        assert hdc_bundle(counter, src_b) == expected
    print(f"  hdc random: {n} vectors PASS")


def test_ecc_directed():
    assert ecc_full(0, 0, False) == 0
    assert ecc_full(1, 2, False) == 3
    assert ecc_full(MASK64, 1, False) == 0
    assert ecc_full(5, 3, True) == 2
    assert ecc_full(0, 1, True) == MASK64
    assert ecc_full(0x123456789ABCDEF0, 0x1111111111111111, True) == 0x0123456789ABCDDF
    print("  ecc directed: PASS")


def test_ecc_random(n=10000):
    for _ in range(n):
        a = random.getrandbits(64)
        b = random.getrandbits(64)
        assert ecc_full(a, b, False) == ((a + b) & MASK64)
        assert ecc_full(a, b, True) == ((a - b) & MASK64)
    print(f"  ecc random: {2 * n} vectors PASS")


def main():
    print("Add/Sub/Counter Golden Model Tests:")
    random.seed(42)
    test_hdc_directed()
    test_hdc_random()
    test_ecc_directed()
    test_ecc_random()
    print("All tests PASSED")


if __name__ == "__main__":
    main()
