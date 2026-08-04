#!/usr/bin/env python3
"""Validate and compare paired VV35 SERIAL/INTERLEAVED board summaries."""

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
COMPARISON_SCHEMA = "vv35-board-paired-comparison-v2"
RESULT_EVIDENCE_SCHEMA = "vv35-vio-result-evidence-v1"
STANDALONE_EVIDENCE_SCHEMA = "vv35-standalone-pl-vio-csv-row-v1"
INTEGRATOR_SCHEMA = "vv35-board-trace-integrator-v2"
INTEGRATOR_VERSION = "2.0.0"
INTEGRATION_ALGORITHM = "per_rail_trapezoidal_complete_common_grid_v1"
MIN_MARKED_SAMPLES_PER_RAIL = 1000
SAMPLE_RATE_REL_TOLERANCE = 0.10
STANDALONE_MARKER_DURATION_REL_TOLERANCE = 0.01
TEMPERATURE_TOLERANCE_C = 1.0

RESULT_MAGIC_HEX = "0x565633354c414231"
EXPECTED_HMATCH_PER_BATCH = 1632
EXPECTED_HMATCH_RESULT_HEX = "0x1f9"
EXPECTED_FINAL_STATUS_LOW_NIBBLE = 0x8
RUN_MODE_BY_SCENARIO = {"SERIAL": 0, "INTERLEAVED": 1}
ENDPOINTS = {"standalone_pl_vio", "cva6_result_block"}
STANDALONE_WINDOW_CYCLES = {"SERIAL": 337853, "INTERLEAVED": 200144}
STANDALONE_HMATCH_COMPLETION_CYCLES = {"SERIAL": 337853, "INTERLEAVED": 200114}
STANDALONE_IDLE_WINDOW_CYCLES = 2_000_000
STANDALONE_PRELOAD_COUNT = 112
STANDALONE_FINAL_STATUS = 0x48
SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")

EXPECTED_INTEGRATOR_PARAMETERS = {
    "minimum_marked_samples_per_rail": MIN_MARKED_SAMPLES_PER_RAIL,
    "sample_rate_relative_tolerance": SAMPLE_RATE_REL_TOLERANCE,
    "standalone_marker_duration_relative_tolerance": STANDALONE_MARKER_DURATION_REL_TOLERANCE,
    "marker_policy": "one_contiguous_high_window_bounded_by_low_samples",
    "timestamp_policy": "original_order_unique_groups_strictly_increasing",
    "rail_policy": "complete_common_grid_unique_rail_per_timestamp",
    "power_policy": "one_nonnegative_finite_input_mode_per_trace",
    "idle_policy": "same_marker_threshold_as_active",
}


def require_dict(parent: dict[str, Any], field: str, label: str) -> dict[str, Any]:
    value = parent.get(field)
    if not isinstance(value, dict):
        raise ValueError(f"{label}.{field} must be an object")
    return value


def require_string(parent: dict[str, Any], field: str, label: str) -> str:
    value = parent.get(field)
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{label}.{field} must be a non-empty string")
    return value


def require_int(
    parent: dict[str, Any], field: str, label: str, *, positive: bool = False
) -> int:
    value = parent.get(field)
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValueError(f"{label}.{field} must be an integer")
    if positive and value <= 0:
        raise ValueError(f"{label}.{field} must be positive")
    return value


def require_number(
    parent: dict[str, Any], field: str, label: str, *, positive: bool = False
) -> float:
    value = parent.get(field)
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{label}.{field} must be numeric")
    number = float(value)
    if not math.isfinite(number):
        raise ValueError(f"{label}.{field} must be finite")
    if positive and number <= 0:
        raise ValueError(f"{label}.{field} must be positive")
    return number


def require_sha256(parent: dict[str, Any], field: str, label: str) -> str:
    value = require_string(parent, field, label)
    if not SHA256_RE.fullmatch(value):
        raise ValueError(
            f"{label}.{field} must be lowercase, 64-character hexadecimal SHA-256"
        )
    return value


def require_close(label: str, actual: float, expected: float) -> None:
    if not math.isclose(actual, expected, rel_tol=1e-9, abs_tol=1e-12):
        raise ValueError(f"{label} is internally inconsistent: {actual} != {expected}")


def load_summary(path: Path) -> tuple[dict[str, Any], str]:
    raw = path.read_bytes()
    raw_sha256 = hashlib.sha256(raw).hexdigest()
    try:
        parsed = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"{path}: invalid UTF-8 JSON: {exc}") from exc
    if not isinstance(parsed, dict):
        raise ValueError(f"{path}: top-level JSON value must be an object")
    return parsed, raw_sha256


