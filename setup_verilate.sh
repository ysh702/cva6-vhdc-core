#!/bin/bash
# ==============================================================================
# cva6 verilate 编译环境修复 + HDEC 协处理器部署脚本
#
# 用法: ./setup_verilate.sh [SPIKE_DIR] [CVA6_DIR]
#   SPIKE_DIR: spike/fesvr 安装目录 (默认: ~/cva6_gcc13_toolchain)
#   CVA6_DIR:  cva6 仓库根目录 (默认: 当前脚本所在目录)
#
# 修复内容:
#   A. 编译环境 (make verilate 无 HDEC 时也能通过):
#      1. SPIKE_INSTALL_DIR 默认值 → 指向实际 spike 路径
#      2. --exe 列表 → 替换旧版 elfloader.cc 为 fesvr_dpi.cc + elfloader.cc
#      3. 补 libyaml-cpp (系统软链接)
#      4. 补 config.h (复制到 fesvr 目录)
#   B. HDEC 协处理器部署:
#      5. 验证 HDEC 源文件存在
#      6. 修改 ariane.sv → 替换 cvxif_example_coprocessor 为 hdec_xif_coprocessor
#      7. 修改 Flist.cva6 → 添加 HDEC 文件到编译列表
#
# 前置条件: 以下 5 个 HDEC 源文件必须已放入 core/ 目录:
#   core/hdec_xif_pkg.sv
#   core/ecc_full_adder.sv
#   core/hdec_lane.sv
#   core/hdec_top.sv
#   core/hdec_xif_coprocessor.sv
# ==============================================================================

set -e

# ---- 参数 ----
SPIKE_DIR="${1:-$HOME/cva6_gcc13_toolchain}"
CVA6_DIR="${2:-$(cd "$(dirname "$0")" && pwd)}"
MAKEFILE="$CVA6_DIR/Makefile"
ARIANE_SV="$CVA6_DIR/corev_apu/src/ariane.sv"
FLIST="$CVA6_DIR/core/Flist.cva6"
FESVR_DPI_SRC="$CVA6_DIR/verif/core-v-verif/vendor/riscv/riscv-isa-sim/fesvr"
SPIKE_LIB="$SPIKE_DIR/lib"
SYSTEM_YAML="/usr/lib/x86_64-linux-gnu/libyaml-cpp.a"

echo "=== CVA6 Verilate + HDEC 协处理器部署 ==="
echo "SPIKE_DIR: $SPIKE_DIR"
echo "CVA6_DIR:  $CVA6_DIR"
echo ""

# ==============================================================================
# A. 编译环境修复
# ==============================================================================

# ---- 步骤 1: 补上 libyaml-cpp ----
if [ ! -e "$SPIKE_LIB/libyaml-cpp.a" ] && [ ! -e "$SPIKE_LIB/libyaml-cpp.so" ]; then
    if [ -e "$SYSTEM_YAML" ]; then
        echo "[1/7] 软链接 libyaml-cpp.a → $SPIKE_LIB/"
        ln -sf "$SYSTEM_YAML" "$SPIKE_LIB/libyaml-cpp.a"
    else
        echo "[1/7] 警告: 找不到系统 libyaml-cpp, 请手动安装 libyaml-cpp-dev"
    fi
else
    echo "[1/7] libyaml-cpp 已存在, 跳过"
fi

# ---- 步骤 2: 补上 config.h ----
if [ ! -f "$FESVR_DPI_SRC/config.h" ]; then
    CFG_SRC="$SPIKE_DIR/include/fesvr/config.h"
    if [ -f "$CFG_SRC" ]; then
        echo "[2/7] 复制 config.h → $FESVR_DPI_SRC/"
        cp "$CFG_SRC" "$FESVR_DPI_SRC/config.h"
    else
        echo "[2/7] 错误: 找不到 $CFG_SRC"
        exit 1
    fi
else
    echo "[2/7] config.h 已存在, 跳过"
fi

# ---- 步骤 3: 修复 Makefile - SPIKE_INSTALL_DIR 默认值 ----
echo "[3/7] 修复 Makefile: SPIKE_INSTALL_DIR 默认值"
if grep -q 'SPIKE_INSTALL_DIR.*\$(root-dir)/tools/spike' "$MAKEFILE"; then
    sed -i "s|SPIKE_INSTALL_DIR.*?= \$(root-dir)/tools/spike|SPIKE_INSTALL_DIR     ?= $SPIKE_DIR|" "$MAKEFILE"
    echo "       SPIKE_INSTALL_DIR → $SPIKE_DIR"
else
    echo "       SPIKE_INSTALL_DIR 已设置或已被修改, 跳过"
fi

