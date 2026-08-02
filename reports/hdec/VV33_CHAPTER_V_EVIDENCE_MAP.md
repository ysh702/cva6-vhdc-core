# VV33 第五章主张、RTL、测试及指标证据映射

日期：2026-08-02
论文主对象：HMATCH 原型关联搜索与 K-233 PMUL 的细粒度交织
归档对象：包含 HPERM、HBIND、HMATCH 的 HDC 驻留式完整推理探索

## 1. 文档结论

第五章以一项执行层方法为主线：

> 面向固定资源生命周期的 HDC/ECC 细粒度时隙匹配。

第四章建立的统一位矩阵及共享计算结构解决空间重复问题。第五章进一步利用 ECC PMUL 的固定 ISSUE、CAP0、CAP1、CAP2、FOLD 生命周期，把已编码查询的 HDC 原型关联搜索映射到不冲突的计算时隙。该方法继续使用同一套 1R1W VRF、8×32 位矩阵、256 位 AND、POPCOUNT、XOR0、XOR1 及 payload，不把 HDEC 改造成两套并列加速器。

当前论文主结果只覆盖 HMATCH 所代表的原型关联搜索阶段。查询超向量与四个类别原型在计时前已经驻留于 VRF。该结果可以写成“HDC 分类推理中的原型关联搜索与 ECC PMUL 的交织”，不能写成“完整 HDC 推理”或“原始传感器到标签的端到端推理”。

完整驻留式推理探索已经单独归档。其计算链为 HPERM、HBIND、三类别 HMATCH。该实验用于记录方法扩展边界，不替代 HMATCH 主结果，不参与当前第五章主性能结论。

## 2. 主结果的冻结证据身份

HMATCH 主结果已经在恢复提交 `0f255e43` 上完成匹配的严格串行与交织重跑。RTL 在整个运行期间保持不变，运行清单同时冻结测试平台、Runner、随机向量及 XSim 日志的内容哈希。当前证据状态为 `VERIFIED_MATCHED_RUN`。

| 项目 | 冻结值 |
|---|---|
| 分支 | `VV33` |
| RTL 恢复提交 | `0f255e4379fababd646918e8d9028faefb8c0bd0` |
| `hdec_top.sv` SHA-256 | `06560b85f3b78ac7db85e8bacb5ac7345cf6ace4c245dd2bb37e31703b772180` |
| `hdec_lane_4x64.sv` SHA-256 | `4eccf93067f22f30caca2b6300c2cab86adf4e39bcc09422b0e7a1c7a5ab594e` |
| `hdec_vrf_64x256.sv` SHA-256 | `5e5f95532ea45024374c42a99c4e604f46bced1fcbf6640009c6971690706784` |
| HMATCH 交织 TB SHA-256 | `cfa9725f88d526dd27424a8f397c96bcf0578a4e646262b3fd3db163a1d97b77` |
| Runner SHA-256 | `c46f79fa763628e5c718fe20851271b34df0874a58d2c8746490030cbff144c8` |
| 运行清单 SHA-256 | `270c1ed0e224f191bdad218e0f74aece032c84b07e3a02461e673f11e048b6ae` |
| 向量清单 SHA-256 | `6abb1e2e726452b99e5f64c4eb78005360cfdf4d2d3bb3075ef479109289bca2` |
| XSim 日志 SHA-256 | `1994b095255699ae8f7316d8abb64bb1c9323158f863e9b46b56ff30a683fb3b` |
| 仿真工具 | Vivado Simulator 2024.2 |
| 综合器件及约束 | `xc7z020clg400-2`，5 ns |
| 随机种子 | `336fdc7c34052eed25f8b01a9b022f5e72e0f563ccaa5c85a1b3518a84734f46` |
| 合法 K-233 标量 | `00000078402f1ce8798d3d405a482bec4304f5551e92be246ee45fbb1af9fa13` |
| K 的 Hamming weight | 115 |
| 方法证据门 | `MET` |

## 3. 第五章主张到证据的逐项映射

