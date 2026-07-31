#!/usr/bin/env python3
"""Generate fresh, replayable VV31 ECC and HDC scheduling vectors."""

from __future__ import annotations

import argparse
import hashlib
import json
import secrets
import sys
from pathlib import Path

import k233_reference as k233


K233_N = k233.GROUP_ORDER
GF_BITS = 233
HV_BITS = 1024
SEED_BYTES = 32
TRAINING_SAMPLES = 4
NOISE_WEIGHT = 32

PROFILE_COUNTS = {
    "baseline_gap": {"scalars": 1, "fields": 64, "episodes": 2},
    "quick": {"scalars": 1, "fields": 64, "episodes": 2},
    # Per-candidate ECC gate: one fresh legal random K.  Multi-K evidence is
    # intentionally deferred to the full profile used at final/freeze.
    "stage": {"scalars": 1, "fields": 4096, "episodes": 8},
    "full": {"scalars": 16, "fields": 4096, "episodes": 32},
    "stress": {"scalars": 64, "fields": 8192, "episodes": 128},
}
SUITES = tuple(PROFILE_COUNTS) + ("replay",)


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
        return secrets.token_bytes(SEED_BYTES), "windows_os_csprng"
    normalized = value[2:] if value.lower().startswith("0x") else value
    if len(normalized) != SEED_BYTES * 2:
        raise ValueError("--seed must contain exactly 64 hexadecimal digits")
    try:
        return bytes.fromhex(normalized), "explicit_replay"
    except ValueError as exc:
        raise ValueError("--seed is not valid hexadecimal") from exc


def sample_unique_scalars(
    seed: bytes,
    count: int,
    domain: str,
    forbidden: frozenset[int] = frozenset(),
) -> list[int]:
    stream = Sha256CounterStream(seed, domain)
    scalars: list[int] = []
    seen: set[int] = set()
    sample_width = K233_N.bit_length()
    while len(scalars) < count:
        candidate = stream.bits(sample_width)
        if (
            candidate == 0
            or candidate >= K233_N
            or candidate in forbidden
            or candidate in seen
        ):
            continue
        if candidate >> 233:
            raise AssertionError("generated scalar violates 233-bit VRF contract")
        seen.add(candidate)
        scalars.append(candidate)
    return scalars


def sample_values(seed: bytes, domain: str, count: int, width: int) -> list[int]:
    stream = Sha256CounterStream(seed, domain)
    return [stream.bits(width) for _ in range(count)]


def rotate_right(value: int, amount: int, width: int = HV_BITS) -> int:
    amount %= width
    mask = (1 << width) - 1
    if amount == 0:
        return value & mask
    return ((value >> amount) | (value << (width - amount))) & mask


def fixed_weight_mask(stream: Sha256CounterStream, weight: int) -> int:
    positions: set[int] = set()
    while len(positions) < weight:
        positions.add(stream.bits(10))
    mask = 0
    for position in positions:
        mask |= 1 << position
    return mask


def directed_scalars() -> list[int]:
    alternating = sum(1 << bit for bit in range(0, GF_BITS, 2)) % K233_N
    if alternating == 0:
        alternating = 5
    return [
        0,
        1,
        2,
        3,
        K233_N - 1,
        1 << 232,
        alternating,
        K233_N - 2,
    ]


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


