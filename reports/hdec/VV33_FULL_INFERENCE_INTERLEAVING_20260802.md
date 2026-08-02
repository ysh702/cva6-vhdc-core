# VV33 完整HDC推理与ECC PMUL交织实验归档

日期：2026-08-02

## 1. 归档定位

本报告保存VV33对完整HDC推理链的阶段性探索。该版本已经通过一个随机K-233标量下的固定工作量仿真，并具有与恢复后RTL精确匹配的OOC综合结果。后续论文版本选择HMATCH原型关联搜索作为第五章的主要机制证据，因此本实验保留为同一分支中的历史提交，不作为当前分支HEAD的主结果。

完整推理在本实验中的计算边界为：

```text
resident binary input and role HV
    -> HPERM
    -> HBIND
    -> encoded query HV
    -> three-class HMATCH
    -> class response
```

原型训练，模型装载，输入量化以及标量特征到二值超向量的上游映射均位于计时区间之外。该边界表示HDEC内部的查询编码与原型决策，不代表从原始传感器数据开始的端到端应用推理。

## 2. 冻结快照

| 项目 | 冻结值 |
|---|---|
| 分支 | `VV33` |
| 入口提交 | `1d0c180f20f0f056878776afb5079a7cdaee12b4` |
| `hdec_top.sv` SHA-256 | `9855de1c7ce7d9c8d558e68465337aa069e03ccbb3ef876445fbe87a37da86b8` |
| 完整推理TB SHA-256 | `e9a4285741a552ee6b3eaf7ad9644c2cb19af13eb85dff50e482ef0e661014e1` |
| Runner SHA-256 | `a01bb2c2e9f2c9ec20cbdf72ef3bd64148dabe58244d7da1867c3080056d3325` |
| 随机种子 | `4a9422d0be538b882135ae183a87db2d2af62346b0f39763b3feeee5f0b7e445` |
| K-233标量 | `0000002efc0829e4a9941d169405836394ab32bf773dc7f2c3ffc8f584f026a6` |
| K汉明重量 | 117 |
| 向量清单SHA-256 | `5bf01cbc5c19f86886ec65bc4b7ffd1959e205a92cccad903377f9ab244a7ab6` |
| XSim日志SHA-256 | `61a83b548b36d7f302fdc67e745a9463f90fb96f1cf62937188ac27615809ff5` |

运行清单确认仿真开始与结束时的`hdec_top.sv`哈希一致，编译，展开，仿真退出码均为0，日志只包含一个PASS标记。

## 3. 固定工作量与原始周期

一次HDC推理包含一条HPERM，一条HBIND以及一次三类别HMATCH。独立执行一次需要161周期。容量探针显示，一次混合PMUL完成前可以退休710次完整推理，第711次为未完成任务，因此固定比较采用：

\[
N=710.
\]

| 执行对象 | 周期 | 性质 |
|---|---:|---|
| 独立K-233 PMUL，\(C_E\) | 146908 | 实测 |
| 单次完整HDC推理 | 161 | 实测 |
| 710次独立HDC推理，\(C_H\) | 114310 | 实际连续回放 |
| 同一HDEC上的串行执行，\(C_S\) | 261219 | 实测 |
| HDEC交织执行，\(C_I\) | 198738 | 实测 |
| 独立双加速器计算下界，\(C_{ideal}\) | 146908 | \(\max(C_E,C_H)\)，理论参考 |

串行实测值与算术和相差一个边界转换周期：

\[
C_E+C_H=261218,
\qquad
C_S=261219.
\]

## 4. 调度效果

交织调度减少的墙钟周期为：

\[
\Delta C=C_S-C_I=62481.
\]

相对同一HDEC串行执行的完工时间缩减为：

\[
R_C=\frac{C_S-C_I}{C_S}=23.92\%.
\]

固定工作量加速比为：

\[
S=\frac{C_S}{C_I}=1.3144\times.
\]

串行执行与独立双加速器理论下界之间存在114311个可消除周期。交织调度消除了其中54.66%：

\[
\eta_{gap}
=\frac{C_S-C_I}{C_S-C_{ideal}}
=54.66\%.
\]

交织结果相对理论下界的效率为：

\[
\eta_{ideal}=\frac{C_{ideal}}{C_I}=73.92\%.
\]

这些指标分别回答三个问题。\(R_C\)表示相对串行HDEC减少了多少总时间，\(S\)表示相同工作量获得的整体加速，\(\eta_{gap}\)表示调度消除了多少原本可被并行隐藏的周期。

## 5. PMUL延迟与资源事件

混合执行中PMUL从开始到完成需要198738周期，相对独立PMUL增加51830周期：

\[
R_{PMUL,wall}
=\frac{198738-146908}{146908}
=35.28\%.
\]

该数值是PMUL端到端墙钟拉伸。它不能与监视器按活动阶段统计的ECC有效服务周期混用。

| 事件 | 数量 |
|---|---:|
| 完整HPERM响应 | 710 |
| 完整HBIND响应 | 710 |
| 完整HMATCH响应 | 710 |
| 配对侧路径接受及响应 | 710及710 |
| 配对位矩阵发射 | 8520 |
| 配对POPCOUNT恢复 | 8520 |
| VRF读冲突 | 0 |
| 位矩阵冲突 | 0 |
| XOR0冲突 | 0 |
| payload冲突 | 0 |
| 未知值及总错误 | 0 |

每次三类别HMATCH需要12个256位查询与原型块，因此：

\[
710\times3\times4=8520.
\]

## 6. 精确匹配的FPGA OOC结果

恢复`9855de1c...`快照后，使用Vivado 2024.2，`xc7z020clg400-2`以及5 ns时钟约束重新执行OOC综合，得到：

| 指标 | 结果 |
|---|---:|
| Logic LUT | 4812 |
| FF | 1536 |
| BRAM | 4 |
| DSP | 0 |
| WNS | 0.208 ns |
| 估算Fmax | 208.681 MHz |

该综合结果与本提交中的完整推理RTL精确对应。此前的4796 LUT结果来自临近但不同的中间快照，不再与23.92%功能结果绑定。

## 7. 证据位置与允许结论

- 本地运行清单：`tmp/hdec_logs/vv33/fused_hperm_square_full_20260802b/run_manifest.json`
- 本地XSim日志：`tmp/hdec_logs/vv33/fused_hperm_square_full_20260802b/xsim_full_inference_interleave/xsim.log`
- 测试平台：`verif/hdec/vv33/integration/tb_vv33_full_inference_interleave.sv`
- Runner：`scripts/hdec/vv33/run_vv33_bank_episode_interleave.ps1 -FullInference`
- 匹配OOC摘要：`reports/hdec/vv33_full_inference_archive_ooc_20260802/reports/run_summary.txt`

该实验支持以下结论：在单一1R1W VRF以及共享位矩阵核心不变的条件下，一次K-233 PMUL与710次包含查询编码及三类别原型决策的HDC推理可由HDEC在198738周期内完成，相对同一HDEC的实测串行执行减少62481周期，完工时间缩减23.92%。

该实验不用于声称数据集准确率，原始传感器到标签的完整应用推理，或者两套独立加速器的实测系统性能。当前论文主结果采用HMATCH原型关联搜索的冻结版本，本报告仅保存完整推理扩展的可复现实验边界。
