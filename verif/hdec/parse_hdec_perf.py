#!/usr/bin/env python3
"""
parse_hdec_perf.py - Parse [HDEC_PERF] logs and produce per-test + global stats.

Usage:
  python3 verif/hdec/parse_hdec_perf.py tmp/hdec_logs/*_test.log
"""

import sys
import re
from collections import defaultdict

PERF_RE = re.compile(r"\[HDEC_PERF\]\s+op=(\w+)\s+cycles=(\d+)")


def parse_log(filepath):
    """Return list of (op, cycles) from a log file."""
    records = []
    with open(filepath) as f:
        for line in f:
            m = PERF_RE.search(line)
            if m:
                records.append((m.group(1), int(m.group(2))))
    return records


def compute_stats(records):
    """Given [(op, cycles), ...], return per-op stats dict."""
    groups = defaultdict(list)
    for op, cyc in records:
        groups[op].append(cyc)

    result = {}
    for op in sorted(groups):
        cycles = groups[op]
        result[op] = {
            "count": len(cycles),
            "min": min(cycles),
            "max": max(cycles),
            "avg": round(sum(cycles) / len(cycles), 1),
            "total": sum(cycles),
            "values": sorted(set(cycles)),
            # value distribution for variable-latency ops
            "dist": {v: cycles.count(v) for v in sorted(set(cycles))},
        }
    return result