def validate_integrator(summary: dict[str, Any], label: str) -> dict[str, Any]:
    integrator = require_dict(summary, "integrator", label)
    if require_string(integrator, "schema", f"{label}.integrator") != INTEGRATOR_SCHEMA:
        raise ValueError(f"{label}.integrator.schema is unsupported")
    if require_string(integrator, "version", f"{label}.integrator") != INTEGRATOR_VERSION:
        raise ValueError(f"{label}.integrator.version is unsupported")
    if (
        require_string(integrator, "algorithm", f"{label}.integrator")
        != INTEGRATION_ALGORITHM
    ):
        raise ValueError(f"{label}.integrator.algorithm is unsupported")
    parameters = require_dict(integrator, "parameters", f"{label}.integrator")
    marker_threshold = require_number(
        parameters, "marker_threshold", f"{label}.integrator.parameters"
    )
    del marker_threshold
    for field, expected in EXPECTED_INTEGRATOR_PARAMETERS.items():
        if parameters.get(field) != expected:
            raise ValueError(
                f"{label}.integrator.parameters.{field} does not match the v2 contract"
            )
    return integrator


def validate_conditions(summary: dict[str, Any], label: str) -> dict[str, Any]:
    conditions = require_dict(summary, "conditions", label)
    endpoint = require_string(summary, "endpoint", label)
    for field in (
        "board_id",
        "clock_config",
        "voltage_config",
        "instrument_model",
        "rail_scope",
        "cycle_counter_kind",
        "cpu_hdec_clock_relation",
    ):
        require_string(conditions, field, f"{label}.conditions")
    require_number(conditions, "temperature_c", f"{label}.conditions")
    nominal_sample_rate_hz = require_number(
        conditions,
        "nominal_sample_rate_hz",
        f"{label}.conditions",
        positive=True,
    )
    cycle_frequency_hz = require_number(
        conditions,
        "cycle_frequency_hz",
        f"{label}.conditions",
        positive=True,
    )
    hdec_frequency_hz = require_number(
        conditions,
        "hdec_frequency_hz",
        f"{label}.conditions",
        positive=True,
    )
    if endpoint == "standalone_pl_vio":
        if conditions["cycle_counter_kind"] != "standalone_hdec_window_cycles":
            raise ValueError(f"{label}.conditions has wrong standalone cycle counter")
        if conditions["cpu_hdec_clock_relation"] != "not_applicable_standalone_pl":
            raise ValueError(f"{label}.conditions claims a CPU for standalone PL")
        if conditions.get("pmul_wait_cycles") is not None:
            raise ValueError(f"{label}.conditions has PMUL wait for standalone PL")
        require_close(
            f"{label}.conditions standalone HDEC frequency",
            cycle_frequency_hz,
            hdec_frequency_hz,
        )
    else:
        if conditions["cycle_counter_kind"] != "cpu_rdcycle":
            raise ValueError(f"{label}.conditions has wrong CVA6 cycle counter")
        require_int(
            conditions, "pmul_wait_cycles", f"{label}.conditions", positive=True
        )
    if conditions["cpu_hdec_clock_relation"] == "same_frequency_ungated":
        require_close(
            f"{label}.conditions same-frequency clocks",
            cycle_frequency_hz,
            hdec_frequency_hz,
        )
    del nominal_sample_rate_hz
    return conditions