# ---- 步骤 4: 修复 Makefile - 替换 elfloader.cc ----
echo "[4/7] 修复 Makefile: verilate --exe 列表"
OLD_EXE="corev_apu/tb/dpi/remote_bitbang.cc corev_apu/tb/dpi/msim_helper.cc corev_apu/tb/dpi/elfloader.cc"
NEW_EXE="corev_apu/tb/dpi/remote_bitbang.cc corev_apu/tb/dpi/msim_helper.cc verif/core-v-verif/vendor/riscv/riscv-isa-sim/fesvr/fesvr_dpi.cc verif/core-v-verif/vendor/riscv/riscv-isa-sim/fesvr/elfloader.cc"

if grep -F "$OLD_EXE" "$MAKEFILE" > /dev/null 2>&1; then
    sed -i "s|$OLD_EXE|$NEW_EXE|" "$MAKEFILE"
    echo "       elfloader.cc → fesvr_dpi.cc + elfloader.cc (verif 版本)"
elif grep -F "fesvr_dpi.cc" "$MAKEFILE" > /dev/null 2>&1; then
    echo "       --exe 列表已包含 fesvr_dpi.cc, 跳过"
else
    echo "       警告: 未找到预期的 --exe 行, 请手动检查 Makefile 第 676 行"
fi

# ==============================================================================
# B. HDEC 协处理器部署
# ==============================================================================

# ---- 步骤 5: 验证 HDEC 源文件 ----
echo "[5/7] 检查 HDEC 源文件"
HDEC_FILES=(
    "core/hdec_xif_pkg.sv"
    "core/ecc_full_adder.sv"
    "core/hdec_lane.sv"
    "core/hdec_top.sv"
    "core/hdec_xif_coprocessor.sv"
)
MISSING=""
for f in "${HDEC_FILES[@]}"; do
    if [ ! -f "$CVA6_DIR/$f" ]; then
        MISSING="$MISSING  $f\n"
    fi
done
if [ -n "$MISSING" ]; then
    echo "       错误: 以下 HDEC 源文件缺失:"
    echo -e "$MISSING"
    echo "       请将文件放入 $CVA6_DIR/core/ 后重新运行"
    exit 1
fi
echo "       全部 5 个 HDEC 源文件已就位"

# ---- 步骤 6: 修改 ariane.sv → 替换协处理器实例化 ----
echo "[6/7] 修改 ariane.sv: cvxif_example_coprocessor → hdec_xif_coprocessor"
if grep -q "cvxif_example_coprocessor" "$ARIANE_SV"; then
    # 替换模块名和实例名
    sed -i 's/cvxif_example_coprocessor/hdec_xif_coprocessor/g' "$ARIANE_SV"
    sed -i 's/gen_example_coprocessor/gen_hdec_coprocessor/g' "$ARIANE_SV"
    sed -i 's/i_cvxif_coprocessor/i_hdec_coprocessor/g' "$ARIANE_SV"
    echo "        cvxif_example_coprocessor → hdec_xif_coprocessor"
elif grep -q "hdec_xif_coprocessor" "$ARIANE_SV"; then
    echo "       ariane.sv 已使用 hdec_xif_coprocessor, 跳过"
else
    echo "       警告: 未在 ariane.sv 中找到 cvxif_example_coprocessor, 请手动检查"
fi

# ---- 步骤 7: 修改 Flist.cva6 → 添加 HDEC 文件 ----
echo "[7/7] 修改 Flist.cva6: 添加 HDEC 编译项"
if ! grep -q "hdec_xif_pkg.sv" "$FLIST"; then
    cat >> "$FLIST" << 'EOF'

// HDEC Co-Processor (HDC + ECC) via CV-X-IF
${CVA6_REPO_DIR}/core/hdec_xif_pkg.sv
${CVA6_REPO_DIR}/core/ecc_full_adder.sv
${CVA6_REPO_DIR}/core/hdec_lane.sv
${CVA6_REPO_DIR}/core/hdec_top.sv
${CVA6_REPO_DIR}/core/hdec_xif_coprocessor.sv
EOF
    echo "       5 个 HDEC 文件已添加到 Flist.cva6"
else
    echo "       Flist.cva6 已包含 HDEC 文件, 跳过"
fi

echo ""
echo "=== 全部 7 步完成 ==="
echo "运行: cd $CVA6_DIR && make verilate"
echo ""
echo "运行 HDC+ECC 测试:"
echo "  cd verif/tests"
echo "  riscv64-unknown-elf-gcc -mabi=lp64 -march=rv64imafdc -static \\"
echo "    -nostdlib -nostartfiles -I./custom/cv_xif -I./custom/env \\"
echo "    -T <linker.ld> ./custom/common/crt.S \\"
echo "    ./custom/cv_xif/hdec_full_test.S -o hdec_full_test.elf"
echo ""
