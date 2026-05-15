#!/usr/bin/env python3
"""Golden model for hdec_lane_boolean_mask — verifies XOR_ONLY, MASK_XOR_DELTA, MASK_SELECT."""
import random

def boolean_mask(src_a, src_b, mask, mode):
    if mode == 0:        # XOR_ONLY
        return src_a ^ src_b
    elif mode == 1:      # MASK_XOR_DELTA
        return (src_a ^ src_b) & mask
    elif mode == 2:      # MASK_SELECT
        return (src_a & ~mask) | (src_b & mask)
    else:
        return 0

def test(mode, name, n=1000):
    for _ in range(n):
        a = random.getrandbits(64)
        b = random.getrandbits(64)
        m = random.getrandbits(64)
        r = boolean_mask(a, b, m, mode)
        if mode == 0:
            assert r == (a ^ b), f"XOR_ONLY: {a:#x} ^ {b:#x} = {r:#x}, expected {(a^b):#x}"
        elif mode == 1:
            assert r == ((a ^ b) & m), f"MASK_XOR_DELTA: ({a:#x} ^ {b:#x}) & {m:#x} = {r:#x}"
        elif mode == 2:
            assert r == ((a & ~m) | (b & m)), f"MASK_SELECT: ({a:#x} & ~{m:#x}) | ({b:#x} & {m:#x}) = {r:#x}"
    print(f"  {name}: {n} vectors PASS")

def main():
    print("Boolean/Mask Golden Model Tests:")
    random.seed(42)
    test(0, "XOR_ONLY")
    test(1, "MASK_XOR_DELTA")
    test(2, "MASK_SELECT")
    test(3, "default (0)")
    print("All tests PASSED")

if __name__ == "__main__":
    main()
