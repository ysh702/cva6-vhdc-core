#!/usr/bin/env python3
"""Generate replayable VV30 vectors from a fresh 256-bit CSPRNG seed."""

from __future__ import annotations

import argparse
import hashlib
import json
import secrets
import sys
from pathlib import Path

import k233_reference as k233


K233_N = int(
    "8000000000000000000000000000069D5BB915BCD46EFB1AD5F173ABDF", 16
)
GF_BITS = 233
SEED_BYTES = 32
SUITE_COUNTS = {
    "quick": {"scalars": 1, "fields": 16, "hdc": 4},
    "stage1": {"scalars": 4, "fields": 4096, "hdc": 64},
    "stage2": {"scalars": 4, "fields": 4096, "hdc": 64},
    "stage3": {"scalars": 4, "fields": 4096, "hdc": 64},
    "full": {"scalars": 16, "fields": 4096, "hdc": 256},
    "stress": {"scalars": 64, "fields": 8192, "hdc": 512},
    "replay": {"scalars": 16, "fields": 4096, "hdc": 256},
}


class Sha256CounterStream:
    """Domain-separated deterministic byte stream."""

    def __init__(self, seed: bytes, domain: str) -> None:
        self.seed = seed
        self.domain = domain.encode("ascii")
        self.counter = 0
        self.buffer = bytearray()

    def read(self, length: int) -> bytes:
        while len(self.buffer) < length:
            material = (
                self.seed
                + len(self.domain).to_bytes(2, "big")
                + self.domain
                + self.counter.to_bytes(8, "big")
            )
            self.buffer.extend(hashlib.sha256(material).digest())
            self.counter += 1
        result = bytes(self.buffer[:length])
        del self.buffer[:length]
        return result

    def bits(self, width: int) -> int:
        byte_count = (width + 7) // 8
        value = int.from_bytes(self.read(byte_count), "big")
        return value & ((1 << width) - 1)


def parse_seed(value: str | None) -> tuple[bytes, str]:
    if value is None:
        return secrets.token_bytes(SEED_BYTES), "os_csprng"
    normalized = value[2:] if value.lower().startswith("0x") else value
    if len(normalized) != SEED_BYTES * 2:
        raise ValueError("--seed must contain exactly 64 hexadecimal digits")
    try:
        return bytes.fromhex(normalized), "explicit_replay"
    except ValueError as exc:
        raise ValueError("--seed is not valid hexadecimal") from exc


def sample_unique_scalars(
    seed: bytes, count: int, domain: str = "sect233k1-scalars-v1"
) -> list[int]:
    stream = Sha256CounterStream(seed, domain)
    scalars: list[int] = []
    seen: set[int] = set()
    sample_width = K233_N.bit_length()
    while len(scalars) < count:
        candidate = stream.bits(sample_width)
        if candidate == 0 or candidate >= K233_N or candidate in seen:
            continue
        if candidate >> 233:
            raise AssertionError("generated scalar violates the 233-bit VRF contract")
        seen.add(candidate)
        scalars.append(candidate)
    return scalars


def sample_values(seed: bytes, domain: str, count: int, width: int) -> list[int]:
    stream = Sha256CounterStream(seed, domain)
    return [stream.bits(width) for _ in range(count)]


def gf233_reduce(polynomial: int) -> int:
    for degree in range(polynomial.bit_length() - 1, 232, -1):
        if (polynomial >> degree) & 1:
            polynomial ^= 1 << degree
            polynomial ^= 1 << (degree - 233)
            polynomial ^= 1 << (degree - 159)
    return polynomial & ((1 << 233) - 1)


def gf233_square(operand: int) -> int:
    polynomial = 0
    for bit_idx in range(GF_BITS):
        polynomial |= ((operand >> bit_idx) & 1) << (2 * bit_idx)
    return gf233_reduce(polynomial)


def gf233_mul(operand_a: int, operand_b: int) -> int:
    polynomial = 0
    for bit_idx in range(GF_BITS):
        if (operand_b >> bit_idx) & 1:
            polynomial ^= operand_a << bit_idx
    return gf233_reduce(polynomial)


def gf233_inv(operand: int) -> int:
    if operand == 0:
        raise ValueError("GF(2^233) inverse is undefined for zero")
    modulus = (1 << 233) | (1 << 74) | 1
    u = operand
    v = modulus
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
    return gf233_reduce(g1)


