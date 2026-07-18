#!/usr/bin/env python3
"""Golden model for the VV23 shared-AND 8x32 diagonal matrix.

One 16x16 carry-less product is packed into eight rows of 32 pairwise partial
products.  Four byte counts per row build all eight complete 32-bit POPCOUNT
results.  XOR1 directly reduces three diagonal segments per row and recovers
the remaining segment from the full POPCOUNT parity.  Of its 87 logical
three-input reductions, 64 map onto live VV22 low-XOR nodes 160..223 and 23
map onto original nodes 0..22.  Three such kernels form the existing 32x32
interface through one Karatsuba level.
"""

from __future__ import annotations

import argparse
import random
from collections.abc import Iterable, Sequence


def clmul(a: int, b: int, width: int) -> int:
    product = 0
    for bit in range(width):
        if (a >> bit) & 1:
            product ^= b << bit
    return product


def row_diagonals(row: int) -> tuple[int, ...]:
    if not 0 <= row < 8:
        raise ValueError(f"row must be in [0, 7], got {row}")
    if row < 7:
        return row, 30 - row, 14 - row, 16 + row
    return 7, 15, 23


def diagonal_terms(a: int, b: int, diagonal: int) -> list[int]:
    terms: list[int] = []
    for a_bit in range(16):
        b_bit = diagonal - a_bit
        if 0 <= b_bit < 16:
            terms.append(((a >> a_bit) & 1) & ((b >> b_bit) & 1))
    return terms


def pack_matrix(a: int, b: int) -> tuple[list[list[int]], list[list[list[int]]]]:
    rows: list[list[int]] = []
    segments: list[list[list[int]]] = []
    for row in range(8):
        row_segments = [diagonal_terms(a, b, d) for d in row_diagonals(row)]
        row_bits = [bit for segment in row_segments for bit in segment]
        if len(row_bits) != 32:
            raise AssertionError(f"row {row} has {len(row_bits)} bits instead of 32")
        rows.append(row_bits)
        segments.append(row_segments)
    return rows, segments


def parity(bits: Iterable[int]) -> int:
    value = 0
    for bit in bits:
        value ^= bit
    return value


def xor1_recover_segments(
    row: int, row_bits: list[int], row_segments: list[list[int]]
) -> tuple[tuple[int, ...], int, int]:
    """Model the 87 direct three-input reductions inside shared XOR1."""
    if len(row_bits) != 32:
        raise AssertionError(f"row {row} does not contain 32 AND bits")

    byte_counts = [sum(row_bits[8 * byte : 8 * byte + 8]) for byte in range(4)]
    if sum(byte_counts) != sum(row_bits):
        raise AssertionError(f"row {row} byte counts are not the complete POPCOUNT")
    row_parity = parity(row_bits)

    if row < 7:
        a = parity(row_segments[0])
        b = parity(row_segments[1])
        c = parity(row_segments[2])
        abc = a ^ b ^ c
        d = row_parity ^ abc
        recovered = a, b, c, d
        tree_nodes = (
            len(row_segments[0]) // 2
            + len(row_segments[1]) // 2
            + len(row_segments[2]) // 2
            + 2
        )
    else:
        a = parity(row_segments[0])
        c = parity(row_segments[2])
        b = row_parity ^ a ^ c
        recovered = a, b, c
        tree_nodes = len(row_segments[0]) // 2 + len(row_segments[2]) // 2 + 1

    expected = tuple(parity(segment) for segment in row_segments)
    if recovered != expected:
        raise AssertionError(
            f"row {row} XOR1 recovery mismatch got={recovered} expected={expected}"
        )

    return recovered, tree_nodes, 4


def recover_diag16(a: int, b: int) -> int:
    rows, segments = pack_matrix(a, b)
    diagonal_parity: list[int | None] = [None] * 31
    xor1_node_count = 0
    popcount_byte_count = 0

    for row, (row_bits, row_segments) in enumerate(zip(rows, segments, strict=True)):
        recovered, row_nodes, row_bytes = xor1_recover_segments(
            row, row_bits, row_segments
        )
        xor1_node_count += row_nodes
        popcount_byte_count += row_bytes

        for diagonal, value in zip(row_diagonals(row), recovered, strict=True):
            diagonal_parity[diagonal] = value

    if any(value is None for value in diagonal_parity):
        raise AssertionError("not all 31 diagonals were reconstructed")
    if xor1_node_count != 87:
        raise AssertionError(f"diagonal mode uses {xor1_node_count} XOR1 nodes, not 87")
    if popcount_byte_count != 32:
        raise AssertionError(
            f"matrix uses {popcount_byte_count} POPCOUNT bytes, not 32"
        )

    return sum(int(value) << diagonal for diagonal, value in enumerate(diagonal_parity))