def build_hdc_vectors(seed: bytes, episodes: int) -> dict[str, list[int]]:
    vector_count = episodes * TRAINING_SAMPLES
    samples = sample_values(seed, "vv31-hdc-train-v1", vector_count, HV_BITS)
    roles = sample_values(seed, "vv31-hdc-role-v1", vector_count, HV_BITS)
    rotation_stream = Sha256CounterStream(seed, "vv31-hdc-rot-v1")
    rotations = [rotation_stream.bits(8) * 4 for _ in range(vector_count)]
    permuted_roles = [
        rotate_right(role, rotation)
        for role, rotation in zip(roles, rotations)
    ]
    bound = [
        sample ^ permuted
        for sample, permuted in zip(samples, permuted_roles)
    ]

    source_stream = Sha256CounterStream(seed, "vv31-hdc-query-source-v1")
    noise_stream = Sha256CounterStream(seed, "vv31-hdc-query-noise-v1")
    query_sources: list[int] = []
    noise_masks: list[int] = []
    prototypes: list[int] = []
    queries: list[int] = []
    hsim_expected: list[int] = []
    hmatch_expected: list[int] = []
    for episode in range(episodes):
        start = episode * TRAINING_SAMPLES
        episode_bound = bound[start : start + TRAINING_SAMPLES]
        prototype = 0
        for encoded_sample in episode_bound:
            prototype |= encoded_sample
        source = source_stream.bits(2)
        noise = fixed_weight_mask(noise_stream, NOISE_WEIGHT)
        query = episode_bound[source] ^ noise
        score = (query & prototype).bit_count()

        query_sources.append(source)
        noise_masks.append(noise)
        prototypes.append(prototype)
        queries.append(query)
        hsim_expected.append(score)
        hmatch_expected.append(score)  # class index is zero for one candidate

    if any(rotation & 3 for rotation in rotations):
        raise AssertionError("HPERM rotation is not 4-bit aligned")
    if any(rotation >= HV_BITS for rotation in rotations):
        raise AssertionError("HPERM rotation is outside 0..1020")
    if any(mask.bit_count() != NOISE_WEIGHT for mask in noise_masks):
        raise AssertionError("query noise weight is not fixed")

    return {
        "hdc_train_samples.mem": samples,
        "hdc_role_vectors.mem": roles,
        "hdc_role_rotations.mem": rotations,
        "hdc_permuted_roles_expected.mem": permuted_roles,
        "hdc_bound_expected.mem": bound,
        "hdc_query_source.mem": query_sources,
        "hdc_noise_masks.mem": noise_masks,
        "hdc_prototypes_expected.mem": prototypes,
        "hdc_query_vectors.mem": queries,
        "hdc_hsim_expected.mem": hsim_expected,
        "hdc_hmatch_expected.mem": hmatch_expected,
    }


