# HDEC Phase 1 — Implementation Status

## Current Commit Chain

```
3a43bb7f HDEC Phase1: add Popcount/Compressor core and real hsim
c550489a HDEC Phase1: add Boolean/Mask core and real hbind with operand isolation
3f04436e HDEC Phase1: add bclr accumulator clear command
515ffa5a HDEC Phase1: add hclr VRF clear command
aa675bad HDEC Phase1: verify multi-index VRF addressing
fec70477 HDEC Phase1: fix multi-bank VRF access transaction handling
6b113d3e HDEC Phase1 minimal baseline: CV-X-IF + vaddr + single-bank VRF access
```

---

## Completed Capabilities

### CV-X-IF Integration
- `hdec_cvxif_wrapper.sv`: single-outstanding-transaction FSM
  - W_IDLE → W_WAIT_REG → W_SEND_TOP → W_WAIT_TOP → W_RESULT
  - `issue_ready` gated by state, not by `matched`
  - `accept = matched && issue_ready` — clean reject for non-HDEC opcodes
  - All top_* signals from latched registers (Rule 9)
- `ariane.sv` updated to instantiate `hdec_cvxif_wrapper` (replaces cvxif_example_coprocessor)

### VRF Management (5 instructions, all verified)
| Instruction | Behavior | Encoding |
|-------------|----------|----------|
| vaddr | Set internal VRF address register from rs1[7:0] | funct7=3, funct3=2 |
| vwr64 | Write rs1[63:0] to VRF[stored_bank][stored_idx] | funct7=2, funct3=0 |
| vrd64 | Read VRF[stored_bank][stored_idx] → rd | funct7=2, funct3=1 |
| hclr | Clear 1 HV slot: 4 consecutive VRF entries × 4 banks | funct7=2, funct3=2 |
| bclr | Clear 1 accumulator: 16 consecutive VRF entries × 4 banks | funct7=2, funct3=3 |

### HDC Compute (2 real instructions)
| Instruction | Behavior | Encoding |
|-------------|----------|----------|
| hbind | src0 XOR src1 → dst, 1024-bit (4-chunk loop) | funct7=2, funct3=5, rs1[11:0] encodes dst/src0/src1 |
| hsim | Hamming distance = popcount(src0 XOR src1), 0–1024 | funct7=2, funct3=7, rs1[7:0] encodes src0/src1 |

### VRF Hardware
- 4-bank × 64-entry × 64-bit = 256-bit × 64 entries = 16 Kbit
- REG/LUTRAM default (parameterized, not hard BRAM)
- Synchronous read (1-cycle), synchronous write, write-forwarding
- Power-on init FSM: 256-cycle clear
- Per-bank: 1 read port + 1 write port

### Lane Compute Units
- **Boolean/Mask Core** (`hdec_lane_boolean_mask.sv`): pure combinational
  - XOR_ONLY, MASK_XOR_DELTA, MASK_SELECT
  - No FSM, no flops, no PASS_A
  - Used by hbind and hsim (XOR diff computed here, not in hdec_top)
- **Popcount/Compressor Core** (`hdec_lane_popcount_compressor.sv`): pure combinational
  - HDC_POPCOUNT: `$countones(diff)` → 7-bit (0–64)
  - ECC_COMPRESS: 3:2 CSA (maj/sum/carry/cout), structurally present, intentionally unconnected
  - Used by hsim: takes bool_result (XOR diff) as diff_i, popcount routed back to hdec_top via `popcount_count_o`
- **hsim data path**: hdec_top reads src0/src1 from VRF → Lane boolean_mask (XOR) → Lane popcount_compressor (count) → hdec_top accumulates per-chunk distance → returns total Hamming distance 0–1024
- **ECC_COMPRESS reserved**: csa_sum/csa_carry/csa_cout ports present but unconnected. ECC control, Shadow RF, and tag routing not implemented yet

---

## Lane Architecture Principles

### Static Parallel Function Blocks
- Each compute block is a **self-contained combinational module** instantiated inside the Lane
- No valid/ready/busy FSM inside compute cores — control is managed at the top/engine level
- Cores are placed side-by-side, not cascaded in a rigid pipeline

### Simple Cores: Pure Combinational
- Boolean/Mask and Popcount/Compressor are always-comb
- Zero pipeline delay from input to output
- Operand isolation (`bool_valid_i`) gates all inputs to 0 when inactive, preventing dynamic power

### Complex Cores: Future Local Micro-Pipelines
- Operators like SAIR multiplier or large shifters can add thin register shells inside the Lane
- Local register stages do NOT change top-level CV-X-IF or VRF protocols
- Lane module boundary remains stable

### Operand Isolation
- All bool-path inputs (src_a, src_b, mask, mode) gated to 0 when `bool_valid_i == 0`
- Prevents spurious combinational toggling and dynamic power in inactive cycles

### Future: Engine-Level Arbiter + Tag Routing
- Current transitional architecture: `hdec_top` directly manages VRF access and Lane compute dispatch
- Target: `hdec_hdc_engine` receives decoded instructions, arbitrates across 7 controllers, dispatches tagged Lane compute requests, collects results
- Tag routing enables out-of-order chunk processing and resource sharing

