# HDEC Seven Souls VMware Regression Baseline

## 1. 基准信息

| Item | Value |
|---|---|
| Repository | cva6-hdcu-cnt-popcount |
| Branch | hdec-seven-souls-vmware-regression-v1 |
| Commit | 9f2485fc |
| RTL baseline | hdec: migrate HDC ops to unified uop pipeline |
| Date | 2026-06-05 |
| Machine | VMware Ubuntu 22.04 |

## 2. 工具链版本

| Tool | Path | Version |
|---|---|---|
| Verilator | /usr/local/bin/verilator | 5.008 2023-03-04 rev v5.008 (mod) |
| riscv-none-elf-gcc | /home/ysh/cva6_gcc13_toolchain/bin/riscv-none-elf-gcc | 13.1.0 |
| riscv-none-elf-nm | /home/ysh/cva6_gcc13_toolchain/bin/riscv-none-elf-nm | GNU Binutils 2.40 |
| uname | | Linux ysh-virtual-machine 6.8.0-107-generic #107~22.04.1-Ubuntu SMP PREEMPT_DYNAMIC x86_64 |

PATH 已写入 /home/ysh/.bashrc 和 /home/ysh/.profile。

## 3. 当前 HDEC 软件协议

### VADDR (funct7=0000011, funct3=010)
- rs1[7:6] → vaddr_bank (0-3)
- rs1[5:0] → vaddr_idx (0-63)
- VADDR = 0 表示 bank0/index0
- VADDR = 65 表示 bank1/index1 (bank=1<<6 | idx=1)

### VWR64 (funct7=0000011, funct3=000)
- 使用内部 vaddr_bank_q / vaddr_idx_q 选择 VRF 位置
- 数据来自 rs1

### VRD64 (funct7=0000011, funct3=001)
- 使用内部 vaddr_bank_q / vaddr_idx_q 选择 VRF 位置
- 读回结果返回 rd

### 指令编码汇总

| 指令 | funct7 | funct3 | 说明 |
|---|---|---|---|
| VADDR | 0000011 | 010 | 设置 VRF 地址 |
| VWR64 | 0000011 | 000 | 写 VRF 64-bit |
| VRD64 | 0000011 | 001 | 读 VRF 64-bit |
| HCLR | 0000011 | 100 | 清 HV slot |
| HCNTCLR | 0000010 | 011 | 清 CNT accumulator bank |
| HCNTADD | 0000010 | 100 | CNT accumulate |
| HCNTCLIP | 0000010 | 101 | Threshold clip |
| HBIND | 0000011 | 101 | XOR bind |
| HPERM | 0000010 | 000 | 4-bit granularity permute/shift |
| HSIM | 0000010 | 001 | Hamming similarity (popcount) |
| HMATCH | 0000010 | 010 | Multi-class match |

### 旧协议测试已删除

以下旧 direct-address 协议测试已删除:
- verif/hdec/min_test.S — 把 VRF 地址放在 VWR64/VRD64 的 rs2/rs1 中
- verif/hdec/test_vrw.S — 同上

替换为当前 VADDR 协议版本:
- verif/hdec/min_test_current_protocol.S
- verif/hdec/vrw_current_protocol_test.S

## 4. 指令覆盖表

| 指令/算子 | 覆盖测试文件 | 覆盖内容 | Fresh Build | PASS |
|---|---|---|---|---|
| VADDR | min_test_current_protocol, vrw_current_protocol_test, va_test, va4_test, hdc_inference_test, hdc_e2e_train_infer_test | 设置 bank/index, preload 数据 | Yes | PASS |
| VWR64 | min_test_current_protocol, vrw_current_protocol_test, va_test, va4_test, hdc_inference_test, hdc_e2e_train_infer_test | 写 VRF, preload HV 数据 | Yes | PASS |
| VRD64 | min_test_current_protocol, vrw_current_protocol_test | 读 VRF, round-trip 验证 | Yes | PASS |
| HCLR | hclr_test, hdc_pipeline_test, hdc_inference_test, hcntadd_test, hcntclip_test, hmatch_test | 清 HV slot | Yes | PASS |
| HCNTCLR | hcntclr_test, hdc_pipeline_test, hdc_inference_test, hcntadd_test, hcntclip_test, hdc_e2e_train_infer_test | 清 CNT accumulator bank | Yes | PASS |
| HCNTADD | hcntadd_test, hdc_pipeline_test, hdc_inference_test, hcntclip_test, hdc_e2e_train_infer_test | CNT accumulate | Yes | PASS |
| HCNTCLIP | hcntclip_test, hdc_pipeline_test, hdc_inference_test, hdc_e2e_train_infer_test | Threshold clip | Yes | PASS |
| HBIND | hbind_test, hdc_pipeline_test | XOR bind | Yes | PASS |
| HPERM | hperm_test | 4-bit granularity perm/shift | Yes | PASS |
| HSIM | hsim_test, hdc_pipeline_test | Hamming similarity (popcount) | Yes | PASS |
| HMATCH | hmatch_test, hdc_pipeline_test, hdc_inference_test, hdc_e2e_train_infer_test | Multi-class match | Yes | PASS |

所有 11 条当前 HDEC 指令均有专用测试或集成测试覆盖，无缺口。

## 5. 回归测试结果

所有测试均为 fresh build，ELF 位于 tmp/hdec_logs/。

