#!/usr/bin/env python3
"""Reference model for K-233 tau-adic scalar multiplication experiments.

This is an algorithm bring-up model for the V38 Koblitz direction. It verifies
that window tau-NAF point multiplication agrees with ordinary affine binary
scalar multiplication on the same K-233 curve used by the HDEC ECC tests.
"""

from __future__ import annotations

import argparse
import random
from dataclasses import dataclass


M = 233
POLY = (1 << 233) | (1 << 74) | 1
MASK = (1 << M) - 1
CURVE_A = 0
CURVE_B = 1
MU = -1  # K-233 is E_a with a=0, so mu=(-1)^(1-a)=-1.

GX = int("017232ba853a7e731af129f22ff4149563a419c26bf50a4c9d6eefad6126", 16)
GY = int("01db537dece819b7f70f555a67c427a8cd9bf18aeb9b56e0c11056fae6a3", 16)
EXPECTED_3G_X = int("0000004656e0aabbe341407715ca4a7fac287b41baa1f789c29bfa27e53a7a46", 16)
EXPECTED_3G_Y = int("000000f79a7245fba513df787a64c618e97ebcc078638ebaaa562e9862bc00ce", 16)

Point = tuple[int, int] | None


def gf_reduce(value: int) -> int:
    while value.bit_length() > M:
        value ^= POLY << (value.bit_length() - 1 - M)
    return value & MASK


def gf_mul(a: int, b: int) -> int:
    result = 0
    aa = a
    bb = b
    while bb:
        if bb & 1:
            result ^= aa
        bb >>= 1
        aa <<= 1
        if aa >> M:
            aa ^= POLY
    return result & MASK


def gf_sqr(a: int) -> int:
    result = 0
    bit = 0
    value = a
    while value:
        if value & 1:
            result |= 1 << (2 * bit)
        value >>= 1
        bit += 1
    return gf_reduce(result)


def gf_inv(a: int) -> int:
    if a == 0:
        raise ZeroDivisionError("GF inverse of zero")

    u = a
    v = POLY
    g1 = 1
    g2 = 0
    while u != 1:
        shift = u.bit_length() - v.bit_length()
        if shift < 0:
            u, v = v, u
            g1, g2 = g2, g1
            shift = -shift
        u ^= v << shift
        g1 ^= g2 << shift
    return gf_reduce(g1)


def gf_div(a: int, b: int) -> int:
    return gf_mul(a, gf_inv(b))


def point_neg(point: Point) -> Point:
    if point is None:
        return None
    x, y = point
    return x, x ^ y


def point_double(point: Point) -> Point:
    if point is None:
        return None
    x, y = point
    if x == 0:
        return None

    lam = x ^ gf_div(y, x)
    x3 = gf_sqr(lam) ^ lam ^ CURVE_A
    y3 = gf_sqr(x) ^ gf_mul(lam ^ 1, x3)
    return x3 & MASK, y3 & MASK


def point_add(left: Point, right: Point) -> Point:
    if left is None:
        return right
    if right is None:
        return left

    x1, y1 = left
    x2, y2 = right
    if x1 == x2:
        if y1 == y2:
            return point_double(left)
        return None

    lam = gf_div(y1 ^ y2, x1 ^ x2)
    x3 = gf_sqr(lam) ^ lam ^ x1 ^ x2 ^ CURVE_A
    y3 = gf_mul(lam, x1 ^ x3) ^ x3 ^ y1
    return x3 & MASK, y3 & MASK


def point_mul_binary(k: int, point: Point) -> Point:
    result: Point = None
    for bit in reversed(range(k.bit_length())):
        result = point_double(result)
        if (k >> bit) & 1:
            result = point_add(result, point)
    return result


def point_tau(point: Point) -> Point:
    if point is None:
        return None
    x, y = point
    return gf_sqr(x), gf_sqr(y)


def tau_mul_pair(u: int, v: int) -> tuple[int, int]:
    """Return tau * (u + v*tau) using tau^2 - mu*tau + 2 = 0."""
    return -2 * v, u + MU * v


