#!/usr/bin/env python3
"""Static integrity checks for the VV35 FPGA-board/ASIC laboratory package."""

from __future__ import annotations

import csv
import hashlib
import importlib.util
import json
import sys
from pathlib import Path


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> int:
    repo = Path(__file__).resolve().parents[3]
    common = repo / "verif/hdec/vv35_eval/common"
    vectors = common / "vectors/frozen_lab_20260803"
    contract = json.loads((common / "workload_contract.json").read_text())
    manifest_path = vectors / "vector_manifest.json"
    manifest = json.loads(manifest_path.read_text())

    require(contract["vector_bundle"]["curve"] == "sect233k1", "curve drift")
    require(contract["workload"]["pmul_operations"] == 1, "PMUL count drift")
    require(contract["workload"]["hmatch_operations"] == 1632, "HMATCH count drift")
    require(contract["workload"]["serial"]["core_reference_cycles"] == 337853,
            "serial cycle drift")
    require(contract["workload"]["interleaved"]["core_reference_cycles"] == 200144,
            "interleaved cycle drift")
    require(manifest["scalars"][0]["hex"] ==
            "0000002fa9f8d054ea7fd4613721adbba762ed34fd11b768a6bff1725e8ce89a",
            "frozen K drift")
    for leaf, metadata in manifest["files"].items():
        path = vectors / leaf
        require(path.is_file(), f"missing vector {leaf}")
        require(sha256(path) == metadata["sha256"], f"hash mismatch {leaf}")
    sha_line = (vectors / "vector_manifest.sha256").read_text().split()[0]
    require(sha_line == sha256(manifest_path), "vector_manifest.sha256 mismatch")

    generator_path = repo / "scripts/hdec/vv35_eval/board/gen_vv35_board_vectors.py"
    spec = importlib.util.spec_from_file_location("vv35_board_vectors", generator_path)
    require(spec is not None and spec.loader is not None, "cannot load vector generator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    expected_include = module.render(vectors)
    include_path = repo / "verif/hdec/vv35_eval/board/vv35_board_vectors.inc"
    require(include_path.read_text(encoding="ascii") == expected_include,
            "board include is not generated from frozen vectors")

    expected_rtl = [
        "core/hdec/rtl/hdec_pkg.sv",
        "core/hdec/rtl/hdec_resource_pkg.sv",
        "core/hdec/rtl/hdec_vrf_64x256.sv",
        "core/hdec/rtl/hdec_lane_boolean_mask.sv",
        "core/hdec/rtl/hdec_lane_popcount_compressor.sv",
        "core/hdec/rtl/hdec_p2_pop_slice.sv",
        "core/hdec/rtl/hdec_cnt_array.sv",
        "core/hdec/rtl/hdec_lane_shift_align.sv",
        "core/hdec/rtl/hdec_lane_clip.sv",
        "core/hdec/rtl/hdec_lane_4x64.sv",
        "core/hdec/rtl/hdec_top.sv",
    ]
    filelist = [line.strip() for line in
                (repo / "verif/hdec/vv35_eval/asic/hdec_vv35_rtl.f").read_text().splitlines()
                if line.strip() and not line.lstrip().startswith("#")]
    require(filelist == expected_rtl, "ASIC RTL filelist drift")
    for relative in filelist:
        require((repo / relative).is_file(), f"missing RTL file {relative}")

    template = repo / "verif/hdec/vv35_eval/asic/results_template.csv"
    rows = list(csv.DictReader(template.open(newline="", encoding="utf-8")))
    require(len(rows) == 6, "ASIC template must contain six scenario/memory rows")
    for row in rows:
        require(row["pmul_count"] == "1", "ASIC template PMUL column shift")
        require(row["hmatch_count"] == "1632", "ASIC template HMATCH column shift")
        expected = "337853" if row["scenario"] == "SERIAL" else "200144"
        require(row["cycles"] == expected, "ASIC template cycle column shift")

    board_template = repo / "verif/hdec/vv35_eval/board/board_results_template.csv"
    board_rows = list(csv.DictReader(board_template.open(newline="", encoding="utf-8")))
    require(len(board_rows) == 3, "board template must contain two tasks and one idle row")
    require([row["scenario"] for row in board_rows] ==
            ["SERIAL", "INTERLEAVED", "CLOCKED_IDLE_SPIN"],
            "board template scenario drift")
    for row in board_rows[:2]:
        require(row["pmul_count_per_batch"] == "1", "board PMUL column shift")
        require(row["hmatch_count_per_batch"] == "1632", "board HMATCH column shift")
        require(row["pmul_wait_cycles"] == "146908", "board PMUL wait drift")

    board_asm = (repo / "verif/hdec/vv35_eval/board/vv35_board_schedule_test.S").read_text()
    for symbol in ("vv35_pmul_wait_cycles", "vv35_idle_window_cycles",
                   "vv35_result_block"):
        require(symbol in board_asm, f"board assembly missing {symbol}")
    require(".zero 88" in board_asm, "board result block size drift")

    required = [
        "verif/hdec/vv35_eval/board/vv35_board_schedule_test.S",
        "verif/hdec/vv35_eval/board/README.md",
        "scripts/hdec/vv35_eval/board/compute_vv35_board_energy.py",
        "scripts/hdec/vv35_eval/asic/run_vv35_asic.sh",
        "scripts/hdec/vv35_eval/asic/dc_synth.tcl",
        "scripts/hdec/vv35_eval/asic/dc_power.tcl",
        "verif/hdec/vv35_eval/asic/tb_vv35_schedule_asic.sv",
        "docs/hdec/vv35_lab_measurement_handoff.md",
    ]
    for relative in required:
        require((repo / relative).is_file(), f"missing laboratory asset {relative}")

    print("[VV35:LAB_ASSETS] PASS")
    print(f"contract_sha256={sha256(common / 'workload_contract.json')}")
    print(f"vector_manifest_sha256={sha256(manifest_path)}")
    print(f"board_include_sha256={sha256(include_path)}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"[VV35:LAB_ASSETS] FAIL {exc}", file=sys.stderr)
        raise
