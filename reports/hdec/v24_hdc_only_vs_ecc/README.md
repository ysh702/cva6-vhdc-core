# V24 仅 HDC vs 当前 HDC+ECC OOC 对比

## 基本信息

- V24 分支：`hdec-ecc-pointmul-v24`
- 对比基准：`hdec-ecc-pointmul-v23`
- V23 基准提交：`81224802 hdec: complete V23 optimization pass`
- Vivado：2024.2
- FPGA part：`xc7z020clg400-2`
- Top：`hdec_top`
- OOC clock：5.000 ns，也就是 200 MHz

V23 已先推送到远程 `origin/hdec-ecc-pointmul-v23`。V24 是基于当前 RTL 做的“仅 HDC 面积边界”对比点。

## 仅 HDC 边界怎么判断

这次不是重新做一个新的 HDEC，也不是把 HDC 结构改成另一个版本，而是在当前 RTL 结构里用 `HDEC_HDC_ONLY` 去掉 ECC-only 逻辑，让 Vivado 在同一个设计骨架下剪枝。

算作 HDC 资源：

- VRF 的基础 4-bank LUTRAM 存储，因为 HDC 本身要存 hypervector、counter、读写和清零。
- HBIND/XOR 数据通路，因为 HBIND 是真实 HDC 指令；ECC ADD 复用 XOR 不改变它属于 HDC 的事实。
- HSIM/HMATCH 的 popcount slice，因为 HDC 自己需要 popcount 做相似度和匹配。
- HPERM 的基础 shift/align 数据通路，因为 HDC 自己有 HPERM；但 ECC 专用平方/扩展模式不算 HDC。
- HDC FSM、uop pipeline、HMATCH countdown、scalar response、HDC VRF writeback。

算作 ECC 增量资源：

- ECC 指令入口、状态、busy/done/status、point multiplication、inversion、LD/ITA 调度控制。
- ECC polynomial multiply 的 leaf/diag/fold 控制、partial/product storage、product bank。
- ECC GF(2^233) reduction、autoreduce、MAC、repeated square、scalar-bit 控制。
- ECC 接入共享 popcount、HPERM、VRF read/write 时新增的选择器和控制压力。

所以这里的 `V23 - V24` 不是“完全独立 ECC 模块面积”，而是当前 ECC 标量点乘能力加到 HDC 数据通路上以后，给总设计额外带来的真实增量，包括共享算子周围的 mux/control 代价。

## 总资源对比

| 版本 | WNS ns | 估算 Fmax MHz | LUT | Logic LUT | LUTRAM | FF | CARRY4 | BRAM | DSP | 最差端点 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| V24 严格仅 HDC | 0.244 | 210.261 | 4090 | 3746 | 344 | 1846 | 16 | 0 | 0 | `lane_result_q_reg[0][14]/D` |
| V23 HDC+ECC | 0.159 | 206.569 | 6258 | 5786 | 472 | 2113 | 20 | 0 | 0 | `ecc_inv_step_q_reg[0]/CE` |
| ECC 增量 | -0.085 | -3.692 | +2168 | +2040 | +128 | +267 | +4 | 0 | 0 | 转移到 ECC/control CE |

## 百分比对比

| 指标 | 仅 HDC | HDC+ECC | ECC 增量 | 相对仅 HDC 增加 | ECC 占当前总量 |
|---|---:|---:|---:|---:|---:|
| LUT | 4090 | 6258 | +2168 | +53.0% | 34.6% |
| Logic LUT | 3746 | 5786 | +2040 | +54.5% | 35.3% |
| LUTRAM | 344 | 472 | +128 | +37.2% | 27.1% |
| FF | 1846 | 2113 | +267 | +14.5% | 12.6% |
| CARRY4 | 16 | 20 | +4 | +25.0% | 20.0% |

直白地说：

