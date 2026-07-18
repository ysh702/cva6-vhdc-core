#!/usr/bin/env python3
"""Bit-exact model for VV24 independent POPCOUNT/XOR1 diagonal ownership."""

from __future__ import annotations

import random


def clmul(a: int, b: int, width: int) -> int:
    product = 0
    for bit in range(width):
        if (b >> bit) & 1:
            product ^= a << bit
    return product


def diag_len(diag: int) -> int:
    return diag + 1 if diag < 16 else 31 - diag


def pop_owner(diag: int) -> bool:
    length = diag_len(diag)
    return length not in (12, 13, 14, 16)


def diagonal_terms(a: int, b: int, diag: int) -> list[int]:
    start_a = max(0, diag - 15)
    return [
        ((a >> a_bit) & 1) & ((b >> (diag - a_bit)) & 1)
        for a_bit in range(start_a, start_a + diag_len(diag))
    ]


def build_layout() -> tuple[list[tuple[int, int]], list[int]]:
    pop_slots: list[tuple[int, int]] = []
    for diag in range(31):
        if pop_owner(diag):
            pop_slots.extend(
                (diag, chunk) for chunk in range((diag_len(diag) + 7) // 8)
            )
    xor_terms = [
        (diag, term)
        for diag in range(31)
        if not pop_owner(diag)
        for term in range(diag_len(diag))
    ]
    assert len(pop_slots) == 32
    assert len(xor_terms) == 94

    layout: list[tuple[int, int]] = []
    pop_mask: list[int] = []
    xor_cursor = 0
    for diag, chunk in pop_slots:
        for bit in range(8):
            term = chunk * 8 + bit
            if term < diag_len(diag):
                layout.append((diag, term))
                pop_mask.append(1)
            else:
                layout.append(xor_terms[xor_cursor])
                pop_mask.append(0)
                xor_cursor += 1
    assert xor_cursor == 94
    assert len(layout) == 256
    assert len(set(layout)) == 256
    return layout, pop_mask


LAYOUT, POP_MASK = build_layout()


def matrix_product(a: int, b: int) -> list[int]:
    diagonals = [diagonal_terms(a, b, diag) for diag in range(31)]
    return [diagonals[diag][term] for diag, term in LAYOUT]


def reduce_leaf(a: int, b: int) -> int:
    matrix = matrix_product(a, b)
    result = 0

    # All 32 byte counters are the existing POPCOUNT subunits.  Only their
    # owned positions are visible in ECC mode.
    byte_counts = [
        sum(matrix[base + bit] for bit in range(8) if POP_MASK[base + bit])
        for base in range(0, 256, 8)
    ]
    byte_cursor = 0
    for diag in range(31):
        if pop_owner(diag):
            chunks = (diag_len(diag) + 7) // 8
            parity = sum(byte_counts[byte_cursor : byte_cursor + chunks]) & 1
            byte_cursor += chunks
        else:
            parity = 0
            for term in diagonal_terms(a, b, diag):
                parity ^= term
        result |= parity << diag
    assert byte_cursor == 32
    return result


def reduce32(a: int, b: int) -> int:
    a0, a1 = a & 0xFFFF, a >> 16
    b0, b1 = b & 0xFFFF, b >> 16
    p0 = reduce_leaf(a0, b0)
    p1 = reduce_leaf(a1, b1)
    pm = reduce_leaf(a0 ^ a1, b0 ^ b1)
    return p0 ^ ((pm ^ p0 ^ p1) << 16) ^ (p1 << 32)


def main() -> None:
    pop_diags = [diag for diag in range(31) if pop_owner(diag)]
    xor_diags = [diag for diag in range(31) if not pop_owner(diag)]
    assert len(pop_diags) == 24
    assert len(xor_diags) == 7
    assert sum(diag_len(diag) for diag in pop_diags) == 162
    assert sum(diag_len(diag) for diag in xor_diags) == 94
    assert sum(diag_len(diag) - 1 for diag in xor_diags) == 87
    assert sum(diag_len(diag) > 8 for diag in pop_diags) == 8

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

    rng = random.Random(0x24A19)
    for _ in range(100_000):
        a = rng.getrandbits(32)
        b = rng.getrandbits(32)
        assert reduce32(a, b) == clmul(a, b, 32)

    print(
        "[VV24_NATIVE_XOR1_MODEL] PASS "
        "partition=256 pop_diags=24 pop_bits=162 pop_bytes=32 "
        "xor_diags=7 xor_bits=94 xor_nodes=87 pop_joins=8 "
        "exhaustive8=65536 random32=100000"
    )


if __name__ == "__main__":
    main()
