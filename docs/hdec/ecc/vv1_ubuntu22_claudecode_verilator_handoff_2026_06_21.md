# VV1 Ubuntu22.04 / ClaudeCode Verilator 验证交接

日期：2026-06-21

目标版本：`VV1`

本文给 Ubuntu22.04 上的 ClaudeCode 使用。目标是在 CVA6/Verilator/RISC-V GCC 环境里验证 VV1 的真实软件调度硬件执行能力，而不是只跑 Vivado testbench。

## 版本获取

建议同时支持分支和 tag：

```bash
git fetch origin
git checkout -B VV1 origin/VV1
git submodule update --init --recursive
```

如果只想固定到不可移动版本：

```bash
git fetch origin --tags
git checkout VV1
git submodule update --init --recursive
```

必须记录：

```bash
git rev-parse HEAD
git status --short
verilator --version
riscv64-unknown-elf-gcc --version
```

预期 HEAD 应落在 `3f1406f0` 之后的 VV1 文档提交。

## 需要验证什么

### 必测 1：HDC 基础训练 + 推理

目的：确认普通 HDC 硬件原语仍然可由 RISC-V 软件调度。

建议先跑现有汇编程序：

- `verif/hdec/hdc_inference_test.S`
- `verif/hdec/hdc_e2e_train_infer_test.S`

验收：

- 程序退出码为 0。
- HDEC 事件日志里能看到 `VADDR/VWR64/HCNTADD/HCNTCLIP/HMATCH`。
- `hdc_e2e_train_infer_test.S` 的 Ladder A/B/C 均通过。

注意：这两个是基础训练/推理自检，不是 VV1 top-k 自学习准确率测试。

### 必测 2：HDC VV1 top-k self-learning

目的：确认软件库可以调度 RTL 硬件完成 top-k fixed-density prototype、AND-overlap 推理和 mistake-only 自学习。

先生成两个 Vivado 已对齐过的 fixture：

```bash
mkdir -p reports/hdec/vv1_ubuntu/fixture_uci_har_l256_seed7
python3 scripts/hdec/algo/gen_hdc_selflearn_fixture.py \
  --dataset uci_har \
  --model L_diffmax_topk256_self_mistake \
  --dim 1024 \
  --seed 7 \
  --out reports/hdec/vv1_ubuntu/fixture_uci_har_l256_seed7 \
  --data-dir reports/hdec/vv1_ubuntu/data

mkdir -p reports/hdec/vv1_ubuntu/fixture_wisdm_k256_seed1
python3 scripts/hdec/algo/gen_hdc_selflearn_fixture.py \
  --dataset wisdm_ar_user_split \
  --model K_own_topk256_self_mistake \
  --dim 1024 \
  --seed 1 \
  --out reports/hdec/vv1_ubuntu/fixture_wisdm_k256_seed1 \
  --data-dir reports/hdec/vv1_ubuntu/data
```

脚本会自动下载 UCI HAR 和 WISDM 数据。如果网络不可用，可以把 Windows 端已有的数据缓存复制到 `reports/hdec/vv1_ubuntu/data`。

生成后检查：

```bash
cat reports/hdec/vv1_ubuntu/fixture_uci_har_l256_seed7/summary.json
cat reports/hdec/vv1_ubuntu/fixture_wisdm_k256_seed1/summary.json
```

参考结果：

| Fixture | Correct | Accuracy | Updates |
| --- | ---: | ---: | ---: |
| UCI HAR / `L_diffmax_topk256_self_mistake` / seed 7 | 2598/2947 | 0.881574483 | 349 |
| WISDM / `K_own_topk256_self_mistake` / seed 1 | 1078/1643 | 0.656116859 | 565 |

#### 软件调度要求

不要在 RTL 里实现 top-k 排序器。Ubuntu 侧要写 C/C++ 或汇编软件库，执行下面流程：

