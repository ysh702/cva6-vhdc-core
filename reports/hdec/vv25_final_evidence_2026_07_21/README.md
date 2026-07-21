# VV25 R31精简证据包

本目录保存VV25最终R31检查点的少量原始综合/层级报告和经核对的回归摘要，避免把完整Vivado/XSim生成目录提交到仓库。

## 最终指标

| Logic LUT | FF | BRAM | DSP | Fmax (MHz) | PMUL wall cycles | `HDEC_ECC_MUL` command cycles |
|---:|---:|---:|---:|---:|---:|---:|
| 4661 | 1304 | 4 | 0 | 214.041 | 166840 | 184 |

OOC口径为不含CV-X-IF wrapper的`hdec_top`，5 ns时钟约束。Fmax由WNS 0.328 ns估算得到。184周期对应启用场运算测试接口时，一条完整`HDEC_ECC_MUL`命令的延迟，不是单个16×16或32×32 leaf的延迟。

## 原始证据

- `ooc_run_summary.txt`：提取后的OOC资源、WNS和Fmax。
- `ooc_utilization.rpt`：Vivado资源利用率原始报告。
- `ooc_utilization_hier.rpt`：Vivado层级利用率原始报告。
- `ooc_timing_summary_top50.rpt`：Vivado时序原始报告。
- `synth_hierarchy_cells.csv`：最终综合网表关键层级清单。
- `synth_inventory_utilization_hier.rpt`：最终inventory层级利用率。
- `VV25_FINAL_METRICS.csv`：版本比较的机器可读数据。
- `REGRESSION_SUMMARY.md`：19项正式XSim结果及关键周期。
- `SHA256SUMS.txt`：本证据包文件完整性校验。

完整选择说明、源文件哈希和候选比较见[`SELECTION.md`](../vv25_r31_final_ooc_20260719/SELECTION.md)。仿真日志、DCP和XSim数据库按仓库规则不提交。

其中`synth_inventory_utilization_hier.rpt`用于核对共享结构和层级归属，其4645 LUT顶层数来自inventory综合口径，不作为最终PPA值；论文与版本比较统一采用上述`hdec_top` OOC的4661 Logic LUT。
