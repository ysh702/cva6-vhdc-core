#!/usr/bin/env python3
"""Golden checks for HDEC BMCA hsim and hbundle packed counter updates."""
import random

MASK64 = (1 << 64) - 1


def bmca_cell(a, b, c):
    lo = a ^ b ^ c
    hi = (a & b) | (a & c) | (b & c)
    return lo, hi


def bmca_compress(row0, row1, row2, valid=(1, 1, 1)):
    lo, hi_a, _hi_b, count = bmca_compress4(row0, row1, row2, 0, valid=(*valid, 0))
    return lo, hi_a, count


def bmca_compress4(row0, row1, row2, row3, valid=(1, 1, 1, 1)):
    rows = [
        row0 & MASK64 if valid[0] else 0,
        row1 & MASK64 if valid[1] else 0,
        row2 & MASK64 if valid[2] else 0,
        row3 & MASK64 if valid[3] else 0,
    ]
    lo = 0
    hi_a = 0
    hi_b = 0
    for bit in range(64):
        lo_a_bit, hi_a_bit = bmca_cell(
            (rows[0] >> bit) & 1,
            (rows[1] >> bit) & 1,
            (rows[2] >> bit) & 1,
        )
        lo_bit, hi_b_bit = bmca_cell(
            lo_a_bit,
            (rows[3] >> bit) & 1,
            0,
        )
        lo |= lo_bit << bit
        hi_a |= hi_a_bit << bit
        hi_b |= hi_b_bit << bit
    count = lo.bit_count() + 2 * hi_a.bit_count() + 2 * hi_b.bit_count()
    return lo, hi_a, hi_b, count


def bmca_bundle_update(counter_word, lo, hi, subgroup):
    return bmca_bundle4_update(counter_word, lo, hi, 0, subgroup)


def bmca_bundle4_update(counter_word, lo, hi_a, hi_b, subgroup):
    shift = 16 * subgroup
    lo_bits = (lo >> shift) & 0xFFFF
    hi_a_bits = (hi_a >> shift) & 0xFFFF
    hi_b_bits = (hi_b >> shift) & 0xFFFF
    result = 0
    for nibble in range(16):
        old = (counter_word >> (4 * nibble)) & 0xF
        inc = (
            ((lo_bits >> nibble) & 1)
            + 2 * ((hi_a_bits >> nibble) & 1)
            + 2 * ((hi_b_bits >> nibble) & 1)
        )
        new = min(old + inc, 0xF)
        result |= new << (4 * nibble)
    return result


def packed_counter_word(value):
    word = 0
    for nibble in range(16):
        word |= (value & 0xF) << (4 * nibble)
    return word


def test_cell_truth_table():
    for a in (0, 1):
        for b in (0, 1):
            for c in (0, 1):
                lo, hi = bmca_cell(a, b, c)
                assert lo == (a ^ b ^ c)
                assert hi == 1 if (a + b + c) >= 2 else hi == 0
                assert lo + 2 * hi == a + b + c
    print("  cell truth table: PASS")


def test_lo_hi_random(n=10000):
    for _ in range(n):
        row0 = random.getrandbits(64)
        row1 = random.getrandbits(64)
        row2 = random.getrandbits(64)
        lo, hi, _ = bmca_compress(row0, row1, row2)
        assert lo == ((row0 ^ row1 ^ row2) & MASK64)
        maj = (row0 & row1) | (row0 & row2) | (row1 & row2)
        assert hi == (maj & MASK64)
    print(f"  64-cell lo/hi random: {n} vectors PASS")


def test_count3_equivalence(n=10000):
    directed = [
        (0, 0, 0),
        (MASK64, 0, 0),
        (MASK64, MASK64, 0),
        (MASK64, MASK64, MASK64),
        (0xAAAAAAAAAAAAAAAA, 0x5555555555555555, MASK64),
    ]
    for rows in directed:
        lo, hi, count3 = bmca_compress(*rows)
        expected = sum(row.bit_count() for row in rows)
        assert lo.bit_count() + 2 * hi.bit_count() == expected
        assert count3 == expected

    for _ in range(n):
        rows = [random.getrandbits(64) for _ in range(3)]
        lo, hi, count3 = bmca_compress(*rows)
        expected = sum(row.bit_count() for row in rows)
        assert lo.bit_count() + 2 * hi.bit_count() == expected
        assert count3 == expected
    print(f"  count3 equivalence: {n + len(directed)} vectors PASS")


