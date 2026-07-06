#!/usr/bin/env python3
"""Check diagonal-group modular-reduction packets against the VV13 leaf packet.

The RTL implementation intentionally starts from a mechanically equivalent
mapping: each diagonal parity group is treated as a sparse 32x32 subproduct,
then mapped through the same fixed packet reduction as the accepted VV13 leaf
packet.  This script proves that accumulating those group packets is equivalent
to reducing the completed leaf product.
"""

from __future__ import annotations

import argparse
import random
from collections import defaultdict


PATH_MASKS = {
    0b00_00: 0x0F,
    0b00_01: 0x0A,
    0b00_10: 0x1E,
    0b01_00: 0x0C,
    0b01_01: 0x08,
    0b01_10: 0x18,
    0b10_00: 0x3C,
    0b10_01: 0x28,
    0b10_10: 0x78,
}

MASK64 = (1 << 64) - 1
MASK128 = (1 << 128) - 1


def rows128(value: int) -> list[int]:
    return [(value >> (32 * idx)) & 0xFFFFFFFF for idx in range(4)]


def pack128(rows: list[int]) -> int:
    return sum((row & 0xFFFFFFFF) << (32 * idx) for idx, row in enumerate(rows))


def store_bitband(group_idx: int, parity_row: int) -> int:
    updated = 0
    if group_idx < 7:
        updated |= (parity_row & 0xFF) << (8 * group_idx)
    else:
        updated |= (parity_row & 0x7F) << 56
    return updated & ~(1 << 63)


def sub32_accum(acc: int, sub_idx: int, sub_product: int) -> int:
    acc_row = rows128(acc)
    sub_lo = sub_product & 0xFFFFFFFF
    sub_hi = (sub_product >> 32) & 0xFFFFFFFF

    if sub_idx == 0:
        acc_row[0] ^= sub_lo
        acc_row[1] ^= sub_hi ^ sub_lo
        acc_row[2] ^= sub_hi
    elif sub_idx == 1:
        acc_row[1] ^= sub_lo
        acc_row[2] ^= sub_hi ^ sub_lo
        acc_row[3] ^= sub_hi
    elif sub_idx == 2:
        acc_row[1] ^= sub_lo
        acc_row[2] ^= sub_hi

    return pack128(acc_row) & MASK128


def fold_word_contrib(mask: int, word_idx: int, leaf_product: int) -> int:
    mask_ext = mask & 0x7F
    lo = leaf_product & MASK64
    hi = (leaf_product >> 64) & MASK64
    contrib = 0
    if (mask_ext >> word_idx) & 1:
        contrib ^= lo
    if word_idx != 0 and ((mask_ext >> (word_idx - 1)) & 1):
        contrib ^= hi
    return contrib & MASK64


def fold_reduce_packet(mask: int, fold_word: int, leaf_product: int) -> list[int]:
    even = fold_word_contrib(mask, (fold_word << 1) | 0, leaf_product)
    odd = fold_word_contrib(mask, (fold_word << 1) | 1, leaf_product)
    packet = [0, 0, 0, 0]

    if fold_word == 0:
        packet[0] = even
        packet[1] = odd
    elif fold_word == 1:
        packet[0] = odd >> 41
        packet[1] = ((odd >> 41) << 10) & MASK64
        packet[2] = even
        packet[3] = odd & ((1 << 41) - 1)
    elif fold_word == 2:
        packet[0] = (even & ((1 << 41) - 1)) << 23
        packet[1] = (((odd & ((1 << 41) - 1)) << 23) | (even >> 41)) ^ (
            (even & ((1 << 31) - 1)) << 33
        )
        packet[2] = (odd >> 41) ^ (
            ((odd & ((1 << 31) - 1)) << 33) | (even >> 31)
        )
        packet[3] = odd >> 31
    else:
        packet[0] = (((odd & 0xFF) << 56) | (even >> 8)) ^ (odd >> 18)
        packet[1] = (((even >> 8) & ((1 << 54) - 1)) << 10) | ((odd >> 8) & 0x3FF)
        packet[2] = ((even & ((1 << 41) - 1)) << 23) ^ (
            ((odd & ((1 << 62) - 1)) << 2) | (even >> 62)
        )
        packet[3] = (
            ((odd & ((1 << 18) - 1)) << 23)
            | (even >> 41)
        ) ^ ((even & 0xFF) << 33) ^ (odd >> 62)

    return [word & MASK64 for word in packet]


