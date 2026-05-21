#!/usr/bin/env python3
"""Golden checks for HDEC HClip packed-counter thresholding."""
import random

MASK64 = (1 << 64) - 1


def clip_word(counter_word, threshold):
    threshold &= 0xF
    result = 0
    for bit in range(16):
        value = (counter_word >> (4 * bit)) & 0xF
        if value >= threshold:
            result |= 1 << bit
    return result


def test_directed_thresholds():
    ramp = 0xFEDCBA9876543210
    assert clip_word(ramp, 0) == 0xFFFF
    assert clip_word(ramp, 1) == 0xFFFE
    assert clip_word(ramp, 8) == 0xFF00
    assert clip_word(ramp, 15) == 0x8000
    print("  directed thresholds: PASS")


def test_all_equal_cases():
    for value in range(16):
        word = 0
        for nibble in range(16):
            word |= value << (4 * nibble)
        for threshold in range(16):
            expected = 0xFFFF if value >= threshold else 0x0000
            assert clip_word(word, threshold) == expected
    print("  all-equal counter words: PASS")


def test_random_words(n=100000):
    for _ in range(n):
        word = random.getrandbits(64)
        threshold = random.randrange(16)
        expected = 0
        for bit in range(16):
            value = (word >> (4 * bit)) & 0xF
            expected |= (1 if value >= threshold else 0) << bit
        assert clip_word(word, threshold) == expected
    print(f"  random packed counters: {n} vectors PASS")


def main():
    print("HDEC HClip golden tests")
    test_directed_thresholds()
    test_all_equal_cases()
    test_random_words()
    print("All tests PASSED")


if __name__ == "__main__":
    main()
