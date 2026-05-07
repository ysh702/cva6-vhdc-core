# HDEC 协处理器 — Agent 自动部署指令

本文档供另一台电脑上的 **Claude Code + DeepSeek V4 Pro** 自动部署 HDEC 协处理器。根据当前环境选择方案 A 或方案 B。

---

## 方案选择

| 方案 | 适用场景 |
|---|---|
| A | 用户已手动部署好 CVA6 v5.2.0 + 工具链，但 CVA6 中**没有** HDEC 代码 |
| B | 直接从 GitHub `ysh702/cva6-vhdc-core` 的 `hdec-coprocessor` 分支 clone |

---

## 方案 A：从零部署 HDEC 到已有 CVA6 v5.2.0

### A.1 环境确认

```bash
# 确认这些命令都存在
which riscv64-unknown-elf-gcc
which verilator
echo $RISCV          # 应指向 RISC-V 工具链安装目录

# 确认 CVA6 在 v5.2.0
cd ~/cva6
git log --oneline -1  # 应该看到 CVA6 v5.2.0 相关 commit
```

### A.2 确认 spike/fesvr 安装位置

```bash
# 找到 spike 安装目录（包含 include/fesvr/dtm.h 和 lib/libfesvr.a）
find ~ -name "dtm.h" -path "*/fesvr/*" 2>/dev/null
# 记下路径，例如 /home/user/spike_install
export SPIKE_DIR=/home/user/spike_install
```

### A.3 补环境依赖

```bash
# libyaml-cpp
if [ ! -f "$SPIKE_DIR/lib/libyaml-cpp.a" ]; then
    ln -sf /usr/lib/x86_64-linux-gnu/libyaml-cpp.a "$SPIKE_DIR/lib/libyaml-cpp.a"
fi

# config.h (fesvr_dpi.cc 需要同目录下的 config.h)
CFG_DST=~/cva6/verif/core-v-verif/vendor/riscv/riscv-isa-sim/fesvr/config.h
if [ ! -f "$CFG_DST" ]; then
    cp "$SPIKE_DIR/include/fesvr/config.h" "$CFG_DST"
fi
```

### A.4 创建 HDEC 源文件

你需要创建以下 **5 个 SystemVerilog 文件**。请严格按顺序创建，每个文件独立写入。

---

#### 文件 1/5: `~/cva6/core/hdec_xif_pkg.sv`