### HDC Main VRF / ECC Shadow RF Separation (Future)
- HDC uses the main 4-bank VRF (64 × 256-bit)
- ECC will use a dedicated Shadow RF (8 × 256-bit) for X1/Z1/X2/Z2/scratch
- Shadow RF avoids VRF port contention between HDC and ECC

---

## HDC / ECC Reuse Points

### Boolean/Mask Core
| Consumer | Mode | Use |
|----------|------|-----|
| HDC hbind | XOR_ONLY | Bind two 1024-bit HV vectors |
| Future ECC cswap | MASK_SELECT | Conditional coordinate swap in Montgomery ladder |
| Future ECC mask-select | MASK_SELECT | Field element selection under condition flag |

### Popcount/Compressor Core
| Consumer | Mode | Use |
|----------|------|-----|
| HDC hsim | HDC_POPCOUNT | Hamming distance over 1024-bit XOR diff (4 chunks × 4 lanes parallel) |
| Future ECC SAIR | ECC_COMPRESS | 3:2 carry-save reduction in GF(2^256) shift-and-add multiplier |
| Reserved ports | — | `csa_sum_o[63:0]`, `csa_carry_o[63:0]`, `csa_cout_o` — present, unconnected, no lint impact |

---

## Test Results

### Assembly Integration Tests
| Test | Result | Description |
|------|--------|-------------|
| `multi_index_test` | SUCCESS | bank0/idx0, bank1/idx7, bank2/idx15, bank3/idx63 w/r |
| `hclr_test` | SUCCESS | Clear 4-entry HV slot, verify isolation |
| `bclr_test` | SUCCESS | Clear 16-entry accumulator, verify isolation |
| `hbind_test` | SUCCESS | XOR bind 1024-bit HV0+HV1→HV2, verify source intact |
| `hsim_test` | SUCCESS | Identical HV→0, complementary HV→1024, mixed pattern→verified |

### Python Golden Models
| Script | Coverage |
|--------|----------|
| `test_boolean_mask.py` | XOR_ONLY / MASK_XOR_DELTA / MASK_SELECT, 1000 random vectors each |
| `test_popcount_compressor.py` | HDC_POPCOUNT (1000+) / ECC_COMPRESS (1000+) |

### Build
- `make verilate`: PASS (zero errors, zero warnings beyond project-default suppressions)

---

## Remaining Phase 1 Instructions (not yet implemented)

| Instruction | Needed Core | Description |
|-------------|-------------|-------------|
| hperm | Shift-Align Core | HDC permute (cyclic shift/rotate across lanes); ECC future SAIR partial-product shift alignment |
| badd | Counter Core | Bundle add (HDC accumulation / counter increment) |
| clip | Compare-Select Core | Threshold binarization |
| hsearch | — | Nearest-neighbor search (likely reuses hsim popcount + comparator) |
| ECC ops | GF(2^256) SAIR multiplier | GF multiply, square, ITA, Montgomery ladder |
| Infrastructure | Engine-level arbiter + tag routing | Migrate hdec_top FSM to hdec_hdc_engine; Shadow RF for ECC |

---

## Next Recommended Step

**Shift-Align Core + real hperm**

Rationale:
- hperm is the next HDC instruction in dependency order (no dependency on badd/clip)
- Shift-Align Core can handle both HDC cyclic permute and ECC SAIR partial-product shift alignment
- Neighbor Lane ports (`neighbor_in_i` / `neighbor_out_o`) are already wired for cross-lane data movement
- Phase 1 scope: test HDC hperm only; ECC SAIR control not connected

Expected implementation pattern (consistent with hbind/hsim):
1. New combinational core: `hdec_lane_shift_align.sv` (barrel shift / rotate / mask-align)
2. Lane instantiation + operand isolation
3. hdec_top: hperm FSM (parse src/dst/shift-amount, 4-chunk loop, cross-lane neighbor routing)
4. `hperm_test.S` + golden model
5. Regression on existing tests

---

## File Inventory (current)

```
core/hdec/rtl/
  hdec_pkg.sv
  hdec_resource_pkg.sv
  hdec_cvxif_wrapper.sv          ← FSM wrapper, stable
  hdec_top.sv                    ← transitional control FSM
  hdec_vrf_64x256.sv             ← 4-bank VRF
  hdec_lane_4x64.sv              ← Lane with bool/popcount static blocks
  hdec_lane_boolean_mask.sv      ← Boolean/Mask core (combinational)
  hdec_lane_popcount_compressor.sv ← Popcount/CSA core (combinational)
  hdec_cmd_decode.sv             ← (source present, not instantiated)
  hdec_hdc_engine.sv             ← (source present, not instantiated)
  hdec_hdc_*_ctrl.sv × 7        ← (source present, not instantiated)

core/Flist.cva6                  ← updated
corev_apu/src/ariane.sv          ← updated

verif/hdec/
  multi_index_test.S
  hclr_test.S
  bclr_test.S
  hbind_test.S
  hsim_test.S
  test_boolean_mask.py
  test_popcount_compressor.py
```