def test_invalid_rows_zeroed(n=10000):
    for _ in range(n):
        row0 = random.getrandbits(64)
        row1 = random.getrandbits(64)
        row2 = random.getrandbits(64)
        _, _, count0 = bmca_compress(row0, row1, row2, valid=(1, 0, 0))
        _, _, count01 = bmca_compress(row0, row1, row2, valid=(1, 1, 0))
        assert count0 == row0.bit_count()
        assert count01 == row0.bit_count() + row1.bit_count()
    print(f"  invalid rows zeroed: {n} vectors PASS")


def test_all_ones_count3():
    _, _, count3 = bmca_compress(MASK64, MASK64, MASK64)
    assert count3 == 192
    print("  all ones count3=192: PASS")


def test_four_row_truth_table():
    for a in (0, 1):
        for b in (0, 1):
            for c in (0, 1):
                for d in (0, 1):
                    lo, hi_a, hi_b, count = bmca_compress4(a, b, c, d)
                    assert count == a + b + c + d
                    assert (lo & 1) + 2 * (hi_a & 1) + 2 * (hi_b & 1) == count
    print("  four-row truth table: PASS")


def test_four_row_count_equivalence(n=100000):
    directed = [
        (0, 0, 0, 0),
        (MASK64, 0, 0, 0),
        (MASK64, MASK64, 0, 0),
        (MASK64, MASK64, MASK64, 0),
        (MASK64, MASK64, MASK64, MASK64),
        (0xAAAAAAAAAAAAAAAA, 0x5555555555555555, MASK64, 0),
        (0xAAAAAAAAAAAAAAAA, 0x5555555555555555, MASK64, MASK64),
    ]
    for rows in directed:
        lo, hi_a, hi_b, count = bmca_compress4(*rows)
        expected = sum(row.bit_count() for row in rows)
        assert lo.bit_count() + 2 * hi_a.bit_count() + 2 * hi_b.bit_count() == expected
        assert count == expected

    for _ in range(n):
        rows = [random.getrandbits(64) for _ in range(4)]
        lo, hi_a, hi_b, count = bmca_compress4(*rows)
        expected = sum(row.bit_count() for row in rows)
        assert lo.bit_count() + 2 * hi_a.bit_count() + 2 * hi_b.bit_count() == expected
        assert count == expected
    print(f"  four-row count equivalence: {n + len(directed)} vectors PASS")


def test_four_row_degrades_to_three_row(n=10000):
    for _ in range(n):
        row0 = random.getrandbits(64)
        row1 = random.getrandbits(64)
        row2 = random.getrandbits(64)
        lo3, hi3, count3 = bmca_compress(row0, row1, row2)
        lo4, hi_a4, hi_b4, count4 = bmca_compress4(row0, row1, row2, 0, valid=(1, 1, 1, 0))
        assert lo4 == lo3
        assert hi_a4 == hi3
        assert hi_b4 == 0
        assert count4 == count3
    print(f"  four-row row3=0 degenerates to three-row: {n} vectors PASS")


def test_four_row_bundle_counter_update_random(n=10000):
    for _ in range(n):
        counter = random.getrandbits(64)
        rows = [random.getrandbits(64) for _ in range(4)]
        lo, hi_a, hi_b, _ = bmca_compress4(*rows)
        for subgroup in range(4):
            result = bmca_bundle4_update(counter, lo, hi_a, hi_b, subgroup)
            expected = 0
            for nibble in range(16):
                bit = 16 * subgroup + nibble
                old = (counter >> (4 * nibble)) & 0xF
                inc = sum((row >> bit) & 1 for row in rows)
                expected |= min(old + inc, 0xF) << (4 * nibble)
            assert result == expected
    print(f"  four-row bundle packed counter update random: {n} vectors PASS")


