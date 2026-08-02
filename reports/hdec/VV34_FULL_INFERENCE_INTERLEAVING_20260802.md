# VV34 完整HDC推理与K-233 PMUL细粒度交织验证报告

日期：2026-08-02
证据状态：`FINAL_VERIFIED`

## 1. 版本边界

VV34固定保存完整HDC推理交织版本。一次HDC任务的计时边界为：

```text
resident binary input and role HV
    -> HPERM
    -> HBIND
    -> encoded query HV
    -> three-class HMATCH
    -> class response
```

该边界覆盖HDEC内部的查询编码与分类决策。原型训练，模型装载，输入量化及原始传感器到二值超向量的映射位于计时区间之外。因此，本文所称“完整HDC推理”是相对于HDEC内部硬件流程而言，不代表原始数据到标签的端到端应用。

VV34继续使用一套1R1W VRF，一套8×32位矩阵，一套AND与POPCOUNT路径，一套XOR0与XOR1，不复制第二套宽计算核心。完整推理调度是在统一表示与共享硬件基础上的执行层扩展。

## 2. 随机输入与可复现身份

本次Vivado 2024.2 XSim复测使用系统随机源生成的合法sect233k1标量：

```text
seed = e8dcb3de0a29179dd5336a5c29c7b456a31284ed54a93955cc6b7ed80b63ce57
K    = 000000075a148cb564975aab1b4a15a86c6840446fca59d44e07b70f23ff4b84
Hamming weight = 109
```

| 对象 | SHA-256或提交 |
|---|---|
| VV34入口提交 | `0a02879370a4a4de9f61765124903945da35c8cb` |
| `hdec_top.sv` | `94f59b5bc959ed0b665a0b768d12bd4f68d76efa9f2c94c009cad652fc600726` |
| 完整推理TB | `6fde75849941c9c1f2a2379b2101bd870cd5054a7365842c1a5eb59b4cfa0001` |
| Runner | `56b0917e150a4e03b58e7e852a3dcdf69e318b391097deb1be344801e67068f5` |
| 运行清单 | `278bd0eea7b559b7347952591b0144e7e4406ba413234fa958973642c4a649e1` |
| 向量清单 | `f6d9c35a676f79db7a6288443239587d13e4edc32db8b94980721ac933901d85` |
| XSim日志 | `523c6ef08b9addde203fa42963a0fdf536a158ee2da83f14ddc7af51c728e146` |

运行清单确认RTL在仿真期间未改变，编译，展开，仿真退出码均为0，日志具有唯一PASS标记。

## 3. 原始周期

容量探针在PMUL结束前观察到711次完整推理，第712次未完成。为排除边界任务对不同执行方式的影响，正式固定工作量使用较保守的710次完整推理。

| 符号 | 含义 | 周期 | 性质 |
|---|---|---:|---|
| \(C_E\) | 独立K-233 PMUL | 146908 | 实测 |
| \(C_F\) | 单次完整HDC推理 | 161 | 实测 |
| \(N\) | 固定完整推理数 | 710 | 实测容量内固定值 |
| \(C_H\) | 710次连续HDC推理 | 114310 | 实际连续回放 |
| \(C_S\) | 同一HDEC严格串行执行 | 261219 | 实测 |
| \(C_I\) | VV34交织执行 | 198738 | 实测 |
| \(C_{ideal}\) | 独立双加速器理论下界 | 146908 | \(\max(C_E,C_H)\) |

严格串行组件和为：

\[
C_E+C_H=146908+114310=261218.
\]

实际串行回放为261219周期，多出的1周期是PMUL结束到HDC批次开始的任务过渡开销。

## 4. 调度指标

### 4.1 完工时间缩减

多任务加速研究通常以共置执行相对串行执行的makespan reduction评价联合完成时间收益。VV34采用相同口径：

\[
R_{ms}=\frac{C_S-C_I}{C_S}.
\]

代入实测值：

\[
\Delta C=261219-198738=62481,
\]

\[
R_{ms}=\frac{62481}{261219}=23.92\%.
\]

Runner使用基点整数输出23.91%，差异来自截断。论文表格按精确除法保留两位小数，写23.92%。

### 4.2 固定工作量加速比及吞吐提升

\[
S=\frac{C_S}{C_I}=1.3144\times.
\]

