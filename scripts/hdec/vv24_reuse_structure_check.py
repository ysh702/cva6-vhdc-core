#!/usr/bin/env python3
"""Fail-closed RTL/netlist-structure audit for the selected VV24 probe."""

from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def module_body(rtl: str, name: str) -> str:
    match = re.search(rf"\bmodule\s+{re.escape(name)}\b(.*?)\bendmodule\b", rtl, re.S)
    require(match is not None, f"module {name} is missing")
    return match.group(1)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", type=Path, required=True)
    parser.add_argument("--inventory", type=Path, required=True)
    args = parser.parse_args()

    rtl_path = args.repo / "core" / "hdec" / "rtl" / "hdec_lane_4x64.sv"
    rtl = rtl_path.read_text(encoding="utf-8")
    native = module_body(rtl, "hdec_xor1_native_224")
    wrapper = module_body(rtl, "hdec_xor1_shared_8x32")
    tile = module_body(rtl, "hdec_gf2_contribution_row_tile_8x32")
    payload = module_body(rtl, "hdec_vector_payload_4x64")

    require(native.count("assign node_o[node_idx] = lhs_i[node_idx] ^ rhs_i[node_idx];") == 1,
            "native XOR1 operator is not exactly lhs ^ rhs")
    for forbidden in ("diag_mode", "diag_aux", "matrix_product", "&"):
        require(forbidden not in native, f"native XOR1 contains forbidden token {forbidden!r}")

    require(wrapper.count("hdec_xor1_native_224 i_native_xor1") == 1,
            "shared wrapper does not instantiate exactly one native XOR1")
    require(tile.count("matrix_src_a_i[rid] & matrix_src_b_i[rid]") == 1,
            "shared matrix AND generator is missing or duplicated")
    require(payload.count("hdec_gf2_contribution_row_tile_8x32 i_gf2_contribution_row_tile") == 1,
            "shared AND/POPCOUNT tile is missing or duplicated")
    require(tile.count("byte_idx < 4") == 1 and tile.count("rid < LANE_NUM*2") >= 1,
            "the 8x4 POPCOUNT byte-slot topology is not present")
    require("logical_node < 87" in wrapper,
            "selected 87-node native-XOR1 mapping is not present")

    for forbidden in (
        "bitband_pair_src_b_i",
        "bitband_pair_parity_o",
        "diag_aux",
        "ecc_private_xor",
    ):
        require(forbidden not in rtl, f"forbidden ECC-private path {forbidden!r} remains")

    hierarchy_path = args.inventory / "hierarchy_cells.csv"
    require(hierarchy_path.is_file(), "synthesized hierarchy inventory is missing")
    with hierarchy_path.open(newline="", encoding="utf-8") as handle:
        hierarchy = list(csv.DictReader(handle))

    def ref_count(ref_name: str) -> int:
        return sum(row["ref_name"] == ref_name for row in hierarchy)

    require(ref_count("hdec_gf2_contribution_row_tile_8x32") == 1,
            "synthesized netlist does not contain exactly one shared row tile")
    require(ref_count("hdec_vector_payload_4x64") == 1,
            "synthesized netlist does not contain exactly one vector payload")
    require(ref_count("hdec_vrf_64x256") == 1,
            "synthesized netlist does not contain exactly one VRF")

    print(
        "[VV24_REUSE_STRUCTURE] PASS shared_tiles=1 matrix_and_generators=1 "
        "popcount_slots=32 native_xor1=1 diag_nodes=87 forbidden_paths=0"
    )


if __name__ == "__main__":
    main()