def test_four_row_bundle_saturation_directed():
    cases = [
        (11, 4, 15),
        (12, 4, 15),
        (13, 2, 15),
        (14, 1, 15),
        (15, 4, 15),
        (0, 4, 4),
    ]
    for old, inc, expected in cases:
        counter = packed_counter_word(old)
        rows = tuple(0xFFFF if idx < inc else 0 for idx in range(4))
        lo, hi_a, hi_b, _ = bmca_compress4(*rows)
        result = bmca_bundle4_update(counter, lo, hi_a, hi_b, 0)
        assert result == packed_counter_word(expected)
    print("  four-row bundle saturation directed cases: PASS")


def test_bundle_lo_hi_inc_equivalence(n=10000):
    directed = [
        (0, 0, 0),
        (MASK64, 0, 0),
        (MASK64, MASK64, 0),
        (MASK64, MASK64, MASK64),
        (0xAAAAAAAAAAAAAAAA, 0x5555555555555555, MASK64),
    ]
    for rows in directed:
        lo, hi, _ = bmca_compress(*rows)
        for bit in range(64):
            inc = ((lo >> bit) & 1) + 2 * ((hi >> bit) & 1)
            expected = sum((row >> bit) & 1 for row in rows)
            assert inc == expected

    for _ in range(n):
        rows = [random.getrandbits(64) for _ in range(3)]
        lo, hi, _ = bmca_compress(*rows)
        for bit in range(64):
            inc = ((lo >> bit) & 1) + 2 * ((hi >> bit) & 1)
            expected = sum((row >> bit) & 1 for row in rows)
            assert inc == expected
    print(f"  bundle lo/hi inc equivalence: {n + len(directed)} vectors PASS")


def test_bundle_counter_update_random(n=10000):
    for _ in range(n):
        counter = random.getrandbits(64)
        rows = [random.getrandbits(64) for _ in range(3)]
        lo, hi, _ = bmca_compress(*rows)
        for subgroup in range(4):
            result = bmca_bundle_update(counter, lo, hi, subgroup)
            expected = 0
            for nibble in range(16):
                bit = 16 * subgroup + nibble
                old = (counter >> (4 * nibble)) & 0xF
                inc = sum((row >> bit) & 1 for row in rows)
                expected |= min(old + inc, 0xF) << (4 * nibble)
            assert result == expected
    print(f"  bundle packed counter update random: {n} vectors PASS")


def test_bundle_counter_saturation_directed():
    cases = [
        (14, 2, 15),
        (14, 3, 15),
        (15, 1, 15),
        (15, 2, 15),
        (13, 3, 15),
        (0, 3, 3),
    ]
    for old, inc, expected in cases:
        counter = packed_counter_word(old)
        # Drive all 16 bits of subgroup 0 with the same increment.
        if inc == 0:
            rows = (0, 0, 0)
        elif inc == 1:
            rows = (0xFFFF, 0, 0)
        elif inc == 2:
            rows = (0xFFFF, 0xFFFF, 0)
        else:
            rows = (0xFFFF, 0xFFFF, 0xFFFF)
        lo, hi, _ = bmca_compress(*rows)
        result = bmca_bundle_update(counter, lo, hi, 0)
        assert result == packed_counter_word(expected)
    print("  bundle saturation directed cases: PASS")


def main():
    print("BMCA Golden Model Tests:")
    random.seed(42)
    test_cell_truth_table()
    test_lo_hi_random()
    test_count3_equivalence()
    test_invalid_rows_zeroed()
    test_all_ones_count3()
    test_four_row_truth_table()
    test_four_row_count_equivalence()
    test_four_row_degrades_to_three_row()
    test_four_row_bundle_counter_update_random()
    test_four_row_bundle_saturation_directed()
    test_bundle_lo_hi_inc_equivalence()
    test_bundle_counter_update_random()
    test_bundle_counter_saturation_directed()
    print("All tests PASSED")


if __name__ == "__main__":
    main()