| 编号 | 论文允许主张 | 计算对象及前提 | RTL 机制 | 测试及直接证据 | 边界 |
|---|---|---|---|---|---|
| C5-1 | 整段任务所有权会遮蔽共享结构中的时间空隙 | ECC PMUL 与待执行 HMATCH 共享 VRF 返回、位矩阵及 payload 生命周期 | HMATCH 侧路径只在固定 PMUL 状态开放，普通冲突状态保持串行 | 严格串行回放为 337853 周期，交织墙钟为 200144 周期 | 不写成任意 HDC、ECC 操作均可并发 |
| C5-2 | 固定 PMUL 状态及 VRF 返回延迟使兼容关系可在设计阶段确定 | ISSUE、CAP0、CAP1、CAP2、FOLD 次序固定，VRF 为单读单写 | `vv33_pair_start`、`vv33_pair_active_q`、`vv33_pair_a_sent_q`、`vv33_pair_read_ready_q` 表示窄生命周期状态 | TB 检查矩阵事件只在 CAP2 发生，POPCOUNT 恢复只在 FOLD 发生 | 不写成通用动态记分牌或乱序调度器 |
| C5-3 | 相邻单读请求可形成一次 HMATCH 双源配对窗口 | 查询块 A 与原型块 B 不能同拍双读，二者已驻留于规定 VRF 区域 | 通过同一 1R1W 端口连续读取 A、B，同时使用原始 BRAM 返回及已寄存返回 | `pair_accept=1177`，`pair_response=1177`，VRF 读冲突为 0 | 不写成 2R1W VRF，不宣称任意地址布局均进入侧路径 |
| C5-4 | CAP2 可在不复制位矩阵的条件下执行 HDC 位积及计数 | CAP2 消费已寄存 ECC 结果，不再次发射同一 ECC 位矩阵操作 | `vv33_pair_product_fire` 进入原有 `i_vec` 位矩阵、AND、POPCOUNT 路径 | CAP2 HDC 矩阵发射 18832 次，位矩阵冲突为 0 | 不能写成新增独立 HDC 计算核心 |
| C5-5 | FOLD 可恢复前一拍 HDC 计数，同时维持 ECC 后续位积流水 | FOLD 读取旧 payload，下一 ECC 位积可在同一时钟沿进入 payload | `vv33_pair_pop_fire` 读取寄存 payload，`vv33_pair_fold_launch` 继续发射下一组读取 | FOLD POPCOUNT 恢复 18832 次，与矩阵事件一一对应，payload 冲突为 0 | 不能写成 HDC 与 ECC 同拍共同写入同一 payload |
| C5-6 | 一次四类别 HMATCH 只需保存窄进度及得分状态 | 四个原型，每个原型四个 256 位块，共 16 组比较 | `vv33_pair_class_idx_q`、`vv33_pair_chunk_q`、`vv33_pair_total_q`、`vv33_pair_best_q`、`vv33_pair_best_idx_q` | 每个侧路径响应严格对应 16 次矩阵发射及 16 次 POPCOUNT 恢复 | 只支持冻结实现中的四类别侧路径及固定 VRF 布局 |
| C5-7 | 交织执行保持 PMUL 与 HMATCH 的计算正确性 | 一个随机合法 K-233 标量，同一查询及四个驻留原型 | 原共享域乘路径及 HMATCH 侧路径同时启用 | 独立及混合 PMUL均通过 K-233 黄金模型，四次独立搜索均为 117 周期，请求响应计数相等，未知值及错误为 0 | 单个随机 K 是当前冻结证据，不等于多 K 完备统计；合成原型不支持数据集准确率 |
| C5-8 | 交织调度显著降低匹配工作量的完工时间 | 一次 PMUL 加 1632 次已完成四类别 HMATCH | CAP2、FOLD 侧路径，既有平方兼容窗口，必要的前台串行时隙共同推进 | 337853 降至 200144 周期，减少 137709 周期，makespan reduction 为 40.76% | 1632 是一次混合 PMUL 窗口内退休的搜索容量，不是完整推理次数 |
| C5-9 | 调度回收了大部分理论可重叠周期 | 理论下界为两套独立加速器同时开始且无系统争用时的 `max` | 不对应额外 RTL，该项是匹配工作量归一化 | 串行至理想间隙为 146909 周期，归一化重叠效率为 93.74%，交织时间比理论下界高 4.82% | 理论下界不是双加速器实测结果 |
| C5-10 | 调度没有复制第二套宽计算核心 | 一个 4-BRAM、1R1W VRF，一套位矩阵、POPCOUNT、XOR0、XOR1 及 payload | 新增状态集中在两级 VRF 返回保留及窄进度控制 | 4764 LUT，1536 FF，4 BRAM，0 DSP，WNS 0.301 ns，估算 Fmax 212.811 MHz | 不能写成零成本。相对紧邻 4652 LUT、1234 FF 入口增加 112 LUT 及 302 FF |

