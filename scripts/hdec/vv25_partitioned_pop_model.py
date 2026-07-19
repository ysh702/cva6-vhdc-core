#!/usr/bin/env python3
"""VV25 partitioned-POPCOUNT plus 14-node native-XOR1 model."""

from __future__ import annotations

import random

from vv25_byte_equation_model import LAYOUT, clmul, diagonal_terms


def matrix_product(a: int, b: int) -> list[int]:
    diagonals = [diagonal_terms(a, b, diag) for diag in range(31)]
    return [diagonals[diag][term] for diag, term in LAYOUT]


def reduce_leaf(a: int, b: int) -> int:
    matrix = matrix_product(a, b)
    byte_count = [
        sum(matrix[base : base + 8]) for base in range(0, 256, 8)
    ]
    byte_pair_parity = [
        (byte_count[row * 4 + side * 2]
         + byte_count[row * 4 + side * 2 + 1]) & 1
        for row in range(8)
        for side in range(2)
    ]

    short_parity: list[int] = []
    for short_len in range(1, 8):
        row = short_len - 1
        for upper in (False, True):
            mixed_byte = row * 4 + (3 if upper else 1)
            base = mixed_byte * 8
            # This is the LSB of the short-section count that also feeds the
            # complete mixed-byte POPCOUNT; it is not a private parity tree.
            short_parity.append(sum(matrix[base : base + short_len]) & 1)

    outputs = [0] * 31
    xor_nodes = 0
    for short_len in range(1, 8):
        row = short_len - 1
        for upper in (False, True):
            side = int(upper)
            short_diag = 31 - short_len if upper else short_len - 1
            long_diag = 15 + short_len if upper else 15 - short_len
            short = short_parity[row * 2 + side]
            long = byte_pair_parity[row * 2 + side] ^ short
            xor_nodes += 1
            outputs[short_diag] = short
            outputs[long_diag] = long

    outputs[7] = byte_count[28] & 1
    outputs[23] = byte_count[29] & 1
    outputs[15] = (byte_count[30] + byte_count[31]) & 1

    assert xor_nodes == 14
    return sum(bit << diag for diag, bit in enumerate(outputs))


def reduce32(a: int, b: int) -> int:
    a0, a1 = a & 0xFFFF, a >> 16
    b0, b1 = b & 0xFFFF, b >> 16
    p0 = reduce_leaf(a0, b0)
    p1 = reduce_leaf(a1, b1)
    pm = reduce_leaf(a0 ^ a1, b0 ^ b1)
    return p0 ^ ((pm ^ p0 ^ p1) << 16) ^ (p1 << 32)


def main() -> None:
    seen = set(LAYOUT)
    assert len(LAYOUT) == 256 and len(seen) == 256

    directed16 = [
        (0, 0),
        (0xFFFF, 0xFFFF),
        (1, 1),
        (0x8000, 0x8000),
        (0xAAAA, 0x5555),
        (0x1357, 0x9BDF),
    ]
    for a, b in directed16:
        assert reduce_leaf(a, b) == clmul(a, b, 16)

    for a in range(256):
        for b in range(256):
            assert reduce_leaf(a, b) == clmul(a, b, 16)

    rng = random.Random(0x25C014)
    for _ in range(100_000):
        a = rng.getrandbits(32)
        b = rng.getrandbits(32)
        assert reduce32(a, b) == clmul(a, b, 32)

    print(
        "[VV25_PARTITIONED_POP_MODEL] PASS layout=8x32 unique_pp=256 "
        "partitioned_mixed_bytes=14 native_xor_nodes=14 "
        "exhaustive8=65536 random32=100000"
    )


if __name__ == "__main__":
    main()
