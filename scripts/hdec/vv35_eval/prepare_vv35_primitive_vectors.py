#!/usr/bin/env python3
"""Complete a hybrid VV35 vector bundle without duplicating the GF model."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def read_hex(path: Path) -> list[int]:
    return [
        int(line.strip(), 16)
        for line in path.read_text(encoding="ascii").splitlines()
        if line.strip()
    ]


def write_hex(path: Path, values: list[int], width: int = 256) -> None:
    digits = (width + 3) // 4
    path.write_text(
        "".join(f"{value:0{digits}x}\n" for value in values),
        encoding="ascii",
        newline="\n",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--vector-dir", type=Path, required=True)
    args = parser.parse_args()

    reference_dir = args.repo_root.resolve() / "scripts" / "hdec" / "vv30"
    sys.path.insert(0, str(reference_dir))
    import k233_reference as k233  # pylint: disable=import-outside-toplevel

    vector_dir = args.vector_dir.resolve()
    operands_a = read_hex(vector_dir / "gf_a_inputs.mem")
    operands_b = read_hex(vector_dir / "gf_b_inputs.mem")
    if len(operands_a) != len(operands_b):
        raise ValueError("GF operand files have different lengths")
    expected = [
        k233.gf_mul(operand_a, operand_b)
        for operand_a, operand_b in zip(operands_a, operands_b)
    ]
    write_hex(vector_dir / "gf_mul_expected.mem", expected)
    print(
        "[VV35:primitive_vector_completion] PASS "
        f"gf_mul_cases={len(expected)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