## 4. HMATCH 主结果的性能口径

### 4.1 原始周期

| 符号 | 含义 | 数值 | 性质 |
|---|---|---:|---|
| `C_E` | 独立 K-233 PMUL | 146908 | 实测 |
| `C_match` | 单次独立四类别 HMATCH | 117 | 实测，连续四次一致 |
| `N` | PMUL 完成边沿前已响应的完整 HMATCH 数 | 1632 | 实测容量 |
| `C_H` | 1632 次连续 HMATCH 批次 | 190944 | 严格批次实测，与 `N C_match` 一致 |
| `C_seq,calc=C_E+C_H` | 独立组件周期之和 | 337852 | 交叉检查值 |
| `C_trans` | PMUL 转入 HMATCH 批次的严格串行边界 | 1 | 实测 |
| `C_seq` | PMUL 后执行 1632 次 HMATCH 的严格串行回放 | 337853 | 实测，论文主串行基线 |
| `C_mix` | 交织执行墙钟 | 200144 | 实测 |
| `C_ideal=max(C_E,C_H)` | 独立双加速器理论计算下界 | 190944 | 理论参考，不是实测 |
| `C_E,service,mix` | 混合执行中的 PMUL 有效服务周期 | 147364 | 实测活动阶段计数 |
| `C_HDC,exclusive` | HDC 前台专属周期 | 52780 | 实测 |

严格串行回放比组件周期之和多 1 个任务转换周期。第五章的串行比较统一采用实测 `C_seq=337853`，同时给出 `C_seq,calc=337852` 及 `C_trans=1` 解释差值。第 1633 个 HMATCH 在 PMUL 完成边沿仍未完成。它不计入 `N`，但已产生的占用仍保留在 `C_mix` 中，因此当前容量计算没有删除部分工作的周期代价。

### 4.2 完工时间缩减

ISPA 在 IEEE Transactions on Computers 中使用 makespan reduction 评价两个共置任务的并发收益，其定义为 `(T1+T2-Tcolo)/(T1+T2)` [L1]。HDEC 采用相同口径：

\[
R_{\mathrm{ms}}
=\frac{C_{\mathrm{seq}}-C_{\mathrm{mix}}}{C_{\mathrm{seq}}}
=\frac{337853-200144}{337853}
=40.76\%.
\]

该指标是第五章的主性能百分比。它表示相同工作量相对于同一 HDEC 串行执行减少的总墙钟时间。

### 4.3 固定工作量加速比

\[
S_{\mathrm{fw}}
=\frac{C_{\mathrm{seq}}}{C_{\mathrm{mix}}}
=1.68805\times.
\]

加速比与完工时间缩减来自同一组周期，但数值不能互换。

### 4.4 等工作量完成率提升

若把固定工作量 `W` 的完成率写为 `Θ=W/C`，则

\[
G_{\Theta}
=\frac{\Theta_{\mathrm{mix}}-\Theta_{\mathrm{seq}}}
       {\Theta_{\mathrm{seq}}}
=\frac{C_{\mathrm{seq}}}{C_{\mathrm{mix}}}-1
=68.805\%.
\]

因此，40.76% 是完工时间缩减，1.68805 倍是固定工作量加速比，68.805% 是相同工作量的完成率提升。一次 PMUL 与一次 HMATCH 不是同质任务，不能直接把两类任务的数量相加为原始吞吐率。

### 4.5 归一化重叠效率

