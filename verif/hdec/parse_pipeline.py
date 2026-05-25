#!/usr/bin/env python3
"""Stage 2: hdc_pipeline_test full breakdown."""

# --- Raw data from sequential HDEC_PERF log ---
# Phase 1: Clear/Init
# Phase 2: Data Preload (fill loop: 32x VADDR + 32x VWR64)
# Phase 3-10: Compute + VCHECK

phases = [
    ("1. Clear/Init", [
        ("HCLR x7", 7, 7, 49),
        ("BCLR x1", 1, 19, 19),
    ]),
    ("2. Data Preload (fill HV1/HV3)", [
        ("VADDR", 32, 3, 96),
        ("VWR64", 32, 3, 96),
    ]),
    ("3. HBIND Compute", [
        ("HBIND", 1, 15, 15),
    ]),
    ("4. VCHECK (HBIND verify)", [
        ("VADDR", 1, 3, 3),
        ("VRD64", 1, 4, 4),
    ]),
    ("5. HBUNDLE4 Compute", [
        ("HBUNDLE4", 1, 63, 63),
    ]),
    ("6. VCHECK x2 (HBUNDLE4 verify)", [
        ("VADDR", 2, 3, 6),
        ("VRD64", 2, 4, 8),
    ]),
    ("7. HCLIP Compute", [
        ("HCLIP", 1, 39, 39),
    ]),
    ("8. VCHECK x2 (HCLIP verify)", [
        ("VADDR", 2, 3, 6),
        ("VRD64", 2, 4, 8),
    ]),
    ("9. HSIM Compute", [
        ("HSIM", 1, 18, 18),
    ]),
    ("10. HMATCH Compute (5 classes)", [
        ("HMATCH", 1, 78, 78),
    ]),
]

sep = "-" * 90

print("=" * 90)
print("A. HDC_PIPELINE_TEST PHASE-BY-PHASE BREAKDOWN")
print("=" * 90)
print()
print("{:<40} {:<25} {:>6} {:>7} {:>8}".format(
    "Phase", "Op", "Count", "cyc/op", "Cycles"))
print(sep)

total = 0
for phase_name, ops in phases:
    phase_total = sum(c for _, _, _, c in ops)
    total += phase_total
    first = True
    for op_name, count, cyc_per, cyc_total in ops:
        label = phase_name if first else ""
        print("{:<40} {:<25} {:>6} {:>7} {:>8}".format(
            label, op_name, count, cyc_per, cyc_total))
        first = False
    print("  {:-<80} subtotal: {}".format("", phase_total))
    print()

print("TOTAL: {} HDEC_PERF cycles".format(total))
print()

# --- Category summary ---
print("=" * 90)
print("B. CATEGORY BREAKDOWN")
print("=" * 90)
print()

categories = [
    ("Clear/Init", ["HCLR", "BCLR"], 68),
    ("Data Preload (VADDR+VWR64)", ["VADDR", "VWR64"], 192),
    ("HDC Compute Kernel", ["HBIND", "HBUNDLE4", "HCLIP", "HSIM", "HMATCH"], 213),
    ("Verification Overhead (VCHECK)", ["VADDR (VCHECK)", "VRD64 (VCHECK)"], 35),
]

print("{:<45} {:>10} {:>8}".format("Category", "Cycles", "%"))
print("-" * 65)
for name, ops, cyc in categories:
    pct = cyc / total * 100
    print("{:<45} {:>10} {:>7.1f}%".format(name, cyc, pct))
print("{:<45} {:>10}".format("TOTAL", total))
print()

# --- Without verification ---
print("=" * 90)
print("C. STRIPPED OF VERIFICATION OVERHEAD (real workload estimate)")
print("=" * 90)
print()

real_total = total - 35
real_cats = [
    ("Clear/Init", 68),
    ("Data Preload (VADDR+VWR64)", 192),
    ("HDC Compute Kernel", 213),
]