def tau_div_once(u: int, v: int) -> tuple[int, int] | None:
    """Return (u + v*tau) / tau when divisible by tau."""
    if u & 1:
        return None
    return v + MU * (u // 2), -(u // 2)


def tau_divisible_by_pow(u: int, v: int, width: int) -> bool:
    for _ in range(width):
        divided = tau_div_once(u, v)
        if divided is None:
            return False
        u, v = divided
    return True


def choose_window_digit(u: int, v: int, width: int) -> int:
    if not (u & 1):
        return 0

    bound = 1 << (width - 1)
    candidates = [
        digit
        for digit in range(-bound + 1, bound, 2)
        if digit and tau_divisible_by_pow(u - digit, v, width)
    ]
    if not candidates:
        raise ValueError(f"no tau-NAF digit for u={u}, v={v}, width={width}")
    return min(candidates, key=lambda digit: (abs(digit), digit < 0))


def window_tnaf_digits(k: int, width: int) -> list[int]:
    if width < 2:
        raise ValueError("window width must be at least 2")

    u = k
    v = 0
    digits: list[int] = []
    while u or v:
        digit = choose_window_digit(u, v, width) if (u & 1) else 0
        u -= digit
        digits.append(digit)
        divided = tau_div_once(u, v)
        if divided is None:
            raise AssertionError("digit selection did not make value tau-divisible")
        u, v = divided
    return digits


def eval_tau_digits(digits: list[int]) -> tuple[int, int]:
    u = 0
    v = 0
    for digit in reversed(digits):
        u, v = tau_mul_pair(u, v)
        u += digit
    return u, v


def precompute_odd_points(point: Point, max_digit: int) -> dict[int, Point]:
    if max_digit < 1:
        return {}

    table: dict[int, Point] = {1: point}
    two_point = point_double(point)
    for digit in range(3, max_digit + 1, 2):
        table[digit] = point_add(table[digit - 2], two_point)
    return table


def point_mul_tau_window(k: int, point: Point, width: int) -> tuple[Point, list[int]]:
    digits = window_tnaf_digits(k, width)
    max_digit = max([abs(digit) for digit in digits] + [1])
    table = precompute_odd_points(point, max_digit)

    result: Point = None
    for digit in reversed(digits):
        result = point_tau(result)
        if digit > 0:
            result = point_add(result, table[digit])
        elif digit < 0:
            result = point_add(result, point_neg(table[-digit]))
    return result, digits


def on_curve(point: Point) -> bool:
    if point is None:
        return True
    x, y = point
    left = gf_sqr(y) ^ gf_mul(x, y)
    right = gf_mul(gf_mul(x, x), x) ^ gf_mul(CURVE_A, gf_sqr(x)) ^ CURVE_B
    return left == right


@dataclass(frozen=True)
class DigitStats:
    width: int
    avg_len: float
    avg_weight: float
    min_weight: int
    max_weight: int
    avg_mul5: float
    avg_mul8: float


def digit_weight(digits: list[int]) -> int:
    return sum(1 for digit in digits if digit)


def collect_stats(samples: int, seed: int) -> list[DigitStats]:
    rng = random.Random(seed)
    stats: list[DigitStats] = []
    for width in range(2, 6):
        lengths: list[int] = []
        weights: list[int] = []
        for _ in range(samples):
            scalar = rng.getrandbits(M)
            digits = window_tnaf_digits(scalar, width)
            lengths.append(len(digits))
            weights.append(digit_weight(digits))
        avg_len = sum(lengths) / samples
        avg_weight = sum(weights) / samples
        stats.append(
            DigitStats(
                width=width,
                avg_len=avg_len,
                avg_weight=avg_weight,
                min_weight=min(weights),
                max_weight=max(weights),
                avg_mul5=avg_weight * 5.0,
                avg_mul8=avg_weight * 8.0,
            )
        )
    return stats


def run_self_test() -> None:
    base = (GX, GY)
    assert on_curve(base)
    assert point_mul_binary(3, base) == (EXPECTED_3G_X, EXPECTED_3G_Y)

    scalars = [0, 1, 2, 3, 5, 7, 0x12345, (1 << 232) + 12345]
    for width in range(2, 6):
        for scalar in scalars:
            binary = point_mul_binary(scalar, base)
            tau_result, digits = point_mul_tau_window(scalar, base, width)
            assert tau_result == binary
            assert eval_tau_digits(digits) == (scalar, 0)


def print_scalar_examples() -> None:
    examples = [3, 0x12345, (1 << 232) + 12345]
    for scalar in examples:
        print(f"scalar=0x{scalar:x}")
        for width in range(2, 6):
            digits = window_tnaf_digits(scalar, width)
            print(
                f"  w={width}: len={len(digits):3d} "
                f"weight={digit_weight(digits):3d} "
                f"max_digit={max([abs(digit) for digit in digits] + [0]):2d} "
                f"est_5M={digit_weight(digits) * 5:4d}"
            )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--samples", type=int, default=100)
    parser.add_argument("--seed", type=int, default=37)
    args = parser.parse_args()

    run_self_test()
    print("[PASS] K-233 base point, 3G vector, and tau-window equivalence")
    print()
    print("Scalar examples, excluding precomputation cost:")
    print_scalar_examples()
    print()
    print(f"Random {M}-bit scalar digit statistics, samples={args.samples}, seed={args.seed}")
    print("width avg_len avg_weight min_weight max_weight est_5M est_8M")
    for stat in collect_stats(args.samples, args.seed):
        print(
            f"{stat.width:5d} "
            f"{stat.avg_len:7.2f} "
            f"{stat.avg_weight:10.2f} "
            f"{stat.min_weight:10d} "
            f"{stat.max_weight:10d} "
            f"{stat.avg_mul5:7.2f} "
            f"{stat.avg_mul8:7.2f}"
        )
    print()
    print("Note: this is unreduced window tau-NAF. Solinas partial reduction is the next step.")


if __name__ == "__main__":
    main()