def main():
    files = sys.argv[1:]
    if not files:
        print("Usage: parse_hdec_perf.py <logfile>...")
        sys.exit(1)

    all_records = []
    test_data = {}  # tname -> {records, stats}

    for fpath in sorted(files):
        tname = fpath.rsplit("/", 1)[-1].replace(".log", "")
        records = parse_log(fpath)
        all_records.extend(records)
        test_data[tname] = {"records": records, "stats": compute_stats(records)}

    # ---- Per-test tables ----
    print("=" * 90)
    print("A. PER-TEST OP BREAKDOWN")
    print("=" * 90)

    for tname in sorted(test_data):
        st = test_data[tname]["stats"]
        total_cyc = sum(v["total"] for v in st.values())
        print(f"\n--- {tname}  (total HDEC_PERF cycles = {total_cyc}) ---")
        print(f"  {'op':<14} {'count':>6} {'min':>6} {'max':>6} {'avg':>8} {'total':>8}  notes")
        print(f"  {'-'*70}")
        for op in sorted(st):
            s = st[op]
            notes = ""
            if len(s["values"]) > 1:
                dist_parts = [f"{c}c x{n}" for c, n in sorted(s["dist"].items())]
                notes = "  [VARIES: " + ", ".join(dist_parts) + "]"
            print(f"  {op:<14} {s['count']:>6} {s['min']:>6} {s['max']:>6} {s['avg']:>8.1f} {s['total']:>8} {notes}")

    # ---- Global summary ----
    print("\n" + "=" * 90)
    print("B. GLOBAL MICROBENCHMARK TABLE (across all 9 tests)")
    print("=" * 90)

    global_st = compute_stats(all_records)
    tests_using_op = defaultdict(set)
    for tname, td in test_data.items():
        for op in td["stats"]:
            tests_using_op[op].add(tname.replace("_test", ""))

    header = f"  {'Instruction':<14} {'Count':>6} {'Min':>6} {'Max':>6} {'Avg':>8} {'Total':>8}  {'Observed in tests'}"
    print(f"\n{header}")
    print(f"  {'-'*90}")
    for op in sorted(global_st):
        s = global_st[op]
        test_list = ", ".join(sorted(tests_using_op[op]))
        notes = ""
        if len(s["values"]) > 1:
            dist_parts = [f"{c}c x{n}" for c, n in sorted(s["dist"].items())]
            notes = f"  [VARIES: {', '.join(dist_parts)}]"
        print(f"  {op:<14} {s['count']:>6} {s['min']:>6} {s['max']:>6} {s['avg']:>8.1f} {s['total']:>8}  {test_list}{notes}")

    # ---- C. Latency stability ----
    print("\n" + "=" * 90)
    print("C. COMPUTE PRIMITIVE LATENCY STABILITY")
    print("=" * 90)

    compute_ops = ["HBIND", "HPERM", "HSIM", "HBUNDLE4", "HCLIP", "HMATCH"]
    for op in compute_ops:
        if op in global_st:
            s = global_st[op]
            stable = "STABLE" if len(s["values"]) == 1 else "VARIES"
            print(f"\n  {op}:")
            print(f"    Total occurrences: {s['count']}")
            print(f"    Stability: {stable}")
            if len(s["values"]) == 1:
                print(f"    Fixed latency: {s['values'][0]} cycles")
            else:
                print(f"    Observed latencies: {s['values']}")
                for cyc, n in sorted(s["dist"].items()):
                    print(f"      {cyc} cycles: {n} time(s)")
                print(f"    Likely cause: depends on operand parameters (e.g. HMATCH class count)")

    # ---- D. Data movement ----
    print("\n" + "=" * 90)
    print("D. DATA MOVEMENT INSTRUCTION BREAKDOWN")
    print("=" * 90)

    for op in ["VADDR", "VWR64", "VRD64"]:
        if op in global_st:
            s = global_st[op]
            print(f"\n  {op}:")
            print(f"    Count: {s['count']}")
            print(f"    Fixed latency: {s['values'][0]} cycles" if len(s["values"]) == 1 else f"    Latencies: {s['values']}")
            print(f"    Total cycles: {s['total']}")
            print(f"    Avg cycles: {s['avg']}")

    # Data movement total
    dm_total = sum(global_st[o]["total"] for o in ["VADDR", "VWR64", "VRD64"] if o in global_st)
    dm_count = sum(global_st[o]["count"] for o in ["VADDR", "VWR64", "VRD64"] if o in global_st)
    all_total = sum(v["total"] for v in global_st.values())
    print(f"\n  TOTAL data movement: {dm_total} cycles ({dm_total/all_total*100:.1f}% of all HDEC_PERF cycles)")
    print(f"  TOTAL data movement ops: {dm_count} ({dm_count/sum(v['count'] for v in global_st.values())*100:.1f}% of all HDEC_PERF ops)")

    # ---- E/F. Bottleneck analysis ----
    print("\n" + "=" * 90)
    print("E/F. PERFORMANCE BOTTLENECK ANALYSIS")
    print("=" * 90)

    # Average latency per op type
    print("\n  Average cycles per instruction type:")
    for op in sorted(global_st):
        s = global_st[op]
        print(f"    {op:<14} avg={s['avg']:>6.1f}  (count={s['count']})")

    # Most cycles overall
    print("\n  Total cycles ranking:")
    for op, s in sorted(global_st.items(), key=lambda x: x[1]["total"], reverse=True):
        pct = s["total"] / all_total * 100
        print(f"    {op:<14} {s['total']:>6} cycles ({pct:>5.1f}%)  count={s['count']}")

    # ---- Summary for paper Table 1 ----
    print("\n" + "=" * 90)
    print("G. PAPER TABLE 1 DRAFT: HDEC Instruction Latency")
    print("=" * 90)
    print(f"\n  {'Instruction':<14} {'Function':<30} {'Operand Size':>14} {'Cycles':>8}  Notes")
    print(f"  {'-'*85}")

    paper_table = [
        ("VADDR",    "VRF address set",          "reg addr",       3,    "always 3"),
        ("VWR64",    "VRF write 64-bit",          "64-bit data",    3,    "always 3"),
        ("VRD64",    "VRF read 64-bit",           "64-bit data",    4,    "always 4"),
        ("HCLR",     "VRF row clear",             "1024-bit row",   7,    "always 7"),
        ("BCLR",     "BMCA bank clear",           "4-row bank",    19,    "always 19"),
        ("HBIND",    "XOR bind",                  "1024-bit vec",  15,    "fixed 15"),
        ("HPERM",    "4-bit granularity permute", "1024-bit vec",  15,    "fixed 15 (init: 3)"),
        ("HSIM",     "similarity (popcount)",     "1024-bit vec",  18,    "fixed 18"),
        ("HBUNDLE4", "4-row majority bundle",     "4×1024-bit",    63,    "fixed 63 (init: 3)"),
        ("HCLIP",    "threshold clip",            "1024-bit vec",  39,    "fixed 39"),
        ("HMATCH",   "multi-class match",         "N×1024-bit",    3,      "varies by class count: 3(cfg)+N×15"),
    ]

    for instr, func, opsize, cyc, notes in paper_table:
        print(f"  {instr:<14} {func:<30} {opsize:>14} {cyc:>8}  {notes}")

    print()


if __name__ == "__main__":
    main()
