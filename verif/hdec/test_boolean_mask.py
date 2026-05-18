#!/usr/bin/env python3
"""Golden model for hdec_lane_boolean_mask XOR-only front-end."""
import random

MASK64 = (1 << 64) - 1


def xor_frontend(src_a, src_b):
    return (src_a ^ src_b) & MASK64


def test_xor_frontend(n=10000):
    directed = [
        (0, 0),
        (MASK64, 0),
        (MASK64, MASK64),
        (0xAAAAAAAAAAAAAAAA, 0x5555555555555555),
        (0x0123456789ABCDEF, 0xFEDCBA9876543210),
    ]

    for a, b in directed:
        assert xor_frontend(a, b) == ((a ^ b) & MASK64)

    for _ in range(n):
        a = random.getrandbits(64)
        b = random.getrandbits(64)
        assert xor_frontend(a, b) == ((a ^ b) & MASK64)

    print(f"  XOR_ONLY: {n + len(directed)} vectors PASS")


def main():
    print("XOR Front-End Golden Model Tests:")
    random.seed(42)
    test_xor_frontend()
    print("All tests PASSED")


if __name__ == "__main__":
    main()