def build_bundle(
    out_dir: Path,
    suite: str,
    profile: str,
    seed: bytes,
    seed_source: str,
) -> dict:
    counts = PROFILE_COUNTS[profile]
    out_dir.mkdir(parents=True, exist_ok=True)

    # K=3 remains a directed boundary vector only.  It is explicitly excluded
    # from the primary randomized PMUL evidence set.
    scalars = sample_unique_scalars(
        seed,
        counts["scalars"],
        "vv31-sect233k1-scalars-v1",
        frozenset({3}),
    )
    point_multipliers = sample_unique_scalars(
        seed,
        counts["scalars"],
        "vv31-sect233k1-point-multipliers-v1",
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

    gf_a = sample_values(seed, "vv31-gf233-a-v1", counts["fields"], GF_BITS)
    gf_b = sample_values(seed, "vv31-gf233-b-v1", counts["fields"], GF_BITS)
    square_inputs = sample_values(
        seed, "vv31-gf233-square-v1", counts["fields"], GF_BITS
    )
    hdc = build_hdc_vectors(seed, counts["episodes"])

    vector_sets: dict[str, tuple[list[int], int]] = {
        "master_seed.mem": ([int.from_bytes(seed, "big")], 256),
        "scalar_count.mem": ([counts["scalars"]], 32),
        "pmul_scalars.mem": (scalars, 256),
        "pmul_directed_scalars.mem": (directed_scalars(), 256),
        "pmul_point_multipliers.mem": (point_multipliers, 256),
        "pmul_point_x.mem": ([point.x for point in points], 256),
        "pmul_point_y.mem": ([point.y for point in points], 256),
        "pmul_expected_x.mem": ([point.x for point in expected_points], 256),
        "pmul_expected_y.mem": ([point.y for point in expected_points], 256),
        "gf_a_inputs.mem": (gf_a, 256),
        "gf_b_inputs.mem": (gf_b, 256),
        "gf_mul_expected.mem": (
            [k233.gf_mul(a, b) for a, b in zip(gf_a, gf_b)],
            256,
        ),
        "square_inputs.mem": (square_inputs, 256),
        "square_expected.mem": (
            [k233.gf_square(value) for value in square_inputs],
            256,
        ),
        "hdc_episode_count.mem": ([counts["episodes"]], 32),
    }
    hdc_widths = {
        "hdc_train_samples.mem": 1024,
        "hdc_role_vectors.mem": 1024,
        "hdc_role_rotations.mem": 32,
        "hdc_permuted_roles_expected.mem": 1024,
        "hdc_bound_expected.mem": 1024,
        "hdc_query_source.mem": 32,
        "hdc_noise_masks.mem": 1024,
        "hdc_prototypes_expected.mem": 1024,
        "hdc_query_vectors.mem": 1024,
        "hdc_hsim_expected.mem": 32,
        "hdc_hmatch_expected.mem": 64,
    }
    for name, values in hdc.items():
        vector_sets[name] = (values, hdc_widths[name])

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
        raise AssertionError("random scalar uniqueness check failed")
    if any(value <= 0 or value >= K233_N for value in scalars):
        raise AssertionError("random scalar range check failed")
    if any(value >> 233 for value in scalars):
        raise AssertionError("random scalar high-23-bit check failed")
    if any(value == 3 for value in scalars):
        raise AssertionError("K=3 leaked into primary randomized validation")

    manifest = {
        "schema": "hdec-vv31-vectors-v1",
        "suite": suite,
        "profile": profile,
        "seed_hex": seed.hex(),
        "seed_source": seed_source,
        "expander": "SHA-256(seed || domain_length || domain || counter_be64)",
        "sect233k1_order_hex": f"{K233_N:064x}",
        "counts": {
            **counts,
            "training_samples_per_episode": TRAINING_SAMPLES,
            "hdc_noise_weight": NOISE_WEIGHT,
        },
        "scalars": scalar_records,
        "checks": {
            "scalar_range": True,
            "scalar_unique": True,
            "scalar_high_23_zero": True,
            "primary_random_k_excludes_3": True,
            "pmul_points_on_curve": True,
            "pmul_expected_points_on_curve": True,
            "hperm_rotations_are_4_bit_aligned": True,
            "hdc_query_noise_has_fixed_weight": True,
        },
        "files": file_hashes,
        "hdc_episode_contract": {
            "training_samples": TRAINING_SAMPLES,
            "binding": "sample XOR ROTR1024(role, rotation)",
            "clip_semantics": "bitwise OR of four encoded samples",
            "similarity_semantics": "popcount(query AND prototype)",
            "match_candidates": 1,
        },
        "system_pmul_random_k": {
            "status": "READY",
            "point_generation": "P=t*G with random unique 1<=t<n",
            "expected_generation": "K*P=(K*t mod n)*G",
            "primary_k3_policy": "excluded; present only in directed vectors",
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
    parser = argparse.ArgumentParser(
        description=(
            "Generate VV31 vectors. Omit --seed for a fresh 256-bit OS CSPRNG "
            "seed; pass it only for replay."
        )
    )
    parser.add_argument("--out-dir", type=Path, required=True)
    parser.add_argument("--suite", choices=SUITES, default="quick")
    parser.add_argument(
        "--replay-profile",
        choices=tuple(PROFILE_COUNTS),
        default="full",
        help="vector cardinality to reproduce when --suite replay is used",
    )
    parser.add_argument("--seed", help="exactly 64 hexadecimal digits")
    args = parser.parse_args()

    if args.suite == "replay" and args.seed is None:
        parser.error("--suite replay requires --seed")
    profile = args.replay_profile if args.suite == "replay" else args.suite
    try:
        seed, seed_source = parse_seed(args.seed)
        manifest = build_bundle(
            args.out_dir.resolve(),
            args.suite,
            profile,
            seed,
            seed_source,
        )
    except (OSError, ValueError, AssertionError, ZeroDivisionError) as exc:
        print(f"[VV31:vector_generator] FAIL {exc}", file=sys.stderr)
        return 1
    print(
        "[VV31:vector_generator] PASS "
        f"suite={args.suite} profile={profile} "
        f"seed={manifest['seed_hex']} source={manifest['seed_source']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