- 当前 HDC+ECC 里，约 65.4% LUT 可以认为是 HDC-only 骨架，约 34.6% LUT 是 ECC 加入后的增量。
- 如果只看 Logic LUT，ECC 增量占总 Logic LUT 约 35.3%。
- FF 的 ECC 增量占比低很多，约 12.6%。
- 最干净的 ECC-only 存储增量是 +128 LUTRAM，主要来自当前 ECC product bank。

## 层级观察

| 层级/桶 | 仅 HDC LUT | HDC+ECC LUT | 增量 | 解释 |
|---|---:|---:|---:|---|
| top/control/local memory | 401 | 1252 | +851 | ECC FSM、点乘/求逆/约减控制、product LUTRAM、状态与调度逻辑 |
| VRF hierarchy | 1796 | 3105 | +1309 | VRF 存储本身仍是 HDC 需要的，但 ECC 加入后读写选择和控制压力明显增加 |
| P2 popcount slices total | 1130 | 1018 | -112 | 这是 Vivado 重映射差异；popcount 本体属于 HDC，共享后反而局部 LUT 重新分布 |
| lane shift/align total | 763 | 883 | +120 | HPERM 基础属于 HDC，增量主要来自 ECC 平方/对齐模式造成的映射变化 |
| lane shift + popcount 合计 | 1893 | 1901 | +8 | 说明共享计算算子本体几乎不是主要增量，真正大头在控制和 VRF 选择 |

这说明目前 ECC 面积故事还不是“几乎免费”，但方向很清楚：共享计算算子本身比较稳，主要额外面积来自 ECC 调度、VRF 读写 mux/control、以及 product/reduction 相关状态。

## 时序对比

两版都过 200 MHz。

V24 仅 HDC 的关键路径回到 HDC P2 lane result capture：

- startpoint：`uop_p2_q_reg[valid]/C`
- endpoint：`lane_result_q_reg[0][14]/D`
- data delay：4.753 ns
- WNS：0.244 ns
- 估算 Fmax：210.261 MHz

V23 HDC+ECC 的关键路径是 ECC/control CE：

- endpoint：`ecc_inv_step_q_reg[0]/CE`
- data delay：4.630 ns
- WNS：0.159 ns
- 估算 Fmax：206.569 MHz

也就是说，ECC 加入后时序余量减少约 0.085 ns，但仍保持 200 MHz 以上。

## 回归验证

| 测试 | 结果 |
|---|---|
| `xsim_hdec_hdc_full_flow_v20.tcl` | PASS |

## 原始报告

V24 严格仅 HDC OOC：

- `reports/hdec/v24_hdc_only_vs_ecc/hdc_only_strict_ooc_200mhz/run_summary.txt`
- `reports/hdec/v24_hdc_only_vs_ecc/hdc_only_strict_ooc_200mhz/utilization.rpt`
- `reports/hdec/v24_hdc_only_vs_ecc/hdc_only_strict_ooc_200mhz/utilization_hier.rpt`
- `reports/hdec/v24_hdc_only_vs_ecc/hdc_only_strict_ooc_200mhz/timing_top200.csv`

V24 严格仅 HDC xsim：

- `reports/hdec/v24_hdc_only_vs_ecc/xsim/xsim_hdc_full_flow_v20_hdc_only_strict.log`

V23 HDC+ECC reference：

- `reports/hdec/v23_optimization/ooc_final_round07_200mhz/run_summary.txt`
- `reports/hdec/v23_optimization/ooc_final_round07_200mhz/utilization.rpt`
- `reports/hdec/v23_optimization/ooc_final_round07_200mhz/utilization_hier.rpt`

## 结论

当前 ECC 标量点乘支持的增量约为：

- +2168 LUT
- +2040 Logic LUT
- +128 LUTRAM
- +267 FF

其中 +128 LUTRAM 比较明确属于 ECC product bank；Logic LUT 大头集中在 ECC 控制、VRF 读写选择、以及共享资源接入控制。下一步如果要把“ECC 几乎免费复用 HDC”讲得更强，重点应该继续压缩 ECC 专属控制状态、减少 VRF 端口选择复杂度，并把 product/reduction 的临时存储更深地并入 HDC 现有数据搬运路径。
