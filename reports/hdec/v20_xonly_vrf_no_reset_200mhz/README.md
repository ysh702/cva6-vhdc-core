# HDEC V20 x-only PMUL + VRF no-reset OOC 基准

本目录记录 V20 当前保留版本的 Vivado 2024.2 OOC 综合结果，作为后续 V21 优化的对比基准。

## 版本信息

| 项目 | 内容 |
|---|---|
| 分支 | `hdec-ecc-pointmul-v20` |
| 基准 commit | `3948936f hdec: remove VRF read output reset` |
| Vivado | 2024.2 |
| Part | `xc7z020clg400-2` |
| Top | `hdec_top` |
| Clock | 5.000 ns / 200 MHz |

## 当前 OOC 结果

| 指标 | 数值 |
|---|---:|
| WNS | 0.293 ns |
| Worst data delay | 4.704 ns |
| Estimated Fmax | 212.450 MHz |
| Slice LUT | 6459 |
| Logic LUT | 5987 |
| LUTRAM | 472 |
| FF | 2150 |
| BRAM | 0 |
| DSP | 0 |
| CARRY4 | 20 |

## 验证结果

| 测试 | 结果 | 说明 |
|---|---|---|
| ECC PMUL xsim | PASS | `PMUL_CYCLES=6005` |
| HDC full-flow xsim | PASS | 覆盖 VRF 写读、HCLR、HBIND、HPERM、HCNTCLR/ADD/CLIP、HSIM、HMATCH |

## 与 V18 基准的高层对比

| 版本 | WNS | Fmax | LUT | Logic LUT | LUTRAM | FF | PMUL cycles |
|---|---:|---:|---:|---:|---:|---:|---:|
| V18 K-233 point multiply | 0.219 ns | 209.161 MHz | 6714 | 6242 | 472 | 2158 | 18414 |
| V20 当前基准 | 0.293 ns | 212.450 MHz | 6459 | 5987 | 472 | 2150 | 6005 |

## 已保留的优化

1. PMUL 主循环改为 true x-only ladder，主循环只维护 X/Z，最后恢复仿射 X/Y。
2. 删除 PMUL scalar word cache。周期从 5547 增至 6005，但 LUT 显著下降，时序更好。
3. 删除 VRF 读输出寄存器 reset。HDC/ECC 功能通过，LUT 继续下降。

## 已尝试但回退的优化

1. PMUL const-one flag 内联：LUT 反涨，WNS 失败。
2. P2 pop 数据寄存器去 reset：LUT 大涨，WNS 失败。

## 附件说明

| 文件 | 说明 |
|---|---|
| `run_summary.txt` | OOC 摘要 |
| `utilization.rpt` | Vivado 资源报告 |
| `utilization_hier.rpt` | 层级资源报告 |
| `timing_top200.csv` | 前 200 条 timing path 表 |
| `timing_summary_top50.rpt` | timing summary/top paths 原始报告 |
| `xsim_ecc_pmul_v20.txt` | ECC PMUL xsim 日志 |
| `xsim_hdc_full_flow_v20.txt` | HDC full-flow xsim 日志 |