def karatsuba32(a: int, b: int) -> int:
    a_lo = a & 0xFFFF
    a_hi = (a >> 16) & 0xFFFF
    b_lo = b & 0xFFFF
    b_hi = (b >> 16) & 0xFFFF

    z0 = recover_diag16(a_lo, b_lo)
    z2 = recover_diag16(a_hi, b_hi)
    zm = recover_diag16(a_lo ^ a_hi, b_lo ^ b_hi)
    middle = z0 ^ z2 ^ zm
    return z0 ^ (middle << 16) ^ (z2 << 32)


def check_matrix_partition() -> None:
    seen: set[tuple[int, int]] = set()
    for row in range(8):
        row_pairs: list[tuple[int, int]] = []
        for diagonal in row_diagonals(row):
            for a_bit in range(16):
                b_bit = diagonal - a_bit
                if 0 <= b_bit < 16:
                    row_pairs.append((a_bit, b_bit))
        if len(row_pairs) != 32:
            raise AssertionError(f"row {row} does not contain exactly 32 terms")
        overlap = seen.intersection(row_pairs)
        if overlap:
            raise AssertionError(f"duplicate matrix terms in row {row}: {sorted(overlap)}")
        seen.update(row_pairs)

    expected = {(a_bit, b_bit) for a_bit in range(16) for b_bit in range(16)}
    if seen != expected:
        raise AssertionError("8x32 rows do not cover the complete 16x16 AND plane")


def check_vectors(vectors: Sequence[tuple[int, int]]) -> None:
    for a, b in vectors:
        got = karatsuba32(a, b)
        expected = clmul(a, b, 32)
        if got != expected:
            raise AssertionError(
                f"32x32 mismatch a=0x{a:08x} b=0x{b:08x} "
                f"got=0x{got:016x} expected=0x{expected:016x}"
            )


def run(random_cases: int, seed: int) -> None:
    check_matrix_partition()

    directed = [
        (0x00000000, 0x00000000),
        (0x00000001, 0x00000001),
        (0xFFFFFFFF, 0xFFFFFFFF),
        (0x0000FFFF, 0xFFFF0000),
        (0x80000000, 0x00000001),
        (0x00008000, 0x00010000),
        (0xAAAAAAAA, 0x55555555),
        (0x01234567, 0x89ABCDEF),
    ]
    check_vectors(directed)

    # Exhaust every pair of 8-bit values through the same 16-bit matrix kernel.
    for a in range(1 << 8):
        for b in range(1 << 8):
            got = recover_diag16(a, b)
            expected = clmul(a, b, 16)
            if got != expected:
                raise AssertionError(
                    f"exhaustive-8 mismatch a=0x{a:02x} b=0x{b:02x} "
                    f"got=0x{got:08x} expected=0x{expected:08x}"
                )

    rng = random.Random(seed)
    for case in range(random_cases):
        a = rng.getrandbits(32)
        b = rng.getrandbits(32)
        got = karatsuba32(a, b)
        expected = clmul(a, b, 32)
        if got != expected:
            raise AssertionError(
                f"random case {case} mismatch a=0x{a:08x} b=0x{b:08x} "
                f"got=0x{got:016x} expected=0x{expected:016x}"
            )

    print(
        "[VV23_UNIFIED_MATRIX_MODEL] PASS "
        f"partition=256 popcount_bytes=32 xor1_nodes=87 exhaustive8=65536 "
        f"random32={random_cases} seed=0x{seed:x}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--random-cases", type=int, default=100_000)
    parser.add_argument("--seed", type=lambda value: int(value, 0), default=0x23A16)
    args = parser.parse_args()
    if args.random_cases < 0:
        parser.error("--random-cases must be non-negative")
    run(args.random_cases, args.seed)


if __name__ == "__main__":
    main()