| # | Test | Source | ELF | tohost | Cycles | Result |
|---|---|---|---|---|---|---|
| 1 | min_test_current_protocol | verif/hdec/min_test_current_protocol.S | tmp/hdec_logs/min_test_current_protocol.elf | 0 | 2902 | PASS |
| 2 | vrw_current_protocol_test | verif/hdec/vrw_current_protocol_test.S | tmp/hdec_logs/vrw_current_protocol_test.elf | 0 | 2933 | PASS |
| 3 | va_test | verif/hdec/va_test.S | tmp/hdec_logs/va_test.elf | 0 | 2891 | PASS |
| 4 | va4_test | verif/hdec/va4_test.S | tmp/hdec_logs/va4_test.elf | 0 | 3092 | PASS |
| 5 | multi_index_test | verif/hdec/multi_index_test.S | tmp/hdec_logs/multi_index_test.elf | 0 | 3041 | PASS |
| 6 | bank0_test | verif/hdec/bank0_test.S | tmp/hdec_logs/bank0_test.elf | 0 | 2955 | PASS |
| 7 | bank1_test | verif/hdec/bank1_test.S | tmp/hdec_logs/bank1_test.elf | 0 | 3008 | PASS |
| 8 | bank2_test | verif/hdec/bank2_test.S | tmp/hdec_logs/bank2_test.elf | 0 | 3008 | PASS |
| 9 | bank3_test | verif/hdec/bank3_test.S | tmp/hdec_logs/bank3_test.elf | 0 | 3008 | PASS |
| 10 | hclr_test | verif/hdec/hclr_test.S | tmp/hdec_logs/hclr_test.elf | 0 | 3035 | PASS |
| 11 | hcntclr_test | verif/hdec/hcntclr_test.S | tmp/hdec_logs/hcntclr_test.elf | 0 | 3246 | PASS |
| 12 | hcntadd_test | verif/hdec/hcntadd_test.S | tmp/hdec_logs/hcntadd_test.elf | 0 | 5091 | PASS |
| 13 | hcntclip_test | verif/hdec/hcntclip_test.S | tmp/hdec_logs/hcntclip_test.elf | 0 | 5309 | PASS |
| 14 | hbind_test | verif/hdec/hbind_test.S | tmp/hdec_logs/hbind_test.elf | 0 | 3141 | PASS |
| 15 | hperm_test | verif/hdec/hperm_test.S | tmp/hdec_logs/hperm_test.elf | 0 | 35849 | PASS |
| 16 | hsim_test | verif/hdec/hsim_test.S | tmp/hdec_logs/hsim_test.elf | 0 | 5026 | PASS |
| 17 | hmatch_test | verif/hdec/hmatch_test.S | tmp/hdec_logs/hmatch_test.elf | 0 | 3936 | PASS |
| 18 | hdc_pipeline_test | verif/hdec/hdc_pipeline_test.S | tmp/hdec_logs/hdc_pipeline_test.elf | 0 | 3869 | PASS |
| 19 | hdc_inference_test | verif/hdec/hdc_inference_test.S | tmp/hdec_logs/hdc_inference_test.elf | 0 | 5487 | PASS |
| 20 | hdc_e2e_train_infer_test | verif/hdec/hdc_e2e_train_infer_test.S | tmp/hdec_logs/hdc_e2e_train_infer_test.elf | 0 | 130358 | PASS |

**Result: 20/20 PASS, 0 FAIL**

## 6. 如何复现实验

### Build 命令模板

```bash
export PATH="/home/ysh/cva6_gcc13_toolchain/bin:$PATH"

riscv-none-elf-gcc \
  -march=rv64gc_zifencei -mabi=lp64d -nostartfiles -nostdlib -mcmodel=medany \
  -I verif/tests/custom/env -I verif/tests/custom/common \
  -T verif/hdec/hdec_link.ld \
  verif/tests/custom/common/crt.S verif/hdec/<test>.S \
  -o tmp/hdec_logs/<test>.elf
```

### Run 命令模板

```bash
work-ver/Variane_testharness +tohost_addr=80001000 tmp/hdec_logs/<test>.elf
```

### PASS 判定

- tohost = 0 → PASS
- tohost != 0 → FAIL
- 输出中包含 `*** SUCCESS *** (tohost = 0)`

### 批量运行所有测试

```bash
export PATH="/home/ysh/cva6_gcc13_toolchain/bin:$PATH"

TESTS=(
  min_test_current_protocol vrw_current_protocol_test
  va_test va4_test multi_index_test
  bank0_test bank1_test bank2_test bank3_test
  hclr_test hcntclr_test hcntadd_test hcntclip_test
  hbind_test hperm_test hsim_test hmatch_test
  hdc_pipeline_test hdc_inference_test hdc_e2e_train_infer_test
)

for t in "${TESTS[@]}"; do
  riscv-none-elf-gcc \
    -march=rv64gc_zifencei -mabi=lp64d -nostartfiles -nostdlib -mcmodel=medany \
    -I verif/tests/custom/env -I verif/tests/custom/common \
    -T verif/hdec/hdec_link.ld \
    verif/tests/custom/common/crt.S "verif/hdec/${t}.S" \
    -o "tmp/hdec_logs/${t}.elf"

  work-ver/Variane_testharness +tohost_addr=80001000 "tmp/hdec_logs/${t}.elf" 2>&1 | grep "tohost ="
done
```

## 7. 后续说明

- 本分支 `hdec-seven-souls-vmware-regression-v1` 作为七个灵魂 RTL 的 VMware 回归基准。
- 后续 Gemini Q 寄存器方案应从此基准分支继续。
- 本分支没有修改 RTL，只整理和修正 current-protocol 测试与环境文档。
- 删除的旧协议测试: min_test.S, test_vrw.S (使用 direct-address，与当前 VADDR 协议不兼容)。
- 新增当前协议测试: min_test_current_protocol.S, vrw_current_protocol_test.S。
- 未跟踪目录 verif/core-v-verif 不在本次 commit 范围内。
