#!/usr/bin/env python3
"""Qualify and integrate VV35 board power traces.

The v2 interface deliberately treats trace integrity, workload completion and
run provenance as prerequisites for reporting board energy.  It accepts only
bounded, contiguous marker windows on a complete synchronous rail grid.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import math
import re
from pathlib import Path
from typing import Any


SUMMARY_SCHEMA = "vv35-board-energy-v2"
RESULT_EVIDENCE_SCHEMA = "vv35-vio-result-evidence-v1"
STANDALONE_EVIDENCE_SCHEMA = "vv35-standalone-pl-vio-csv-row-v1"
INTEGRATOR_SCHEMA = "vv35-board-trace-integrator-v2"
INTEGRATOR_VERSION = "2.0.0"
INTEGRATION_ALGORITHM = "per_rail_trapezoidal_complete_common_grid_v1"
MIN_MARKED_SAMPLES_PER_RAIL = 1000
SAMPLE_RATE_REL_TOLERANCE = 0.10
STANDALONE_MARKER_DURATION_REL_TOLERANCE = 0.01

RESULT_MAGIC = 0x565633354C414231
EXPECTED_HMATCH_PER_BATCH = 1632
EXPECTED_HMATCH_RESULT = 0x1F9
EXPECTED_FINAL_STATUS_LOW_NIBBLE = 0x8
RUN_MODE_BY_SCENARIO = {"SERIAL": 0, "INTERLEAVED": 1}
ENDPOINTS = ("standalone_pl_vio", "cva6_result_block")
STANDALONE_WINDOW_CYCLES = {"SERIAL": 337853, "INTERLEAVED": 200144}
STANDALONE_HMATCH_COMPLETION_CYCLES = {"SERIAL": 337853, "INTERLEAVED": 200114}
STANDALONE_IDLE_WINDOW_CYCLES = 2_000_000
STANDALONE_PRELOAD_COUNT = 112
STANDALONE_FINAL_STATUS = 0x48
SHA256_RE = re.compile(r"[0-9a-fA-F]{64}\Z")


def require_nonempty(name: str, value: str) -> str:
    normalized = value.strip()
    if not normalized:
        raise ValueError(f"{name} must be non-empty")
    return normalized


def require_sha256(name: str, value: str) -> str:
    normalized = value.strip().lower()
    if not SHA256_RE.fullmatch(normalized):
        raise ValueError(f"{name} must be exactly 64 hexadecimal characters")
    return normalized


def require_finite(name: str, value: float) -> float:
    if not math.isfinite(value):
        raise ValueError(f"{name} must be finite")
    return value


def require_positive(name: str, value: float) -> float:
    require_finite(name, value)
    if value <= 0:
        raise ValueError(f"{name} must be positive")
    return value


def parse_row_float(
    path: Path,
    row_number: int,
    field: str,
    raw_value: str,
    *,
    positive: bool = False,
    nonnegative: bool = False,
) -> float:
    if not raw_value.strip():
        raise ValueError(f"{path}:{row_number}: {field} is empty")
    try:
        value = float(raw_value)
    except ValueError as exc:
        raise ValueError(
            f"{path}:{row_number}: {field} is not numeric: {raw_value!r}"
        ) from exc
    require_finite(f"{path}:{row_number}: {field}", value)
    if positive and value <= 0:
        raise ValueError(f"{path}:{row_number}: {field} must be positive")
    if nonnegative and value < 0:
        raise ValueError(f"{path}:{row_number}: {field} must be nonnegative")
    return value


def integrate_rail(samples: list[tuple[float, float]], path: Path, rail: str) -> float:
    energy_j = 0.0
    for (t0, p0), (t1, p1) in zip(samples, samples[1:]):
        if t1 <= t0:
            raise ValueError(
                f"{path}: rail {rail!r} timestamps are not strictly increasing"
            )
        energy_j += 0.5 * (p0 + p1) * (t1 - t0)
    return require_positive(f"{path}: rail {rail!r} energy", energy_j)


def load_marked_trace(path: Path, marker_threshold: float) -> dict[str, Any]:
    """Load one raw trace and return a fully qualified marked-window summary."""
    raw_bytes = path.read_bytes()
    raw_sha256 = hashlib.sha256(raw_bytes).hexdigest()
    try:
        decoded = raw_bytes.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise ValueError(f"{path}: trace must be UTF-8 CSV") from exc

    rows = csv.DictReader(io.StringIO(decoded, newline=""))
    fieldnames = rows.fieldnames or []
    if len(fieldnames) != len(set(fieldnames)):
        raise ValueError(f"{path}: duplicate CSV column names are not allowed")
    required = {"timestamp_s", "marker", "rail"}
    missing = sorted(required.difference(fieldnames))
    if missing:
        raise ValueError(f"{path}: missing required columns: {', '.join(missing)}")

    groups: list[dict[str, Any]] = []
    power_input_mode: str | None = None
    for row_number, row in enumerate(rows, start=2):
        if None in row:
            raise ValueError(f"{path}:{row_number}: unexpected extra CSV fields")
        timestamp = parse_row_float(
            path,
            row_number,
            "timestamp_s",
            row.get("timestamp_s", ""),
            nonnegative=True,
        )
        marker = parse_row_float(
            path, row_number, "marker", row.get("marker", "")
        )
        marker_high = marker >= marker_threshold
        rail = row.get("rail", "").strip()
        if not rail:
            raise ValueError(f"{path}:{row_number}: rail must be non-empty")

        power_raw = row.get("power_w", "").strip()
        voltage_raw = row.get("voltage_v", "").strip()
        current_raw = row.get("current_a", "").strip()
        if power_raw:
            if voltage_raw or current_raw:
                raise ValueError(
                    f"{path}:{row_number}: provide power_w or voltage/current, not both"
                )
            row_mode = "power_w"
            power_w = parse_row_float(
                path, row_number, "power_w", power_raw, nonnegative=True
            )
        else:
            if bool(voltage_raw) != bool(current_raw):
                raise ValueError(
                    f"{path}:{row_number}: voltage_v and current_a must both be present"
                )
            if not voltage_raw:
                raise ValueError(
                    f"{path}:{row_number}: need power_w or voltage_v and current_a"
                )
            row_mode = "voltage_v_x_current_a"
            voltage_v = parse_row_float(
                path, row_number, "voltage_v", voltage_raw, positive=True
            )
            current_a = parse_row_float(
                path, row_number, "current_a", current_raw, nonnegative=True
            )
            power_w = require_finite(
                f"{path}:{row_number}: voltage_v * current_a", voltage_v * current_a
            )
        if power_input_mode is None:
            power_input_mode = row_mode
        elif row_mode != power_input_mode:
            raise ValueError(f"{path}:{row_number}: mixed power input modes are not allowed")

        if not groups or timestamp != groups[-1]["timestamp_s"]:
            if groups and timestamp <= groups[-1]["timestamp_s"]:
                raise ValueError(
                    f"{path}:{row_number}: timestamp groups must be strictly increasing "
                    "in original file order"
                )
            groups.append(
                {
                    "timestamp_s": timestamp,
                    "marker_high": marker_high,
                    "powers": {},
                }
            )
        group = groups[-1]
        if marker_high != group["marker_high"]:
            raise ValueError(
                f"{path}:{row_number}: rails disagree on marker state at timestamp {timestamp}"
            )
        if rail in group["powers"]:
            raise ValueError(
                f"{path}:{row_number}: duplicate rail {rail!r} at timestamp {timestamp}"
            )
        group["powers"][rail] = power_w

    if not groups:
        raise ValueError(f"{path}: trace contains no data rows")
    rail_names = sorted({rail for group in groups for rail in group["powers"]})
    if not rail_names:
        raise ValueError(f"{path}: trace contains no rails")
    expected_rails = set(rail_names)
    for group in groups:
        actual_rails = set(group["powers"])
        if actual_rails != expected_rails:
            missing_rails = sorted(expected_rails - actual_rails)
            extra_rails = sorted(actual_rails - expected_rails)
            raise ValueError(
                f"{path}: incomplete rail set at timestamp {group['timestamp_s']}; "
                f"missing={missing_rails}, extra={extra_rails}"
            )

    high_indices = [index for index, group in enumerate(groups) if group["marker_high"]]
    if not high_indices:
        raise ValueError(f"{path}: marker has no high window")
    first_high = high_indices[0]
    last_high = high_indices[-1]
    if any(not groups[index]["marker_high"] for index in range(first_high, last_high + 1)):
        raise ValueError(f"{path}: marker must contain exactly one contiguous high window")
    if first_high == 0 or last_high == len(groups) - 1:
        raise ValueError(
            f"{path}: marker high window must be bounded by at least one low sample "
            "on each side"
        )
    marked_groups = groups[first_high : last_high + 1]
    marked_timestamp_count = len(marked_groups)
    if marked_timestamp_count < MIN_MARKED_SAMPLES_PER_RAIL:
        raise ValueError(
            f"{path}: marker window has {marked_timestamp_count} samples per rail; "
            f"at least {MIN_MARKED_SAMPLES_PER_RAIL} are required"
        )

    marker_start_s = marked_groups[0]["timestamp_s"]
    marker_end_s = marked_groups[-1]["timestamp_s"]
    marker_duration_s = require_positive(
        f"{path}: marker duration", marker_end_s - marker_start_s
    )
    per_rail: dict[str, dict[str, float]] = {}
    total_energy_j = 0.0
    for rail in rail_names:
        samples = [
            (group["timestamp_s"], group["powers"][rail]) for group in marked_groups
        ]
        rail_energy_j = integrate_rail(samples, path, rail)
        total_energy_j += rail_energy_j
        per_rail[rail] = {
            "average_power_w": rail_energy_j / marker_duration_s,
            "energy_mj": rail_energy_j * 1e3,
        }
    total_energy_j = require_positive(f"{path}: total energy", total_energy_j)
    observed_sample_rate_hz = require_positive(
        f"{path}: observed sample rate",
        (marked_timestamp_count - 1) / marker_duration_s,
    )
    return {
        "path": str(path.resolve()),
        "raw_sha256": raw_sha256,
        "rail_names": rail_names,
        "power_input_mode": power_input_mode,
        "full_timestamp_count": len(groups),
        "full_sample_count_total": len(groups) * len(rail_names),
        "marked_timestamp_count_per_rail": marked_timestamp_count,
        "marked_sample_count_total": marked_timestamp_count * len(rail_names),
        "marker_low_before_s": groups[first_high - 1]["timestamp_s"],
        "marker_start_s": marker_start_s,
        "marker_end_s": marker_end_s,
        "marker_low_after_s": groups[last_high + 1]["timestamp_s"],
        "marker_duration_s": marker_duration_s,
        "observed_sample_rate_hz": observed_sample_rate_hz,
        "average_power_w": total_energy_j / marker_duration_s,
        "energy_mj": total_energy_j * 1e3,
        "per_rail": per_rail,
    }


def parse_hex_field(path: Path, row: dict[str, str], field: str) -> int:
    raw = row.get(field, "").strip()
    if not raw:
        raise ValueError(f"{path}: evidence field {field} is empty")
    try:
        return int(raw, 16)
    except ValueError as exc:
        raise ValueError(f"{path}: evidence field {field} is not hexadecimal") from exc


def load_result_evidence(
    path: Path,
    *,
    endpoint: str,
    scenario: str,
    batch_count: int,
    trial_id: str,
    pair_id: str,
    active_trace_sha256: str,
    idle_trace_sha256: str,
    cycle_delta: int,
    evidence_trial: str | None,
) -> dict[str, Any]:
    """Read, hash and validate endpoint-specific VIO/result evidence."""
    raw_bytes = path.read_bytes()
    raw_sha256 = hashlib.sha256(raw_bytes).hexdigest()
    if endpoint == "cva6_result_block":
        try:
            payload = json.loads(raw_bytes.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise ValueError(f"{path}: invalid UTF-8 result evidence JSON: {exc}") from exc
        if not isinstance(payload, dict):
            raise ValueError(f"{path}: result evidence must be a JSON object")
        if payload.get("schema") != RESULT_EVIDENCE_SCHEMA:
            raise ValueError(f"{path}: unsupported result evidence schema")
        if payload.get("status") != "PASS" or payload.get("vio_pass") is not True:
            raise ValueError(f"{path}: VIO/result evidence is not explicit PASS")
        expected_bindings = {
            "trial_id": trial_id,
            "pair_id": pair_id,
            "scenario": scenario,
            "active_trace_sha256": active_trace_sha256,
            "idle_trace_sha256": idle_trace_sha256,
        }
        for field, expected in expected_bindings.items():
            if payload.get(field) != expected:
                raise ValueError(f"{path}: result evidence {field} binding mismatch")
        require_sha256(
            f"{path}: active_trace_sha256",
            str(payload.get("active_trace_sha256", "")),
        )
        result_block = payload.get("result_block")
        if not isinstance(result_block, dict):
            raise ValueError(f"{path}: result_block must be a JSON object")
        expected_fields = {
            "magic_hex": f"0x{RESULT_MAGIC:016x}",
            "error_count": 0,
            "run_mode": RUN_MODE_BY_SCENARIO[scenario],
            "batch_count": batch_count,
            "hmatch_completions": EXPECTED_HMATCH_PER_BATCH * batch_count,
            "last_hmatch_hex": f"0x{EXPECTED_HMATCH_RESULT:x}",
        }
        for field, expected in expected_fields.items():
            value = result_block.get(field)
            if isinstance(expected, int) and isinstance(value, bool):
                raise ValueError(f"{path}: result_block.{field} has invalid boolean type")
            if value != expected:
                raise ValueError(f"{path}: result_block.{field} mismatch")
        final_status_hex = result_block.get("final_status_hex")
        if not isinstance(final_status_hex, str):
            raise ValueError(f"{path}: result_block.final_status_hex must be a string")
        try:
            final_status = int(final_status_hex, 0)
        except ValueError as exc:
            raise ValueError(f"{path}: result_block.final_status_hex is invalid") from exc
        if final_status < 0 or final_status & 0xF != EXPECTED_FINAL_STATUS_LOW_NIBBLE:
            raise ValueError(f"{path}: result-block final status low nibble mismatch")
        normalized_result_block = {
            **expected_fields,
            "hmatch_per_batch": EXPECTED_HMATCH_PER_BATCH,
            "final_status_hex": f"0x{final_status:x}",
            "final_status_low_nibble": final_status & 0xF,
        }
        if payload.get("idle_vio_pass") is not True:
            raise ValueError(f"{path}: idle VIO/result evidence is not explicit PASS")
        idle_result_block = payload.get("idle_result_block")
        if not isinstance(idle_result_block, dict):
            raise ValueError(f"{path}: idle_result_block must be a JSON object")
        expected_idle_fields = {
            "magic_hex": f"0x{RESULT_MAGIC:016x}",
            "error_count": 0,
            "run_mode": 2,
            "batch_count": batch_count,
            "hmatch_completions": 0,
            "last_hmatch_hex": "0x0",
            "final_status_hex": "0x0",
        }
        for field, expected in expected_idle_fields.items():
            if idle_result_block.get(field) != expected:
                raise ValueError(f"{path}: idle_result_block.{field} mismatch")
        return {
            "source": "cva6_result_evidence_json",
            "evidence_payload": payload,
            "result_evidence_sha256": raw_sha256,
            "evidence_record_sha256": raw_sha256,
            "result_block": normalized_result_block,
            "idle_result_block": {
                **expected_idle_fields,
                "hmatch_per_batch": 0,
                "final_status_low_nibble": 0,
            },
        }

    try:
        decoded = raw_bytes.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise ValueError(f"{path}: standalone VIO evidence must be UTF-8 CSV") from exc
    reader = csv.DictReader(io.StringIO(decoded, newline=""))
    required = {
        "scenario",
        "requested_mode",
        "actual_mode",
        "sequence",
        "snapshot_valid",
        "pass",
        "fail",
        "idle",
        "busy",
        "metric_active",
        "phase",
        "window_cycles",
        "hmatch_completed",
        "error_count",
        "error_code",
        "last_hmatch",
        "final_status",
        "preload_count",
        "hmatch_completion_cycles",
        "validation",
    }
    missing = sorted(required.difference(reader.fieldnames or []))
    if missing:
        raise ValueError(f"{path}: standalone evidence missing columns: {missing}")
    normalized_rows = [
        (row_number, {key: value.strip() for key, value in row.items()})
        for row_number, row in enumerate(reader, start=2)
    ]

    def select_row(scenario_names: set[str]) -> tuple[int, dict[str, str]]:
        candidates = []
        for candidate_number, candidate in normalized_rows:
            if candidate.get("scenario", "") not in scenario_names:
                continue
            if evidence_trial is not None:
                if candidate.get("trial", "") != evidence_trial:
                    continue
            candidates.append((candidate_number, candidate))
        if len(candidates) != 1:
            raise ValueError(
                f"{path}: expected exactly one evidence row for {sorted(scenario_names)}, "
                f"found {len(candidates)}; use --evidence-trial for multi-trial CSV"
            )
        return candidates[0]

    row_number, row = select_row({scenario})
    idle_row_number, idle_row = select_row({"CLOCKED_IDLE", "CLOCKED_IDLE_SPIN"})
    expected_mode = RUN_MODE_BY_SCENARIO[scenario]
    decimal_expectations = {
        "requested_mode": expected_mode,
        "actual_mode": expected_mode,
        "snapshot_valid": 1,
        "pass": 1,
        "fail": 0,
        "idle": 1,
        "busy": 0,
        "metric_active": 0,
    }
    for field, expected in decimal_expectations.items():
        try:
            actual = int(row[field], 10)
        except ValueError as exc:
            raise ValueError(f"{path}:{row_number}: {field} is not decimal") from exc
        if actual != expected:
            raise ValueError(f"{path}:{row_number}: {field} mismatch")
    if row["validation"] != "PASS":
        raise ValueError(f"{path}:{row_number}: validation is not PASS")
    if parse_hex_field(path, row, "phase") != 0:
        raise ValueError(f"{path}:{row_number}: controller phase is not terminal idle")
    window_cycles = parse_hex_field(path, row, "window_cycles")
    hmatch_completed = parse_hex_field(path, row, "hmatch_completed")
    error_count = parse_hex_field(path, row, "error_count")
    error_code = parse_hex_field(path, row, "error_code")
    last_hmatch = parse_hex_field(path, row, "last_hmatch")
    final_status = parse_hex_field(path, row, "final_status")
    preload_count = parse_hex_field(path, row, "preload_count")
    hmatch_completion_cycles = parse_hex_field(
        path, row, "hmatch_completion_cycles"
    )
    if window_cycles != cycle_delta or window_cycles != STANDALONE_WINDOW_CYCLES[scenario]:
        raise ValueError(f"{path}:{row_number}: window_cycles does not match cycle delta")
    if hmatch_completed != EXPECTED_HMATCH_PER_BATCH * batch_count:
        raise ValueError(f"{path}:{row_number}: hmatch_completed mismatch")
    if error_count != 0 or error_code != 0:
        raise ValueError(f"{path}:{row_number}: VIO error fields are nonzero")
    if last_hmatch != EXPECTED_HMATCH_RESULT:
        raise ValueError(f"{path}:{row_number}: last_hmatch mismatch")
    if final_status != STANDALONE_FINAL_STATUS:
        raise ValueError(f"{path}:{row_number}: final_status is not exact PASS status")
    if preload_count != STANDALONE_PRELOAD_COUNT:
        raise ValueError(f"{path}:{row_number}: preload_count mismatch")
    if hmatch_completion_cycles != STANDALONE_HMATCH_COMPLETION_CYCLES[scenario]:
        raise ValueError(f"{path}:{row_number}: hmatch_completion_cycles mismatch")

    idle_decimal_expectations = {
        "requested_mode": 2,
        "actual_mode": 2,
        "snapshot_valid": 1,
        "pass": 1,
        "fail": 0,
        "idle": 1,
        "busy": 0,
        "metric_active": 0,
    }
    for field, expected in idle_decimal_expectations.items():
        try:
            actual = int(idle_row[field], 10)
        except ValueError as exc:
            raise ValueError(
                f"{path}:{idle_row_number}: idle {field} is not decimal"
            ) from exc
        if actual != expected:
            raise ValueError(f"{path}:{idle_row_number}: idle {field} mismatch")
    if idle_row["validation"] != "PASS":
        raise ValueError(f"{path}:{idle_row_number}: idle validation is not PASS")
    idle_hex_expectations = {
        "phase": 0,
        "window_cycles": STANDALONE_IDLE_WINDOW_CYCLES,
        "hmatch_completed": 0,
        "error_count": 0,
        "error_code": 0,
        "last_hmatch": 0,
        "final_status": 0,
        "preload_count": STANDALONE_PRELOAD_COUNT,
        "hmatch_completion_cycles": 0,
    }
    for field, expected in idle_hex_expectations.items():
        if parse_hex_field(path, idle_row, field) != expected:
            raise ValueError(f"{path}:{idle_row_number}: idle {field} mismatch")
    record_bytes = json.dumps(
        {"active": row, "idle": idle_row},
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=True,
    ).encode("ascii")
    evidence_payload = {
        "schema": STANDALONE_EVIDENCE_SCHEMA,
        "selector": {"scenario": scenario, "trial": evidence_trial},
        "selected_row": row,
        "selected_idle_row": idle_row,
    }
    return {
        "source": "standalone_pl_vio_csv",
        "evidence_payload": evidence_payload,
        "result_evidence_sha256": raw_sha256,
        "evidence_record_sha256": hashlib.sha256(record_bytes).hexdigest(),
        "result_block": {
            "magic_hex": None,
            "error_count": error_count,
            "error_code": error_code,
            "run_mode": expected_mode,
            "batch_count": batch_count,
            "hmatch_completions": hmatch_completed,
            "hmatch_per_batch": EXPECTED_HMATCH_PER_BATCH,
            "last_hmatch_hex": f"0x{last_hmatch:x}",
            "final_status_hex": f"0x{final_status:x}",
            "final_status_low_nibble": final_status & 0xF,
            "window_cycles": window_cycles,
            "preload_count": preload_count,
            "hmatch_completion_cycles": hmatch_completion_cycles,
            "sequence_hex": f"0x{parse_hex_field(path, row, 'sequence'):x}",
            "snapshot_valid": True,
            "controller_pass": True,
        },
        "idle_result_block": {
            "magic_hex": None,
            "error_count": 0,
            "error_code": 0,
            "run_mode": 2,
            "batch_count": batch_count,
            "hmatch_completions": 0,
            "hmatch_per_batch": 0,
            "last_hmatch_hex": "0x0",
            "final_status_hex": "0x0",
            "final_status_low_nibble": 0,
            "window_cycles": STANDALONE_IDLE_WINDOW_CYCLES,
            "preload_count": STANDALONE_PRELOAD_COUNT,
            "hmatch_completion_cycles": 0,
            "sequence_hex": f"0x{parse_hex_field(path, idle_row, 'sequence'):x}",
            "snapshot_valid": True,
            "controller_pass": True,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("trace", type=Path, help="active SERIAL or INTERLEAVED CSV")
    parser.add_argument("--idle-trace", type=Path, required=True)
    parser.add_argument("--endpoint", choices=ENDPOINTS, required=True)
    parser.add_argument("--scenario", choices=tuple(RUN_MODE_BY_SCENARIO), required=True)
    parser.add_argument("--marker-threshold", type=float, default=0.5)
    parser.add_argument("--batch-count", type=int, required=True)
    parser.add_argument("--trial-id", required=True)
    parser.add_argument("--pair-id", required=True)

    parser.add_argument(
        "--result-evidence",
        type=Path,
        required=True,
        help="validated standalone VIO CSV or bound CVA6 result evidence JSON",
    )
    parser.add_argument(
        "--evidence-trial",
        help="trial selector when result evidence CSV has repeated scenario rows",
    )

    parser.add_argument(
        "--cycle-delta", "--rdcycle-delta", dest="cycle_delta", type=int, required=True
    )
    parser.add_argument(
        "--cycle-frequency-hz",
        "--rdcycle-frequency-hz",
        dest="cycle_frequency_hz",
        type=float,
        required=True,
    )
    parser.add_argument("--hdec-frequency-hz", type=float, required=True)
    parser.add_argument("--pmul-wait-cycles", type=int)
    parser.add_argument("--cpu-hdec-clock-relation")
    parser.add_argument("--rail-scope", required=True)
    parser.add_argument("--instrument-model", required=True)
    parser.add_argument("--sample-rate-hz", type=float, required=True)
    parser.add_argument("--board-id", required=True)
    parser.add_argument("--clock-config", required=True)
    parser.add_argument("--voltage-config", required=True)
    parser.add_argument("--temperature-c", type=float, required=True)
    parser.add_argument("--active-power-uncertainty-w", type=float, required=True)
    parser.add_argument("--idle-power-uncertainty-w", type=float, required=True)

    parser.add_argument("--bitstream-sha256", required=True)
    parser.add_argument("--firmware-sha256")
    parser.add_argument("--vector-bundle-sha256", required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    try:
        require_finite("--marker-threshold", args.marker_threshold)
        if args.batch_count < 1:
            raise ValueError("--batch-count must be positive")
        if args.cycle_delta < 1:
            raise ValueError("--cycle-delta must be positive")
        require_positive("--cycle-frequency-hz", args.cycle_frequency_hz)
        require_positive("--hdec-frequency-hz", args.hdec_frequency_hz)
        require_positive("--sample-rate-hz", args.sample_rate_hz)
        require_finite("--temperature-c", args.temperature_c)
        require_finite(
            "--active-power-uncertainty-w", args.active_power_uncertainty_w
        )
        require_finite("--idle-power-uncertainty-w", args.idle_power_uncertainty_w)
        if args.active_power_uncertainty_w < 0 or args.idle_power_uncertainty_w < 0:
            raise ValueError("power uncertainty inputs must be nonnegative")

        if args.endpoint == "cva6_result_block":
            cpu_hdec_clock_relation = require_nonempty(
                "--cpu-hdec-clock-relation", args.cpu_hdec_clock_relation or ""
            )
            if args.pmul_wait_cycles is None or args.pmul_wait_cycles < 1:
                raise ValueError(
                    "CVA6 endpoint requires positive --pmul-wait-cycles"
                )
            if not args.firmware_sha256:
                raise ValueError("CVA6 endpoint requires --firmware-sha256")
            cycle_counter_kind = "cpu_rdcycle"
        else:
            if args.firmware_sha256:
                raise ValueError("standalone PL endpoint must not claim firmware")
            if args.pmul_wait_cycles is not None or args.cpu_hdec_clock_relation:
                raise ValueError(
                    "standalone PL endpoint must not use CPU clock or PMUL-wait options"
                )
            cpu_hdec_clock_relation = "not_applicable_standalone_pl"
            cycle_counter_kind = "standalone_hdec_window_cycles"
            if not math.isclose(
                args.cycle_frequency_hz,
                args.hdec_frequency_hz,
                rel_tol=1e-9,
                abs_tol=0.0,
            ):
                raise ValueError(
                    "standalone PL cycle frequency must equal HDEC frequency"
                )

        trial_id = require_nonempty("--trial-id", args.trial_id)
        pair_id = require_nonempty("--pair-id", args.pair_id)
        conditions = {
            "board_id": require_nonempty("--board-id", args.board_id),
            "clock_config": require_nonempty("--clock-config", args.clock_config),
            "voltage_config": require_nonempty("--voltage-config", args.voltage_config),
            "temperature_c": args.temperature_c,
            "instrument_model": require_nonempty(
                "--instrument-model", args.instrument_model
            ),
            "nominal_sample_rate_hz": args.sample_rate_hz,
            "rail_scope": require_nonempty("--rail-scope", args.rail_scope),
            "cycle_counter_kind": cycle_counter_kind,
            "cycle_frequency_hz": args.cycle_frequency_hz,
            "hdec_frequency_hz": args.hdec_frequency_hz,
            "cpu_hdec_clock_relation": cpu_hdec_clock_relation,
            "pmul_wait_cycles": args.pmul_wait_cycles,
        }
        if conditions["cpu_hdec_clock_relation"] == "same_frequency_ungated":
            if not math.isclose(
                args.cycle_frequency_hz,
                args.hdec_frequency_hz,
                rel_tol=1e-9,
                abs_tol=0.0,
            ):
                raise ValueError(
                    "same_frequency_ungated requires equal CPU rdcycle and HDEC frequencies"
                )

        provenance = {
            "bitstream_sha256": require_sha256(
                "--bitstream-sha256", args.bitstream_sha256
            ),
            "firmware_sha256": None
            if args.firmware_sha256 is None
            else require_sha256("--firmware-sha256", args.firmware_sha256),
            "vector_bundle_sha256": require_sha256(
                "--vector-bundle-sha256", args.vector_bundle_sha256
            ),
        }
        active_trace = load_marked_trace(args.trace, args.marker_threshold)
        idle_trace = load_marked_trace(args.idle_trace, args.marker_threshold)
        if active_trace["raw_sha256"] == idle_trace["raw_sha256"]:
            raise ValueError("active and idle traces must be different raw captures")
        if active_trace["rail_names"] != idle_trace["rail_names"]:
            raise ValueError("active and idle traces use different rail sets")
        if active_trace["power_input_mode"] != idle_trace["power_input_mode"]:
            raise ValueError("active and idle traces use different power input modes")
        evidence = load_result_evidence(
            args.result_evidence,
            endpoint=args.endpoint,
            scenario=args.scenario,
            batch_count=args.batch_count,
            trial_id=trial_id,
            pair_id=pair_id,
            active_trace_sha256=active_trace["raw_sha256"],
            idle_trace_sha256=idle_trace["raw_sha256"],
            cycle_delta=args.cycle_delta,
            evidence_trial=args.evidence_trial,
        )
        for label, trace_summary in (
            ("active", active_trace),
            ("idle", idle_trace),
        ):
            observed = trace_summary["observed_sample_rate_hz"]
            relative_error = abs(observed - args.sample_rate_hz) / args.sample_rate_hz
            if relative_error > SAMPLE_RATE_REL_TOLERANCE:
                raise ValueError(
                    f"{label} observed sample rate {observed} Hz differs from "
                    f"--sample-rate-hz by more than {SAMPLE_RATE_REL_TOLERANCE:.0%}"
                )

        standalone_duration_checks: dict[str, float | str | None]
        if args.endpoint == "standalone_pl_vio":
            expected_active_duration_s = (
                args.cycle_delta / args.cycle_frequency_hz
            )
            expected_idle_duration_s = (
                STANDALONE_IDLE_WINDOW_CYCLES / args.hdec_frequency_hz
            )
            for label, trace_summary, expected_duration_s in (
                ("active", active_trace, expected_active_duration_s),
                ("idle", idle_trace, expected_idle_duration_s),
            ):
                sampling_tolerance_s = 2.0 / trace_summary["observed_sample_rate_hz"]
                duration_tolerance_s = max(
                    sampling_tolerance_s,
                    expected_duration_s * STANDALONE_MARKER_DURATION_REL_TOLERANCE,
                )
                if (
                    abs(trace_summary["marker_duration_s"] - expected_duration_s)
                    > duration_tolerance_s
                ):
                    raise ValueError(
                        f"{label} marker duration does not match the standalone "
                        "cycle window within sampling tolerance"
                    )
            standalone_duration_checks = {
                "qualification": "MATCHES_STANDALONE_CYCLE_WINDOWS",
                "expected_active_duration_s": expected_active_duration_s,
                "active_duration_error_s": active_trace["marker_duration_s"]
                - expected_active_duration_s,
                "expected_idle_duration_s": expected_idle_duration_s,
                "idle_duration_error_s": idle_trace["marker_duration_s"]
                - expected_idle_duration_s,
            }
        else:
            standalone_duration_checks = {
                "qualification": "NOT_APPLICABLE_CVA6_MARKER_AND_RDCYCLE_BOUNDARIES_DIFFER",
                "expected_active_duration_s": None,
                "active_duration_error_s": None,
                "expected_idle_duration_s": None,
                "idle_duration_error_s": None,
            }

        active_duration_s = active_trace["marker_duration_s"]
        gross_energy_mj = active_trace["energy_mj"]
        gross_average_power_w = active_trace["average_power_w"]
        idle_power_w = idle_trace["average_power_w"]
        idle_energy_over_active_window_mj = idle_power_w * active_duration_s * 1e3
        incremental_energy_mj = gross_energy_mj - idle_energy_over_active_window_mj
        incremental_average_power_w = gross_average_power_w - idle_power_w
        require_finite("incremental average power", incremental_average_power_w)
        require_finite("incremental energy", incremental_energy_mj)
        incremental_power_uncertainty_w = math.hypot(
            args.active_power_uncertainty_w, args.idle_power_uncertainty_w
        )
        gross_energy_uncertainty_mj = (
            args.active_power_uncertainty_w * active_duration_s * 1e3
        )
        idle_energy_uncertainty_mj = (
            args.idle_power_uncertainty_w * active_duration_s * 1e3
        )
        incremental_energy_uncertainty_mj = (
            incremental_power_uncertainty_w * active_duration_s * 1e3
        )
        incremental_reduction_eligible = (
            incremental_average_power_w > incremental_power_uncertainty_w
            and incremental_energy_mj > incremental_energy_uncertainty_mj
        )

        integrator = {
            "schema": INTEGRATOR_SCHEMA,
            "version": INTEGRATOR_VERSION,
            "algorithm": INTEGRATION_ALGORITHM,
            "parameters": {
                "marker_threshold": args.marker_threshold,
                "minimum_marked_samples_per_rail": MIN_MARKED_SAMPLES_PER_RAIL,
                "sample_rate_relative_tolerance": SAMPLE_RATE_REL_TOLERANCE,
                "standalone_marker_duration_relative_tolerance": STANDALONE_MARKER_DURATION_REL_TOLERANCE,
                "marker_policy": "one_contiguous_high_window_bounded_by_low_samples",
                "timestamp_policy": "original_order_unique_groups_strictly_increasing",
                "rail_policy": "complete_common_grid_unique_rail_per_timestamp",
                "power_policy": "one_nonnegative_finite_input_mode_per_trace",
                "idle_policy": "same_marker_threshold_as_active",
            },
        }
        verification = {
            "status": "PASS",
            "source": evidence["source"],
            "vio_pass": True,
            "evidence_path": str(args.result_evidence.resolve()),
            "result_evidence_sha256": evidence["result_evidence_sha256"],
            "evidence_record_sha256": evidence["evidence_record_sha256"],
            "evidence_payload": evidence["evidence_payload"],
            "result_block": evidence["result_block"],
            "idle_result_block": evidence["idle_result_block"],
            "binding": {
                "endpoint": args.endpoint,
                "trial_id": trial_id,
                "pair_id": pair_id,
                "scenario": args.scenario,
                "active_trace_sha256": active_trace["raw_sha256"],
                "idle_trace_sha256": idle_trace["raw_sha256"],
                "result_evidence_sha256": evidence["result_evidence_sha256"],
                "evidence_record_sha256": evidence["evidence_record_sha256"],
            },
        }
        metrics = {
            "marker_duration_s": active_duration_s,
            "gross_average_power_w": gross_average_power_w,
            "idle_average_power_w": idle_power_w,
            "incremental_average_power_w": incremental_average_power_w,
            "active_power_uncertainty_w": args.active_power_uncertainty_w,
            "idle_power_uncertainty_w": args.idle_power_uncertainty_w,
            "incremental_power_uncertainty_w": incremental_power_uncertainty_w,
            "gross_energy_mj": gross_energy_mj,
            "gross_energy_uncertainty_mj": gross_energy_uncertainty_mj,
            "idle_energy_over_active_window_mj": idle_energy_over_active_window_mj,
            "idle_energy_uncertainty_mj": idle_energy_uncertainty_mj,
            "incremental_energy_mj": incremental_energy_mj,
            "incremental_energy_uncertainty_mj": incremental_energy_uncertainty_mj,
            "incremental_reduction_eligible": incremental_reduction_eligible,
            "incremental_qualification": "POSITIVE_ABOVE_UNCERTAINTY"
            if incremental_reduction_eligible
            else "SIGNED_VALUE_ONLY_NOT_REDUCTION_QUALIFIED",
            "amortized_gross_energy_per_batch_mj": gross_energy_mj
            / args.batch_count,
            "amortized_incremental_energy_per_batch_mj": incremental_energy_mj
            / args.batch_count,
            "amortized_incremental_energy_uncertainty_per_batch_mj": incremental_energy_uncertainty_mj
            / args.batch_count,
            "cycle_delta_total": args.cycle_delta,
            "cycles_per_batch_amortized": args.cycle_delta / args.batch_count,
            "cycle_time_s": args.cycle_delta / args.cycle_frequency_hz,
            "standalone_duration_checks": standalone_duration_checks,
        }
        result = {
            "schema": SUMMARY_SCHEMA,
            "qualification": "QUALIFIED_BOARD_MEASUREMENT_V2",
            "endpoint": args.endpoint,
            "scenario": args.scenario,
            "trial_id": trial_id,
            "pair_id": pair_id,
            "batch_count": args.batch_count,
            "provenance": provenance,
            "conditions": conditions,
            "integrator": integrator,
            "verification": verification,
            "active_trace": active_trace,
            "idle_trace": idle_trace,
            "metrics": metrics,
        }
        rendered = json.dumps(result, indent=2, sort_keys=True, allow_nan=False)
    except (OSError, UnicodeError, ValueError) as exc:
        parser.error(str(exc))

    if args.output:
        args.output.write_text(rendered + "\n", encoding="utf-8")
    print(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