def xor_packet(a: list[int], b: list[int]) -> list[int]:
    return [(x ^ y) & MASK64 for x, y in zip(a, b)]


def leaf_reduce_packet(mask: int, leaf_product: int) -> list[int]:
    packet = [0, 0, 0, 0]
    for fold_word in range(4):
        packet = xor_packet(packet, fold_reduce_packet(mask, fold_word, leaf_product))
    packet[3] &= (1 << 41) - 1
    return packet


def diag_group_reduce_packet(mask: int, sub_idx: int, group_idx: int, parity_row: int) -> list[int]:
    sub_product = store_bitband(group_idx, parity_row)
    leaf_delta = sub32_accum(0, sub_idx, sub_product)
    return leaf_reduce_packet(mask, leaf_delta)


def sv_bits(value: int, width: int) -> str:
    return format(value, f"0{width}b")


def sv_parity_ref(lo: int, hi: int) -> str:
    if lo == hi:
        return f"parity_row[{lo}]"
    return f"parity_row[{hi}:{lo}]"


def sv_shifted_parity_term(lo: int, hi: int, shift: int) -> str:
    dest_lo = lo + shift
    dest_hi = hi + shift
    high_zeros = 63 - dest_hi
    low_zeros = dest_lo
    parts: list[str] = []
    if high_zeros:
        parts.append(f"{high_zeros}'b0")
    parts.append(sv_parity_ref(lo, hi))
    if low_zeros:
        parts.append(f"{low_zeros}'b0")
    return "{" + ", ".join(parts) + "}"


def diag_case_lane_terms(mask: int, sub_idx: int, group_idx: int, lane: int) -> list[str]:
    shifted_runs: dict[int, list[int]] = defaultdict(list)

    for rid in range(8):
        if group_idx == 7 and rid == 7:
            continue
        packet = diag_group_reduce_packet(mask, sub_idx, group_idx, 1 << rid)
        word = packet[lane]
        for bit in range(64):
            if (word >> bit) & 1:
                shifted_runs[bit - rid].append(rid)

    terms: list[str] = []
    for shift in sorted(shifted_runs):
        rids = sorted(shifted_runs[shift])
        lo = hi = rids[0]
        for rid in rids[1:]:
            if rid == hi + 1:
                hi = rid
                continue
            terms.append(sv_shifted_parity_term(lo, hi, shift))
            lo = hi = rid
        terms.append(sv_shifted_parity_term(lo, hi, shift))
    return terms


def emit_sv_diag_reduce_function() -> str:
    lines: list[str] = [
        "    function automatic logic [LANE_NUM-1:0][LANE_WIDTH-1:0] ecc_kpd64_diag_reduce_packet(",
        "        input logic [3:0]             path,",
        "        input logic [1:0]             sub_idx,",
        "        input logic [2:0]             group_idx,",
        "        input logic [LANE_NUM*2-1:0]  parity_row",
        "    );",
        "        logic [LANE_NUM-1:0][LANE_WIDTH-1:0] packet;",
        "        begin",
        "            packet = '0;",
        "            unique case ({path, sub_idx, group_idx})",
    ]

    for path, mask in PATH_MASKS.items():
        for sub_idx in range(3):
            for group_idx in range(8):
                lines.append(
                    f"                9'b{sv_bits(path, 4)}_{sv_bits(sub_idx, 2)}_{sv_bits(group_idx, 3)}: begin"
                )
                for lane in range(4):
                    terms = diag_case_lane_terms(mask, sub_idx, group_idx, lane)
                    if not terms:
                        continue
                    if len(terms) == 1:
                        lines.append(f"                    packet[{lane}] = {terms[0]};")
                    else:
                        lines.append(f"                    packet[{lane}] = {terms[0]}")
                        for term in terms[1:-1]:
                            lines.append(f"                              ^ {term}")
                        lines.append(f"                              ^ {terms[-1]};")
                lines.append("                end")

    lines.extend(
        [
            "                default: begin",
            "                end",
            "            endcase",
            "            ecc_kpd64_diag_reduce_packet = packet;",
            "        end",
            "    endfunction",
        ]
    )
    return "\n".join(lines)