def write_mem(path: Path, values: list[int], width_bits: int) -> None:
    hex_width = (width_bits + 3) // 4
    text = "".join(f"{value:0{hex_width}x}\n" for value in values)
    path.write_text(text, encoding="ascii", newline="\n")


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def build_bundle(out_dir: Path, suite: str, seed: bytes, seed_source: str) -> dict:
    counts = SUITE_COUNTS[suite]
    out_dir.mkdir(parents=True, exist_ok=True)

    scalars = sample_unique_scalars(seed, counts["scalars"])
    point_multipliers = sample_unique_scalars(
        seed, counts["scalars"], "sect233k1-point-multipliers-v1"
    )
    points = [k233.scalar_mul(value) for value in point_multipliers]
    expected_points = [
        k233.scalar_mul((scalar * point_multiplier) % K233_N)
        for scalar, point_multiplier in zip(scalars, point_multipliers)
    ]
    if any(point is None for point in points + expected_points):
        raise AssertionError("nonzero scalar unexpectedly generated infinity")
    if any(not k233.is_on_curve(point) for point in points + expected_points):
        raise AssertionError("generated PMUL point is not on sect233k1")
    gf_a = sample_values(seed, "gf233-a-v1", counts["fields"], GF_BITS)
    gf_b = sample_values(seed, "gf233-b-v1", counts["fields"], GF_BITS)
    gf_acc = sample_values(seed, "gf233-acc-v1", counts["fields"], GF_BITS)
    gf_mac_expected = [
        accumulator ^ gf233_mul(operand_a, operand_b)
        for operand_a, operand_b, accumulator in zip(gf_a, gf_b, gf_acc)
    ]
    square_inputs = sample_values(
        seed, "gf233-square-v1", counts["fields"], GF_BITS
    )
    square_expected = [gf233_square(value) for value in square_inputs]
    inv_inputs = sample_values(
        seed, "gf233-inverse-v1", counts["scalars"], GF_BITS
    )
    inv_inputs = [value if value != 0 else 1 for value in inv_inputs]
    inv_expected = [gf233_inv(value) for value in inv_inputs]
    if any(gf233_mul(value, inverse) != 1
           for value, inverse in zip(inv_inputs, inv_expected)):
        raise AssertionError("GF(2^233) inverse self-check failed")
    hdc_inputs = sample_values(seed, "hdc1024-v1", counts["hdc"], 1024)

    vector_sets = {
        "master_seed.mem": ([int.from_bytes(seed, "big")], 256),
        "scalar_count.mem": ([counts["scalars"]], 32),
        "pmul_scalars.mem": (scalars, 256),
        "pmul_point_multipliers.mem": (point_multipliers, 256),
        "pmul_point_x.mem": ([point.x for point in points], 256),
        "pmul_point_y.mem": ([point.y for point in points], 256),
        "pmul_expected_x.mem": (
            [point.x for point in expected_points],
            256,
        ),
        "pmul_expected_y.mem": (
            [point.y for point in expected_points],
            256,
        ),
        "gf_a_inputs.mem": (gf_a, 256),
        "gf_b_inputs.mem": (gf_b, 256),
        "gf_acc_inputs.mem": (gf_acc, 256),
        "gf_mac_expected.mem": (gf_mac_expected, 256),
        "square_inputs.mem": (square_inputs, 256),
        "square_expected.mem": (square_expected, 256),
        "inv_count.mem": ([counts["scalars"]], 32),
        "inv_inputs.mem": (inv_inputs, 256),
        "inv_expected.mem": (inv_expected, 256),
        "hdc_inputs.mem": (hdc_inputs, 1024),
    }
    for name, (values, width) in vector_sets.items():
        write_mem(out_dir / name, values, width)

    file_hashes = {
        name: {
            "sha256": sha256_file(out_dir / name),
            "count": len(values),
            "width_bits": width,
        }
        for name, (values, width) in vector_sets.items()
    }
    scalar_records = [
        {
            "hex": f"{value:064x}",
            "hamming_weight": value.bit_count(),
        }
        for value in scalars
    ]
    if len({record["hex"] for record in scalar_records}) != len(scalar_records):
        raise AssertionError("scalar uniqueness check failed")
    if any(value <= 0 or value >= K233_N for value in scalars):
        raise AssertionError("scalar range check failed")
    if any(value >> 233 for value in scalars):
        raise AssertionError("scalar high-23-bit check failed")

    manifest = {
        "schema": "hdec-vv30-vectors-v1",
        "suite": suite,
        "seed_hex": seed.hex(),
        "seed_source": seed_source,
        "expander": "SHA-256(seed || domain_length || domain || counter_be64)",
        "sect233k1_order_hex": f"{K233_N:064x}",
        "counts": counts,
        "scalars": scalar_records,
        "checks": {
            "scalar_range": True,
            "scalar_unique": True,
            "scalar_high_23_zero": True,
            "pmul_points_on_curve": True,
            "pmul_expected_points_on_curve": True,
        },
        "files": file_hashes,
        "system_pmul_random_k": {
            "status": "READY",
            "point_generation": "P=t*G with unique random 1<=t<n",
            "expected_generation": "K*P=(K*t mod n)*G",
        },
    }
    manifest_path = out_dir / "vector_manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    (out_dir / "vector_manifest.sha256").write_text(
        f"{sha256_file(manifest_path)}  vector_manifest.json\n",
        encoding="ascii",
        newline="\n",
    )
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--suite", choices=sorted(SUITE_COUNTS), default="quick")
    parser.add_argument("--seed", help="exactly 64 hexadecimal digits")
    args = parser.parse_args()
    try:
        seed, seed_source = parse_seed(args.seed)
        manifest = build_bundle(args.out_dir.resolve(), args.suite, seed, seed_source)
    except (OSError, ValueError, AssertionError) as exc:
        print(f"[VV30:vector_generator] FAIL {exc}", file=sys.stderr)
        return 1
    print(
        "[VV30:vector_generator] PASS "
        f"suite={args.suite} seed={manifest['seed_hex']} "
        f"source={manifest['seed_source']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
