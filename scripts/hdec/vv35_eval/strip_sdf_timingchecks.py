#!/usr/bin/env python3
"""Remove SDF TIMINGCHECK groups while preserving routed delay annotation."""

from __future__ import annotations

import pathlib
import sys


def strip_group(text: str, keyword: str) -> tuple[str, int]:
    upper = text.upper()
    needle = f"({keyword.upper()}"
    pieces: list[str] = []
    cursor = 0
    count = 0
    while True:
        start = upper.find(needle, cursor)
        if start < 0:
            pieces.append(text[cursor:])
            break
        pieces.append(text[cursor:start])
        depth = 0
        quoted = False
        escaped = False
        end = start
        while end < len(text):
            char = text[end]
            if quoted:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == '"':
                    quoted = False
            elif char == '"':
                quoted = True
            elif char == "(":
                depth += 1
            elif char == ")":
                depth -= 1
                if depth == 0:
                    end += 1
                    break
            end += 1
        if depth != 0:
            raise ValueError(f"Unbalanced SDF group beginning at byte {start}")
        pieces.append("\n    // TIMINGCHECK removed for delay-only functional simulation\n")
        cursor = end
        count += 1
    return "".join(pieces), count


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("usage: strip_sdf_timingchecks.py INPUT.sdf OUTPUT.sdf")
    source = pathlib.Path(sys.argv[1])
    target = pathlib.Path(sys.argv[2])
    text = source.read_text(encoding="ascii")
    stripped, count = strip_group(text, "TIMINGCHECK")
    if count == 0:
        raise SystemExit("no TIMINGCHECK groups found; refusing an unverified copy")
    target.write_text(stripped, encoding="ascii", newline="\n")
    print(f"removed_timingcheck_groups={count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
