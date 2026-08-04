#!/usr/bin/env python3
"""Integrate marked board power traces and report gross/incremental energy."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from collections import defaultdict
from pathlib import Path


def load_samples(path: Path, marker_threshold: float | None) -> list[tuple[float, float]]:
    grouped: dict[float, list[float]] = defaultdict(list)
    with path.open(newline="", encoding="utf-8-sig") as handle:
        rows = csv.DictReader(handle)
        required = {"timestamp_s"}
        if not required.issubset(rows.fieldnames or []):
            raise ValueError(f"{path}: timestamp_s is required")
        for row in rows:
            if marker_threshold is not None:
                if "marker" not in row or not row["marker"].strip():
                    raise ValueError(f"{path}: marker column required")
                if float(row["marker"]) < marker_threshold:
                    continue
            timestamp = float(row["timestamp_s"])
            if row.get("power_w", "").strip():
                power = float(row["power_w"])
            elif row.get("voltage_v", "").strip() and row.get("current_a", "").strip():
                power = float(row["voltage_v"]) * float(row["current_a"])
            else:
                raise ValueError(f"{path}: need power_w or voltage_v and current_a")
            grouped[timestamp].append(power)
    samples = sorted((t, sum(values)) for t, values in grouped.items())
    if len(samples) < 2:
        raise ValueError(f"{path}: fewer than two selected timestamp samples")
    return samples


def integrate(samples: list[tuple[float, float]]) -> tuple[float, float, float]:
    energy = 0.0
    for (t0, p0), (t1, p1) in zip(samples, samples[1:]):
        if t1 <= t0:
            raise ValueError("timestamps must be strictly increasing")
        energy += 0.5 * (p0 + p1) * (t1 - t0)
    duration = samples[-1][0] - samples[0][0]
    return duration, energy, energy / duration


def file_sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("trace", type=Path)
    parser.add_argument("--scenario", choices=("SERIAL", "INTERLEAVED"), required=True)
    parser.add_argument("--marker-threshold", type=float, default=0.5)
    idle = parser.add_mutually_exclusive_group()
    idle.add_argument("--idle-power-w", type=float)
    idle.add_argument("--idle-trace", type=Path)
    parser.add_argument("--repeat-count", type=int, default=1)
    parser.add_argument("--rdcycle-delta", type=int)
    parser.add_argument("--rdcycle-frequency-hz", type=float)
    parser.add_argument("--pmul-wait-cycles", type=int, default=146908)
    parser.add_argument("--cpu-hdec-clock-relation", default="same_frequency_ungated")
    parser.add_argument("--rail-scope", required=True)
    parser.add_argument("--bitstream-sha256")
    parser.add_argument("--firmware-sha256")
    parser.add_argument("--vector-bundle-sha256")
    parser.add_argument("--instrument-model")
    parser.add_argument("--sample-rate-hz", type=float)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.repeat_count < 1:
        parser.error("--repeat-count must be positive")

    samples = load_samples(args.trace, args.marker_threshold)
    duration, gross_energy, gross_average = integrate(samples)
    idle_power = args.idle_power_w
    if args.idle_trace:
        _, _, idle_power = integrate(load_samples(args.idle_trace, None))
    idle_energy = None if idle_power is None else idle_power * duration
    incremental = None if idle_energy is None else gross_energy - idle_energy
    result = {
        "schema": "vv35-board-energy-v1",
        "qualification": "board-level measured power for the named rails",
        "scenario": args.scenario,
        "trace": str(args.trace),
        "trace_sha256": file_sha(args.trace),
        "idle_trace_sha256": None if args.idle_trace is None else file_sha(args.idle_trace),
        "bitstream_sha256": args.bitstream_sha256,
        "firmware_sha256": args.firmware_sha256,
        "vector_bundle_sha256": args.vector_bundle_sha256,
        "rail_scope": args.rail_scope,
        "instrument_model": args.instrument_model,
        "sample_rate_hz": args.sample_rate_hz,
        "repeat_count": args.repeat_count,
        "sample_count": len(samples),
        "duration_s": duration,
        "gross_average_power_w": gross_average,
        "gross_energy_mj": gross_energy * 1e3,
        "gross_energy_per_batch_mj": gross_energy * 1e3 / args.repeat_count,
        "idle_power_w": idle_power,
        "incremental_average_power_w": None if idle_power is None
        else gross_average - idle_power,
        "idle_energy_mj": None if idle_energy is None else idle_energy * 1e3,
        "incremental_energy_mj": None if incremental is None else incremental * 1e3,
        "incremental_energy_per_batch_mj": None if incremental is None
        else incremental * 1e3 / args.repeat_count,
        "rdcycle_delta": args.rdcycle_delta,
        "rdcycle_frequency_hz": args.rdcycle_frequency_hz,
        "pmul_wait_cycles": args.pmul_wait_cycles,
        "cpu_hdec_clock_relation": args.cpu_hdec_clock_relation,
        "rdcycle_time_s": None if args.rdcycle_delta is None or not args.rdcycle_frequency_hz
        else args.rdcycle_delta / args.rdcycle_frequency_hz,
    }
    rendered = json.dumps(result, indent=2, sort_keys=True)
    if args.output:
        args.output.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