```systemverilog
// =============================================================================
// hdec_xif_pkg.sv — HDEC coprocessor type definitions for CV-X-IF integration
// =============================================================================
package hdec_xif_pkg;

    typedef enum logic [3:0] {
        HDEC_BIND         = 4'd0,
        HDEC_BUNDLE       = 4'd1,
        HDEC_MATCH        = 4'd2,
        HDEC_INGEST       = 4'd3,
        HDEC_BINARIZE     = 4'd4,
        HDEC_PERMUTE      = 4'd5,
        HDEC_ECC_START    = 4'd6,
        HDEC_ECC_FETCH    = 4'd7,
        HDEC_BUNDLE_ACCUM = 4'd8,
        HDEC_CLEAR_CNT    = 4'd9
    } hdec_op;

    localparam int unsigned HDEC_TRANS_ID_BITS = 4;
    localparam logic [1:0] OWNER_NONE = 2'd0;
    localparam logic [1:0] OWNER_HDC  = 2'd1;
    localparam logic [1:0] OWNER_ECC  = 2'd2;

    localparam logic [6:0] OPCODE_HDEC = 7'b0001011;
    localparam logic [6:0] F7_DEFAULT      = 7'b000_0000;
    localparam logic [6:0] F7_BUNDLE_ACCUM = 7'b000_0001;

    typedef struct packed {
        logic        accept;
        logic [0:0]  writeback;
        logic [1:0]  register_read;
    } hdec_issue_resp_t;

    typedef hdec_op opcode_t;

    typedef struct packed {
        logic [31:0] mask;
        logic [31:0] instr;
        hdec_issue_resp_t resp;
        opcode_t opcode;
    } hdec_instr_entry_t;

    localparam int unsigned HDEC_NB_INSTR = 10;

    function automatic hdec_instr_entry_t [HDEC_NB_INSTR-1:0] get_hdec_instr_table();
        hdec_instr_entry_t [HDEC_NB_INSTR-1:0] tbl;
        logic [31:0] base_mask = 32'hFE00_707F;
        logic [31:0] base_op   = {16'h0000, 2'b00, OPCODE_HDEC};
        // BIND
        tbl[0].mask=base_mask; tbl[0].instr=base_op|(F7_DEFAULT<<25)|(3'b000<<12);
        tbl[0].resp='{accept:1'b1,writeback:1'b1,register_read:2'b01}; tbl[0].opcode=HDEC_BIND;
        // BUNDLE
        tbl[1].mask=base_mask; tbl[1].instr=base_op|(F7_DEFAULT<<25)|(3'b001<<12);
        tbl[1].resp='{accept:1'b1,writeback:1'b1,register_read:2'b01}; tbl[1].opcode=HDEC_BUNDLE;
        // MATCH
        tbl[2].mask=base_mask; tbl[2].instr=base_op|(F7_DEFAULT<<25)|(3'b010<<12);
        tbl[2].resp='{accept:1'b1,writeback:1'b1,register_read:2'b01}; tbl[2].opcode=HDEC_MATCH;
        // INGEST
        tbl[3].mask=base_mask; tbl[3].instr=base_op|(F7_DEFAULT<<25)|(3'b011<<12);
        tbl[3].resp='{accept:1'b1,writeback:1'b1,register_read:2'b11}; tbl[3].opcode=HDEC_INGEST;
        // BINARIZE
        tbl[4].mask=base_mask; tbl[4].instr=base_op|(F7_DEFAULT<<25)|(3'b100<<12);
        tbl[4].resp='{accept:1'b1,writeback:1'b1,register_read:2'b01}; tbl[4].opcode=HDEC_BINARIZE;
        // PERMUTE
        tbl[5].mask=base_mask; tbl[5].instr=base_op|(F7_DEFAULT<<25)|(3'b101<<12);
        tbl[5].resp='{accept:1'b1,writeback:1'b1,register_read:2'b01}; tbl[5].opcode=HDEC_PERMUTE;
        // ECC_START
        tbl[6].mask=base_mask; tbl[6].instr=base_op|(F7_DEFAULT<<25)|(3'b110<<12);
        tbl[6].resp='{accept:1'b1,writeback:1'b1,register_read:2'b01}; tbl[6].opcode=HDEC_ECC_START;
        // ECC_FETCH
        tbl[7].mask=base_mask; tbl[7].instr=base_op|(F7_DEFAULT<<25)|(3'b111<<12);
        tbl[7].resp='{accept:1'b1,writeback:1'b1,register_read:2'b00}; tbl[7].opcode=HDEC_ECC_FETCH;
        // CLEAR_CNT (funct7=1, funct3=001)
        tbl[8].mask=base_mask; tbl[8].instr=base_op|(F7_BUNDLE_ACCUM<<25)|(3'b001<<12);
        tbl[8].resp='{accept:1'b1,writeback:1'b1,register_read:2'b00}; tbl[8].opcode=HDEC_CLEAR_CNT;
        // BUNDLE_ACCUM (funct7=1, funct3=100)
        tbl[9].mask=base_mask; tbl[9].instr=base_op|(F7_BUNDLE_ACCUM<<25)|(3'b100<<12);
        tbl[9].resp='{accept:1'b1,writeback:1'b1,register_read:2'b01}; tbl[9].opcode=HDEC_BUNDLE_ACCUM;
        return tbl;
    endfunction
endpackage
```

---

#### 文件 2/5: `~/cva6/core/ecc_full_adder.sv`

```systemverilog
// ecc_full_adder.sv — 1-bit full adder with ECC mode control
module ecc_full_adder (
    input  logic ecc_mode, input  logic a, input  logic b,
    input  logic cin,      output logic sum, output logic cout
);
    logic half_sum, half_carry;
    assign half_sum = a ^ b;
    assign half_carry = a & b;
    assign sum = half_sum ^ cin;
    assign cout = ecc_mode ? 1'b0 : (half_carry | (half_sum & cin));
endmodule
```

---

#### 文件 3/5, 4/5, 5/5

`hdec_lane.sv`, `hdec_top.sv`, `hdec_xif_coprocessor.sv` 这三个文件内容很长，从 GitHub 仓库直接获取：

```bash
GH_BASE="https://raw.githubusercontent.com/ysh702/cva6-vhdc-core/hdec-coprocessor"
wget -O ~/cva6/core/hdec_lane.sv           "$GH_BASE/core/hdec_lane.sv"
wget -O ~/cva6/core/hdec_top.sv            "$GH_BASE/core/hdec_top.sv"
wget -O ~/cva6/core/hdec_xif_coprocessor.sv "$GH_BASE/core/hdec_xif_coprocessor.sv"
```

---

### A.5 创建测试文件

```bash
mkdir -p ~/cva6/verif/tests/custom/cv_xif
GH_BASE="https://raw.githubusercontent.com/ysh702/cva6-vhdc-core/hdec-coprocessor"
wget -O ~/cva6/verif/tests/custom/cv_xif/hdec_test_macros.h "$GH_BASE/verif/tests/custom/cv_xif/hdec_test_macros.h"
wget -O ~/cva6/verif/tests/custom/cv_xif/hdec_full_test.S  "$GH_BASE/verif/tests/custom/cv_xif/hdec_full_test.S"
```

---

### A.6 修改已有文件

**Makefile** (`~/cva6/Makefile`)：

1. 搜索 `SPIKE_INSTALL_DIR.*=.*tools/spike`，替换为 `SPIKE_INSTALL_DIR     ?= $SPIKE_DIR`
2. 搜索 `corev_apu/tb/dpi/elfloader.cc`，替换为 `verif/core-v-verif/vendor/riscv/riscv-isa-sim/fesvr/fesvr_dpi.cc verif/core-v-verif/vendor/riscv/riscv-isa-sim/fesvr/elfloader.cc`