def emit_sv_diag_reduce_mask_function() -> str:
    lines: list[str] = [
        "    function automatic logic [LANE_NUM-1:0][LANE_WIDTH-1:0] ecc_kpd64_diag_word_reduce_packet(",
        "        input logic [2:0]             word_idx,",
        "        input logic [1:0]             sub_idx,",
        "        input logic [2:0]             group_idx,",
        "        input logic [LANE_NUM*2-1:0]  parity_row",
        "    );",
        "        logic [LANE_NUM-1:0][LANE_WIDTH-1:0] packet;",
        "        begin",
        "            packet = '0;",
        "            unique case ({word_idx, sub_idx, group_idx})",
    ]

    for word_idx in range(7):
        mask = 1 << word_idx
        for sub_idx in range(3):
            for group_idx in range(8):
                lines.append(
                    f"                8'b{sv_bits(word_idx, 3)}_{sv_bits(sub_idx, 2)}_{sv_bits(group_idx, 3)}: begin"
                )
                for lane in range(4):
                    terms = diag_case_lane_terms(mask, sub_idx, group_idx, lane)
                    if not terms:
                        continue
                    if len(terms) == 1:
                        lines.append(f"                    packet[{lane}] = {terms[0]};")
                    else:
                        lines.append(f"                    packet[{lane}] = {terms[0]}")
                        for term in terms[1:-1]:
                            lines.append(f"                              ^ {term}")
                        lines.append(f"                              ^ {terms[-1]};")
                lines.append("                end")

    lines.extend(
        [
            "                default: begin",
            "                end",
            "            endcase",
            "            ecc_kpd64_diag_word_reduce_packet = packet;",
            "        end",
            "    endfunction",
            "",
            "    function automatic logic [LANE_NUM-1:0][LANE_WIDTH-1:0] ecc_kpd64_diag_reduce_packet(",
            "        input logic [6:0]             mask,",
            "        input logic [1:0]             sub_idx,",
            "        input logic [2:0]             group_idx,",
            "        input logic [LANE_NUM*2-1:0]  parity_row",
            "    );",
            "        logic [LANE_NUM-1:0][LANE_WIDTH-1:0] packet;",
            "        begin",
            "            packet = '0;",
        ]
    )
    for word_idx in range(7):
        lines.extend(
            [
                f"            if (mask[{word_idx}]) begin",
                f"                packet ^= ecc_kpd64_diag_word_reduce_packet(3'd{word_idx}, sub_idx, group_idx, parity_row);",
                "            end",
            ]
        )
    lines.extend(
        [
            "            ecc_kpd64_diag_reduce_packet = packet;",
            "        end",
            "    endfunction",
        ]
    )
    return "\n".join(lines)


def sub_product_group_row(sub_product: int, group_idx: int) -> int:
    if group_idx < 7:
        return (sub_product >> (8 * group_idx)) & 0xFF
    return (sub_product >> 56) & 0x7F


def verify_case(mask: int, sub_products: list[int]) -> None:
    leaf_product = 0
    diag_packet = [0, 0, 0, 0]

    for sub_idx, sub_product in enumerate(sub_products):
        sub_product &= ~(1 << 63)
        leaf_product = sub32_accum(leaf_product, sub_idx, sub_product)
        for group_idx in range(8):
            row = sub_product_group_row(sub_product, group_idx)
            diag_packet = xor_packet(
                diag_packet,
                diag_group_reduce_packet(mask, sub_idx, group_idx, row),
            )

    oracle = leaf_reduce_packet(mask, leaf_product)
    if diag_packet != oracle:
        raise AssertionError(
            f"packet mismatch mask=0x{mask:02x} sub_products="
            f"{[hex(x) for x in sub_products]} diag={diag_packet} oracle={oracle}"
        )


def verify_all() -> None:
    for mask in PATH_MASKS.values():
        for sub_idx in range(3):
            for bit in range(63):
                sub_products = [0, 0, 0]
                sub_products[sub_idx] = 1 << bit
                verify_case(mask, sub_products)

        rng = random.Random(mask)
        for _ in range(1000):
            sub_products = [rng.getrandbits(63) for _ in range(3)]
            verify_case(mask, sub_products)

    print("PASS: diagonal group packets match VV13 leaf packet reduction")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--emit-sv-function",
        action="store_true",
        help="emit the fixed-coordinate SystemVerilog diagonal reduce function",
    )
    parser.add_argument(
        "--emit-sv-mask-function",
        action="store_true",
        help="emit the mask-factored SystemVerilog diagonal reduce function",
    )
    args = parser.parse_args()

    if args.emit_sv_mask_function:
        print(emit_sv_diag_reduce_mask_function())
        return

    if args.emit_sv_function:
        print(emit_sv_diag_reduce_function())
        return

    verify_all()


if __name__ == "__main__":
    main()