print("{:<45} {:>10} {:>8}".format("Category", "Cycles", "%"))
print("-" * 65)
for name, cyc in real_cats:
    pct = cyc / real_total * 100
    print("{:<45} {:>10} {:>7.1f}%".format(name, cyc, pct))
print("{:<45} {:>10}".format("TOTAL", real_total))
print()
print("Compute-to-Data-Movement ratio: 213 / (68+192) = {:.2f}".format(213/(68+192)))
print()

# --- Compute detail ---
print("=" * 90)
print("D. COMPUTE KERNEL BREAKDOWN")
print("=" * 90)
print()

compute_ops = [
    ("HBIND", 1, 15, 15),
    ("HBUNDLE4", 1, 63, 63),
    ("HCLIP", 1, 39, 39),
    ("HSIM", 1, 18, 18),
    ("HMATCH (5 classes)", 1, 78, 78),
]

print("{:<25} {:>6} {:>8} {:>8} {:>8}".format(
    "Op", "Count", "Cycles", "%/Kernel", "%/Total"))
print("-" * 60)
for name, count, cyc_per, cyc_tot in compute_ops:
    print("{:<25} {:>6} {:>8} {:>7.1f}% {:>7.1f}%".format(
        name, count, cyc_tot, cyc_tot/213*100, cyc_tot/total*100))
print("{:<25} {:>6} {:>8}".format("Kernel Total", "", 213))
print()

# --- Normalized throughput ---
print("=" * 90)
print("E. NORMALIZED THROUGHPUT (bits/cycle)")
print("=" * 90)
print()

throughput = [
    ("HBIND", 1, 15, 1024),
    ("HPERM", 1, 15, 1024),
    ("HSIM", 1, 18, 1024),
    ("HBUNDLE4", 4, 63, 4096),
    ("HCLIP", 1, 39, 1024),
    ("HMATCH (5 class)", 5, 78, 5120),
]

print("{:<22} {:>6} {:>8} {:>10} {:>12} {:>12}".format(
    "Op", "HVs", "Cycles", "Total bits", "bits/cycle", "HV/cycle"))
print("-" * 75)
for name, hvs, cyc, bits in throughput:
    bpc = bits / cyc
    hpc = hvs / cyc
    print("{:<22} {:>6} {:>8} {:>10} {:>11.1f} {:>11.4f}".format(
        name, hvs, cyc, bits, bpc, hpc))

print()
print("HMATCH asymptotic (N->inf): bits/cycle = 1024/15 = 68.3")
print()

# --- Data movement breakdown ---
print("=" * 90)
print("F. DATA MOVEMENT BREAKDOWN")
print("=" * 90)
print()

dm_items = [
    ("VADDR (preload: fill HV data)", 32, 3, 96),
    ("VWR64 (preload: write HV data)", 32, 3, 96),
    ("VADDR (VCHECK: readback verify)", 5, 3, 15),
    ("VRD64 (VCHECK: readback verify)", 5, 4, 20),
]

print("{:<40} {:>6} {:>7} {:>8}".format("Purpose", "Count", "cyc/op", "Cycles"))
print("-" * 65)
for purpose, count, cpo, cyc in dm_items:
    print("{:<40} {:>6} {:>7} {:>8}".format(purpose, count, cpo, cyc))

preload_total = 96 + 96
vcheck_total = 15 + 20
print()
print("Preload subtotal:  {} cycles ({:.1f}% of data movement)".format(
    preload_total, preload_total/(preload_total+vcheck_total)*100))
print("VCHECK subtotal:   {} cycles ({:.1f}% of data movement)".format(
    vcheck_total, vcheck_total/(preload_total+vcheck_total)*100))
print("Data movement total: {} cycles ({:.1f}% of all HDEC_PERF cycles)".format(
    preload_total + vcheck_total, (preload_total+vcheck_total)/total*100))

print()
print("=" * 90)
print("G. KEY JUDGMENTS")
print("=" * 90)
