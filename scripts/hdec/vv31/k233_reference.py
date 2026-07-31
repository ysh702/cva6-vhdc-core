#!/usr/bin/env python3
"""Independent SEC 2 sect233k1 mathematical reference for VV31 vectors.

The model intentionally contains no HDEC RTL lookup table, scheduling state,
folding mask, or datapath helper.  It is therefore suitable as an independent
source of PMUL input and expected-output vectors.
"""

from __future__ import annotations

from dataclasses import dataclass


FIELD_BITS = 233
FIELD_MASK = (1 << FIELD_BITS) - 1
FIELD_POLYNOMIAL = (1 << 233) | (1 << 74) | 1
CURVE_A = 0
CURVE_B = 1
GROUP_ORDER = int(
    "8000000000000000000000000000069D5BB915BCD46EFB1AD5F173ABDF", 16
)
BASE_X = int(
    "017232BA853A7E731AF129F22FF4149563A419C26BF50A4C9D6EEFAD6126", 16
)
BASE_Y = int(
    "01DB537DECE819B7F70F555A67C427A8CD9BF18AEB9B56E0C11056FAE6A3", 16
)


def gf_reduce(value: int) -> int:
    """Reduce a polynomial modulo x^233 + x^74 + 1."""
    if value < 0:
        raise ValueError("GF(2) polynomials must be non-negative")
    while value.bit_length() > FIELD_BITS:
        shift = value.bit_length() - 1 - FIELD_BITS
        value ^= FIELD_POLYNOMIAL << shift
    return value


def gf_add(left: int, right: int) -> int:
    return (left ^ right) & FIELD_MASK


def gf_mul(left: int, right: int) -> int:
    left &= FIELD_MASK
    right &= FIELD_MASK
    product = 0
    while right:
        if right & 1:
            product ^= left
        right >>= 1
        left <<= 1
    return gf_reduce(product)


def gf_square(value: int) -> int:
    value &= FIELD_MASK
    expanded = 0
    bit_index = 0
    while value:
        if value & 1:
            expanded |= 1 << (2 * bit_index)
        value >>= 1
        bit_index += 1
    return gf_reduce(expanded)


def gf_inv(value: int) -> int:
    value &= FIELD_MASK
    if value == 0:
        raise ZeroDivisionError("zero has no multiplicative inverse")
    u = value
    v = FIELD_POLYNOMIAL
    g_u = 1
    g_v = 0
    while u != 1:
        degree_delta = u.bit_length() - v.bit_length()
        if degree_delta < 0:
            u, v = v, u
            g_u, g_v = g_v, g_u
            degree_delta = -degree_delta
        u ^= v << degree_delta
        g_u ^= g_v << degree_delta
    return gf_reduce(g_u)


def gf_div(numerator: int, denominator: int) -> int:
    return gf_mul(numerator, gf_inv(denominator))


@dataclass(frozen=True, slots=True)
class AffinePoint:
    x: int
    y: int

    def normalized(self) -> "AffinePoint":
        return AffinePoint(self.x & FIELD_MASK, self.y & FIELD_MASK)


INFINITY: AffinePoint | None = None
BASE_POINT = AffinePoint(BASE_X, BASE_Y)


def is_on_curve(point: AffinePoint | None) -> bool:
    if point is INFINITY:
        return True
    point = point.normalized()
    left = gf_add(gf_square(point.y), gf_mul(point.x, point.y))
    x_squared = gf_square(point.x)
    right = gf_add(
        gf_add(gf_mul(x_squared, point.x), gf_mul(CURVE_A, x_squared)),
        CURVE_B,
    )
    return left == right


def point_neg(point: AffinePoint | None) -> AffinePoint | None:
    if point is INFINITY:
        return INFINITY
    return AffinePoint(point.x, gf_add(point.x, point.y))


def point_double(point: AffinePoint | None) -> AffinePoint | None:
    if point is INFINITY or point.x == 0:
        return INFINITY
    slope = gf_add(point.x, gf_div(point.y, point.x))
    x_out = gf_add(gf_add(gf_square(slope), slope), CURVE_A)
    y_out = gf_add(gf_square(point.x), gf_mul(gf_add(slope, 1), x_out))
    return AffinePoint(x_out, y_out)


def point_add(
    left: AffinePoint | None, right: AffinePoint | None
) -> AffinePoint | None:
    if left is INFINITY:
        return right
    if right is INFINITY:
        return left
    if left.x == right.x:
        if gf_add(left.y, right.y) == left.x:
            return INFINITY
        if left.y == right.y:
            return point_double(left)
        raise AssertionError("invalid equal-x point pair on a binary curve")
    slope = gf_div(gf_add(left.y, right.y), gf_add(left.x, right.x))
    x_out = gf_add(
        gf_add(gf_add(gf_square(slope), slope), left.x),
        gf_add(right.x, CURVE_A),
    )
    y_out = gf_add(
        gf_add(gf_mul(slope, gf_add(left.x, x_out)), x_out),
        left.y,
    )
    return AffinePoint(x_out, y_out)


def scalar_mul(
    scalar: int, point: AffinePoint | None = BASE_POINT
) -> AffinePoint | None:
    """Variable-time reference multiplication, used only offline."""
    if scalar < 0:
        return scalar_mul(-scalar, point_neg(point))
    result = INFINITY
    addend = point
    while scalar:
        if scalar & 1:
            result = point_add(result, addend)
        scalar >>= 1
        if scalar:
            addend = point_double(addend)
    return result


def self_test() -> None:
    expected_3g = AffinePoint(
        int(
            "004656E0AABBE341407715CA4A7FAC287B41BAA1F789C29BFA27E53A7A46",
            16,
        ),
        int(
            "00F79A7245FBA513DF787A64C618E97EBCC078638EBAAA562E9862BC00CE",
            16,
        ),
    )
    if not is_on_curve(BASE_POINT):
        raise AssertionError("sect233k1 base point is not on the modeled curve")
    if scalar_mul(0) is not INFINITY:
        raise AssertionError("0*G must be infinity")
    if scalar_mul(1) != BASE_POINT:
        raise AssertionError("1*G must equal G")
    if scalar_mul(3) != expected_3g:
        raise AssertionError("reference does not reproduce the known 3G vector")
    if scalar_mul(GROUP_ORDER) is not INFINITY:
        raise AssertionError("n*G must be infinity")


if __name__ == "__main__":
    self_test()
    print("[VV31:k233_reference] PASS")
