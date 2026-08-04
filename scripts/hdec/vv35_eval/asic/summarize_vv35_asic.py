#!/usr/bin/env python3
"""Summarize paired VV35 DC/Power Compiler reports without inventing data."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


NUMBER = r"([-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)"


def first(text: str, patterns: list[str]) -> float | None:
    for pattern in patterns:
        match = re.search(pattern, text, re.MULTILINE | re.IGNORECASE)
        if match:
            return float(match.group(1))
    return None


def power_to_mw(value: float, unit: str) -> float:
    factors = {"w": 1e3, "mw": 1.0, "uw": 1e-3, "nw": 1e-6}
    try:
        return value * factors[unit.lower()]
    except KeyError as exc:
        raise ValueError(f"unsupported power unit {unit}") from exc


def power_value(text: str, label: str) -> float | None:
    match = re.search(
        rf"{re.escape(label)}\s*=\s*{NUMBER}\s*(W|mW|uW|nW)",
        text,
        re.MULTILINE | re.IGNORECASE,
    )
    return None if not match else power_to_mw(float(match.group(1)), match.group(2))


def parse_power(path: Path) -> dict[str, float | None]:
    text = path.read_text(errors="replace")
    return {
        "internal_power_mw": power_value(text, "Cell Internal Power"),
        "switching_power_mw": power_value(text, "Net Switching Power"),
        "leakage_power_mw": power_value(text, "Cell Leakage Power"),
        "total_power_mw": power_value(text, "Total Power"),
    }


def parse_manifest(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        if "=" in raw:
            key, value = raw.split("=", 1)
            result[key.strip()] = value.strip()
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--serial", type=Path, required=True)
    parser.add_argument("--interleaved", type=Path, required=True)
    parser.add_argument("--serial-manifest", type=Path, required=True)
    parser.add_argument("--interleaved-manifest", type=Path, required=True)
    parser.add_argument("--frequency-hz", type=float, default=200_000_000.0)
    parser.add_argument("--serial-cycles", type=int, default=337_853)
    parser.add_argument("--interleaved-cycles", type=int, default=200_144)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    serial_manifest = parse_manifest(args.serial_manifest)
    interleaved_manifest = parse_manifest(args.interleaved_manifest)
    for key in ("ddc_sha256", "contract_sha256", "vector_manifest_sha256", "vrf_mode"):
        if not serial_manifest.get(key) or not interleaved_manifest.get(key):
            raise ValueError(f"paired manifests are missing {key}")
        if serial_manifest.get(key) != interleaved_manifest.get(key):
            raise ValueError(f"paired manifests disagree on {key}")
    if serial_manifest.get("scenario") != "SERIAL":
        raise ValueError("serial manifest scenario is not SERIAL")
    if interleaved_manifest.get("scenario") != "INTERLEAVED":
        raise ValueError("interleaved manifest scenario is not INTERLEAVED")
    manifests = {"serial": serial_manifest, "interleaved": interleaved_manifest}

    serial = parse_power(args.serial)
    interleaved = parse_power(args.interleaved)
    serial_time = args.serial_cycles / args.frequency_hz
    interleaved_time = args.interleaved_cycles / args.frequency_hz
    serial_total = serial["total_power_mw"]
    interleaved_total = interleaved["total_power_mw"]
    serial_energy = None if serial_total is None else serial_total * serial_time
    interleaved_energy = (
        None if interleaved_total is None else interleaved_total * interleaved_time
    )
    result = {
        "qualification": "synthesis-level pre-layout ASIC power estimate; SAIF coverage review required",
        "serial": {**serial, "cycles": args.serial_cycles, "time_s": serial_time,
                   "total_energy_mj": serial_energy},
        "interleaved": {**interleaved, "cycles": args.interleaved_cycles,
                        "time_s": interleaved_time,
                        "total_energy_mj": interleaved_energy},
        "cycle_reduction": 1.0 - args.interleaved_cycles / args.serial_cycles,
        "speedup": args.serial_cycles / args.interleaved_cycles,
        "energy_reduction": None if not serial_energy or interleaved_energy is None
        else 1.0 - interleaved_energy / serial_energy,
        "paired_manifest_checks": manifests,
    }
    rendered = json.dumps(result, indent=2, sort_keys=True)
    if args.output:
        args.output.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
