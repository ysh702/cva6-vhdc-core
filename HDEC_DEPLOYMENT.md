# HDEC-v1 协处理器 — 完整部署与验证指南

本文档面向另一台机器上的 Claude Code Agent，描述如何从零部署 CVA6 + HDEC 工具链并运行完整验证。

## 仓库地址

```
git clone https://github.com/ysh702/cva6.git
cd cva6
git checkout hdec-coprocessor
```

---

## 一、前提条件

| 工具 | 版本要求 | 检查命令 |
|------|---------|---------|
| RISC-V GCC | 13.x+ | `riscv64-unknown-elf-gcc --version` |
| Verilator | 5.x | `verilator --version` |
| Python 3 | 3.8+ | `python3 --version` |
| GNU Make | any | `make --version` |
| Spike/fesvr | 预编译 | 需 `libfesvr.a`, `libriscv.so`, `fesvr/dtm.h` |

---

## 二、HDEC 源文件清单

### RTL 文件 (1784 行 SystemVerilog 总计)

| 文件 | 行数 | 功能 |
|------|------|------|
| `core/hdec_xif_pkg.sv` | 147 | 10 条自定义指令编码 + OWNER 常量 |
| `core/ecc_full_adder.sv` | 24 | 1-bit 进位可切断全加器 |
| `core/hdec_lane.sv` | 217 | 64-bit Lane 流水线 + 6 级多态加法树 |
| `core/hdec_top.sv` | 1129 | HDC+ECC 融合协处理器顶层 (VRF + FSM + ITA) |
| `core/hdec_xif_coprocessor.sv` | 267 | CV-X-IF 协议包装器 |

### 测试与验证文件

| 文件 | 功能 |
|------|------|
| `verif/tests/custom/cv_xif/hdec_test_macros.h` | HDEC 汇编宏 (`.insn r` 格式) |
| `verif/tests/custom/cv_xif/hdec_full_test.S` | HDC+ECC 完整集成测试 |
| `verif/tests/custom/cv_xif/hdec_steal_test.S` | Cycle-Stealing 验证测试 |
| `verif/tests/custom/cv_xif/bench.c` | 5 模式基准测试 (M0-M4) |
| `verif/tests/custom/cv_xif/ecc_ref.py` | ECC GF(2^256) Python 参考模型 |

---

## 三、CVA6 集成修改清单

部署 HDEC 需要对 CVA6 v5.2.0 做以下修改（本仓库已在 `hdec-coprocessor` 分支完成）：

### 3.1 `corev_apu/src/ariane.sv`
将 `cvxif_example_coprocessor` 替换为 `hdec_xif_coprocessor`。

### 3.2 `core/Flist.cva6`
在文件末尾添加 5 个 HDEC 源文件路径。

### 3.3 `Makefile`
- 设置 `SPIKE_INSTALL_DIR` 指向 Spike 安装目录
- 修改 `--exe` elfloader 路径指向 `verif/core-v-verif/vendor/riscv/riscv-isa-sim/fesvr/`

### 3.4 环境依赖
- `libyaml-cpp.a` symlink 到 Spike lib 目录
- `config.h` 从 Spike include 复制到 verif 目录

---

## 四、编译与运行

### 4.1 Verilator 编译
```bash
cd /path/to/cva6
make verilate
```
生成 `work-ver/Variane_testharness`。

### 4.2 编译测试 ELF
```bash
# 链接脚本
cat > /tmp/hdec_link.ld << 'EOF'
OUTPUT_ARCH("riscv")
ENTRY(_start)
SECTIONS {
  . = 0x80000000;
  .text.init : { *(.text.init) }
  . = ALIGN(0x1000);
  .tohost : { *(.tohost) }
  . = ALIGN(0x1000);
  .text : { *(.text) }
  .data : { *(.data) }
  .sdata : { __global_pointer$ = . + 0x800; *(.srodata*) *(.sdata*) }
  .bss : { *(.bss) }
  _end = .;
}
EOF

# 集成测试
riscv64-unknown-elf-gcc -march=rv64gc_zifencei -mabi=lp64d \
    -nostartfiles -nostdlib \
    -I verif/tests/custom/env -I verif/tests/custom/cv_xif \
    -T /tmp/hdec_link.ld \
    verif/tests/custom/common/crt.S \
    verif/tests/custom/cv_xif/hdec_full_test.S \
    -o /tmp/hdec_full_test.elf

# 基准测试 (5 modes: MODE=0..4)
for m in 0 1 2 3 4; do
  riscv64-unknown-elf-gcc -march=rv64gc_zifencei -mabi=lp64d \
      -nostartfiles -nostdlib -DMODE=$m -mcmodel=medany \
      -I verif/tests/custom/env -I verif/tests/custom/cv_xif \
      -T /tmp/hdec_link.ld \
      verif/tests/custom/common/crt.S \
      verif/tests/custom/cv_xif/bench.c \
      -o /tmp/bench_m$m.elf
done
```