\[
\eta_{\mathrm{ov}}
=\frac{C_{\mathrm{seq}}-C_{\mathrm{mix}}}
       {C_{\mathrm{seq}}-C_{\mathrm{ideal}}}
=\frac{137709}{146909}
=93.74\%.
\]

当前严格串行基线包含 1 个任务转换周期，因此分母为 `min(C_E,C_H)+C_trans=146909`。该指标表示实际调度回收了串行执行至理论双加速器下界之间的周期比例。它与旧报告中的 gap closure 数学等价，正文只保留一个名称。

作为辅助指标，可报告

\[
\eta_{\mathrm{ideal}}
=\frac{C_{\mathrm{ideal}}}{C_{\mathrm{mix}}}
=95.40\%,
\]

等价地，交织完工时间比理论独立双加速器下界高 4.82%。该值不能表述为两套独立加速器的实测效率。

### 4.6 PMUL 服务开销及墙钟拉伸

混合执行中的 PMUL 活动阶段增加 456 周期：

\[
R_{E,\mathrm{service}}
=\frac{147364-146908}{146908}
=0.31\%.
\]

该值只表示排除 HDC 专属时隙后，调度对 PMUL 有效服务路径增加的周期。它不能写成“PMUL 延迟只增加 0.31%”。从请求开始到 PMUL 完成边沿的墙钟拉伸为

\[
R_{E,\mathrm{wall}}
=\frac{200144-146908}{146908}
=36.24\%.
\]

第五章报告前者时必须同时给出 `C_mix` 或墙钟拉伸，避免通过隐藏 HDC 专属时隙弱化 PMUL 延迟代价。

## 5. HMATCH 主结果的功能及结构证据

| 证据 | 数值 | 允许解释 |
|---|---:|---|
| 侧路径 HMATCH 接受及响应 | 1177、1177 | 每个请求只接受并响应一次 |
| CAP2 HDC 矩阵发射 | 18832 | 1177 次搜索乘16个查询原型块对 |
| FOLD POPCOUNT 恢复 | 18832 | 与矩阵发射一一对应 |
| 一次 PMUL 窗口内完整搜索 | 1632 | 包含侧路径、平方兼容窗口及普通前台推进 |
| 数据重叠事件 | 21811 | 仿真监视事件，不等于唯一重叠周期数 |
| 控制重叠事件 | 14560 | 仿真监视事件，不等于吞吐率 |
| 资源配对事件 | 47080 | 仿真监视事件，不直接换算为利用率 |
| VRF 读冲突 | 0 | 当前随机用例下通过 |
| 位矩阵冲突 | 0 | 当前随机用例下通过 |
| XOR0 冲突 | 0 | 当前随机用例下通过 |
| POPCOUNT 冲突 | 0 | 当前随机用例下通过 |
| payload 冲突 | 0 | 当前随机用例下通过 |
| 未知值及错误 | 0 | 当前随机用例下通过 |

`data_overlap`、`control_overlap`、`resource_pair` 是事件计数。多个事件可能发生在同一周期，因此不得把事件数除以墙钟周期后称为硬件利用率。若论文需要位矩阵或功能单元利用率，应增加逐周期唯一占用计数器。

## 6. PPA 及消融边界

| 版本 | Logic LUT | FF | WNS | 结论 |
|---|---:|---:|---:|---|
| 紧邻低面积入口 | 4652 | 1234 | 0.299 ns | 匹配调度入口 |
| 三路 256 位矩阵入口 | 5008 | 1535 | -3.649 ns | 拒绝，扩展宽数据面 |
| 二路入口，结果直接写回 | 4701 | 1536 | -0.001 ns | 拒绝，未达到 200 MHz |
| 窄得分定时切断 | 4743 | 1537 | 0.308 ns | 功能通过，缺少最终边界保护 |
| HMATCH 主结果 | 4764 | 1536 | 0.301 ns | 接受 |

主结果相对紧邻入口增加 112 LUT及302 FF。新增 FF 中约256位用于同时保留 VRF 原始返回与已寄存返回，其余用于阶段、地址及得分生命周期。该结构保持4 BRAM、0 DSP，未增加第二读口、第二套 VRF、第二套位矩阵或第二套 ECC 上下文。

