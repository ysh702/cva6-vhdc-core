#!/usr/bin/env python3
"""Golden checks for the HDEC BMCA hvsim batch compressor."""
import random

MASK64 = (1 << 64) - 1


def bmca_cell(a, b, c):
    lo = a ^ b ^ c
    hi = (a & b) | (a & c) | (b & c)
    return lo, hi


def bmca_compress(row0, row1, row2, valid=(1, 1, 1)):
    rows = [
        row0 & MASK64 if valid[0] else 0,
        row1 & MASK64 if valid[1] else 0,
        row2 & MASK64 if valid[2] else 0,
    ]
    lo = 0
    hi = 0
    for bit in range(64):
        lbit, hbit = bmca_cell(
            (rows[0] >> bit) & 1,
            (rows[1] >> bit) & 1,
            (rows[2] >> bit) & 1,
        )
        lo |= lbit << bit
        hi |= hbit << bit
    count3 = lo.bit_count() + 2 * hi.bit_count()
    return lo, hi, count3


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


def main():
    print("BMCA Golden Model Tests:")
    random.seed(42)
    test_cell_truth_table()
    test_lo_hi_random()
    test_count3_equivalence()
    test_invalid_rows_zeroed()
    test_all_ones_count3()
    print("All tests PASSED")


if __name__ == "__main__":
    main()
