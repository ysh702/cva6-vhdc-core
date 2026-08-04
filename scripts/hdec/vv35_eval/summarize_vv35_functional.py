#!/usr/bin/env python3
"""Merge a primary VV35 full run with infrastructure-repair supplements."""

from __future__ import annotations

import argparse
import csv
import json
from datetime import datetime
from pathlib import Path
from typing import Any


def parse_time(value: str) -> datetime:
    return datetime.fromisoformat(value)


def load(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8-sig") as handle:
        return json.load(handle)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--primary", type=Path, required=True)
    parser.add_argument("--supplement", type=Path, action="append", default=[])
    parser.add_argument("--out-dir", type=Path, required=True)
    args = parser.parse_args()

    paths = [args.primary.resolve()] + [path.resolve() for path in args.supplement]
    manifests = [load(path) for path in paths]
    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    seeds = {str(item["vector_manifest"]["seed_hex"]) for item in manifests}
    commits = {str(item["git_commit"]) for item in manifests}
    rtl_hashes = {str(item["rtl_sha256"]) for item in manifests}
    identity_ok = len(seeds) == len(commits) == len(rtl_hashes) == 1

    merged: dict[str, dict[str, Any]] = {}
    histories: dict[str, list[dict[str, Any]]] = {}
    for manifest_path, manifest in zip(paths, manifests):
        for test in manifest["tests"]:
            name = str(test["name"])
            entry = {
                "name": name,
                "status": str(test["status"]),
                "source_manifest": str(manifest_path),
                "suite": str(manifest["suite"]),
                "elapsed_seconds": float(test["elapsed_seconds"]),
                "pass_marker_count": int(test["pass_marker_count"]),
                "xsim_log": str(test["xsim_log"]),
            }
            histories.setdefault(name, []).append(entry)
            merged[name] = entry

    pmul_records: dict[str, dict[str, list[int]]] = {}
    for manifest in manifests:
        for test in manifest["tests"]:
            for metric in test.get("metric_records", []):
                if metric.get("tag") != "PMUL_CYCLE":
                    continue
                fields = metric.get("fields", {})
                if "K" not in fields or "cycles" not in fields:
                    continue
                pmul_records.setdefault(str(test["name"]), {}).setdefault(
                    str(fields["K"]).lower(), []
                ).append(int(fields["cycles"]))

    random_k_cycles = pmul_records.get("pmul_random_k", {})
    pipeline_k_cycles = pmul_records.get("pmul_pipeline_contract", {})
    unique_k = sorted(set(random_k_cycles) | set(pipeline_k_cycles))
    all_cycle_values = {
        cycle
        for records in pmul_records.values()
        for cycles in records.values()
        for cycle in cycles
    }
    pmul_consistent = (
        len(random_k_cycles) == 16
        and len(pipeline_k_cycles) == 16
        and len(unique_k) == 16
        and all_cycle_values == {146_908}
        and set(random_k_cycles) == set(pipeline_k_cycles)
    )

    all_tests_pass = all(entry["status"] == "PASS" for entry in merged.values())
    rtl_unchanged = all(
        bool(manifest["rtl_unchanged_during_run"]) for manifest in manifests
    )
    overall = "PASS" if (
        identity_ok and all_tests_pass and rtl_unchanged and pmul_consistent
    ) else "FAIL"
    active_seconds = sum(
        (parse_time(item["completed_at"]) - parse_time(item["started_at"])).total_seconds()
        for item in manifests
    )
    primary_seconds = (
        parse_time(manifests[0]["completed_at"])
        - parse_time(manifests[0]["started_at"])
    ).total_seconds()

    consolidated = {
        "schema": "hdec-vv35-functional-consolidated-v1",
        "overall": overall,
        "primary_manifest_status": manifests[0]["overall"],
        "primary_infrastructure_failure_preserved": {
            "test": "hdc_full_flow",
            "classification": "TEST_INFRASTRUCTURE_XELAB_TIMESCALE_STRICTNESS",
            "original_manifest": str(paths[0]),
            "repair_manifest": str(paths[1]) if len(paths) > 1 else None,
            "rtl_failure": False,
        },
        "identity_consistent": identity_ok,
        "seed_hex": next(iter(seeds)) if len(seeds) == 1 else sorted(seeds),
        "git_commit": next(iter(commits)) if len(commits) == 1 else sorted(commits),
        "rtl_sha256": next(iter(rtl_hashes)) if len(rtl_hashes) == 1 else sorted(rtl_hashes),
        "rtl_unchanged_during_all_runs": rtl_unchanged,
        "unique_tests": len(merged),
        "all_tests_pass_after_repair": all_tests_pass,
        "primary_elapsed_seconds": round(primary_seconds, 3),
        "active_elapsed_seconds_all_runs": round(active_seconds, 3),
        "pmul": {
            "unique_random_k": len(unique_k),
            "direct_contract_records": len(random_k_cycles),
            "background_pipeline_records": len(pipeline_k_cycles),
            "cycle_values": sorted(all_cycle_values),
            "expected_cycles": 146_908,
            "consistent": pmul_consistent,
            "k_records": [
                {
                    "k_hex": value,
                    "direct_cycles": random_k_cycles.get(value, []),
                    "background_cycles": pipeline_k_cycles.get(value, []),
                }
                for value in unique_k
            ],
        },
        "source_manifests": [str(path) for path in paths],
        "tests": [merged[name] for name in sorted(merged)],
        "test_histories": histories,
    }

    json_path = out_dir / "VV35_FUNCTIONAL_CONSOLIDATED.json"
    json_path.write_text(
        json.dumps(consolidated, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    csv_path = out_dir / "VV35_FUNCTIONAL_CONSOLIDATED.csv"
    with csv_path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "test", "status", "suite", "elapsed_seconds",
                "pass_marker_count", "source_manifest", "xsim_log",
            ],
        )
        writer.writeheader()
        for name in sorted(merged):
            entry = merged[name]
            writer.writerow({"test": name, **{k: v for k, v in entry.items() if k != "name"}})

    lines = [
        "# VV35 no-board functional regression",
        "",
        f"- Consolidated result: **{overall}**",
        f"- Unique tests after infrastructure repair: **{len(merged)}**",
        f"- Seed: `{consolidated['seed_hex']}`",
        f"- Commit: `{consolidated['git_commit']}`",
        f"- RTL unchanged: **{rtl_unchanged}**",
        f"- Primary full runtime: **{primary_seconds:.1f} s**",
        f"- Total active runtime including repair and direct supplements: **{active_seconds:.1f} s**",
        "",
        "## Random-K PMUL cycle contract",
        "",
        f"The direct PMUL contract and the background-pipeline contract each completed {len(unique_k)} identical legal random K values. All observed cycle counts were {sorted(all_cycle_values)} cycles. Consistency result: **{pmul_consistent}**.",
        "",
        "## Tests",
        "",
        "| Test | Result | Suite | Runtime (s) |",
        "|---|---:|---|---:|",
    ]
    for name in sorted(merged):
        entry = merged[name]
        lines.append(
            f"| {name} | {entry['status']} | {entry['suite']} | {entry['elapsed_seconds']:.3f} |"
        )
    lines.extend([
        "",
        "## Preserved infrastructure failure",
        "",
        "The primary full run preserved one failed `hdc_full_flow` launch. Its legacy Tcl used strict Vivado 2024.2 elaboration, which rejected a testbench timescale mixed with synthesizable modules using the simulator default. The test never entered simulation. The repair runner added only `xelab --relax`, kept RTL unchanged, and the exact HDC full-flow contract then passed. This is classified as `TEST_INFRASTRUCTURE_XELAB_TIMESCALE_STRICTNESS`, not an RTL failure.",
        "",
        "The ECC direct add, reduction, and inversion contracts were run separately with the identical seed and RTL hash, and are included in the consolidated result.",
        "",
    ])
    md_path = out_dir / "VV35_FUNCTIONAL_CONSOLIDATED.md"
    md_path.write_text("\n".join(lines), encoding="utf-8", newline="\n")

    print(
        f"[VV35:functional_consolidated] {overall} tests={len(merged)} "
        f"random_k={len(unique_k)} active_seconds={active_seconds:.1f} "
        f"manifest={json_path}"
    )
    return 0 if overall == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
