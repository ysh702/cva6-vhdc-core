# VV35 全局等价 PPA 收敛最终报告

## 1. 最终结论

VV35 达到可提交目标，并保持全部冻结功能、周期及交织事件不变。最终采用默认 Vivado 综合策略，结果如下：

| 指标 | VV35-0 | VV35 最终 | 变化 | 目标判定 |
|---|---:|---:|---:|---|
| Logic LUT | 4764 | 4694 | -70，-1.469% | 通过不高于4700 |
| FF | 1536 | 1513 | -23，-1.497% | 通过不高于1525 |
| BRAM | 4 | 4 | 0 | 通过 |
| DSP | 0 | 0 | 0 | 通过 |
| LUTRAM | 0 | 0 | 0 | 通过 |
| WNS | 0.301 ns | 0.293 ns | -0.008 ns | 通过不低于0.280 ns |
| 估算 Fmax | 212.811 MHz | 212.450 MHz | -0.170% | 通过200 MHz |
| PMUL | 146908 | 146908 | 0 | 周期精确一致 |

最终版本达到“可提交目标”，没有达到不高于4650 LUT的强目标或4500 LUT理想目标。面积导向策略最低可进入4458至4666 LUT区间，但均出现时序失败、门槛不足或FF增加，未被采用。

## 2. 被接受的等价优化

### 2.1 互斥生命周期状态复用

普通 HSIM/HMATCH 与并发 HMATCH sidecar 不会同时拥有计算状态。最终 RTL 复用普通路径的 `hsim_total_q`、`hmatch_best_dist_q` 与 `hmatch_best_idx_q`，删除并发路径重复的累计值、最佳距离及最佳索引寄存器。该修改不改变请求接受、分块次序、比较周期或响应打包周期。

### 2.2 leaf-B 更新类别因式化

ECC leaf-B 存在两类互斥更新：VRF 捕获同时更新主字与低异或字，CAP2 局部变换只更新主字。最终 RTL 用 `ecc_leaf_b_capture_we` 与 `ecc_leaf_b_transform_we` 明确这两类既有写入时刻，使综合器消除重复的下一状态保持选择。该修改不改变任何数据变换、流水边界或 PMUL 状态。

这两项均属于全局实现收敛，不作为新的论文创新，也不改变统一位矩阵、共享算术核心或 VV31/VV33 调度方法。

## 3. 消融边界

候选收益存在明显非线性。固定地址单项可达4719 LUT，但与生命周期复用组合后回升至4745 LUT。局部阶段编码单项可达4701 LUT、1508 FF、WNS 0.305 ns，但与 leaf-B 使能分解组合后为4714 LUT、1511 FF。状态复用加 HCNTCLIP 镜像压缩为4754 LUT。上述组合均按实测结果拒绝，没有把独立收益算术相加。

主 FSM 改编码、宽标量寄存器复用、POPCOUNT 小计压缩、VRF 地址保持及面积综合策略也已实测。它们分别引入 LUT 增长、长组合路径、负 WNS 或控制锥扩张，因此未进入最终累计链。

## 4. 功能、周期及调度证据

最终候选通过4096组GF乘加、4096组平方、融合映射、原生斜线映射、2048组shift-align基向量、四个新合法K-233随机标量、完整HDC、HPERM全部1024种旋转编码、ECC ADD/REDUCE/INV及VV33精确HMATCH交织合同。

四个K的PMUL均为146908 cycles。HMATCH交织继续完成1632次搜索，固定工作量从337853 cycles降至200144 cycles，节省137709 cycles，周期下降40.76%，加速比1.688x，向独立双加速器理想边界收敛93.73%。接受/响应为1177/1177，位矩阵/POPCOUNT事件为18832/18832，所有共享资源冲突为0。

VV30 stage3 的Runner总体字段因既有PASS正则未转义而误报FAIL，实际九个测试均输出功能PASS。相同误判存在于旧VV31基线。VV31现存五项测试全部通过，另四项源文件缺失，因此该层严格记为NO_DECISION，而不是完整stage通过。

## 5. 结构保持

最终DCP确认唯一 `i_vrf`、唯一 `i_vec`、`i_vec` 内唯一 GF(2) tile，资源为4 RAMB36、0 LUTRAM、0 DSP。RTL唯一实例与共同输入连接联合支持单套位矩阵、AND、完整POPCOUNT、XOR1及XOR0仍由HDC与ECC共同使用。综合扁平化使现有脚本不能按原RTL名称逐门计数全部细粒度算子，因此不作超出该证据的逐门物理唯一性宣称。

## 6. 可重复性

最终Default OOC连续两次得到相同综合校验和 `e9217b8f`，并逐项复现4694 LUT、1513 FF、4 BRAM、0 DSP、WNS 0.293 ns。最终RTL、周期合同、消融表及结构检查报告共同构成VV35冻结证据。

## 7. 关键证据路径

- 基线：`tmp/hdec_logs/vv35/vv35_0_ooc_baseline_20260803/`
- 最终OOC-1：`tmp/hdec_logs/vv35/final_candidate_ooc_run1/`
- 最终OOC-2：`tmp/hdec_logs/vv35/final_candidate_ooc_run2/`
- 最终DCP：`tmp/hdec_logs/vv35/final_structure_ooc/vivado/vv35_final_structure.dcp`
- 四K回归：`tmp/hdec_logs/vv35/final_stage3_20260803/run_manifest.json`
- HMATCH精确合同：`tmp/hdec_logs/vv35/final_hmatch_exact_20260803/run_manifest.json`
- 模式对照：`tmp/hdec_logs/vv35/final_vv33_on_off_20260803/run_manifest.json`
- VV31现存合同：`tmp/hdec_logs/vv35/final_vv31_stage_existing/run_manifest.json`
