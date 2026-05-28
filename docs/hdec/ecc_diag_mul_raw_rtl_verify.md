# GF(2^256) Diagonal Popcount/Parity Raw Multiplier — RTL Verification Report

Date: 2026-05-28
Branch: vrf-lutram-inference-v1
Baseline: 1707a6d6 (hdec-phase1-hdc-baseline-pre-ecc)

---

## 1. Algorithm Description

### Shift-XOR Reference
```
acc = 0
for i in 0..255:
    if B[i] == 1:
        acc ^= A << i
return acc  // 511-bit raw product
```

### Diagonal Formula
```
P[k] = XOR over all valid i of A[i] & B[k-i]
where 0 <= i < 256 and 0 <= k-i < 256
```

### 4-Lane 64-bit Mapping
- 4 lanes, each covering a 64-bit slice of A (bases: 0, 64, 128, 192)
- Per lane: build 64-bit vector v where v[t] = A[base+t] & B[k-base-t]
- Lane parity = XOR-reduce(v)
- P[k] = lane0_parity ^ lane1_parity ^ lane2_parity ^ lane3_parity

---

## 2. Python Software Verification

| Test | Result |
|---|---|
| 8-bit small-scale example | PASS (all 3 algorithms match) |
| 8 boundary tests | PASS |
| 1000 random 256-bit pairs | PASS |
| Vector export (8 boundary + 100 random) | 108 vectors exported |

---

## 3. RTL Implementation

### Module
- **Name**: `gf2_256_diag_mul_raw`
- **File**: `core/hdec/rtl/gf2_256_diag_mul_raw.sv`

### Interface
```
input  clk_i, rst_ni
input  start_i
input  [255:0] a_i, b_i
output busy_o, done_o
output [510:0] product_o
```

### State Machine
- **IDLE**: waits for start_i, latches operands
- **RUN**: k = 0..510, one product bit per cycle
- **DONE_S**: asserts done_o for 1 cycle, product_o stable

### Combinational Core
- `function automatic logic lane_diag_parity(a, b, base, k)` computes one lane's parity
- Uses `int` arithmetic for clean bounds checking: `bj >= 0 && bj < 256`
- 4 function calls in parallel via continuous assignments
- `product_bit = ^lane_parity`

### Latency
- 512 cycles from start_i to done_o (511 compute + 1 done)
- done_o appears at cycle 512 after start

---

## 4. Verilator Verification

| Metric | Result |
|---|---|
| Vectors | 108 (8 boundary + 100 random) |
| Passed | 108/108 |
| Failed | 0 |
| Timeout | 0 |
| done latency | ~511-513 cycles per vector |

### Bug Found and Fixed
- **Root cause**: `a_reg`/`b_reg` only latched on `state_q == IDLE`, but restart from `DONE_S` never re-latched new operands.
- **Fix**: Expand latch condition to `state_q == IDLE || state_q == DONE_S`.

---

## 5. Conclusion

- Raw product hardware prototype is **verified correct** against Python golden model
- GF(2^256) reduction is **not yet implemented**
- HDEC popcount tree integration is **not yet done**
- Vivado OOC synthesis is **not yet run**
- Next step: hand off to Win11 Codex App for Vivado OOC synthesis evaluation

---

## 6. File Inventory

### New files (not staged):
- `core/hdec/rtl/gf2_256_diag_mul_raw.sv` — RTL module
- `verif/hdec/ecc_diag_mul/` — test directory
  - `tb_gf2_256_diag_mul_raw.cpp` — C++ Verilator testbench
  - `tb_gf2_256_diag_mul_raw.sv` — (unused) SV testbench
  - `tb_debug.sv` — debugging testbench
  - `Makefile` — build/run automation
- `tools/hdec/ecc_diag_mul_verify.py` — Python golden model + vector export
- `tools/hdec/ecc_diag_mul_vectors.txt` — 108 test vectors
- `tools/hdec/ecc_diag_mul_vectors.h` — C header (auto-generated)

### Modified files (not staged):
- `core/hdec/rtl/hdec_vrf_64x256.sv` — VRF LUTRAM patch (prior work)
