# VV35-0 基线冻结报告

## 1. 冻结对象

- 基线提交：`VV33@4647c5806c0156b8791477aa61352d95dbb7d2e9`
- VV35 分支：`VV35`
- 顶层：`hdec_top`
- 器件：`xc7z020clg400-2`
- 工具：Vivado 2024.2
- 时钟约束：5.000 ns
- 综合模式：out-of-context，默认综合策略

VV35 只进行等功能 PPA 收敛。统一 8x32 位矩阵，单套 256 位 AND，完整 POPCOUNT，XOR1，XOR0，融合模贡献映射，VV31 ECC 内部调度，VV33 HMATCH 交织调度，4-BRAM VRF 及成对返回保持级均被冻结。

## 2. PPA 基线

| 指标 | VV35-0 |
|---|---:|
| Logic LUT | 4764 |
| Slice LUT | 4764 |
| LUTRAM | 0 |
| FF | 1536 |
| BRAM | 4 |
| DSP | 0 |
| CARRY4 | 17 |
| WNS | 0.301 ns |
| 估算 Fmax | 212.811 MHz |

最差路径为 `ecc_pmul_subop_q_reg[0]/C` 至 `ecc_leaf_b_q_reg[0]/CE`，数据路径延迟为 4.488 ns。

层级资源为：

| 层级 | LUT | FF | BRAM |
|---|---:|---:|---:|
| `hdec_top` 顶层私有逻辑 | 1875 | 976 | 0 |
| `i_vec` | 2889 | 304 | 0 |
| `i_gf2_contribution_row_tile` | 576 | 0 | 0 |
| `i_vrf` | 0 | 256 | 4 |

## 3. 周期及交织合同

冻结随机向量包下的基线结果为：

| 合同 | 结果 |
|---|---:|
| PMUL | 146908 cycles |
| 四类普通 HMATCH | 117 cycles |
| 串行固定工作量 | 337853 cycles |
| HMATCH 交织固定工作量 | 200144 cycles |
| 交织期间完成 HMATCH | 1632 |
| HMATCH 接受/响应 | 1177/1177 |
| 位矩阵/POPCOUNT 事件 | 18832/18832 |
| 数据重叠事件 | 21811 |
| 控制重叠事件 | 14560 |
| 资源配对事件 | 47080 |

交织版本相对严格串行基线减少 137709 cycles，周期下降 40.76%，加速比为 1.688x，向独立双加速器理想边界的差距收敛比例为 93.73%。VRF，位矩阵，POPCOUNT，XOR0，payload 冲突均为 0，未知写回及协议错误均为 0。

## 4. 基线证据

- OOC：`tmp/hdec_logs/vv35/vv35_0_ooc_baseline_20260803/`
- HMATCH 合同：`tmp/hdec_logs/vv35/baseline_hmatch_20260803_024327/run_manifest.json`

VV31 登记测试中有四个 testbench 源文件缺失，因此最终只能分别引用现存五项 VV31 合同，不得写成“VV31 完整 stage 回归通过”。该基础设施缺口不改变已经独立覆盖的 PMUL，HDC，HMATCH 及资源冲突结论。
