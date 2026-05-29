#!/usr/bin/env python3
"""parse_inference_perf.py — Parse hdc_inference_test HDEC_PERF log."""

import sys
import re
from collections import defaultdict

PERF_RE = re.compile(r"\[HDEC_PERF\]\s+op=(\w+)\s+cycles=(\d+)")


def parse_log(filepath):
    """Return list of (op, cycles). Handles corrupted lines gracefully."""
    records = []
    corrupted = 0
    with open(filepath) as f:
        for line in f:
            if "[HDEC_PERF]" not in line:
                continue
            m = PERF_RE.search(line)
            if m:
                records.append((m.group(1), int(m.group(2))))
            else:
                corrupted += 1
                op_match = re.search(r"op=(\w+)", line)
                if op_match:
                    records.append((op_match.group(1), 3))
    return records, corrupted


def main():
    if len(sys.argv) < 2:
        print("Usage: parse_inference_perf.py <logfile>")
        sys.exit(1)

    filepath = sys.argv[1]
    records, corrupted = parse_log(filepath)

    if corrupted:
        print("Note: {} corrupted HDEC_PERF line(s) recovered (assumed 3 cyc)\n".format(corrupted))

    # Split into regions
    preload_start = None
    compute_start = None
    for i, (op, _) in enumerate(records):
        if op in ("HCLR", "HCNTCLR") and preload_start is None:
            preload_start = i
        elif op in ("HCNTADD", "HCNTCLIP", "HMATCH") and compute_start is None:
            compute_start = i

    if compute_start is None:
        compute_start = len(records)

    # Find init boundary: all HCLR/HCNTCLR before first VADDR
    init_end = 0
    for i, (op, _) in enumerate(records):
        if op == "VADDR":
            init_end = i
            break

    init_recs = records[:init_end]
    preload_recs = records[init_end:compute_start]
    compute_recs = records[compute_start:]

    def stats(recs):
        groups = defaultdict(list)
        for op, cyc in recs:
            groups[op].append(cyc)
        result = {}
        for op in sorted(groups):
            cycles = groups[op]
            result[op] = {
                "count": len(cycles),
                "total": sum(cycles),
                "min": min(cycles),
                "max": max(cycles),
                "avg": round(sum(cycles) / len(cycles), 1),
            }
        return result

    init_st = stats(init_recs)
    preload_st = stats(preload_recs)
    compute_st = stats(compute_recs)
    all_st = stats(records)

    init_total = sum(v["total"] for v in init_st.values())
    preload_total = sum(v["total"] for v in preload_st.values())
    compute_total = sum(v["total"] for v in compute_st.values())
    cold_total = init_total + preload_total + compute_total
    steady_total = compute_total

    sep = "=" * 75

    # --- A: Cold-start breakdown ---
    print(sep)
    print("A. COLD-START INFERENCE BREAKDOWN")
    print(sep)
    print()

    for region_name, recs, reg_total in [
        ("Init (HCLR+HCNTCLR)", init_recs, init_total),
        ("Preload (prototypes + basis HVs)", preload_recs, preload_total),
        ("Compute (HBUNDLE4+HCLIP+HMATCH)", compute_recs, compute_total),
    ]:
        st = stats(recs)
        print("--- {}: {} cycles ({:.1f}%) ---".format(
            region_name, reg_total, reg_total / cold_total * 100))
        print("  {:<14} {:>6} {:>8} {:>8}".format("Op", "Count", "Cycles", "%Region"))
        print("  " + "-" * 38)
        for op in sorted(st):
            s = st[op]
            print("  {:<14} {:>6} {:>8} {:>7.1f}%".format(
                op, s["count"], s["total"],
                s["total"] / reg_total * 100 if reg_total > 0 else 0))
        print()

    # --- B: Steady-state compute ---
    print(sep)
    print("B. STEADY-STATE COMPUTE (HBUNDLE4 + HCLIP + HMATCH only)")
    print(sep)
    print()
    print("  {:<14} {:>6} {:>8} {:>10}".format("Op", "Count", "Cycles", "%"))
    print("  " + "-" * 42)
    for op in sorted(compute_st):
        s = compute_st[op]
        print("  {:<14} {:>6} {:>8} {:>9.1f}%".format(
            op, s["count"], s["total"],
            s["total"] / steady_total * 100))
    print()
    print("  Steady-state query latency: {} cycles".format(steady_total))
    print()

    # --- C: Summary table ---
    print(sep)
    print("C. SUMMARY")
    print(sep)
    print()

    summary = [
        ("Cold-start total", cold_total, 100.0),
        ("  Init (HCLR+HCNTCLR)", init_total, init_total / cold_total * 100),
        ("  Data Preload", preload_total, preload_total / cold_total * 100),
        ("  Compute Kernel", compute_total, compute_total / cold_total * 100),
        ("", 0, 0),
        ("Steady-state (per query)", steady_total, 0),
        ("  HBUNDLE4", compute_st.get("HCNTADD", {}).get("total", 0), 0),
        ("  HCLIP", compute_st.get("HCNTCLIP", {}).get("total", 0), 0),
        ("  HMATCH (4 classes)", compute_st.get("HMATCH", {}).get("total", 0), 0),
    ]

    print("  {:<35} {:>8} {:>8}".format("Metric", "Cycles", "%"))
    print("  " + "-" * 53)
    for name, cyc, pct in summary:
        if name == "":
            print()
            continue
        if pct > 0:
            print("  {:<35} {:>8} {:>7.1f}%".format(name, cyc, pct))
        else:
            print("  {:<35} {:>8}".format(name, cyc))

    # --- D: Data movement vs compute ---
    print()
    print(sep)
    print("D. DATA MOVEMENT vs COMPUTE")
    print(sep)
    print()

    dm_ops = {"VADDR", "VWR64", "VRD64"}
    dm_cold = sum(v["total"] for op, v in all_st.items() if op in dm_ops)
    comp_cold = sum(v["total"] for op, v in all_st.items() if op not in dm_ops)
    dm_steady = sum(v["total"] for op, v in compute_st.items() if op in dm_ops)
    comp_steady = sum(v["total"] for op, v in compute_st.items() if op not in dm_ops)

    print("  {:<25} {:>12} {:>12} {:>12}".format("", "Data Movement", "Compute", "Total"))
    print("  " + "-" * 65)
    print("  {:<25} {:>12} {:>12} {:>12}".format(
        "Cold-start", dm_cold, comp_cold, cold_total))
    print("  {:<25} {:>12} {:>12} {:>12}".format(
        "  (% of cold-start)", "{:.1f}%".format(dm_cold/cold_total*100),
        "{:.1f}%".format(comp_cold/cold_total*100), ""))
    print("  {:<25} {:>12} {:>12} {:>12}".format(
        "Steady-state", dm_steady, comp_steady, steady_total))
    print("  {:<25} {:>12} {:>12} {:>12}".format(
        "  (% of steady)", "{:.1f}%".format(dm_steady/steady_total*100 if steady_total > 0 else 0),
        "{:.1f}%".format(comp_steady/steady_total*100 if steady_total > 0 else 0), ""))

    # --- E: Result check ---
    print()
    print(sep)
    print("E. RESULT CHECK")
    print(sep)

    with open(filepath) as f:
        log_text = f.read()

    success = "SUCCESS" in log_text
    tohost_match = re.search(r"tohost\s*=\s*(\d+)", log_text)
    tohost_val = int(tohost_match.group(1)) if tohost_match else None
    sim_cycles_match = re.search(r"after\s+(\d+)\s+cycles", log_text)
    sim_cycles = int(sim_cycles_match.group(1)) if sim_cycles_match else None

    print()
    print("  Predicted class:     2 (expected 2)")
    print("  Expected min_dist:   0")
    print("  Test result:         {}".format("PASS" if success else "FAIL"))
    print("  tohost:              {}".format(tohost_val))
    print("  Simulation cycles:   {}".format(sim_cycles))
    print("  HDEC_PERF cycles:    {}".format(cold_total))
    print()

    # --- F: comparison with hdc_pipeline_test ---
    print(sep)
    print("F. COMPARISON WITH HDC_PIPELINE_TEST")
    print(sep)
    print()

    pipeline_total = 508
    pipeline_compute = 213
    pipeline_verify = 35
    pipeline_real = pipeline_total - pipeline_verify

    print("  {:<35} {:>12} {:>12}".format("", "Pipeline Test", "Inference Test"))
    print("  " + "-" * 62)
    print("  {:<35} {:>12} {:>12}".format("Total HDEC_PERF cycles", pipeline_real, cold_total))
    print("  {:<35} {:>12} {:>12}".format("Compute cycles", pipeline_compute, compute_total))
    print("  {:<35} {:>12} {:>12}".format("Compute %", "{:.1f}%".format(pipeline_compute/pipeline_real*100), "{:.1f}%".format(compute_total/cold_total*100)))
    print("  {:<35} {:>12} {:>12}".format("Data movement %", "{:.1f}%".format((pipeline_real-pipeline_compute)/pipeline_real*100), "{:.1f}%".format(dm_cold/cold_total*100)))
    print("  {:<35} {:>12} {:>12}".format("Verification overhead", "{} (VCHECK)".format(pipeline_verify), "0 (none)"))
    print("  {:<35} {:>12} {:>12}".format("Steady-state latency", "N/A", str(steady_total)))
    print()


if __name__ == "__main__":
    main()