不能把全局 RTL 面积压缩与调度机制混为同一贡献。论文应分别报告调度增量及最终完整实现面积。

## 7. HMATCH 工作负载语义

主实验的 HDC 对象为：

> 已编码查询的四类别最高重叠度原型关联搜索。

每次 HMATCH 对查询与四个 VRF 驻留原型进行 AND、POPCOUNT 重叠计分，并返回最高得分类别。计时前已经完成原型构建、查询编码及 VRF 预装。类0来自实际构建的合成原型，类1至类3为确定性扰动，用于功能及容量验证。

允许使用：

- HDC 分类推理中的原型关联搜索阶段。
- 已编码查询的分类决策后端。
- 四类别最高重叠度搜索。
- HMATCH 原型搜索内核。

禁止使用：

- 1632 次完整 HDC 推理。
- 原始传感器到标签的端到端推理。
- 真实数据集分类准确率。
- Hamming 距离搜索。当前实现使用 AND、POPCOUNT 最高重叠度计分。
- 全部 HDC 运算均可与 PMUL 同周期执行。

## 8. 完整驻留式推理归档，不进入主结果

完整推理探索保存以下计算链：

```text
resident binary input and role HV
    -> HPERM
    -> HBIND
    -> encoded query HV
    -> three-class HMATCH
    -> class response
```

原型训练、模型装载、输入量化、原始特征到二值超向量的映射位于计时区间之外。因此，即使归档实验包含查询编码及类别决策，也只能称为“accelerator-resident inference”，不能称为原始输入端到端应用推理。

### 8.1 归档快照身份

| 项目 | 冻结值 |
|---|---|
| `hdec_top.sv` SHA-256 | `9855de1c7ce7d9c8d558e68465337aa069e03ccbb3ef876445fbe87a37da86b8` |
| 完整推理 TB SHA-256 | `e9a4285741a552ee6b3eaf7ad9644c2cb19af13eb85dff50e482ef0e661014e1` |
| Runner SHA-256 | `a01bb2c2e9f2c9ec20cbdf72ef3bd64148dabe58244d7da1867c3080056d3325` |
| 向量清单 SHA-256 | `5bf01cbc5c19f86886ec65bc4b7ffd1959e205a92cccad903377f9ab244a7ab6` |
| XSim 日志 SHA-256 | `61a83b548b36d7f302fdc67e745a9463f90fb96f1cf62937188ac27615809ff5` |
| 合法随机 K | `0000002efc0829e4a9941d169405836394ab32bf773dc7f2c3ffc8f584f026a6` |
| 匹配 OOC | Vivado 2024.2，`xc7z020clg400-2`，5 ns |

### 8.2 归档指标

| 指标 | 归档值 | 论文定位 |
|---|---:|---|
| 独立 PMUL | 146908 周期 | 边界参考 |
| 单次 HPERM、HBIND、三类别 HMATCH | 161 周期 | 驻留式推理链 |
| 完整任务数 | 710 | 固定归档工作量 |
| 连续 HDC 批次 | 114310 周期 | 实测 |
| HDEC 串行 | 261219 周期 | 实测 |
| HDEC 交织 | 198738 周期 | 实测 |
| 完工时间缩减 | 23.92% | 归档，不作为第五章主百分比 |
| 固定工作量加速比 | 1.3144 倍 | 归档 |
| 归一化重叠效率 | 54.66% | 归档 |
| PMUL 墙钟拉伸 | 35.28% | 必须与收益同时保留 |
| Logic LUT | 4812 | 匹配归档快照 |
| FF、BRAM、DSP | 1536、4、0 | 匹配归档快照 |
| WNS、估算 Fmax | 0.208 ns、208.681 MHz | OOC，非布局布线结果 |

### 8.3 归档允许结论

允许写入内部记录：

> 在一个随机合法 K-233 标量下，HDEC以198738周期完成一次 PMUL 与710次包含 HPERM、HBIND及三类别 HMATCH 的驻留式 HDC 推理链，相对同一 HDEC 的实测串行执行缩短23.92%。

