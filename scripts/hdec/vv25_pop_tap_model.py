#!/usr/bin/env python3
"""VV25 POPCOUNT-intermediate-tap plus native-XOR1 diagonal model."""

from __future__ import annotations

import argparse
import random
from dataclasses import dataclass

from vv25_byte_equation_model import LAYOUT, clmul, diagonal_terms


MATRIX_SOURCE_BASE = 0
BYTE_PARITY_SOURCE_BASE = 256
BYTE_PAIR_PARITY_SOURCE_BASE = 288
SHORT_TAP_SOURCE_BASE = 304
NODE_SOURCE_BASE = 314


@dataclass(frozen=True)
class XorNode:
    lhs: int
    rhs: int


def byte_source(byte: int) -> int:
    return BYTE_PARITY_SOURCE_BASE + byte


def byte_pair_source(row: int, upper: bool) -> int:
    return BYTE_PAIR_PARITY_SOURCE_BASE + row * 2 + int(upper)


def short_tap_source(short_len: int, upper: bool) -> int:
    tap_base = {2: 0, 3: 2, 4: 4, 5: 6, 6: 8}[short_len]
    return SHORT_TAP_SOURCE_BASE + tap_base + int(upper)


def node_source(node: int) -> int:
    return NODE_SOURCE_BASE + node


def build_network() -> tuple[list[XorNode], list[int]]:
    nodes: list[XorNode] = []
    outputs = [-1] * 31

    def add_node(lhs: int, rhs: int) -> int:
        source = node_source(len(nodes))
        nodes.append(XorNode(lhs, rhs))
        return source

    for short_len in range(1, 8):
        row = short_len - 1
        for upper in (False, True):
            short_diag = 31 - short_len if upper else short_len - 1
            long_diag = 15 + short_len if upper else 15 - short_len
            mixed_byte = row * 4 + (3 if upper else 1)
            mixed_flat = mixed_byte * 8

            if short_len == 1:
                short_parity = mixed_flat
            elif short_len in (2, 4):
                short_parity = short_tap_source(short_len, upper)
            elif short_len in (3, 5):
                short_parity = add_node(
                    short_tap_source(short_len, upper),
                    mixed_flat + short_len - 1,
                )
            elif short_len == 6:
                # M=S||T, |T|=2.  The existing byte parity and pair-3
                # counter LSB recover S without a private reduction tree.
                short_parity = add_node(
                    byte_source(mixed_byte), short_tap_source(short_len, upper)
                )
            else:
                # M=S||T, |T|=1.
                short_parity = add_node(byte_source(mixed_byte), mixed_flat + 7)

            # The existing HDC row-count byte-pair sum exposes
            # x=parity(H)+parity(M)=g^s.  One native XOR1 node recovers g.
            long_parity = add_node(byte_pair_source(row, upper), short_parity)
            outputs[short_diag] = short_parity
            outputs[long_diag] = long_parity

    outputs[7] = byte_source(28)
    outputs[23] = byte_source(29)
    outputs[15] = byte_pair_source(7, True)

    assert len(nodes) == 22
    assert all(source >= 0 for source in outputs)
    return nodes, outputs


NODES, OUTPUT_SOURCES = build_network()


def matrix_product(a: int, b: int) -> list[int]:
    diagonals = [diagonal_terms(a, b, diag) for diag in range(31)]
    return [diagonals[diag][term] for diag, term in LAYOUT]


def build_pop_taps(matrix: list[int]) -> tuple[list[int], list[int], list[int]]:
    byte_parity = [
        sum(matrix[base : base + 8]) & 1 for base in range(0, 256, 8)
    ]
    byte_pair_parity = [
        byte_parity[row * 4 + side * 2]
        ^ byte_parity[row * 4 + side * 2 + 1]
        for row in range(8)
        for side in range(2)
    ]

    short_taps: list[int] = []
    for short_len in (2, 3, 4, 5, 6):
        row = short_len - 1
        for upper in (False, True):
            mixed_byte = row * 4 + (3 if upper else 1)
            base = mixed_byte * 8
            if short_len in (2, 3):
                short_taps.append((matrix[base] + matrix[base + 1]) & 1)
            elif short_len in (4, 5):
                short_taps.append(sum(matrix[base : base + 4]) & 1)
            else:
                short_taps.append((matrix[base + 6] + matrix[base + 7]) & 1)
    assert len(short_taps) == 10
    return byte_parity, byte_pair_parity, short_taps


def source_value(
    source: int,
    matrix: list[int],
    byte_parity: list[int],
    byte_pair_parity: list[int],
    short_taps: list[int],
    node_values: list[int],
) -> int:
    if source < BYTE_PARITY_SOURCE_BASE:
        return matrix[source]
    if source < BYTE_PAIR_PARITY_SOURCE_BASE:
        return byte_parity[source - BYTE_PARITY_SOURCE_BASE]
    if source < SHORT_TAP_SOURCE_BASE:
        return byte_pair_parity[source - BYTE_PAIR_PARITY_SOURCE_BASE]
    if source < NODE_SOURCE_BASE:
        return short_taps[source - SHORT_TAP_SOURCE_BASE]
    return node_values[source - NODE_SOURCE_BASE]


def reduce_leaf(a: int, b: int) -> int:
    matrix = matrix_product(a, b)
    byte_parity, byte_pair_parity, short_taps = build_pop_taps(matrix)
    node_values: list[int] = []
    for node in NODES:
        node_values.append(
            source_value(
                node.lhs,
                matrix,
                byte_parity,
                byte_pair_parity,
                short_taps,
                node_values,
            )
            ^ source_value(
                node.rhs,
                matrix,
                byte_parity,
                byte_pair_parity,
                short_taps,
                node_values,
            )
        )

    product = 0
    for diag, source in enumerate(OUTPUT_SOURCES):
        product |= source_value(
            source,
            matrix,
            byte_parity,
            byte_pair_parity,
            short_taps,
            node_values,
        ) << diag
    return product


def reduce32(a: int, b: int) -> int:
    a0, a1 = a & 0xFFFF, a >> 16
    b0, b1 = b & 0xFFFF, b >> 16
    p0 = reduce_leaf(a0, b0)
    p1 = reduce_leaf(a1, b1)
    pm = reduce_leaf(a0 ^ a1, b0 ^ b1)
    return p0 ^ ((pm ^ p0 ^ p1) << 16) ^ (p1 << 32)


def emit_sv() -> None:
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

    for source, node_idx in (
        (source, node_idx)
        for node_idx, node in enumerate(NODES)
        for source in (node.lhs, node.rhs)
    ):
        if source >= NODE_SOURCE_BASE:
            assert source - NODE_SOURCE_BASE < node_idx

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

    rng = random.Random(0x25C022)
    for _ in range(100_000):
        a = rng.getrandbits(32)
        b = rng.getrandbits(32)
        assert reduce32(a, b) == clmul(a, b, 32)

    print(
        "[VV25_POP_TAP_MODEL] PASS layout=8x32 unique_pp=256 "
        "pop_bytes=32 pop_byte_pairs=16 pop_short_taps=10 "
        "native_xor_nodes=22 exhaustive8=65536 random32=100000"
    )


if __name__ == "__main__":
    main()
