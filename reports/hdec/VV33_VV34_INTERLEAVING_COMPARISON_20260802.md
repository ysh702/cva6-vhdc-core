# VV33 HMATCH与VV34完整HDC推理交织调度对比

日期：2026-08-02
证据状态：`FINAL_VERIFIED`

## 1. 两个实验回答不同问题

- **VV33，已编码查询的四类HMATCH原型关联搜索。** 查询及原型已驻留于VRF，用于观察最适合交织的数据承载内核及调度能力上限。
- **VV34，HDEC内部完整HDC推理。** 每次任务依次执行HPERM、HBIND及三类别HMATCH，用于观察加入查询编码后的真实流程收益。

两组结果可以同时写入论文。VV33说明调度机制在高兼容内核上的能力，VV34说明同一方法扩展到完整HDEC内部推理链后的系统效果。二者是同一调度方法的不同工作负载，不是两个并列创新。

## 2. 完整原始数据

| 指标 | VV33 HMATCH | VV34 完整HDC推理 |
|---|---:|---:|
| HDC任务定义 | 四类别HMATCH | HPERM、HBIND、三类别HMATCH |
| 单次HDC任务周期 | 117 | 161 |
| PMUL窗口内固定完成数 \(N\) | 1632 | 710 |
| 等量HDC批次周期 \(C_H\) | 190944 | 114310 |
| 独立PMUL周期 \(C_E\) | 146908 | 146908 |
| 严格串行实测 \(C_S\) | 337853 | 261219 |
| 组件算术和 | 337852 | 261218 |
| 串行任务过渡 | 1 | 1 |
| 交织实测 \(C_I\) | 200144 | 198738 |
| 独立双加速器理论下界 \(C_{ideal}\) | 190944 | 146908 |
| 实际减少周期 | 137709 | 62481 |
| Makespan reduction | 40.76% | 23.92% |
| 固定工作量加速比 | 1.68805× | 1.3144× |
| 等工作量完成率提升 | 68.80% | 31.44% |
| 理论间隙回收率 | 93.74% | 54.66% |
| 理想下界效率 | 95.40% | 73.92% |
| PMUL混合墙钟拉伸 | 36.24% | 35.28% |
| Logic LUT | 4764 | 4812 |
| FF | 1536 | 1536 |
| BRAM | 4 | 4 |
| DSP | 0 | 0 |
| WNS | 0.301 ns | 0.208 ns |
| 约束裕量估算Fmax | 212.811 MHz | 208.681 MHz |

## 3. 共同公式

论文主指标采用共置调度论文常用的联合完工时间缩减：

\[
R_{ms}=\frac{C_S-C_I}{C_S}.
\]

固定工作量加速比为：

\[
S=\frac{C_S}{C_I}.
\]

同工作量完成率提升为：

\[
G_{throughput}=S-1.
\]

HDEC另外定义理论可重叠间隙回收率：

\[
\eta_{gap}=\frac{C_S-C_I}{C_S-C_{ideal}}.
\]

理想下界效率为：

\[
\eta_{ideal}=\frac{C_{ideal}}{C_I}.
\]

其中：

\[
C_{ideal}=\max(C_E,C_H).
\]

\(C_{ideal}\)是忽略CPU发射、共享带宽及同步代价的理论双加速器下界，不是两套物理加速器的实测周期。

## 4. VV33 HMATCH计算

\[
C_S=337853,\qquad C_I=200144.
\]

\[
\Delta C=137709,
\qquad
R_{ms}=40.76\%,
\qquad
S=1.68805\times.
\]

\[
G_{throughput}=68.80\%,
\qquad
\eta_{gap}=93.74\%,
\qquad
\eta_{ideal}=95.40\%.
\]

PMUL混合窗口内完成1632次四类搜索。1177次搜索通过CAP2与FOLD直接配对路径退休，其占比为：

\[
1177/1632=72.12\%.
\]

直接路径产生18832次位矩阵发射及18832次POPCOUNT恢复：

\[
1177\times4\text{类}\times4\text{块}=18832.
\]

VRF、位矩阵、XOR0、POPCOUNT及payload冲突均为0。

## 5. VV34完整推理计算

\[
C_S=261219,\qquad C_I=198738.
\]

\[
\Delta C=62481,
\qquad
R_{ms}=23.92\%,
\qquad
S=1.3144\times.
\]

\[
G_{throughput}=31.44\%,
\qquad
\eta_{gap}=54.66\%,
\qquad
\eta_{ideal}=73.92\%.
\]

固定工作量包含710次HPERM、710次HBIND及710次三类别HMATCH。配对路径产生8520次位矩阵发射及8520次POPCOUNT恢复：

\[
710\times3\text{类}\times4\text{块}=8520.
\]

VRF、位矩阵、XOR0及payload冲突均为0，未知值及功能错误均为0。

## 6. 为什么VV34百分比低于VV33

VV33只执行已编码查询的原型关联搜索。该路径的大部分计算可嵌入PMUL的CAP2与FOLD兼容窗口，因此能够完成更多任务并更接近理论双加速器下界。

VV34还包含HPERM及HBIND。查询编码增加了VRF读取、置换、XOR及写回生命周期，其中部分阶段与PMUL共享端口或共享状态，只能有界串行。因此，VV34的23.92%不是功能退化，而是扩大任务边界后更严格的系统结果。

## 7. 论文建议呈现

建议将VV34完整推理作为主应用级结果，将VV33 HMATCH作为调度机制的内核级消融或上限结果：

> 对完整HDEC内部推理链，调度将联合完成时间降低23.92%。当查询编码已完成，仅执行最常见的原型关联搜索后端时，完成时间降低40.76%，表明编码阶段的共享端口生命周期是进一步提高时间利用率的主要边界。

这样既能展示完整流程，也能解释机制为何在HMATCH路径上更有效，而不会把HMATCH错误写成完整推理。

## 8. 学术指标依据

- ISPA以串行总执行时间与共置执行时间之差归一化，评价多任务共置的makespan reduction：[IEEE Transactions on Computers, 2023](https://doi.org/10.1109/TC.2022.3214088)。
- STP与ANTT要求每个任务在共享运行中的独立性能或周转时间：[Eyerman and Eeckhout, IEEE Micro, 2008](https://users.elis.ugent.be/~leeckhou/papers/micro08.pdf)。当前两个实验冻结的是联合完工时间与ECC活动周期，而不是两项任务各自的共享IPC或独立周转时间，因此不报告STP或ANTT。

## 9. 版本及证据

- VV33 HMATCH：分支`VV33`，随机K复测目录`tmp/hdec_logs/vv33/bank_episode_interleave_20260802_224044_578/`，OOC摘要`reports/hdec/vv33_hmatch_final_ooc_20260802/reports/run_summary.txt`。
- VV34完整推理：分支`VV34`，随机K复测目录`tmp/hdec_logs/vv33/full_inference_interleave_20260802_224824_239/`，OOC摘要`reports/hdec/vv34_full_inference_final_ooc_20260802/reports/run_summary.txt`。

测试目录中的`vv33`是开发阶段路径名，不改变VV34分支中的版本归属。