1. 把 `initial_proto.mem` 写入 HDEC VRF 的 class slots。
2. 每个样本：
   - 把 `query_words` 写入 query slot。
   - 对每个 class 调一次 `HSIM(query_slot, class_slot)`。
   - 软件用分数选择预测类别。
   - 软件按 fixture 的 `update_flag/update_cls/suppress_cls` 或自己复现 Python 规则做更新。
   - 如果更新，把新 prototype 写回对应 class slot。
3. 结束后读回 class prototypes，逐 word 比较 `final_proto.mem`。

验收必须同时满足：

- `correct_count` 与 `summary.json.correct` 完全一致。
- `updates` 与 `summary.json.updates` 完全一致。
- 每个样本每个 class 的 HSIM score 与 `samples.mem` 中的 class scores 一致。
- 最终 VRF prototype 与 `final_proto.mem` 逐 64-bit word 一致。

### 必测 3：HSIM/HMATCH 的新相似度语义

VV1 的相似度不是 XOR distance，而是：

```text
score = popcount(query & prototype)
```

请写一个最小测试确认：

- query = all ones，prototype = all ones，HSIM score 应为 1024。
- query = all ones，prototype = all zeros，HSIM score 应为 0。
- query = `0xAAAAAAAA...`，prototype = `0xAAAAAAAA...`，HSIM score 应为 512。
- HMATCH 返回最高 overlap 的 class。

如果旧测试仍按 min Hamming distance 检查，需要同步改成 max overlap。

### 必测 4：ECC PMUL 功能和周期

目的：确认 VV1 没有破坏 ECC 点乘。

RISC-V 软件需要通过 `HDEC_ECC_STATUS` 启动 PMUL：

```text
operand[30]    = 1       // start PMUL
operand[17:12] = out_x
operand[11:6]  = point_x
operand[5:0]   = scalar
```

其中：

- `point_y = point_x + 1`
- `out_y = out_x + 1`
- 标量和点坐标按现有 testbench 的 4x64 VRF row 格式写入。

验收：

- PMUL 输出 X/Y 与 Vivado `tb_hdec_ecc_pmul_profile_v27.sv` 的参考点乘结果一致。
- `PMUL wall cycles = 190151`，不得因为 HDC 修改而变多。
- ECC reduce、ECC add、ECC align 的基础功能保持通过。

建议把 Verilator 日志里输出这些字段：

```text
PMUL_PROFILE_WALL_CYCLES=190151
PMUL_STATUS_LOW16=<status[31:16]>
PMUL_X_MATCH=1
PMUL_Y_MATCH=1
```

### 建议补测：HDC/ECC 交错

如果 CVA6/Verilator 环境支持较长仿真，补测 PMUL 运行期间插入 HDC 前台操作：

- 参考 Vivado testbench：`verif/hdec/tb_hdec_ecc_pmul_bg_hdc_loop_v31.sv`
- 目标：PMUL 后台状态不丢，HDC 前台 HSIM/HBIND/HCNTCLIP 能正确完成。

验收：

- PMUL 最终 X/Y 正确。
- HDC loop 的 HSIM/HMATCH 返回值正确。
- 日志记录 HDC 插入次数和 PMUL wall cycles。

## RISC-V intrinsic / inline asm 示例

下面只是示例，ClaudeCode 可按 CVA6 仿真框架调整寄存器约束。