def validate_trace(
    trace: dict[str, Any], label: str, nominal_sample_rate_hz: float
) -> tuple[list[str], str]:
    trace_path = Path(require_string(trace, "path", label))
    declared_raw_sha256 = require_sha256(trace, "raw_sha256", label)
    try:
        actual_raw_sha256 = hashlib.sha256(trace_path.read_bytes()).hexdigest()
    except OSError as exc:
        raise ValueError(f"{label}.path cannot be read: {exc}") from exc
    if actual_raw_sha256 != declared_raw_sha256:
        raise ValueError(f"{label}.raw_sha256 does not match the raw trace file")
    rails = trace.get("rail_names")
    if not isinstance(rails, list) or not rails:
        raise ValueError(f"{label}.rail_names must be a non-empty list")
    if any(not isinstance(rail, str) or not rail.strip() for rail in rails):
        raise ValueError(f"{label}.rail_names contains an invalid rail")
    if rails != sorted(set(rails)):
        raise ValueError(f"{label}.rail_names must be sorted and unique")
    power_input_mode = require_string(trace, "power_input_mode", label)
    if power_input_mode not in {"power_w", "voltage_v_x_current_a"}:
        raise ValueError(f"{label}.power_input_mode is unsupported")

    full_timestamp_count = require_int(
        trace, "full_timestamp_count", label, positive=True
    )
    full_sample_count_total = require_int(
        trace, "full_sample_count_total", label, positive=True
    )
    marked_timestamp_count = require_int(
        trace, "marked_timestamp_count_per_rail", label, positive=True
    )
    marked_sample_count_total = require_int(
        trace, "marked_sample_count_total", label, positive=True
    )
    if marked_timestamp_count < MIN_MARKED_SAMPLES_PER_RAIL:
        raise ValueError(
            f"{label} has fewer than {MIN_MARKED_SAMPLES_PER_RAIL} marked samples per rail"
        )
    if full_timestamp_count < marked_timestamp_count + 2:
        raise ValueError(f"{label} lacks low marker samples on both sides")
    if full_sample_count_total != full_timestamp_count * len(rails):
        raise ValueError(f"{label}.full_sample_count_total does not match its rail grid")
    if marked_sample_count_total != marked_timestamp_count * len(rails):
        raise ValueError(f"{label}.marked_sample_count_total does not match its rail grid")

    low_before = require_number(trace, "marker_low_before_s", label)
    start = require_number(trace, "marker_start_s", label)
    end = require_number(trace, "marker_end_s", label)
    low_after = require_number(trace, "marker_low_after_s", label)
    duration = require_number(trace, "marker_duration_s", label, positive=True)
    if not low_before < start < end < low_after:
        raise ValueError(f"{label} marker boundary timestamps are not strictly ordered")
    require_close(f"{label}.marker_duration_s", duration, end - start)

    observed_sample_rate_hz = require_number(
        trace, "observed_sample_rate_hz", label, positive=True
    )
    expected_observed_rate = (marked_timestamp_count - 1) / duration
    require_close(
        f"{label}.observed_sample_rate_hz",
        observed_sample_rate_hz,
        expected_observed_rate,
    )
    if (
        abs(observed_sample_rate_hz - nominal_sample_rate_hz)
        / nominal_sample_rate_hz
        > SAMPLE_RATE_REL_TOLERANCE
    ):
        raise ValueError(f"{label} observed sample rate violates the v2 tolerance")

    average_power_w = require_number(
        trace, "average_power_w", label, positive=True
    )
    energy_mj = require_number(trace, "energy_mj", label, positive=True)
    require_close(
        f"{label}.energy_mj", energy_mj, average_power_w * duration * 1e3
    )
    per_rail = require_dict(trace, "per_rail", label)
    if sorted(per_rail) != rails:
        raise ValueError(f"{label}.per_rail keys do not match rail_names")
    summed_average_power_w = 0.0
    summed_energy_mj = 0.0
    for rail in rails:
        rail_summary = per_rail.get(rail)
        if not isinstance(rail_summary, dict):
            raise ValueError(f"{label}.per_rail[{rail!r}] must be an object")
        rail_average = require_number(
            rail_summary,
            "average_power_w",
            f"{label}.per_rail[{rail!r}]",
            positive=True,
        )
        rail_energy = require_number(
            rail_summary,
            "energy_mj",
            f"{label}.per_rail[{rail!r}]",
            positive=True,
        )
        require_close(
            f"{label}.per_rail[{rail!r}].energy_mj",
            rail_energy,
            rail_average * duration * 1e3,
        )
        summed_average_power_w += rail_average
        summed_energy_mj += rail_energy
    require_close(f"{label}.average_power_w", average_power_w, summed_average_power_w)
    require_close(f"{label}.energy_mj", energy_mj, summed_energy_mj)
    return rails, power_input_mode