**ariane.sv** (`~/cva6/corev_apu/src/ariane.sv`)：

1. 搜索 `cvxif_example_coprocessor`，全部替换为 `hdec_xif_coprocessor`
2. 搜索 `gen_example_coprocessor`，替换为 `gen_hdec_coprocessor`
3. 搜索 `i_cvxif_coprocessor`，替换为 `i_hdec_coprocessor`

**Flist.cva6** (`~/cva6/core/Flist.cva6`)：

在文件末尾 `// end of manifest` 之后追加：
```
// HDEC Co-Processor (HDC + ECC) via CV-X-IF
${CVA6_REPO_DIR}/core/hdec_xif_pkg.sv
${CVA6_REPO_DIR}/core/ecc_full_adder.sv
${CVA6_REPO_DIR}/core/hdec_lane.sv
${CVA6_REPO_DIR}/core/hdec_top.sv
${CVA6_REPO_DIR}/core/hdec_xif_coprocessor.sv
```

---

### A.7 编译和测试

```bash
cd ~/cva6 && rm -rf work-ver && make verilate

# 编译测试
cd ~/cva6/verif/tests
riscv64-unknown-elf-gcc -mabi=lp64 -march=rv64imafdc -static -mcmodel=medany \
    -nostdlib -nostartfiles -I./custom/cv_xif -I./custom/env \
    -T ~/cva6/config/gen_from_riscv_config/linker/link.ld \
    ./custom/common/crt.S ./custom/cv_xif/hdec_full_test.S \
    -o /tmp/test.elf

# 运行仿真（预期 SUCCESS）
~/cva6/work-ver/Variane_testharness /tmp/test.elf
```

预期输出：`*** SUCCESS *** (tohost = 0) after 35771 cycles`

---

## 方案 B：直接从 GitHub Clone 并部署

### B.1 Clone

```bash
git clone git@github.com:ysh702/cva6-vhdc-core.git ~/cva6-hdec
cd ~/cva6-hdec
git checkout hdec-coprocessor
```

如果 SSH 不通，用 HTTPS：
```bash
git clone https://github.com/ysh702/cva6-vhdc-core.git ~/cva6-hdec
```

### B.2 初始化 submodule

```bash
cd ~/cva6-hdec
git submodule update --init --recursive
```

### B.3 确认工具链

```bash
which riscv64-unknown-elf-gcc
which verilator
```

找到你的 spike/fesvr 安装路径（包含 `include/fesvr/dtm.h` 和 `lib/libfesvr.a`）：
```bash
SPIKE_DIR=/path/to/your/spike
```

### B.4 补环境依赖

```bash
# libyaml-cpp
if [ ! -f "$SPIKE_DIR/lib/libyaml-cpp.a" ]; then
    ln -sf /usr/lib/x86_64-linux-gnu/libyaml-cpp.a "$SPIKE_DIR/lib/libyaml-cpp.a"
fi

# config.h
CFG_DST=~/cva6-hdec/verif/core-v-verif/vendor/riscv/riscv-isa-sim/fesvr/config.h
if [ ! -f "$CFG_DST" ]; then
    cp "$SPIKE_DIR/include/fesvr/config.h" "$CFG_DST"
fi
```

### B.5 运行部署脚本

```bash
cd ~/cva6-hdec
chmod +x setup_verilate.sh
./setup_verilate.sh $SPIKE_DIR ~/cva6-hdec
```

脚本会检查和修复 Makefile、ariane.sv、Flist.cva6，幂等可重复执行。

### B.6 编译和测试

```bash
make verilate

cd verif/tests
riscv64-unknown-elf-gcc -mabi=lp64 -march=rv64imafdc -static -mcmodel=medany \
    -nostdlib -nostartfiles -I./custom/cv_xif -I./custom/env \
    -T ~/cva6-hdec/config/gen_from_riscv_config/linker/link.ld \
    ./custom/common/crt.S ./custom/cv_xif/hdec_full_test.S \
    -o /tmp/test.elf

~/cva6-hdec/work-ver/Variane_testharness /tmp/test.elf
```

预期输出：`*** SUCCESS *** (tohost = 0) after 35771 cycles`

---

## 故障排查

| 问题 | 检查 |
|---|---|
| `fesvr/dtm.h: No such file` | SPIKE_DIR 路径不对，或 config.h 未复制 |
| `undefined reference to read_section_void` | Makefile 的 --exe 列表未替换 elfloader.cc |
| `Active region did not converge` | 检查 hdec_top.sv ECC_FETCH 中 `ready_o=1'b0` 基于 `ecc_fetch_pending_q`（寄存器），不是 `operator_i`（组合） |
| 仿真超时无输出 | ECC 未在 256 cycle 内完成，检查 spin-wait 长度 |
| `make verilate` 找不到 verilator | `export VERILATOR_INSTALL_DIR=/usr/local` |
