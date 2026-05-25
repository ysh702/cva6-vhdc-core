# HDEC Phase 1 HDC Baseline Results Before ECC

## Purpose

This document records the HDEC HDC benchmark baseline before integrating tag
dataflow, shadow registers, and ECC. It serves as the reference point for
future design comparisons.

## Git Baseline

- branch: `hdec-phase1`
- tag: `hdec-phase1-hdc-baseline-pre-ecc`

## Environment

- toolchain: `riscv64-unknown-elf-gcc` (-march=rv64gc_zifencei -mabi=lp64d)
- simulator: `work-ver/Variane_testharness` (Verilator)
- RTL status: pre-ECC, HDC primitives only
- HV dimension: 1024-bit (8 slots x 1024 bits, 2 accumulators)

---

## Stage 3: Single-query HDC Inference Benchmark

### Files

- test: `verif/hdec/hdc_inference_test.S`
- parser: `verif/hdec/parse_inference_perf.py`

### Command

```
riscv64-unknown-elf-gcc -march=rv64gc_zifencei -mabi=lp64d \
  -nostartfiles -nostdlib -mcmodel=medany \
  -I verif/tests/custom/env -I verif/tests/custom/common \
  -T verif/hdec/hdec_link.ld verif/tests/custom/common/crt.S \
  verif/hdec/hdc_inference_test.S -o tmp/hdec_logs/hdc_inference_test.elf

work-ver/Variane_testharness tmp/hdec_logs/hdc_inference_test.elf \
  > tmp/hdec_logs/hdc_inference_test.log
```

### Result

- PASS
- tohost = 0
- ILLEGAL = 0
- Predicted class: 2 (expected 2)
- min_dist = 0

### Cycle Breakdown

| Metric | Cycles | % |
|--------|--------|---|
| Cold-start total | 912 | 100% |
| Init (HCLR+BCLR) | 75 | 8.2% |
| Data preload | 672 | 73.7% |
| Compute kernel (HBUNDLE4+HCLIP+HMATCH) | 165 | 18.1% |
| Steady-state per query | 165 | - |

### Key Observations

- Data preload dominates cold-start (73.7%). Prototypes can be amortized across queries.
- Steady-state compute is 165 cycles: HBUNDLE4 (63) + HCLIP (39) + HMATCH-4class (63).
- No verification overhead (zero VCHECK).
- HMATCH formula verified: 3 + N x 15 = 63 cycles for N=4 classes.

---

## Stage 4: E2E Train+Infer Ladder Benchmark

### Files

- test: `verif/hdec/hdc_e2e_train_infer_test.S`
- parser: `verif/hdec/parse_e2e_train_infer_perf.py`

### Command

```
riscv64-unknown-elf-gcc -march=rv64gc_zifencei -mabi=lp64d \
  -nostartfiles -nostdlib -mcmodel=medany \
  -I verif/tests/custom/env -I verif/tests/custom/common \
  -T verif/hdec/hdec_link.ld verif/tests/custom/common/crt.S \
  verif/hdec/hdc_e2e_train_infer_test.S -o tmp/hdec_logs/hdc_e2e_train_infer_test.elf

work-ver/Variane_testharness tmp/hdec_logs/hdc_e2e_train_infer_test.elf \
  > tmp/hdec_logs/hdc_e2e_train_infer_test.log
```

### Result

- PASS
- tohost = 0
- ILLEGAL = 0

### Ladder Results

| Ladder | Description | Result |
|--------|-------------|--------|
| A | Sample encoding self-check (4 classes) | PASS |
| B | Prototype build self-check (4 classes) | PASS |
| C | Full train (4x4) + inference (8 samples) | PASS |

### Inference Accuracy

8/8 = 100%, all min_dist = 0.

### Cycle Breakdown

| Region | Cycles | % |
|--------|--------|---|
| A. Sample Encoding Self-Check | 2,656 | 7.3% |
| B. Prototype Build Self-Check | 14,384 | 39.6% |
| C. Full Training (4 classes x 4 samples) | 15,239 | 42.0% |
| D. Inference (8 samples) | 4,036 | 11.1% |
| **Total** | **36,315** | **100%** |

### Data Movement vs Compute

| Category | Training (A+B+C-train) | Inference (D) |
|----------|----------------------|---------------|
| Data movement | 24,960 (77.3%) | 2,685 (66.5%) |
| Compute | 7,319 (22.7%) | 1,351 (33.5%) |
| Total | 32,279 | 4,036 |
| Per sample | — | 504 |

### Key Observations

- Complete synthetic train+infer HDC flow passes on Verilator.
- HBUNDLE4 accumulation verified: repeated calls without BCLR accumulate correctly into the same acc.
- Data movement remains dominant due to explicit per-HV fill policy.
- Per-sample inference: 504 cycles (feature preload + encode + match).
- 4 classes x 4 training samples x 4 features is sufficient to build correct class prototypes.

---

## Limitations

- Deterministic synthetic benchmark only; not a real sensor dataset.
- No ECC yet.
- No tag dataflow yet.
- No shadow register execution model yet.
- No Vivado synthesis / timing / power data yet.
- Data movement ratio is high due to explicit fill-per-HV policy; optimized preload strategies not yet explored.

---

## Use as Future Comparison Baseline

The following future additions must be compared against this baseline:

| Addition | Compare |
|----------|---------|
| Tag dataflow | correctness, cycles, HDEC stall |
| Shadow registers | correctness, cycles, context switch overhead |
| ECC background execution | correctness, cycles, HDEC-ECC interaction |
| Vivado synthesis | LUT, FF, BRAM, DSP |
| Vivado timing | Fmax |
| Vivado power | total / dynamic power |
