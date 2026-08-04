#!/usr/bin/env python3
"""Compare paired SERIAL and INTERLEAVED board energy summaries."""

from __future__ import annotations

import argparse
import json
from pathlib import Path


def reduction(serial: float | None, interleaved: float | None) -> float | None:
    if serial is None or interleaved is None or serial == 0:
        return None
    return (serial - interleaved) / serial


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("serial", type=Path)
    parser.add_argument("interleaved", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    serial = json.loads(args.serial.read_text())
    interleaved = json.loads(args.interleaved.read_text())
    if serial.get("scenario") != "SERIAL" or interleaved.get("scenario") != "INTERLEAVED":
        raise ValueError("input scenarios are not SERIAL and INTERLEAVED")
    if serial.get("repeat_count") != interleaved.get("repeat_count"):
        raise ValueError("paired board runs use different repeat counts")
    invariants = (
        "bitstream_sha256",
        "firmware_sha256",
        "vector_bundle_sha256",
        "rail_scope",
        "rdcycle_frequency_hz",
        "pmul_wait_cycles",
        "cpu_hdec_clock_relation",
    )
    for field in invariants:
        if serial.get(field) in (None, "") or interleaved.get(field) in (None, ""):
            raise ValueError(f"paired board runs are missing required {field}")
        if serial.get(field) != interleaved.get(field):
            raise ValueError(f"paired board runs differ in {field}")
    serial_cycles = serial.get("rdcycle_delta")
    interleaved_cycles = interleaved.get("rdcycle_delta")
    result = {
        "schema": "vv35-board-paired-comparison-v1",
        "qualification": "board-level measured power for the same named rails",
        "repeat_count": serial.get("repeat_count"),
        "bitstream_sha256": serial.get("bitstream_sha256"),
        "firmware_sha256": serial.get("firmware_sha256"),
        "vector_bundle_sha256": serial.get("vector_bundle_sha256"),
        "rail_scope": serial.get("rail_scope"),
        "serial_cycles": serial_cycles,
        "interleaved_cycles": interleaved_cycles,
        "cycle_reduction": reduction(serial_cycles, interleaved_cycles),
        "speedup": None if not interleaved_cycles else serial_cycles / interleaved_cycles,
        "serial_gross_energy_per_batch_mj": serial.get("gross_energy_per_batch_mj"),
        "interleaved_gross_energy_per_batch_mj": interleaved.get("gross_energy_per_batch_mj"),
        "gross_energy_reduction": reduction(
            serial.get("gross_energy_per_batch_mj"),
            interleaved.get("gross_energy_per_batch_mj"),
        ),
        "serial_incremental_energy_per_batch_mj": serial.get(
            "incremental_energy_per_batch_mj"
        ),
        "interleaved_incremental_energy_per_batch_mj": interleaved.get(
            "incremental_energy_per_batch_mj"
        ),
        "incremental_energy_reduction": reduction(
            serial.get("incremental_energy_per_batch_mj"),
            interleaved.get("incremental_energy_per_batch_mj"),
        ),
    }
    rendered = json.dumps(result, indent=2, sort_keys=True)
    if args.output:
        args.output.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