def validate_verification(
    summary: dict[str, Any], label: str, scenario: str, batch_count: int
) -> dict[str, Any]:
    verification = require_dict(summary, "verification", label)
    endpoint = summary["endpoint"]
    if require_string(verification, "status", f"{label}.verification") != "PASS":
        raise ValueError(f"{label}.verification.status is not PASS")
    expected_source = (
        "standalone_pl_vio_csv"
        if endpoint == "standalone_pl_vio"
        else "cva6_result_evidence_json"
    )
    if require_string(verification, "source", f"{label}.verification") != expected_source:
        raise ValueError(f"{label}.verification.source does not match endpoint")
    if verification.get("vio_pass") is not True:
        raise ValueError(f"{label}.verification.vio_pass must be true")
    result_evidence_sha256 = require_sha256(
        verification, "result_evidence_sha256", f"{label}.verification"
    )
    evidence_record_sha256 = require_sha256(
        verification, "evidence_record_sha256", f"{label}.verification"
    )
    evidence_path = Path(
        require_string(verification, "evidence_path", f"{label}.verification")
    )
    try:
        evidence_raw = evidence_path.read_bytes()
    except OSError as exc:
        raise ValueError(f"{label} result evidence file cannot be read: {exc}") from exc
    if hashlib.sha256(evidence_raw).hexdigest() != result_evidence_sha256:
        raise ValueError(f"{label} result evidence SHA-256 mismatch")
    evidence_payload = require_dict(
        verification, "evidence_payload", f"{label}.verification"
    )
    if endpoint == "cva6_result_block":
        try:
            evidence_from_file = json.loads(evidence_raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as exc:
            raise ValueError(f"{label} result evidence file is invalid JSON: {exc}") from exc
        if evidence_from_file != evidence_payload:
            raise ValueError(f"{label} stored VIO payload differs from its evidence file")
        if evidence_payload.get("schema") != RESULT_EVIDENCE_SCHEMA:
            raise ValueError(f"{label} result evidence schema is unsupported")
        if (
            evidence_payload.get("status") != "PASS"
            or evidence_payload.get("vio_pass") is not True
        ):
            raise ValueError(f"{label} result evidence payload is not explicit PASS")
        if evidence_record_sha256 != result_evidence_sha256:
            raise ValueError(f"{label} CVA6 evidence record hash mismatch")
    else:
        if evidence_payload.get("schema") != STANDALONE_EVIDENCE_SCHEMA:
            raise ValueError(f"{label} standalone evidence schema is unsupported")
        selected_row = evidence_payload.get("selected_row")
        selected_idle_row = evidence_payload.get("selected_idle_row")
        selector = evidence_payload.get("selector")
        if (
            not isinstance(selected_row, dict)
            or not isinstance(selected_idle_row, dict)
            or not isinstance(selector, dict)
        ):
            raise ValueError(f"{label} standalone evidence payload is malformed")
        try:
            decoded = evidence_raw.decode("utf-8-sig")
        except UnicodeDecodeError as exc:
            raise ValueError(f"{label} standalone evidence is not UTF-8 CSV") from exc
        rows = [
            {key: value.strip() for key, value in row.items()}
            for row in csv.DictReader(io.StringIO(decoded, newline=""))
        ]
        if sum(row == selected_row for row in rows) != 1:
            raise ValueError(f"{label} selected VIO row is not unique in evidence CSV")
        if sum(row == selected_idle_row for row in rows) != 1:
            raise ValueError(f"{label} selected idle VIO row is not unique in evidence CSV")
        record_bytes = json.dumps(
            {"active": selected_row, "idle": selected_idle_row},
            sort_keys=True,
            separators=(",", ":"),
            ensure_ascii=True,
        ).encode("ascii")
        if hashlib.sha256(record_bytes).hexdigest() != evidence_record_sha256:
            raise ValueError(f"{label} standalone evidence record SHA-256 mismatch")
        if selector.get("scenario") != scenario or selected_row.get("scenario") != scenario:
            raise ValueError(f"{label} standalone scenario selector mismatch")
        required_vio_values = {
            "requested_mode": str(RUN_MODE_BY_SCENARIO[scenario]),
            "actual_mode": str(RUN_MODE_BY_SCENARIO[scenario]),
            "snapshot_valid": "1",
            "pass": "1",
            "fail": "0",
            "idle": "1",
            "busy": "0",
            "metric_active": "0",
            "validation": "PASS",
        }
        for field, expected in required_vio_values.items():
            if selected_row.get(field) != expected:
                raise ValueError(f"{label} standalone VIO field {field} mismatch")
        idle_required_vio_values = {
            "requested_mode": "2",
            "actual_mode": "2",
            "snapshot_valid": "1",
            "pass": "1",
            "fail": "0",
            "idle": "1",
            "busy": "0",
            "metric_active": "0",
            "validation": "PASS",
        }
        if selected_idle_row.get("scenario") not in {
            "CLOCKED_IDLE",
            "CLOCKED_IDLE_SPIN",
        }:
            raise ValueError(f"{label} selected idle row has wrong scenario")
        for field, expected in idle_required_vio_values.items():
            if selected_idle_row.get(field) != expected:
                raise ValueError(f"{label} standalone idle VIO field {field} mismatch")

    result_block = require_dict(verification, "result_block", f"{label}.verification")
    if endpoint == "cva6_result_block":
        if (
            require_string(result_block, "magic_hex", f"{label}.result_block")
            != RESULT_MAGIC_HEX
        ):
            raise ValueError(f"{label} result-block magic mismatch")
    elif result_block.get("magic_hex") is not None:
        raise ValueError(f"{label} standalone VIO evidence must not invent magic")
    if require_int(result_block, "error_count", f"{label}.result_block") != 0:
        raise ValueError(f"{label} result-block error count is nonzero")
    if (
        require_int(result_block, "run_mode", f"{label}.result_block")
        != RUN_MODE_BY_SCENARIO[scenario]
    ):
        raise ValueError(f"{label} result-block run mode mismatch")
    if require_int(result_block, "batch_count", f"{label}.result_block") != batch_count:
        raise ValueError(f"{label} result-block batch count mismatch")
    if (
        require_int(result_block, "hmatch_per_batch", f"{label}.result_block")
        != EXPECTED_HMATCH_PER_BATCH
    ):
        raise ValueError(f"{label} result-block HMATCH-per-batch mismatch")
    if (
        require_int(result_block, "hmatch_completions", f"{label}.result_block")
        != EXPECTED_HMATCH_PER_BATCH * batch_count
    ):
        raise ValueError(f"{label} result-block HMATCH completion mismatch")
    if (
        require_string(result_block, "last_hmatch_hex", f"{label}.result_block")
        != EXPECTED_HMATCH_RESULT_HEX
    ):
        raise ValueError(f"{label} result-block last HMATCH mismatch")
    final_status_hex = require_string(
        result_block, "final_status_hex", f"{label}.result_block"
    )
    try:
        final_status = int(final_status_hex, 0)
    except ValueError as exc:
        raise ValueError(f"{label} result-block final status is invalid") from exc
    if final_status < 0:
        raise ValueError(f"{label} result-block final status must be nonnegative")
    if final_status & 0xF != EXPECTED_FINAL_STATUS_LOW_NIBBLE:
        raise ValueError(f"{label} result-block final status low nibble mismatch")
    if (
        require_int(result_block, "final_status_low_nibble", f"{label}.result_block")
        != EXPECTED_FINAL_STATUS_LOW_NIBBLE
    ):
        raise ValueError(f"{label} result-block decoded status mismatch")

    active_trace = require_dict(summary, "active_trace", label)
    if endpoint == "cva6_result_block":
        payload_bindings = {
            "trial_id": summary["trial_id"],
            "pair_id": summary["pair_id"],
            "scenario": scenario,
            "active_trace_sha256": require_sha256(
                active_trace, "raw_sha256", f"{label}.active_trace"
            ),
        }
        for field, expected in payload_bindings.items():
            if evidence_payload.get(field) != expected:
                raise ValueError(f"{label} result evidence {field} binding mismatch")

    binding = require_dict(verification, "binding", f"{label}.verification")
    if require_string(binding, "endpoint", f"{label}.binding") != endpoint:
        raise ValueError(f"{label} VIO binding endpoint mismatch")
    if require_string(binding, "trial_id", f"{label}.binding") != summary["trial_id"]:
        raise ValueError(f"{label} VIO binding trial_id mismatch")
    if require_string(binding, "pair_id", f"{label}.binding") != summary["pair_id"]:
        raise ValueError(f"{label} VIO binding pair_id mismatch")
    if require_string(binding, "scenario", f"{label}.binding") != scenario:
        raise ValueError(f"{label} VIO binding scenario mismatch")
    if (
        require_sha256(binding, "active_trace_sha256", f"{label}.binding")
        != require_sha256(active_trace, "raw_sha256", f"{label}.active_trace")
    ):
        raise ValueError(f"{label} VIO binding active trace hash mismatch")
    if (
        require_sha256(binding, "result_evidence_sha256", f"{label}.binding")
        != result_evidence_sha256
    ):
        raise ValueError(f"{label} VIO binding result evidence hash mismatch")
    if (
        require_sha256(binding, "evidence_record_sha256", f"{label}.binding")
        != evidence_record_sha256
    ):
        raise ValueError(f"{label} VIO binding evidence record hash mismatch")
    return verification


def validate_metrics(
    summary: dict[str, Any], label: str, batch_count: int
) -> dict[str, Any]:
    metrics = require_dict(summary, "metrics", label)
    active_trace = require_dict(summary, "active_trace", label)
    idle_trace = require_dict(summary, "idle_trace", label)

    duration = require_number(metrics, "marker_duration_s", f"{label}.metrics", positive=True)
    gross_average = require_number(
        metrics, "gross_average_power_w", f"{label}.metrics", positive=True
    )
    idle_average = require_number(
        metrics, "idle_average_power_w", f"{label}.metrics", positive=True
    )
    incremental_average = require_number(
        metrics, "incremental_average_power_w", f"{label}.metrics"
    )
    gross_energy = require_number(
        metrics, "gross_energy_mj", f"{label}.metrics", positive=True
    )
    idle_energy = require_number(
        metrics,
        "idle_energy_over_active_window_mj",
        f"{label}.metrics",
        positive=True,
    )
    incremental_energy = require_number(
        metrics, "incremental_energy_mj", f"{label}.metrics"
    )
    gross_per_batch = require_number(
        metrics,
        "amortized_gross_energy_per_batch_mj",
        f"{label}.metrics",
        positive=True,
    )
    incremental_per_batch = require_number(
        metrics,
        "amortized_incremental_energy_per_batch_mj",
        f"{label}.metrics",
    )
    cycle_total = require_int(
        metrics, "cycle_delta_total", f"{label}.metrics", positive=True
    )
    cycles_per_batch = require_number(
        metrics,
        "cycles_per_batch_amortized",
        f"{label}.metrics",
        positive=True,
    )
    cycle_time = require_number(
        metrics, "cycle_time_s", f"{label}.metrics", positive=True
    )

    for field in (
        "active_power_uncertainty_w",
        "idle_power_uncertainty_w",
        "incremental_power_uncertainty_w",
        "gross_energy_uncertainty_mj",
        "idle_energy_uncertainty_mj",
        "incremental_energy_uncertainty_mj",
        "amortized_incremental_energy_uncertainty_per_batch_mj",
    ):
        if require_number(metrics, field, f"{label}.metrics") < 0:
            raise ValueError(f"{label}.metrics.{field} must be nonnegative")
    incremental_reduction_eligible = metrics.get("incremental_reduction_eligible")
    if not isinstance(incremental_reduction_eligible, bool):
        raise ValueError(
            f"{label}.metrics.incremental_reduction_eligible must be boolean"
        )
    expected_incremental_qualification = (
        "POSITIVE_ABOVE_UNCERTAINTY"
        if incremental_reduction_eligible
        else "SIGNED_VALUE_ONLY_NOT_REDUCTION_QUALIFIED"
    )
    if (
        require_string(metrics, "incremental_qualification", f"{label}.metrics")
        != expected_incremental_qualification
    ):
        raise ValueError(f"{label}.metrics incremental qualification mismatch")

    require_close(
        f"{label}.metrics.marker_duration_s",
        duration,
        require_number(active_trace, "marker_duration_s", f"{label}.active_trace"),
    )
    require_close(
        f"{label}.metrics.gross_average_power_w",
        gross_average,
        require_number(active_trace, "average_power_w", f"{label}.active_trace"),
    )
    require_close(
        f"{label}.metrics.idle_average_power_w",
        idle_average,
        require_number(idle_trace, "average_power_w", f"{label}.idle_trace"),
    )
    require_close(
        f"{label}.metrics.incremental_average_power_w",
        incremental_average,
        gross_average - idle_average,
    )
    require_close(
        f"{label}.metrics.gross_energy_mj",
        gross_energy,
        require_number(active_trace, "energy_mj", f"{label}.active_trace"),
    )
    require_close(
        f"{label}.metrics.idle_energy_over_active_window_mj",
        idle_energy,
        idle_average * duration * 1e3,
    )
    require_close(
        f"{label}.metrics.incremental_energy_mj",
        incremental_energy,
        gross_energy - idle_energy,
    )
    require_close(
        f"{label}.metrics.amortized_gross_energy_per_batch_mj",
        gross_per_batch,
        gross_energy / batch_count,
    )
    require_close(
        f"{label}.metrics.amortized_incremental_energy_per_batch_mj",
        incremental_per_batch,
        incremental_energy / batch_count,
    )
    require_close(
        f"{label}.metrics.cycles_per_batch_amortized",
        cycles_per_batch,
        cycle_total / batch_count,
    )
    cycle_frequency_hz = require_number(
        require_dict(summary, "conditions", label),
        "cycle_frequency_hz",
        f"{label}.conditions",
        positive=True,
    )
    require_close(
        f"{label}.metrics.cycle_time_s",
        cycle_time,
        cycle_total / cycle_frequency_hz,
    )
    duration_checks = require_dict(
        metrics, "standalone_duration_checks", f"{label}.metrics"
    )
    endpoint = summary["endpoint"]
    if endpoint == "standalone_pl_vio":
        if (
            require_string(duration_checks, "qualification", f"{label}.duration_checks")
            != "MATCHES_STANDALONE_CYCLE_WINDOWS"
        ):
            raise ValueError(f"{label} standalone duration qualification mismatch")
        expected_active_duration = cycle_total / cycle_frequency_hz
        hdec_frequency_hz = require_number(
            require_dict(summary, "conditions", label),
            "hdec_frequency_hz",
            f"{label}.conditions",
            positive=True,
        )
        expected_idle_duration = STANDALONE_IDLE_WINDOW_CYCLES / hdec_frequency_hz
        active_error = require_number(
            duration_checks, "active_duration_error_s", f"{label}.duration_checks"
        )
        idle_error = require_number(
            duration_checks, "idle_duration_error_s", f"{label}.duration_checks"
        )
        require_close(
            f"{label}.duration_checks.expected_active_duration_s",
            require_number(
                duration_checks,
                "expected_active_duration_s",
                f"{label}.duration_checks",
                positive=True,
            ),
            expected_active_duration,
        )
        require_close(
            f"{label}.duration_checks.expected_idle_duration_s",
            require_number(
                duration_checks,
                "expected_idle_duration_s",
                f"{label}.duration_checks",
                positive=True,
            ),
            expected_idle_duration,
        )
        require_close(
            f"{label}.duration_checks.active_duration_error_s",
            active_error,
            duration - expected_active_duration,
        )
        idle_duration = require_number(
            idle_trace, "marker_duration_s", f"{label}.idle_trace", positive=True
        )
        require_close(
            f"{label}.duration_checks.idle_duration_error_s",
            idle_error,
            idle_duration - expected_idle_duration,
        )
        active_tolerance = max(
            2.0
            / require_number(
                active_trace,
                "observed_sample_rate_hz",
                f"{label}.active_trace",
                positive=True,
            ),
            expected_active_duration * STANDALONE_MARKER_DURATION_REL_TOLERANCE,
        )
        idle_tolerance = max(
            2.0
            / require_number(
                idle_trace,
                "observed_sample_rate_hz",
                f"{label}.idle_trace",
                positive=True,
            ),
            expected_idle_duration * STANDALONE_MARKER_DURATION_REL_TOLERANCE,
        )
        if abs(active_error) > active_tolerance or abs(idle_error) > idle_tolerance:
            raise ValueError(f"{label} standalone marker duration exceeds tolerance")
    else:
        if (
            require_string(duration_checks, "qualification", f"{label}.duration_checks")
            != "NOT_APPLICABLE_CVA6_MARKER_AND_RDCYCLE_BOUNDARIES_DIFFER"
        ):
            raise ValueError(f"{label} CVA6 duration qualification mismatch")
        for field in (
            "expected_active_duration_s",
            "active_duration_error_s",
            "expected_idle_duration_s",
            "idle_duration_error_s",
        ):
            if duration_checks.get(field) is not None:
                raise ValueError(f"{label}.duration_checks.{field} must be null")
    return metrics


def validate_summary(
    summary: dict[str, Any], expected_scenario: str, label: str
) -> dict[str, Any]:
    if require_string(summary, "schema", label) != SUMMARY_SCHEMA:
        raise ValueError(f"{label}.schema must be {SUMMARY_SCHEMA}")
    if (
        require_string(summary, "qualification", label)
        != "QUALIFIED_BOARD_MEASUREMENT_V2"
    ):
        raise ValueError(f"{label}.qualification is not qualified v2 board data")
    scenario = require_string(summary, "scenario", label)
    if scenario != expected_scenario:
        raise ValueError(f"{label}.scenario must be {expected_scenario}")
    require_string(summary, "trial_id", label)
    require_string(summary, "pair_id", label)
    batch_count = require_int(summary, "batch_count", label, positive=True)

    endpoint = require_string(summary, "endpoint", label)
    if endpoint not in ENDPOINTS:
        raise ValueError(f"{label}.endpoint is unsupported")
    provenance = require_dict(summary, "provenance", label)
    require_sha256(provenance, "bitstream_sha256", f"{label}.provenance")
    require_sha256(provenance, "vector_bundle_sha256", f"{label}.provenance")
    if endpoint == "standalone_pl_vio":
        if provenance.get("firmware_sha256") is not None:
            raise ValueError(f"{label}.provenance invents standalone firmware")
    else:
        require_sha256(provenance, "firmware_sha256", f"{label}.provenance")
    conditions = validate_conditions(summary, label)
    validate_integrator(summary, label)

    nominal_sample_rate_hz = require_number(
        conditions,
        "nominal_sample_rate_hz",
        f"{label}.conditions",
        positive=True,
    )
    active_trace = require_dict(summary, "active_trace", label)
    idle_trace = require_dict(summary, "idle_trace", label)
    active_rails, active_power_mode = validate_trace(
        active_trace, f"{label}.active_trace", nominal_sample_rate_hz
    )
    idle_rails, idle_power_mode = validate_trace(
        idle_trace, f"{label}.idle_trace", nominal_sample_rate_hz
    )
    if active_rails != idle_rails:
        raise ValueError(f"{label} active and idle rail sets differ")
    if active_power_mode != idle_power_mode:
        raise ValueError(f"{label} active and idle power input modes differ")
    if active_trace["raw_sha256"] == idle_trace["raw_sha256"]:
        raise ValueError(f"{label} active and idle traces reuse the same raw capture")

    validate_verification(summary, label, scenario, batch_count)
    validate_metrics(summary, label, batch_count)
    return summary


def reduction(serial: float, interleaved: float) -> float:
    if serial <= 0 or interleaved <= 0:
        raise ValueError("comparison inputs must be positive")
    return (serial - interleaved) / serial


def optional_incremental_reduction(
    serial: float, interleaved: float, *, qualified: bool
) -> float | None:
    if not qualified:
        return None
    return reduction(serial, interleaved)


def trace_without_path(trace: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in trace.items() if key != "path"}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("serial", type=Path)
    parser.add_argument("interleaved", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    try:
        serial, serial_summary_sha256 = load_summary(args.serial)
        interleaved, interleaved_summary_sha256 = load_summary(args.interleaved)
        validate_summary(serial, "SERIAL", "serial")
        validate_summary(interleaved, "INTERLEAVED", "interleaved")

        if serial["pair_id"] != interleaved["pair_id"]:
            raise ValueError("paired board summaries use different pair_id values")
        if serial["trial_id"] == interleaved["trial_id"]:
            raise ValueError("SERIAL and INTERLEAVED must have distinct trial_id values")
        if serial["batch_count"] != interleaved["batch_count"]:
            raise ValueError("paired board summaries use different batch_count values")
        if serial["provenance"] != interleaved["provenance"]:
            raise ValueError("paired board summaries differ in image/vector provenance")
        serial_conditions = serial["conditions"]
        interleaved_conditions = interleaved["conditions"]
        serial_temperature_c = float(serial_conditions["temperature_c"])
        interleaved_temperature_c = float(interleaved_conditions["temperature_c"])
        serial_fixed_conditions = {
            key: value
            for key, value in serial_conditions.items()
            if key != "temperature_c"
        }
        interleaved_fixed_conditions = {
            key: value
            for key, value in interleaved_conditions.items()
            if key != "temperature_c"
        }
        if serial_fixed_conditions != interleaved_fixed_conditions:
            raise ValueError("paired board summaries differ in fixed physical conditions")
        temperature_difference_c = abs(
            serial_temperature_c - interleaved_temperature_c
        )
        if temperature_difference_c > TEMPERATURE_TOLERANCE_C:
            raise ValueError(
                "paired board summaries exceed the allowed temperature difference"
            )
        if serial["integrator"] != interleaved["integrator"]:
            raise ValueError("paired board summaries differ in integrator or parameters")

        serial_active = serial["active_trace"]
        interleaved_active = interleaved["active_trace"]
        serial_idle = serial["idle_trace"]
        interleaved_idle = interleaved["idle_trace"]
        if serial_active["rail_names"] != interleaved_active["rail_names"]:
            raise ValueError("paired board summaries use different active rail sets")
        if serial_active["power_input_mode"] != interleaved_active["power_input_mode"]:
            raise ValueError("paired board summaries use different power input modes")
        if serial_active["raw_sha256"] == interleaved_active["raw_sha256"]:
            raise ValueError("SERIAL and INTERLEAVED reuse the same active raw trace")
        if serial_idle["raw_sha256"] != interleaved_idle["raw_sha256"]:
            raise ValueError("paired board summaries do not use the same idle raw trace")
        if trace_without_path(serial_idle) != trace_without_path(interleaved_idle):
            raise ValueError("paired board summaries disagree on the shared idle trace")

        serial_verification = serial["verification"]
        interleaved_verification = interleaved["verification"]
        if (
            serial_verification["evidence_record_sha256"]
            == interleaved_verification["evidence_record_sha256"]
        ):
            raise ValueError("SERIAL and INTERLEAVED reuse the same selected VIO record")

        serial_metrics = serial["metrics"]
        interleaved_metrics = interleaved["metrics"]
        serial_cycles = float(serial_metrics["cycle_delta_total"])
        interleaved_cycles = float(interleaved_metrics["cycle_delta_total"])
        serial_cycles_per_batch = float(
            serial_metrics["cycles_per_batch_amortized"]
        )
        interleaved_cycles_per_batch = float(
            interleaved_metrics["cycles_per_batch_amortized"]
        )
        serial_gross_energy = float(
            serial_metrics["amortized_gross_energy_per_batch_mj"]
        )
        interleaved_gross_energy = float(
            interleaved_metrics["amortized_gross_energy_per_batch_mj"]
        )
        serial_incremental_energy = float(
            serial_metrics["amortized_incremental_energy_per_batch_mj"]
        )
        interleaved_incremental_energy = float(
            interleaved_metrics["amortized_incremental_energy_per_batch_mj"]
        )
        serial_gross_power = float(serial_metrics["gross_average_power_w"])
        interleaved_gross_power = float(interleaved_metrics["gross_average_power_w"])
        serial_incremental_power = float(
            serial_metrics["incremental_average_power_w"]
        )
        interleaved_incremental_power = float(
            interleaved_metrics["incremental_average_power_w"]
        )
        incremental_reduction_qualified = bool(
            serial_metrics["incremental_reduction_eligible"]
            and interleaved_metrics["incremental_reduction_eligible"]
        )

        result = {
            "schema": COMPARISON_SCHEMA,
            "qualification": "QUALIFIED_PER_PAIR_BOARD_COMPARISON_V2",
            "pair_id": serial["pair_id"],
            "serial_trial_id": serial["trial_id"],
            "interleaved_trial_id": interleaved["trial_id"],
            "batch_count": serial["batch_count"],
            "serial_summary_sha256": serial_summary_sha256,
            "interleaved_summary_sha256": interleaved_summary_sha256,
            "serial_active_trace_sha256": serial_active["raw_sha256"],
            "interleaved_active_trace_sha256": interleaved_active["raw_sha256"],
            "shared_idle_trace_sha256": serial_idle["raw_sha256"],
            "serial_result_evidence_sha256": serial_verification[
                "result_evidence_sha256"
            ],
            "interleaved_result_evidence_sha256": interleaved_verification[
                "result_evidence_sha256"
            ],
            "serial_evidence_record_sha256": serial_verification[
                "evidence_record_sha256"
            ],
            "interleaved_evidence_record_sha256": interleaved_verification[
                "evidence_record_sha256"
            ],
            "rail_names": serial_active["rail_names"],
            "provenance": serial["provenance"],
            "conditions": {
                **serial_fixed_conditions,
                "serial_temperature_c": serial_temperature_c,
                "interleaved_temperature_c": interleaved_temperature_c,
                "temperature_difference_c": temperature_difference_c,
                "temperature_tolerance_c": TEMPERATURE_TOLERANCE_C,
            },
            "integrator": serial["integrator"],
            "metrics": {
                "serial_cycle_delta_total": serial_cycles,
                "interleaved_cycle_delta_total": interleaved_cycles,
                "serial_cycles_per_batch_amortized": serial_cycles_per_batch,
                "interleaved_cycles_per_batch_amortized": interleaved_cycles_per_batch,
                "cycle_reduction": reduction(serial_cycles, interleaved_cycles),
                "speedup": serial_cycles / interleaved_cycles,
                "serial_gross_average_power_w": serial_gross_power,
                "interleaved_gross_average_power_w": interleaved_gross_power,
                "gross_average_power_reduction": reduction(
                    serial_gross_power, interleaved_gross_power
                ),
                "serial_incremental_average_power_w": serial_incremental_power,
                "interleaved_incremental_average_power_w": interleaved_incremental_power,
                "incremental_reduction_qualified": incremental_reduction_qualified,
                "incremental_average_power_reduction": optional_incremental_reduction(
                    serial_incremental_power,
                    interleaved_incremental_power,
                    qualified=incremental_reduction_qualified,
                ),
                "serial_amortized_gross_energy_per_batch_mj": serial_gross_energy,
                "interleaved_amortized_gross_energy_per_batch_mj": interleaved_gross_energy,
                "gross_energy_reduction": reduction(
                    serial_gross_energy, interleaved_gross_energy
                ),
                "serial_amortized_incremental_energy_per_batch_mj": serial_incremental_energy,
                "interleaved_amortized_incremental_energy_per_batch_mj": interleaved_incremental_energy,
                "incremental_energy_reduction": optional_incremental_reduction(
                    serial_incremental_energy,
                    interleaved_incremental_energy,
                    qualified=incremental_reduction_qualified,
                ),
            },
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