```c
#include <stdint.h>

static inline uint64_t hdec_vaddr(uint64_t addr) {
  register uint64_t a0 asm("a0") = addr;
  register uint64_t rd asm("t0");
  asm volatile (".insn r 0x0B, 2, 3, %0, %1, zero"
                : "=r"(rd) : "r"(a0) : "memory");
  return rd;
}

static inline uint64_t hdec_vwr64(uint64_t data) {
  register uint64_t a0 asm("a0") = data;
  register uint64_t rd asm("t0");
  asm volatile (".insn r 0x0B, 0, 2, %0, %1, zero"
                : "=r"(rd) : "r"(a0) : "memory");
  return rd;
}

static inline uint64_t hdec_vrd64(void) {
  register uint64_t rd asm("t0");
  asm volatile (".insn r 0x0B, 1, 2, %0, zero, zero"
                : "=r"(rd) :: "memory");
  return rd;
}

static inline uint64_t hdec_hsim(uint64_t operand) {
  register uint64_t a0 asm("a0") = operand;
  register uint64_t rd asm("t0");
  asm volatile (".insn r 0x0B, 7, 2, %0, %1, zero"
                : "=r"(rd) : "r"(a0) : "memory");
  return rd;
}

static inline uint64_t hdec_hmatch(uint64_t operand) {
  register uint64_t a0 asm("a0") = operand;
  register uint64_t rd asm("t0");
  asm volatile (".insn r 0x0B, 1, 3, %0, %1, zero"
                : "=r"(rd) : "r"(a0) : "memory");
  return rd;
}

static inline uint64_t hdec_ecc_status(uint64_t operand) {
  register uint64_t a0 asm("a0") = operand;
  register uint64_t rd asm("t0");
  asm volatile (".insn r 0x0B, 4, 3, %0, %1, zero"
                : "=r"(rd) : "r"(a0) : "memory");
  return rd;
}

static inline uint64_t hsim_operand(unsigned query_slot, unsigned class_slot) {
  return ((uint64_t)class_slot << 4) | (uint64_t)query_slot;
}

static inline uint64_t hmatch_operand(unsigned query_slot,
                                      unsigned class_base_slot,
                                      unsigned num_classes) {
  return ((uint64_t)num_classes << 16)
       | ((uint64_t)class_base_slot << 4)
       | (uint64_t)query_slot;
}

static inline uint64_t ecc_pmul_operand(unsigned out_x,
                                        unsigned point_x,
                                        unsigned scalar) {
  return (1ULL << 30)
       | ((uint64_t)out_x << 12)
       | ((uint64_t)point_x << 6)
       | (uint64_t)scalar;
}
```

VRF 1024-bit HDC slot 写入顺序：

```c
static void write_hv_slot(unsigned slot, const uint64_t words[16]) {
  for (unsigned word = 0; word < 16; word++) {
    unsigned bank = word & 3;
    unsigned entry_off = (word >> 2) & 3;
    unsigned entry = (slot << 2) + entry_off;
    hdec_vaddr(((uint64_t)bank << 6) | entry);
    hdec_vwr64(words[word]);
  }
}

static void read_hv_slot(unsigned slot, uint64_t words[16]) {
  for (unsigned word = 0; word < 16; word++) {
    unsigned bank = word & 3;
    unsigned entry_off = (word >> 2) & 3;
    unsigned entry = (slot << 2) + entry_off;
    hdec_vaddr(((uint64_t)bank << 6) | entry);
    words[word] = hdec_vrd64();
  }
}
```

## 最终报告格式

请在 Ubuntu 侧生成一个 Markdown 报告，至少包含：

```text
# VV1 Ubuntu22.04 Verilator Report

Commit:
Toolchain:
CVA6 version:
Verilator version:
RISC-V GCC version:

## HDC basic train/infer
PASS/FAIL, logs, cycle count if available

## HDC top-k self-learning
UCI HAR: correct, accuracy, updates, final_proto_match
WISDM: correct, accuracy, updates, final_proto_match

## HDC similarity semantics
HSIM all-one score:
HSIM zero score:
HSIM 0xAAAA score:
HMATCH best class:

## ECC PMUL
PMUL wall cycles:
X match:
Y match:
ECC reduce/add/align:

## Regressions or differences from Vivado xsim
List exact mismatch sample/class/word if any.
```

## 不要改 RTL 的情况

如果 Ubuntu 结果和 Vivado xsim 不一致，先查这些：

- HSIM/HMATCH 是否仍按旧 XOR distance 判断。
- top-k tie-break 是否和 Python fixture 一致。
- `samples.mem` 的 word 顺序是否按 16 个 64-bit word、bank=`word&3`、entry=`slot*4+(word>>2)` 写入。
- WISDM 的 user-disjoint split 是否被改了。
- PMUL 是否用了固定 233-bit full-width scalar schedule，而不是短标量特例。

只有确认不是软件调度、数据集、bit packing、tie-break、周期计数问题后，再考虑 RTL 修改。
