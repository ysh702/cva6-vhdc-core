# VV30-2 HPERM 修复阶段报告

## 结论

HPERM 的 4 位粒度契约已经恢复。1024 种旋转编码全部检查完成，256 种
合法编码生成完整 1024 位旋转结果，768 种非对齐编码返回
`STATUS_ERROR`，非法请求全过程不写 VRF。合法 HPERM 仍为 62 周期。

阶段二以已经完成融合映射的阶段一结果作为入口，不以原始 VV25 或
HPERM 孤立消融作为验收基线。最终 H2 地址逻辑相对阶段入口减少 2 个
Logic LUT，增加 4 个 FF，WNS 与频率不变。该幅 FF 波动在用户确认的
阶段容差内，阶段二据此封存。

这是 HDC 功能正确性修复，不是论文创新点。

## 已复现的基线错误

新的契约测试在未修改的 `a3ba6f4` 基线上捕获了三类错误。

1. `ROTR 4` 的末尾数据从相邻 HV 读取。
2. 非 4 位对齐的 `ROTR 1` 返回成功。
3. 非法请求实际写入目的 HV。

基线探针证据位于：

`E:\HDEC\cva6-vhdc-core\tmp\hdec_vv30_hperm_probe\tmp\hdec_logs\vv30\hperm_clean_baseline_probe2`

## RTL 修复

只改变 `hdec_top.sv` 内的 HDC HPERM 控制。

- 首个 chunk 直接拼接 HV 槽高四位与两位行号，下一行在两位域内自然
  环回。
- 后续 chunk 继承源地址高四位，仅更新低两位行号。
- `rot_amt[1:0] != 0` 在发射微操作前返回错误。
- `dst == src` 继续返回错误。
- 现有两级 64 位 Shift-Align 路径、FSM 状态数、`HDEC_ECC_ALIGN` 路径均不变。

## 功能与周期

| 检查 | 结果 |
|---|---|
| 1024 种旋转编码 | PASS |
| 256 种合法编码的完整 1024 位结果 | PASS |
| 768 种非法编码的零 VRF 写使能 | PASS |
| 16×16 源/目的槽组合 | PASS |
| 源 HV、相邻 HV、其他槽不变 | PASS |
| `dst == src` | PASS |
| 非法后合法、连续合法 | PASS |
| 合法周期一致 | PASS，62 周期 |
| Shift-Align | PASS |
| `HDEC_ECC_ALIGN` | PASS |
| HDC full flow | PASS |
| VV25 native XOR1 | PASS |
| ECC_MUL | PASS，184 周期 |
| PMUL profile | PASS |

移植到主 VV30 后增强的槽组合测试再次通过：

`E:\HDEC\cva6-vhdc-core\tmp\hdec_vv30_three_structures_worktree\tmp\hdec_logs\vv30\20260731_004143_stage2_hperm_main`

## 累计版本的匹配 OOC 综合

器件为 `xc7z020clg400-2`，时钟约束为 5 ns，工具为 Vivado 2024.2。
阶段入口是已包含 F1d 融合映射的 VV30-1，阶段出口是 F1d 与 H2 HPERM
的累计版本。

| 指标 | 阶段一入口 | 阶段二出口 | 本阶段变化 |
|---|---:|---:|---:|
| Logic LUT | 4658 | 4656 | -2 |
| FF | 1304 | 1308 | +4 |
| BRAM | 4 | 4 | 0 |
| DSP | 0 | 0 | 0 |
| WNS | 0.328 ns | 0.328 ns | 0 |
| 估算 Fmax | 214.041 MHz | 214.041 MHz | 0 |

累计候选综合证据位于：

`tmp/hdec_logs/vv30/stage2_h2_direct_row_logic/ooc`

最终 H2 进一步去掉通用地址函数，在实际操作数字段上直接生成首行地址，
后续只更新地址低两位。上一版累计结果为 4663 LUT、1310 FF，H2 将其
压缩为 4656 LUT、1308 FF。

HPERM 的孤立消融仍保留为诊断证据，其结果为 4644 LUT、1301 FF，但不
用于判定阶段二是否通过，也不与累计结果做算术相加。

## 最终随机与穷举回归

阶段二 Runner 使用新的系统随机主种子
`24db68f91eb59eba9bf708edd14389598d659d455acecc67a6075b37a635e191`。

| 测试 | 覆盖 | 结果 |
|---|---:|---|
| HPERM 契约 | 1024 编码，256 合法，768 非法 | PASS |
| Shift-Align | 2048 单位基 | PASS |
| 融合映射 | 4464 单位基 | PASS |
| 数学平方约减基线 | 233 单位基，10 定向，4096 随机 | PASS |

运行清单位于：

`tmp/hdec_logs/vv30/stage2_h2_final_regression/run_manifest.json`

## 文件边界

主 VV30 已移植：

- `core/hdec/rtl/hdec_top.sv`
- `verif/hdec/vv30/integration/tb_vv30_hperm_contract.sv`
- `scripts/hdec/vv30/vv30_hperm_contract.tcl`
- `verif/hdec/tb_hdec_hperm_bit_align.sv`
- `verif/hdec/tb_hdec_hdc_full_flow_v20.sv`

未修改禁止文件，未修改未实例化的 `hdec_hdc_perm_ctrl.sv`，未提交，未推送。