### 4.3 运行仿真
```bash
# 集成测试
./work-ver/Variane_testharness /tmp/hdec_full_test.elf

# 基准测试
./work-ver/Variane_testharness /tmp/bench_m3.elf  # HW_ECC-only
./work-ver/Variane_testharness /tmp/bench_m4.elf  # HW_HDC+ECC fused
```

---

## 五、基准测试模式定义

| MODE | 名称 | 说明 |
|------|------|------|
| 0 | SW_HDC | 纯 C 软件 HDC (1024-bit vectors) |
| 1 | SW_ECC | 纯 C 软件 GF(2^256) 乘法 |
| 2 | HW_HDC | 硬件 HDC-only, 4 features × 4 prototypes |
| 3 | HW_ECC | 硬件 ECC-only, 255-step Ladder + ITA + 256-bit FETCH |
| 4 | HW_FUSED | HDC+ECC 融合, ECC 后台执行, HDC 优先 |

---

## 六、HDEC-v1 关键架构特性

### 6.1 指令集 (10 条自定义指令, opcode=0x0B)

| 指令 | funct3 | 说明 |
|------|--------|------|
| HDEC_BIND | 0 | VRF XOR |
| HDEC_BUNDLE | 1 | 累加+二值化 |
| HDEC_MATCH | 2 | popcnt 汉明距离 |
| HDEC_INGEST | 3 | 写入 VRF |
| HDEC_BINARIZE | 4 | 阈值二值化 |
| HDEC_PERMUTE | 5 | 循环移位 |
| HDEC_ECC_START | 6 | 启动 ECC (K=rs1) |
| HDEC_ECC_FETCH | 7 | 读取 ECC 结果 (256-bit, word-indexed) |
| HDEC_CLEAR_CNT | 1+ | 清零累加器 (funct7=1) |
| HDEC_BUNDLE_ACCUM | 4+ | 累加 vs2=0 (funct7=1) |

### 6.2 VRF 分区

| 寄存器 | 用途 | Owner |
|--------|------|-------|
| 0-3 | Feature vectors | HDC |
| 4-7 | Prototype vectors | HDC |
| 8-12 | BIND/BUNDLE/MATCH work regs | HDC |
| 14 | X1/Z1/X2/Z2 | ECC |
| 15 | xG/T1/T2/scratch | ECC |

### 6.3 Lane 流水线

3 级流水线 (S1→mid→S2)，每级独立追踪 owner/ecc_mode/op_mode/data。

6 级多态加法树：L1(64→32)→L2(32→16)→L3(16→8)→mid-pipe→L4(8→4)→L5(4→2)→L6(2→1)。

ecc_mode=0: 正常进位 (HDC popcnt); ecc_mode=1: 进位切断 (ECC GF(2) XOR)。

### 6.4 ECC 算法

- Montgomery Ladder: 255 steps × 13 sub-steps, GF(2^256)
- ITA Itoh-Tsujii inversion chain: 1→2→3→6→12→15→30→60→120→240→255
- 256-bit ECC_FETCH: word-indexed (operand_a_i[1:0])
- Z1 × ZINV = 1 hardware self-check

### 6.5 调度原则

- HDC 优先：Lane S1 仲裁 HDC send phase 最高优先级
- ECC 填空隙：GF_MUL 仅在 Lane 空闲时注入 (cycle-stealing)
- HDC 不被阻塞：ready_o 不受 ECC 全局状态压制
- ECC VRF 读仅在 `state_q == ST_IDLE` 时启动

---

## 七、验证检查清单

部署后按此顺序验证：

1. `hdec_full_test.S` → `*** SUCCESS *** (tohost = 0)`
2. `bench_m3.elf` → `[ITA] DONE | XAFF = 3f57b8a5470cc4a2...`
3. `bench_m4.elf` → XAFF 同 M3
4. `python3 verif/tests/custom/cv_xif/ecc_ref.py` → `ALL PASS`

---

## 八、修复记录

| # | Bug | 根因 | 修复 |
|---|-----|------|------|
| 1 | INIT K 值错误 | `operand_a_i` 在 INIT uPC=1/2 时已变化 | `saved_ecc_k_q` 快照 |
| 2 | Early FETCH 阻塞 | ready_o=0 造成组合环 | pending-based 延迟 |
| 3 | Lane ecc_mode 共享 | L1-L3 用组合 `i_ecc_mode` | `s1_ecc_mode_q` 寄存器 |
| 4 | Lane op_mode 共享 | S2 用当前 S1 的 `s1_op_mode` | `mid_op_mode_q` 传播 |
| 5 | Lane data 共享 | S2 用当前 S1 的 `s1_xor_result` | `mid_xor_result_q` 传播 |
| 6 | ECC 用错 op_mode | `current_lane_op` 依赖 `hdc_active` | 改为 `lane_owner_in` 判定 |
| 7 | GF_MUL 提前推进 | 无 result 确认 | `gf_wait_result_q` handshake |