该结论不进入第五章主性能段，不与 HMATCH 的40.76%合并平均，不用4812 LUT替代 HMATCH 主快照的4764 LUT。它只说明编码阶段加入后，可利用重叠比例下降，因而形成当前方法的适用边界。

## 9. 评价指标的文献依据

### L1. Makespan reduction

H. Zhao, W. Cui, Q. Chen, and M. Guo, “ISPA: Exploiting Intra-SM Parallelism in GPUs via Fine-grained Resource Management,” IEEE Transactions on Computers, 2022。

- DOI：<https://doi.org/10.1109/TC.2022.3214088>
- ISPA Eq. (1)：`Makespan Reduction=(T1+T2-Tcolo)/(T1+T2)`。
- ISPA 将 throughput 定义为单位时间完成的任务数。

该文支持 HDEC 把 40.76% 命名为等工作量 makespan reduction。若报告吞吐提升，应使用固定工作量完成率的比值 68.805%，不能把 40.76% 改称吞吐提升。

### L2. STP 及 ANTT

S. Eyerman and L. Eeckhout, “System-Level Performance Metrics for Multiprogram Workloads,” IEEE Micro, vol. 28, no. 3, pp. 42–53, 2008。

- DOI：<https://doi.org/10.1109/MM.2008.44>
- 作者版本：<https://users.elis.ugent.be/~leeckhou/papers/micro08.pdf>

标准系统吞吐率与平均归一化周转时间可写为

\[
\mathrm{STP}=\sum_i\frac{C_i^{\mathrm{solo}}}{C_i^{\mathrm{co}}},
\qquad
\mathrm{ANTT}=\frac{1}{M}\sum_i\frac{C_i^{\mathrm{co}}}{C_i^{\mathrm{solo}}}.
\]

当前 HMATCH 容量实验冻结了混合总完工时间及 PMUL 完成前退休的搜索数量，没有分别冻结 PMUL 与整个 HMATCH 批次的共享执行周转时间。因此，当前报告不把固定工作量加速比改称 STP，也不计算 ANTT。即使在某些简化假设下二者数值可能相同，也不能省略每项任务的完成时刻证据。

### L3. 多任务加速器调度的吞吐及延迟边界

Y. Choi and M. Rhu, “PREMA: A Predictive Multi-task Scheduling Algorithm for Preemptible Neural Processing Units,” HPCA 2020。

- DOI：<https://doi.org/10.1109/HPCA47549.2020.00027>
- 作者预印本：<https://arxiv.org/abs/1909.04548>

PREMA同时报告系统吞吐及归一化周转时间，说明多任务调度不能只给出总吞吐而省略被共享任务的延迟代价。HDEC据此同时保留 PMUL 有效服务开销、混合墙钟及理论下界边界。

## 10. 论文段落及图表证据责任

### 第五章开头

说明共享计算结构减少空间重复，但整段任务所有权仍会留下可利用的时间空隙。依据固定 PMUL 状态、VRF 返回及 payload 生命周期，引出设计阶段可确定的兼容关系。不开列局部信号，不把调度写成独立于统一表示及共享架构之外的新论文级贡献。

### 方法段

按以下因果链组织：

1. 单端口无法同拍读取查询及原型。
2. 相邻请求在后续周期形成两个同时可用的返回级。
3. CAP2允许查询与原型进入既有位矩阵及POPCOUNT。
4. FOLD从旧 payload 恢复 HDC 计数，同时保持 ECC 下一位积的数据流。
5. 窄进度状态跨多个 PMUL 微阶段累计类别得分。

### 结果段

主结果按以下顺序报告：

1. 独立 PMUL、连续 HMATCH 批次、严格串行回放、完成搜索数及混合墙钟。
2. 40.76% makespan reduction。
3. 1.68805 倍固定工作量加速比。
4. 93.74%归一化重叠效率。
5. PMUL有效服务开销0.31%及墙钟拉伸36.24%。
6. 4764 LUT、1536 FF、4 BRAM、0 DSP及WNS 0.301 ns。
7. 18832次CAP2矩阵发射、18832次FOLD恢复、五类资源冲突均为0。

