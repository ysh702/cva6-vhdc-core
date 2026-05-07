# HDEC 协处理器部署指南

本文档用于在另一台机器上由 Claude Code + DeepSeek V4 Pro 自动完成部署。

---

## 前提条件

目标机器上需要已经存在以下内容：

1. **CVA6 v5.2.0**：`git clone https://github.com/openhwgroup/cva6.git` 并 checkout `v5.2.0` tag
2. **RISC-V GCC 工具链**：`riscv64-unknown-elf-gcc` 在 PATH 中
3. **Verilator**：`verilator` 在 PATH 中（5.x 版本）
4. **Spike/fesvr 已编译**：包含 `libfesvr.a`, `libriscv.so`, `libdisasm.a` 和 fesvr 头文件（`fesvr/dtm.h` 等）

---

## 第一步：复制 HDEC 源文件到 CVA6 仓库

将以下 **5 个新增文件** 放入 CVA6 仓库的 `core/` 目录：

| 文件 | 说明 |
|---|---|
| `core/hdec_xif_pkg.sv` | 指令定义包 + OWNER 常量 |
| `core/ecc_full_adder.sv` | ECC模式可切换 1-bit 全加器 |
| `core/hdec_lane.sv` | 64-bit Lane + 多态加法树 (含 poly_adder) |
| `core/hdec_top.sv` | HDC+ECC 融合协处理器顶层 |
| `core/hdec_xif_coprocessor.sv` | CV-X-IF 协议包装器 |

将以下 **2 个测试文件** 放入 `verif/tests/custom/cv_xif/` 目录：

| 文件 | 说明 |
|---|---|
| `verif/tests/custom/cv_xif/hdec_test_macros.h` | HDEC 汇编宏（`.insn r` 格式） |
| `verif/tests/custom/cv_xif/hdec_full_test.S` | HDC+ECC 完整测试 |

---

## 第二步：修改已有文件

### 2.1 `Makefile`

**修改 1**：`SPIKE_INSTALL_DIR` 默认值（约第 70 行）：
```makefile
# 原始:
SPIKE_INSTALL_DIR     ?= $(root-dir)/tools/spike
# 改为实际 spike 路径:
SPIKE_INSTALL_DIR     ?= /path/to/your/spike/install
```

**修改 2**：verilate `--exe` 列表（约第 676 行）：
```makefile
# 原始:
--exe ... corev_apu/tb/dpi/elfloader.cc
# 改为:
--exe ... verif/core-v-verif/vendor/riscv/riscv-isa-sim/fesvr/fesvr_dpi.cc verif/core-v-verif/vendor/riscv/riscv-isa-sim/fesvr/elfloader.cc
```

### 2.2 `corev_apu/src/ariane.sv`

搜索 `cvxif_example_coprocessor`，替换为 `hdec_xif_coprocessor`：

```systemverilog
// 原始:
cvxif_example_coprocessor #( ...
) i_cvxif_coprocessor ( ...
// 改为:
hdec_xif_coprocessor #( ...
) i_hdec_coprocessor ( ...
```

同时将 `gen_example_coprocessor` 改为 `gen_hdec_coprocessor`。

### 2.3 `core/Flist.cva6`

在文件末尾（`// end of manifest` 之后）添加：

```
// HDEC Co-Processor (HDC + ECC) via CV-X-IF
${CVA6_REPO_DIR}/core/hdec_xif_pkg.sv
${CVA6_REPO_DIR}/core/ecc_full_adder.sv
${CVA6_REPO_DIR}/core/hdec_lane.sv
${CVA6_REPO_DIR}/core/hdec_top.sv
${CVA6_REPO_DIR}/core/hdec_xif_coprocessor.sv
```

---

## 第三步：补环境依赖

### 3.1 libyaml-cpp

如果 spike 安装目录的 `lib/` 下没有 `libyaml-cpp.a`：
```bash
ln -sf /usr/lib/x86_64-linux-gnu/libyaml-cpp.a /path/to/spike/lib/libyaml-cpp.a
```

### 3.2 config.h

如果 `verif/core-v-verif/vendor/riscv/riscv-isa-sim/fesvr/` 下没有 `config.h`：
```bash
cp /path/to/spike/include/fesvr/config.h verif/core-v-verif/vendor/riscv/riscv-isa-sim/fesvr/config.h
```

---

## 第四步：编译

```bash
cd /path/to/cva6
make verilate
```

成功后生成 `work-ver/Variane_testharness`。

---

## 第五步：编译测试

```bash
cd verif/tests
riscv64-unknown-elf-gcc -mabi=lp64 -march=rv64imafdc -static -mcmodel=medany \
    -nostdlib -nostartfiles \
    -I./custom/cv_xif -I./custom/env \
    -T /path/to/config/gen_from_riscv_config/linker/link.ld \
    ./custom/common/crt.S \
    ./custom/cv_xif/hdec_full_test.S \
    -o /tmp/hdec_full_test.elf
```

---

## 第六步：运行仿真

```bash
/path/to/cva6/work-ver/Variane_testharness /tmp/hdec_full_test.elf
```

预期输出：`*** SUCCESS *** (tohost = 0) after 35771 cycles`

---

## 自动化脚本

上述步骤 2-3 可以使用仓库根目录下的 `setup_verilate.sh` 脚本自动完成：
```bash
chmod +x setup_verilate.sh
./setup_verilate.sh /path/to/spike /path/to/cva6
```

脚本幂等执行，已完成的步骤自动跳过。

---

## 更简单的部署方案：Git 仓库

如果你想在另一台电脑上让 Claude 一键部署，推荐：

**方案 A：Fork CVA6 + 提交所有改动**

```bash
cd cva6
git checkout -b hdec-coprocessor
git add core/hdec_*.sv core/ecc_full_adder.sv
git add corev_apu/src/ariane.sv core/Flist.cva6 Makefile
git add verif/tests/custom/cv_xif/hdec_*
git add setup_verilate.sh
git commit -m "Add HDEC (HDC+ECC) coprocessor via CV-X-IF"
git push origin hdec-coprocessor
```

部署时：`git clone` + 运行 `./setup_verilate.sh`。

**方案 B：单独的 HDEC patch 仓库**

将 5 个 SV 文件 + 2 个测试文件 + `setup_verilate.sh` + patch 文件放入一个新仓库 `hdec-cva6-patch`。部署时：
1. Clone CVA6 v5.2.0
2. Clone hdec-cva6-patch
3. 复制文件 + 运行 setup_verilate.sh

---

## Claude Code 指令（给另一台机器上的 Claude）

将此指令粘贴给另一台机器上的 Claude Code：

```
你将部署 CVA6 v5.2.0 的 HDEC 协处理器。请按顺序执行：

1. 确认环境：which riscv64-unknown-elf-gcc && which verilator
2. 确认 CVA6 仓库在 ~/cva6 且已在 v5.2.0 tag
3. 确认 HDEC 源文件已放置在 ~/cva6/core/ 下（hdec_*.sv + ecc_full_adder.sv）
4. 确认测试文件在 ~/cva6/verif/tests/custom/cv_xif/ 下
5. 读取 ~/cva6/HDEC_DEPLOYMENT.md 中的修改清单
6. 执行所有文件修改（Makefile、ariane.sv、Flist.cva6）
7. 补环境依赖（libyaml-cpp symlink、config.h）
8. cd ~/cva6 && make verilate
9. 编译并运行 hdec_full_test.S，验证 SUCCESS
10. 如果任何步骤失败，读取相关文件排查并修复
```
