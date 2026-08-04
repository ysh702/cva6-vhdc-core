#!/usr/bin/env python3
"""End-to-end positive and fail-closed tests for the VV35 board energy tools."""

from __future__ import annotations

import csv
import json
import subprocess
import sys
import tempfile
from pathlib import Path


HERE = Path(__file__).resolve().parent
COMPUTE = HERE / "compute_vv35_board_energy.py"
COMPARE = HERE / "compare_vv35_board_runs.py"
RATE_HZ = 1_000_000


def write_trace(path: Path, expected_duration_s: float, power_w: float) -> None:
    steps = round(expected_duration_s * RATE_HZ)
    dt = 1.0 / RATE_HZ
    rows = ["timestamp_s,marker,rail,power_w", f"0.000000000,0,VCCINT,{power_w}"]
    for index in range(steps + 1):
        rows.append(f"{dt * (index + 1):.9f},1,VCCINT,{power_w}")
    rows.append(f"{dt * (steps + 2):.9f},0,VCCINT,{power_w}")
    path.write_text("\n".join(rows) + "\n", encoding="utf-8")


def write_evidence(path: Path, *, tamper_serial_pass: bool = False) -> None:
    fieldnames = [
        "trial", "scenario", "requested_mode", "actual_mode", "sequence",
        "snapshot_valid", "pass", "fail", "idle", "busy", "metric_active",
        "phase", "window_cycles", "hmatch_completed", "error_count",
        "error_code", "last_hmatch", "final_status", "preload_count",
        "hmatch_completion_cycles", "validation",
    ]
    rows = [
        ["1", "INTERLEAVED", "1", "1", "00000001", "1", "1", "0", "1", "0", "0", "00", "00030dd0", "00000660", "00000000", "00000000", "00000000000001f9", "0000000000000048", "00000070", "00030db2", "PASS"],
        ["1", "SERIAL", "0", "0", "00000002", "1", "0" if tamper_serial_pass else "1", "0", "1", "0", "0", "00", "000527bd", "00000660", "00000000", "00000000", "00000000000001f9", "0000000000000048", "00000070", "000527bd", "PASS"],
        ["1", "CLOCKED_IDLE", "2", "2", "00000003", "1", "1", "0", "1", "0", "0", "00", "001e8480", "00000000", "00000000", "00000000", "0000000000000000", "0000000000000000", "00000070", "00000000", "PASS"],
    ]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(fieldnames)
        writer.writerows(rows)


def compute_command(
    root: Path,
    scenario: str,
    trace: Path,
    idle: Path,
    evidence: Path,
    output: Path,
    *,
    power_uncertainty_w: str = "0.001",
) -> list[str]:
    cycle_delta = "337853" if scenario == "SERIAL" else "200144"
    return [
        sys.executable, str(COMPUTE), str(trace), "--idle-trace", str(idle),
        "--endpoint", "standalone_pl_vio", "--scenario", scenario,
        "--batch-count", "1", "--trial-id", scenario.lower(), "--pair-id", "pair01",
        "--result-evidence", str(evidence), "--evidence-trial", "1",
        "--cycle-delta", cycle_delta, "--cycle-frequency-hz", "200000000",
        "--hdec-frequency-hz", "200000000", "--rail-scope", "VCCINT",
        "--instrument-model", "SYNTHETIC_SELFTEST", "--sample-rate-hz", str(RATE_HZ),
        "--board-id", "SELFTEST", "--clock-config", "200MHz",
        "--voltage-config", "nominal", "--temperature-c", "25.0",
        "--active-power-uncertainty-w", power_uncertainty_w,
        "--idle-power-uncertainty-w", power_uncertainty_w,
        "--bitstream-sha256", "a" * 64, "--vector-bundle-sha256", "b" * 64,
        "--output", str(output),
    ]


def run_quiet(command: list[str], *, expect_success: bool) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, text=True, capture_output=True, check=False)
    if expect_success and result.returncode != 0:
        raise RuntimeError(result.stderr or result.stdout)
    if not expect_success and result.returncode == 0:
        raise RuntimeError("negative self-test unexpectedly succeeded")
    return result


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="vv35_energy_selftest_") as temp:
        root = Path(temp)
        evidence = root / "evidence.csv"
        tampered = root / "tampered.csv"
        serial = root / "serial.csv"
        interleaved = root / "interleaved.csv"
        idle = root / "idle.csv"
        write_evidence(evidence)
        write_evidence(tampered, tamper_serial_pass=True)
        write_trace(serial, 337853 / 200_000_000, 0.30)
        write_trace(interleaved, 200144 / 200_000_000, 0.35)
        write_trace(idle, 2_000_000 / 200_000_000, 0.10)

        serial_json = root / "serial.json"
        interleaved_json = root / "interleaved.json"
        run_quiet(compute_command(root, "SERIAL", serial, idle, evidence, serial_json), expect_success=True)
        run_quiet(compute_command(root, "INTERLEAVED", interleaved, idle, evidence, interleaved_json), expect_success=True)
        comparison_json = root / "comparison.json"
        run_quiet(
            [sys.executable, str(COMPARE), str(serial_json), str(interleaved_json), "--output", str(comparison_json)],
            expect_success=True,
        )
        comparison = json.loads(comparison_json.read_text(encoding="utf-8"))
        assert comparison["qualification"] == "QUALIFIED_PER_PAIR_BOARD_COMPARISON_V2"

        run_quiet(compute_command(root, "SERIAL", serial, idle, tampered, root / "bad.json"), expect_success=False)
        split_lines = serial.read_text(encoding="utf-8").splitlines()
        split_fields = split_lines[len(split_lines) // 2].split(",")
        split_fields[1] = "0"
        split_lines[len(split_lines) // 2] = ",".join(split_fields)
        split = root / "split.csv"
        split.write_text("\n".join(split_lines) + "\n", encoding="utf-8")
        run_quiet(compute_command(root, "SERIAL", split, idle, evidence, root / "split.json"), expect_success=False)

        serial_below = root / "serial_below.csv"
        interleaved_below = root / "interleaved_below.csv"
        write_trace(serial_below, 337853 / 200_000_000, 0.05)
        write_trace(interleaved_below, 200144 / 200_000_000, 0.06)
        signed_serial_json = root / "signed_serial.json"
        signed_interleaved_json = root / "signed_interleaved.json"
        run_quiet(compute_command(root, "SERIAL", serial_below, idle, evidence, signed_serial_json), expect_success=True)
        run_quiet(compute_command(root, "INTERLEAVED", interleaved_below, idle, evidence, signed_interleaved_json), expect_success=True)
        signed_comparison_json = root / "signed_comparison.json"
        run_quiet(
            [sys.executable, str(COMPARE), str(signed_serial_json), str(signed_interleaved_json), "--output", str(signed_comparison_json)],
            expect_success=True,
        )
        signed = json.loads(signed_comparison_json.read_text(encoding="utf-8"))
        assert signed["metrics"]["incremental_reduction_qualified"] is False
        assert signed["metrics"]["incremental_energy_reduction"] is None

    print("[VV35:BOARD_ENERGY_TOOLS] PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