### 推荐图表

- 双时间轴图：标出VRF连续读取、CAP2矩阵发射、FOLD计数恢复及ECC下一位积推进。
- 资源生命周期表：VRF读、位矩阵、POPCOUNT、payload、XOR0在各微阶段的占用及兼容性。
- 等工作量对比表：串行、交织、理论独立双加速器下界。
- PPA消融表：低面积入口、拒绝的宽数据面候选、最终HMATCH版本。

## 11. 主张禁区

- 不得把 HMATCH 主实验写成完整 HDC 推理。
- 不得把 1632 写成完整推理次数。
- 不得把理论独立双加速器下界写成实测系统数据。
- 不得把0.31%有效服务开销写成PMUL墙钟延迟增量。
- 不得把40.76% makespan reduction写成40.76%吞吐提升。
- 不得同时把gap closure及overlap efficiency作为两个独立指标。
- 不得把事件数量直接换算为功能单元利用率。
- 不得声称使用2R1W VRF、第二套位矩阵或第二套完整任务上下文。
- 不得把AND、POPCOUNT、XOR0、XOR1等局部单元拆成第五章的并列创新。
- 不得用当前合成向量实验支持真实数据集准确率、端到端应用延迟、功耗或布局布线后频率。

## 12. 证据文件索引

### HMATCH 主结果

- 方法及结果报告：`reports/hdec/VV33_HMATCH_PMUL_INTERLEAVING_20260802.md`
- 运行清单：`tmp/hdec_logs/vv33/bank_episode_interleave_20260802_224044_578/run_manifest.json`
- XSim 日志：`tmp/hdec_logs/vv33/bank_episode_interleave_20260802_224044_578/xsim_bank_episode_interleave/xsim.log`
- Runner 日志：`tmp/hdec_logs/vv33/bank_episode_interleave_20260802_224044_578/bank_episode_interleave.runner.log`
- 测试平台：`verif/hdec/vv33/integration/tb_vv33_bank_episode_interleave.sv`
- OOC 摘要：`reports/hdec/vv33_hmatch_final_ooc_20260802/reports/run_summary.txt`
- OOC 资源：`reports/hdec/vv33_hmatch_final_ooc_20260802/reports/utilization.rpt`
- OOC 时序：`reports/hdec/vv33_hmatch_final_ooc_20260802/reports/timing_summary_top50.rpt`

### 完整驻留式推理归档

- 归档报告：`reports/hdec/VV33_FULL_INFERENCE_INTERLEAVING_20260802.md`
- 运行清单：`tmp/hdec_logs/vv33/fused_hperm_square_full_20260802b/run_manifest.json`
- XSim 日志：`tmp/hdec_logs/vv33/fused_hperm_square_full_20260802b/xsim_full_inference_interleave/xsim.log`
- 测试平台：`verif/hdec/vv33/integration/tb_vv33_full_inference_interleave.sv`
- 匹配 OOC 摘要：`reports/hdec/vv33_full_inference_archive_ooc_20260802/reports/run_summary.txt`
- 匹配 OOC 资源：`reports/hdec/vv33_full_inference_archive_ooc_20260802/reports/utilization.rpt`
- 匹配 OOC 时序：`reports/hdec/vv33_full_inference_archive_ooc_20260802/reports/timing_summary_top50.rpt`

## 13. 发布前检查

在第五章使用本证据图前，应完成以下检查：

1. HMATCH 主 RTL 已由提交 `0f255e43` 保存，TB、Runner 及报告在推送前应形成独立证据提交。
2. 远程分支中的主 RTL、TB 及 Runner 哈希与第2节完全一致。
3. 完整推理归档提交可从远程独立恢复，且第8节内容哈希一致。
4. 正式论文表格只绑定同一RTL快照的功能、周期及PPA数据。
5. 若重新运行产生不同K，报告新的种子、向量哈希、日志哈希及结果，不覆盖本次冻结记录。
6. 若补充STP、ANTT或功能单元利用率，先增加对应的逐任务完成时刻及逐周期唯一占用证据。