在相同工作量下，等效完成率提升为：

\[
G_{throughput}=S-1=31.44\%.
\]

### 4.3 理论重叠间隙回收率

\[
\eta_{gap}=\frac{C_S-C_I}{C_S-C_{ideal}}=54.66\%.
\]

该指标表示VV34消除了串行执行到理想双加速器下界之间54.66%的可重叠周期。它是HDEC为本实验明确定义的归一化指标，不应冒充通用标准名称。

### 4.4 理想下界效率

\[
\eta_{ideal}=\frac{C_{ideal}}{C_I}=73.92\%.
\]

独立双加速器下界是理论参考，不是两套物理加速器的板级实测结果。

### 4.5 PMUL混合墙钟拉伸

\[
\Delta C_{PMUL}=198738-146908=51830,
\]

\[
R_{PMUL,wall}=\frac{51830}{146908}=35.28\%.
\]

这一数值表示并发窗口中PMUL从启动到完成的墙钟延长。与此同时，窗口内完成710次HPERM、HBIND及三类别HMATCH，联合完工时间仍相对串行减少23.92%。

## 5. 数据承载事件与正确性

| 事件 | 数量 |
|---|---:|
| 完整HPERM响应 | 710 |
| 完整HBIND响应 | 710 |
| 完整三类别HMATCH响应 | 710 |
| 配对侧路径接受及响应 | 710及710 |
| 位矩阵配对发射 | 8520 |
| POPCOUNT恢复 | 8520 |
| VRF读冲突 | 0 |
| 位矩阵冲突 | 0 |
| XOR0冲突 | 0 |
| payload冲突 | 0 |
| 未知值 | 0 |
| 总错误 | 0 |

一次三类别HMATCH含12个256位查询与原型块，因此：

\[
710\times3\times4=8520.
\]

这证明交织事件包含真实位矩阵与POPCOUNT计算，而不是只重叠控制推进。

## 6. FPGA OOC结果

Vivado 2024.2，目标器件`xc7z020clg400-2`，时钟约束5 ns，VV34重新综合结果为：

| 指标 | VV34 |
|---|---:|
| Logic LUT | 4812 |
| FF | 1536 |
| BRAM | 4 |
| DSP | 0 |
| WNS | 0.208 ns |
| 约束裕量估算Fmax | 208.681 MHz |

该结果属于`hdec_top` FPGA OOC综合，不是完整CVA6系统，ASIC后端或板级功耗结果。

## 7. 证据路径

- 测试平台：`verif/hdec/vv33/integration/tb_vv33_full_inference_interleave.sv`
- Runner：`scripts/hdec/vv33/run_vv33_bank_episode_interleave.ps1 -FullInference`
- 新随机复测：`tmp/hdec_logs/vv33/full_inference_interleave_20260802_224824_239/`
- VV34 OOC摘要：`reports/hdec/vv34_full_inference_final_ooc_20260802/reports/run_summary.txt`

测试目录仍沿用VV33开发阶段名称，版本归属由VV34分支与本报告固定。后续若仅做命名迁移，不应改变RTL或重新解释PPA。

## 8. 论文允许表述

> 对于由HPERM、HBIND及三类别HMATCH构成的HDEC内部完整推理链，资源生命周期调度在一次K-233 PMUL窗口内完成710次推理。相对于实测严格串行基准，联合完成时间由261219降至198738周期，减少23.92%，对应1.3144倍固定工作量加速。实现使用4812个Logic LUT、1536个FF及4个BRAM，在5 ns约束下获得0.208 ns WNS。

不得将该结果写成原始传感器到标签的完整端到端推理，不得将理论独立下界称为双加速器实测，也不得把VV34调度拆成独立于统一表示与共享架构之外的新论文级贡献。

## 9. 指标来源

- ISPA采用串行总时间与共置总时间的差额归一化评价makespan reduction：[IEEE Transactions on Computers, 2023](https://doi.org/10.1109/TC.2022.3214088)。
- STP与ANTT需要每个共运行任务在共享执行中的独立性能或独立周转时间：[Eyerman and Eeckhout, IEEE Micro, 2008](https://users.elis.ugent.be/~leeckhou/papers/micro08.pdf)。当前日志没有冻结两个任务各自独立的共享周转时间，因此不报告STP或ANTT，避免将系统makespan误写成公平性指标。
