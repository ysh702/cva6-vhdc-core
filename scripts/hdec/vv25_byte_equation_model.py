#!/usr/bin/env python3
"""Bit-exact model for VV25 complementary-byte diagonal equations.

The 16x16 partial products are permuted once into 32 eight-bit POPCOUNT
slots.  POPCOUNT exposes all 32 byte parities, while the existing native
two-input XOR1 nodes provide only the short correction equations needed to
recover the 31 carry-less-product diagonals.
"""

from __future__ import annotations

import argparse
import random
from dataclasses import dataclass


MATRIX_SOURCE_BASE = 0
BYTE_PARITY_SOURCE_BASE = 256
NODE_SOURCE_BASE = 288


def clmul(a: int, b: int, width: int) -> int:
    product = 0
    for bit in range(width):
        if (b >> bit) & 1:
            product ^= a << bit
    return product


def diag_len(diag: int) -> int:
    return diag + 1 if diag < 16 else 31 - diag


def diagonal_terms(a: int, b: int, diag: int) -> list[int]:
    start_a = max(0, diag - 15)
    return [
        ((a >> a_bit) & 1) & ((b >> (diag - a_bit)) & 1)
        for a_bit in range(start_a, start_a + diag_len(diag))
    ]


def build_layout() -> list[tuple[int, int]]:
    """Return the fixed 8-row x 4-byte complementary-diagonal layout."""

    layout: list[tuple[int, int]] = []
    for short_len in range(1, 8):
        lower_short = short_len - 1
        lower_long = 15 - short_len
        upper_short = 31 - short_len
        upper_long = 15 + short_len

        # Each side contributes one full eight-bit long-diagonal head and one
        # eight-bit mixed byte: short diagonal || remaining long-diagonal tail.
        layout.extend((lower_long, term) for term in range(8))
        layout.extend((lower_short, term) for term in range(short_len))
        layout.extend(
            (lower_long, term) for term in range(8, diag_len(lower_long))
        )
        layout.extend((upper_long, term) for term in range(8))
        layout.extend((upper_short, term) for term in range(short_len))
        layout.extend(
            (upper_long, term) for term in range(8, diag_len(upper_long))
        )

    # The final row contains the two unpaired length-eight diagonals and the
    # two halves of the length-sixteen centre diagonal.
    layout.extend((7, term) for term in range(8))
    layout.extend((23, term) for term in range(8))
    layout.extend((15, term) for term in range(8))
    layout.extend((15, term) for term in range(8, 16))

    expected = {
        (diag, term)
        for diag in range(31)
        for term in range(diag_len(diag))
    }
    assert len(layout) == 256
    assert len(set(layout)) == 256
    assert set(layout) == expected
    return layout


LAYOUT = build_layout()
FLAT_OF_TERM = {term: flat for flat, term in enumerate(LAYOUT)}


@dataclass(frozen=True)
class XorNode:
    lhs: int
    rhs: int


def matrix_source(diag: int, term: int) -> int:
    return MATRIX_SOURCE_BASE + FLAT_OF_TERM[(diag, term)]


def byte_source(byte: int) -> int:
    return BYTE_PARITY_SOURCE_BASE + byte


def node_source(node: int) -> int:
    return NODE_SOURCE_BASE + node


def build_equation_network() -> tuple[list[XorNode], list[int]]:
    nodes: list[XorNode] = []
    outputs = [-1] * 31

    def add_node(lhs: int, rhs: int) -> int:
        source = node_source(len(nodes))
        nodes.append(XorNode(lhs, rhs))
        return source

    def xor_reduce(sources: list[int]) -> int:
        assert sources
        level = list(sources)
        while len(level) > 1:
            next_level: list[int] = []
            for index in range(0, len(level) - 1, 2):
                next_level.append(add_node(level[index], level[index + 1]))
            if len(level) & 1:
                next_level.append(level[-1])
            level = next_level
        return level[0]

    for short_len in range(1, 8):
        row = short_len - 1
        for upper in (False, True):
            short_diag = 31 - short_len if upper else short_len - 1
            long_diag = 15 + short_len if upper else 15 - short_len
            head_parity = byte_source(row * 4 + (2 if upper else 0))
            mixed_parity = byte_source(row * 4 + (3 if upper else 1))

            if short_len <= 4:
                correction = xor_reduce(
                    [matrix_source(short_diag, term) for term in range(short_len)]
                )
                # Associate (head ^ mixed) ^ short so the longest L=4 path is
                # three native XOR stages instead of four, with no extra node.
                head_mixed = add_node(head_parity, mixed_parity)
                long_parity = add_node(head_mixed, correction)
                short_parity = correction
            else:
                tail_len = 8 - short_len
                correction = xor_reduce(
                    [
                        matrix_source(long_diag, term)
                        for term in range(8, 8 + tail_len)
                    ]
                )
                short_parity = add_node(mixed_parity, correction)
                long_parity = add_node(head_parity, correction)

            outputs[short_diag] = short_parity
            outputs[long_diag] = long_parity

    outputs[7] = byte_source(28)
    outputs[23] = byte_source(29)
    outputs[15] = add_node(byte_source(30), byte_source(31))

    assert len(nodes) == 47
    assert all(source >= 0 for source in outputs)
    return nodes, outputs


