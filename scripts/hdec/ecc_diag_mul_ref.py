#!/usr/bin/env python3
"""Reference model for HDEC ECC V1 raw GF(2) diagonal multiplication."""

MASK64 = (1 << 64) - 1


def gf2_raw_mul(a: int, b: int, width: int = 256) -> int:
    """Return the raw polynomial product without modular reduction."""
    product = 0
    for i in range(width):
        if (a >> i) & 1:
            product ^= b << i
    return product


def words_le(value: int, words: int = 8) -> list[int]:
    return [(value >> (64 * idx)) & MASK64 for idx in range(words)]


def main() -> None:
    vectors = [
        (
            0x13579BDF2468ACE0FFEEDDCCBBAA99880F1E2D3C4B5A69780123456789ABCDEF,
            0x0BADF00DDEADBEEF10203040506070808877665544332211FEDCBA9876543210,
        ),
        (
            0x8000000000000000000000000000000000000000000000000000000000000001,
            0x4000000000000000000000000000000000000000000000000000000000000003,
        ),
    ]

    for idx, (a, b) in enumerate(vectors):
        p = gf2_raw_mul(a, b)
        print(f"vector {idx}")
        print(f"A = 0x{a:064x}")
        print(f"B = 0x{b:064x}")
        print(f"P = 0x{p:0128x}")
        for word_idx, word in enumerate(words_le(p)):
            print(f"  W{word_idx} = 0x{word:016x}")


if __name__ == "__main__":
    main()
