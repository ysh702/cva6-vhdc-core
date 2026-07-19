#!/usr/bin/env python3
"""Fail-closed static RTL audit for the VV25 shared diagonal datapath.

The audit follows the hierarchy instantiated by ``hdec_top``.  This matters
because ``hdec_lane_4x64.sv`` still carries source-compatible legacy modules
that are not instantiated by the selected VV25 top-level implementation.

The check intentionally does not encode the selected tap equations.  R10 and
the local-tail probes may choose different POPCOUNT intermediates while still
meeting the same structural boundary: one 16x16 AND matrix, all thirty-two
8-bit POPCOUNT slots, and exactly fourteen nodes from the original two-input
XOR1 array.
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Callable


LANE_RTL = Path("core/hdec/rtl/hdec_lane_4x64.sv")
TOP_RTL = Path("core/hdec/rtl/hdec_top.sv")
PKG_RTL = Path("core/hdec/rtl/hdec_pkg.sv")


@dataclass(frozen=True)
class AuditResult:
    name: str
    passed: bool
    detail: str


class AuditFailure(RuntimeError):
    """One fail-closed audit assertion failed."""


def require(condition: bool, detail: str) -> None:
    if not condition:
        raise AuditFailure(detail)


def module_body(rtl: str, name: str) -> str:
    match = re.search(
        rf"(?ms)^\s*module\s+{re.escape(name)}\b(.*?)^\s*endmodule\b",
        rtl,
    )
    require(match is not None, f"module {name} is missing")
    return match.group(1)


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"//[^\r\n]*", " ", text)


def synthesized_text(text: str) -> str:
    """Remove simulation-only assertions/reference models before auditing."""

    text = re.sub(
        r"//\s*synthesis\s+translate_off.*?"
        r"//\s*synthesis\s+translate_on",
        " ",
        text,
        flags=re.S | re.I,
    )
    return strip_comments(text)


def compact(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def assignment_rhs(text: str, signal: str) -> str:
    match = re.search(
        rf"\bassign\s+{re.escape(signal)}\s*=\s*(.*?);",
        text,
        flags=re.S,
    )
    require(match is not None, f"continuous assignment for {signal} is missing")
    return compact(match.group(1))


def int_localparam(text: str, name: str) -> int:
    match = re.search(
        rf"\blocalparam\s+int\s+{re.escape(name)}\s*=\s*(\d+)\s*;",
        text,
    )
    require(match is not None, f"integer localparam {name} is missing")
    return int(match.group(1))


def int_array(text: str, name: str) -> tuple[int, list[int]]:
    match = re.search(
        rf"\blocalparam\s+int\s+{re.escape(name)}\s*"
        rf"\[\s*0\s*:\s*(\d+)\s*\]\s*=\s*'\{{(.*?)\}}\s*;",
        text,
        flags=re.S,
    )
    require(match is not None, f"integer array {name} is missing")
    upper = int(match.group(1))
    values = [int(value) for value in re.findall(r"(?<![\w'])-?\d+", match.group(2))]
    return upper, values


def single_bitwise_and_count(text: str) -> int:
    return len(re.findall(r"(?<!&)&(?!&)", text))


def physical_node_expression(wrapper: str, destination: str, source: str) -> str:
    match = re.search(
        rf"\b{re.escape(destination)}\s*\[\s*(.*?)\s*\]\s*=\s*"
        rf"{re.escape(source)}\s*\[\s*logical_node\s*\]\s*;",
        wrapper,
        flags=re.S,
    )
    require(match is not None, f"{destination} does not receive {source}")
    return compact(match.group(1))


def evaluate_node_expression(expression: str, logical_node: int) -> int:
    require(
        re.fullmatch(r"[\d\s()+\-]*logical_node[\d\s()+\-]*", expression)
        is not None,
        f"unsupported physical-node expression: {expression!r}",
    )
    substituted = expression.replace("logical_node", str(logical_node))
    require(
        re.fullmatch(r"[\d\s()+\-]+", substituted) is not None,
        f"unsafe physical-node expression: {expression!r}",
    )
    # Only decimal integers, parentheses, plus, and minus survive the guards.
    return int(eval(substituted, {"__builtins__": {}}, {}))


def run_check(name: str, check: Callable[[], str]) -> AuditResult:
    try:
        return AuditResult(name, True, check())
    except (AuditFailure, OSError, ValueError, IndexError) as error:
        return AuditResult(name, False, str(error))


def audit(repo: Path) -> list[AuditResult]:
    lane_path = repo / LANE_RTL
    top_path = repo / TOP_RTL
    pkg_path = repo / PKG_RTL
    for path in (lane_path, top_path, pkg_path):
        require(path.is_file(), f"required source is missing: {path}")

    lane_raw = lane_path.read_text(encoding="utf-8")
    top_raw = top_path.read_text(encoding="utf-8")
    pkg_raw = pkg_path.read_text(encoding="utf-8")

    native = synthesized_text(module_body(lane_raw, "hdec_xor1_native_224"))
    wrapper = synthesized_text(module_body(lane_raw, "hdec_xor1_shared_8x32"))
    tile = synthesized_text(
        module_body(lane_raw, "hdec_gf2_contribution_row_tile_8x32")
    )
    payload = synthesized_text(module_body(lane_raw, "hdec_vector_payload_4x64"))
    top = synthesized_text(top_raw)
    package = strip_comments(lane_raw)
    pkg = strip_comments(pkg_raw)

    def check_active_hierarchy() -> str:
        require(
            len(re.findall(r"\bhdec_vector_payload_4x64\s*#\s*\(", top)) == 1,
            "hdec_top must instantiate exactly one selected vector payload",
        )
        require(
            len(
                re.findall(
                    r"\bhdec_gf2_contribution_row_tile_8x32\s+\w+\s*\(",
                    payload,
                )
            )
            == 1,
            "vector payload must instantiate exactly one shared row tile",
        )
        require(
            len(re.findall(r"\bhdec_xor1_shared_8x32\s+\w+\s*\(", tile)) == 1,
            "row tile must instantiate exactly one shared XOR1 wrapper",
        )
        require(
            len(re.findall(r"\bhdec_xor1_native_224\s+\w+\s*\(", wrapper)) == 1,
            "shared wrapper must instantiate exactly one native XOR1",
        )
        for inactive in ("hdec_lane_4x64", "hdec_vector_4x64"):
            require(
                re.search(rf"\b{inactive}\s+(?:#\s*\([^;]*?\)\s*)?\w+\s*\(", top)
                is None,
                f"legacy datapath {inactive} is also instantiated by hdec_top",
            )
        return "single active hierarchy: payload -> row tile -> shared XOR1 -> native XOR1"

    def check_matrix_bijection() -> str:
        lane_num = int_localparam(pkg, "LANE_NUM")
        require(lane_num == 4, f"LANE_NUM is {lane_num}, expected 4")
        require(
            len(re.findall(r"\binput\s+logic\s*\[\s*15\s*:\s*0\s*\]\s*bitmatrix_src_[ab]_i", payload))
            == 2,
            "payload does not expose exactly two 16-bit matrix operands",
        )
        diag_upper, diag = int_array(package, "HDEC_VV25_MATRIX_DIAG")
        term_upper, term = int_array(package, "HDEC_VV25_MATRIX_TERM")
        require(
            (diag_upper, term_upper) == (255, 255)
            and len(diag) == 256
            and len(term) == 256,
            "matrix maps must each contain exactly 256 entries",
        )
        pairs: list[tuple[int, int]] = []
        for diagonal, term_index in zip(diag, term):
            a_index = max(0, diagonal - 15) + term_index
            b_index = diagonal - a_index
            require(
                0 <= a_index < 16 and 0 <= b_index < 16,
                f"matrix map produced invalid pair ({a_index}, {b_index})",
            )
            pairs.append((a_index, b_index))
        multiplicity = Counter(pairs)
        require(
            len(multiplicity) == 256 and set(multiplicity.values()) == {1},
            "16x16 map is not a bijection over all 256 partial products",
        )
        require(lane_num * 2 == 8, "matrix does not form eight 32-bit rows")
        return "16x16 operands map bijectively to one unified 8x32 matrix"

    def check_single_shared_and() -> str:
        active_lane = "\n".join((native, wrapper, tile, payload))
        require(
            single_bitwise_and_count(active_lane) == 1,
            "active lane hierarchy must contain exactly one bitwise AND generator",
        )
        require(
            len(
                re.findall(
                    r"assign\s+matrix_product_o\s*\[\s*rid\s*\]\s*=\s*"
                    r"matrix_src_a_i\s*\[\s*rid\s*\]\s*&\s*"
                    r"matrix_src_b_i\s*\[\s*rid\s*\]\s*;",
                    tile,
                )
            )
            == 1,
            "the one AND is not the shared row-wise matrix generator",
        )
        suspicious_top_and = re.findall(
            r"[^;]*(?:bitmatrix|ecc_diag|ecc_leaf)[^;]*"
            r"(?<!&)&(?!&)[^;]*;",
            top,
            flags=re.I,
        )
        require(
            not suspicious_top_and,
            "hdec_top contains an ECC/bitmatrix bitwise-AND bypass",
        )
        return "one generated row-wise AND statement elaborates all 256 shared products"

    def check_complete_popcount() -> str:
        require(
            re.search(
                r"logic\s*\[\s*LANE_NUM\s*\*\s*2\s*-\s*1\s*:\s*0\s*\]"
                r"\s*\[\s*3\s*:\s*0\s*\]\s*\[\s*3\s*:\s*0\s*\]"
                r"\s*matrix_byte_count\s*;",
                tile,
            )
            is not None,
            "8-row x 4-byte POPCOUNT storage is missing",
        )
        require(
            len(re.findall(r"\brid\s*<\s*LANE_NUM\s*\*\s*2\b", tile)) >= 1
            and len(re.findall(r"\bbyte_idx\s*<\s*4\b", tile)) == 1,
            "8x4 byte-counter generate topology is missing or duplicated",
        )
        require(
            len(
                re.findall(
                    r"assign\s+matrix_byte_count\s*\[\s*rid\s*\]"
                    r"\s*\[\s*byte_idx\s*\]\s*=",
                    tile,
                )
            )
            == 2,
            "partitioned and balanced branches do not both produce a full byte count",
        )
        pair_rhs = assignment_rhs(tile, "matrix_byte_pair_count[rid][side]")
        require(
            "matrix_byte_count[rid][side * 2]" in pair_rhs
            and "matrix_byte_count[rid][side * 2 + 1]" in pair_rhs
            and "+" in pair_rhs,
            "byte-pair count does not combine both owned 8-bit counters",
        )
        row_rhs = assignment_rhs(tile, "matrix_count_o[rid]")
        require(
            "matrix_byte_pair_count[rid][0]" in row_rhs
            and "matrix_byte_pair_count[rid][1]" in row_rhs
            and "+" in row_rhs,
            "row count does not combine all four byte counters",
        )
        require(
            re.search(
                r"\.matrix_product_i\s*\(\s*matrix_product_q_i\s*\)", tile
            )
            is not None,
            "the shared XOR1 wrapper is not connected to the registered matrix source bus",
        )
        return "32 complete 8-bit counters consume the one shared 256-bit AND matrix"

    def check_native_xor1_body() -> str:
        assignments = re.findall(r"\bassign\s+.*?;", native, flags=re.S)
        require(
            len(assignments) == 1,
            f"native XOR1 contains {len(assignments)} assignments, expected one generated form",
        )
        require(
            compact(assignments[0])
            == "assign node_o[node_idx] = lhs_i[node_idx] ^ rhs_i[node_idx];",
            "native XOR1 node body is not exactly lhs_i ^ rhs_i",
        )
        for forbidden in (
            "diag_mode",
            "diag_aux",
            "matrix_product",
            "$countones",
            "&",
        ):
            require(forbidden not in native, f"native XOR1 contains {forbidden!r}")
        require(native.count("^") == 1, "native XOR1 has an extra XOR operand/operator")
        return "all 224 original nodes remain mode-free, two-input lhs ^ rhs cells"

    def check_fourteen_native_nodes() -> str:
        count = int_localparam(package, "HDEC_VV25_XOR_NODE_COUNT")
        require(count == 14, f"diagonal mode selects {count} nodes, expected 14")
        lhs_upper, lhs_values = int_array(package, "HDEC_VV25_XOR_NODE_LHS")
        rhs_upper, rhs_values = int_array(package, "HDEC_VV25_XOR_NODE_RHS")
        require(
            lhs_upper == rhs_upper == 13
            and len(lhs_values) == len(rhs_values) == count,
            "XOR1 equation source tables do not each contain fourteen entries",
        )
        byte_source_base = int_localparam(package, "HDEC_VV25_BYTE_SOURCE_BASE")
        require(
            all(source >= byte_source_base for source in lhs_values + rhs_values),
            "a selected R31 XOR1 node consumes a raw matrix bit instead of a POPCOUNT summary",
        )
        require(
            len(
                re.findall(
                    r"logical_node\s*<\s*HDEC_VV25_XOR_NODE_COUNT",
                    wrapper,
                )
            )
            == 3,
            "operand selection/output mapping does not use three fourteen-node loops",
        )
        lhs_expr = physical_node_expression(wrapper, "native_lhs", "diag_node_lhs")
        rhs_expr = physical_node_expression(wrapper, "native_rhs", "diag_node_rhs")
        lhs_nodes = [evaluate_node_expression(lhs_expr, index) for index in range(count)]
        rhs_nodes = [evaluate_node_expression(rhs_expr, index) for index in range(count)]
        # The output assignment is written in the opposite direction:
        # diag_node[logical_node] = xor_node[physical].  Parse it separately.
        map_match = re.search(
            r"diag_node\s*\[\s*logical_node\s*\]\s*=\s*"
            r"xor_node\s*\[\s*(.*?)\s*\]\s*;",
            wrapper,
            flags=re.S,
        )
        require(map_match is not None, "diagonal nodes are not aliases of native XOR1")
        output_expr = compact(map_match.group(1))
        output_nodes = [
            evaluate_node_expression(output_expr, index) for index in range(count)
        ]
        require(
            lhs_nodes == rhs_nodes == output_nodes,
            "diagonal operand and output maps address different native nodes",
        )
        require(
            len(set(output_nodes)) == count
            and all(0 <= node < 224 for node in output_nodes),
            "diagonal map does not address fourteen unique native XOR1 nodes",
        )
        require(
            not set(output_nodes).intersection(range(160, 224)),
            "diagonal mapping overwrites original leaf low-XOR nodes 160..223",
        )
        return (
            f"14 unique native nodes selected at physical indices {output_nodes}; "
            "all operands are shared-POPCOUNT parity summaries"
        )

    def check_no_private_reduction() -> str:
        combined = compact("\n".join((lane_raw, top_raw))).lower()
        for forbidden in (
            "bitband_pair_src_b_i",
            "bitband_pair_parity_o",
            "diag_aux",
            "ecc_private_xor",
            "ecc_private_reduce",
        ):
            require(forbidden not in combined, f"forbidden private path {forbidden!r} remains")
        require("bitband_pair" not in combined, "a bitband_pair path remains")
        require("diag_aux" not in combined, "a diag_aux path remains")
        require("$countones" not in wrapper, "XOR1 wrapper contains a private counter")

        diag_assignments = re.findall(
            r"\bassign\s+diag16_product_o\s*\[.*?;", wrapper, flags=re.S
        )
        require(diag_assignments, "no diagonal-output aliases were found")
        for statement in diag_assignments:
            require(
                not re.search(r"(?<!&)&(?!&)|\^|\$countones", statement),
                "diag16_product_o is computed by a private reduction operator",
            )
        require(
            not re.search(
                r"\b(?:function|module)\b[^;\n]*(?:private|diag.*(?:xor|reduce|parity))",
                "\n".join((wrapper, tile)),
                flags=re.I,
            ),
            "active shared modules define an ECC-private diagonal reducer",
        )
        return "no bitband-pair, diag-aux, second AND, or private diagonal reducer"

    def check_fold_preissue_and_lowxor() -> str:
        preissue = assignment_rhs(top, "ecc_diag_fold_preissue")
        require(
            "st_q == S_ECC_DIAG_FOLD_ISSUE" in preissue
            and "ecc_diag_sub_shadow_mode" in preissue
            and re.search(r"ecc_kpd64_sub_q\s*<\s*2'd2", preissue),
            "fold/preissue enable is not restricted to reusable sub0/sub1 launches",
        )
        product_issue = assignment_rhs(top, "ecc_diag_product_issue")
        require(
            "ecc_diag_fold_preissue" in product_issue
            and "S_ECC_DIAG_ISSUE" in product_issue
            and "S_ECC_DIAG_CAPTURE0" in product_issue
            and "S_ECC_DIAG_CAPTURE1" in product_issue,
            "shared AND issue path does not include normal and fold-preissue launches",
        )
        require(
            "ecc_diag_issue_group" not in top
            and "ecc_diag_group_q" not in top
            and "ecc_diag_group_n" not in top,
            "split capture phases still retain a runtime group selector/register",
        )
        diag_mode = assignment_rhs(top, "ecc_xor1_diag_mode")
        require(
            all(
                state in diag_mode
                for state in (
                    "S_ECC_DIAG_CAPTURE0",
                    "S_ECC_DIAG_CAPTURE1",
                    "S_ECC_DIAG_CAPTURE2",
                )
            ),
            "XOR1 diagonal mode must cover exactly the three capture phases",
        )
        require(
            assignment_rhs(wrapper, "legacy_lowxor_a_o") == "xor_node[191:160]"
            and assignment_rhs(wrapper, "legacy_lowxor_b_o") == "xor_node[223:192]",
            "original leaf low-XOR outputs are not preserved on nodes 160..223",
        )
        require(
            assignment_rhs(wrapper, "legacy_accum_o") == "xor_node[159:32]",
            "original XOR1 accumulator output is not preserved",
        )
        require(
            re.search(r"native_lhs\s*=\s*legacy_lhs\s*;", wrapper)
            and re.search(r"native_rhs\s*=\s*legacy_rhs\s*;", wrapper),
            "diagonal operand selection does not default to all legacy XOR1 operands",
        )
        require(
            "S_ECC_DIAG_CAPTURE0" in top
            and "ecc_leaf_a_q[31:16]" in top
            and "S_ECC_DIAG_CAPTURE1" in top
            and "ecc_leaf_a_q[15:0] ^ ecc_leaf_a_q[31:16]" in top,
            "fixed capture phases do not select matrix groups 1 and 2",
        )

        capture_match = re.search(
            r"S_ECC_DIAG_CAPTURE2\s*:\s*begin(.*?)"
            r"S_ECC_LEAF_FOLD\s*:\s*begin",
            top,
            flags=re.S,
        )
        require(capture_match is not None, "diagonal capture2 state body is missing")
        capture = compact(capture_match.group(1))
        require(
            "ecc_leaf_a_n = ecc_leaf_a_lowxor_xor1;" in capture
            and "ecc_leaf_b_n = ecc_leaf_b_lowxor_xor1;" in capture,
            "capture2 does not consume the original XOR1 low-XOR outputs concurrently",
        )
        require(
            "ecc_leaf_a_next_q" not in top
            and "ecc_leaf_xor_a_next_q" not in top
            and "ecc_leaf_a_n = ecc_leaf_lowxor_rd[31:0];" in capture
            and "ecc_leaf_xor_a_n = ecc_leaf_lowxor_rd[63:32];" in capture,
            "next-leaf A is not handed directly into the existing leaf registers",
        )

        fold_match = re.search(
            r"S_ECC_DIAG_FOLD_ISSUE\s*:\s*begin(.*?)"
            r"S_ECC_DIAG_CAPTURE0\s*:\s*begin",
            top,
            flags=re.S,
        )
        require(fold_match is not None, "dedicated diagonal fold/preissue state is missing")
        fold = compact(fold_match.group(1))
        require(
            "ecc_sub32_capture_accum_xor1" in fold
            and "ecc_diag_fold_preissue" in fold
            and "S_ECC_DIAG_CAPTURE0" in fold,
            "fold state does not combine legacy XOR1 folding with shared-AND preissue",
        )
        return (
            "capture2 keeps low-XOR live, reuses leaf registers, and fold preissues "
            "the shared AND without a runtime group selector"
        )

    checks: tuple[tuple[str, Callable[[], str]], ...] = (
        ("active hierarchy", check_active_hierarchy),
        ("unified 16x16 matrix", check_matrix_bijection),
        ("single shared AND", check_single_shared_and),
        ("complete POPCOUNT", check_complete_popcount),
        ("native XOR1 body", check_native_xor1_body),
        ("fourteen diagonal nodes", check_fourteen_native_nodes),
        ("no ECC-private reducer", check_no_private_reduction),
        ("fold/preissue collaboration", check_fold_preissue_and_lowxor),
    )
    return [run_check(name, check) for name, check in checks]


def main() -> int:
    default_repo = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(
        description="Audit VV25 strict AND/POPCOUNT/native-XOR1 reuse in static RTL."
    )
    parser.add_argument(
        "--repo",
        type=Path,
        default=default_repo,
        help=f"repository root (default: {default_repo})",
    )
    args = parser.parse_args()

    try:
        results = audit(args.repo.resolve())
    except (AuditFailure, OSError) as error:
        print(f"[FAIL] source setup: {error}")
        print("[VV25_REUSE_STRUCTURE] FAIL passed=0 failed=1")
        return 1

    for result in results:
        status = "PASS" if result.passed else "FAIL"
        print(f"[{status}] {result.name}: {result.detail}")

    passed = sum(result.passed for result in results)
    failed = len(results) - passed
    summary = "PASS" if failed == 0 else "FAIL"
    print(
        f"[VV25_REUSE_STRUCTURE] {summary} "
        f"passed={passed} failed={failed} popcount_slots=32 diag_nodes=14"
    )
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