NODES, OUTPUT_SOURCES = build_equation_network()


def matrix_product(a: int, b: int) -> list[int]:
    diagonals = [diagonal_terms(a, b, diag) for diag in range(31)]
    return [diagonals[diag][term] for diag, term in LAYOUT]


def source_value(
    source: int,
    matrix: list[int],
    byte_parity: list[int],
    node_values: list[int],
) -> int:
    if source < BYTE_PARITY_SOURCE_BASE:
        return matrix[source]
    if source < NODE_SOURCE_BASE:
        return byte_parity[source - BYTE_PARITY_SOURCE_BASE]
    return node_values[source - NODE_SOURCE_BASE]


def reduce_leaf(a: int, b: int) -> int:
    matrix = matrix_product(a, b)
    byte_parity = [
        sum(matrix[base : base + 8]) & 1 for base in range(0, 256, 8)
    ]
    node_values: list[int] = []
    for node in NODES:
        node_values.append(
            source_value(node.lhs, matrix, byte_parity, node_values)
            ^ source_value(node.rhs, matrix, byte_parity, node_values)
        )

    product = 0
    for diag, source in enumerate(OUTPUT_SOURCES):
        product |= source_value(source, matrix, byte_parity, node_values) << diag
    return product


def reduce32(a: int, b: int) -> int:
    a0, a1 = a & 0xFFFF, a >> 16
    b0, b1 = b & 0xFFFF, b >> 16
    p0 = reduce_leaf(a0, b0)
    p1 = reduce_leaf(a1, b1)
    pm = reduce_leaf(a0 ^ a1, b0 ^ b1)
    return p0 ^ ((pm ^ p0 ^ p1) << 16) ^ (p1 << 32)


def source_depth(source: int, node_depth: list[int]) -> int:
    if source < NODE_SOURCE_BASE:
        return 0
    return node_depth[source - NODE_SOURCE_BASE]


def emit_sv() -> None:
    print("MATRIX_DIAG = '{")
    print(",".join(str(diag) for diag, _ in LAYOUT))
    print("};")
    print("MATRIX_TERM = '{")
    print(",".join(str(term) for _, term in LAYOUT))
    print("};")
    print("XOR_NODE_LHS = '{")
    print(",".join(str(node.lhs) for node in NODES))
    print("};")
    print("XOR_NODE_RHS = '{")
    print(",".join(str(node.rhs) for node in NODES))
    print("};")
    print("DIAG_SOURCE = '{")
    print(",".join(str(source) for source in OUTPUT_SOURCES))
    print("};")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--emit-sv", action="store_true")
    args = parser.parse_args()

    if args.emit_sv:
        emit_sv()
        return

    byte_uses = [0] * 32
    for node in NODES:
        for source in (node.lhs, node.rhs):
            if BYTE_PARITY_SOURCE_BASE <= source < NODE_SOURCE_BASE:
                byte_uses[source - BYTE_PARITY_SOURCE_BASE] += 1
    for source in OUTPUT_SOURCES:
        if BYTE_PARITY_SOURCE_BASE <= source < NODE_SOURCE_BASE:
            byte_uses[source - BYTE_PARITY_SOURCE_BASE] += 1
    assert all(uses > 0 for uses in byte_uses)

    node_depth: list[int] = []
    for node_idx, node in enumerate(NODES):
        for source in (node.lhs, node.rhs):
            if source >= NODE_SOURCE_BASE:
                assert source - NODE_SOURCE_BASE < node_idx
        node_depth.append(
            1 + max(source_depth(node.lhs, node_depth), source_depth(node.rhs, node_depth))
        )
    assert max(node_depth) == 3

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

    rng = random.Random(0x25B17E)
    for _ in range(100_000):
        a = rng.getrandbits(32)
        b = rng.getrandbits(32)
        assert reduce32(a, b) == clmul(a, b, 32)

    print(
        "[VV25_BYTE_EQUATION_MODEL] PASS "
        "layout=8x32 unique_pp=256 pop_bytes=32 native_xor_nodes=47 "
        f"max_xor_depth={max(node_depth)} exhaustive8=65536 random32=100000"
    )


if __name__ == "__main__":
    main()
