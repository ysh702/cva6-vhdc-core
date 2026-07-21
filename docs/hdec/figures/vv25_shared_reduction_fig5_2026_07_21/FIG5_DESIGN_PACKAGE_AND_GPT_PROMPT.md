# Fig. 5 设计包：VV25 共享槽感知规约架构与 GPT 绘图提示词

> 日期：2026-07-21
>
> RTL 基线：`VV25 @ b3dede99bfc92fb243f82906d8d8bb5a3f2fea77`
>
> 建议图名：**Shared Slot-Aware Bit-Matrix Reduction Architecture**
>
> 备选图名：**Shared POPCOUNT Fabric With Native XOR1 Diagonal Reconstruction**

## 0. 最快使用方法

给 GPT 上传本目录中的前四张“必选参考图”，第五、第六张仅在需要强化层级或数据流风格时上传：

1. `reference_images/01_current_fig3_style_and_handoff.png`
2. `reference_images/02_dual_micro2020_fig8_global_composition.png`
3. `reference_images/03_eggimann_tcas2021_fig4_repeated_reduction.png`
4. `reference_images/04_date2007_fig2_data_strips_xor_registers.png`
5. 可选：`reference_images/05_datta_jetcas2019_fig4_unit_hierarchy.png`
6. 可选：`reference_images/06_user_reference_dataflow_units.png`

上传后，将本文最后的“主提示词”整段复制给 GPT。参考图只用于学习视觉语法，**不得拼贴或复刻论文原图**。

---

## 1. Fig. 5 必须让读者一眼读出的结论

**同一份已寄存的 `Q∈{0,1}^{8×32}` 只经过一套 32 个 8-bit POPCOUNT 单元（PC8）；HDC 读取完整计数，ECC 复用计数树的奇偶摘要，并仅调用现有 XOR1 阵列中的 14 个节点闭合被分槽的长斜线。**

这不是“两条算术通道”，而是：

- 一份物理数据 `Q`；
- 一套共享 PC8 规约硬件；
- 两种结果解释：HDC 使用整数计数，ECC 使用 GF(2) 奇偶；
- ECC 只有一个很小的跨槽闭合动作，而不是第二套 ECC 专用规约树。

旧表述 **“AND+POPCOUNT / AND+XOR 双通道执行”** 会误导读者认为存在两条并行硬件通道，应弃用。

---

## 2. Fig. 3、Fig. 4、Fig. 5、Fig. 6 的严格边界

| 图 | 回答的问题 | 起点 | 终点 | 本图禁止越界的内容 |
|---|---|---|---|---|
| Fig. 3 | HDC 与 ECC 如何被转换成同一种 `8×32` 位矩阵计算？ | HDC/ECC 原生索引 | Pointwise AND 后的 `Q` | 不展开 PC8、XOR1、对角线闭合与 PMUL 调度 |
| Fig. 4 | HDEC 在 CVA6 系统中位于哪里、如何被调用？ | CVA6/CVXIF/存储系统 | HDEC 宏模块接口 | 不展开 32 个 PC8、斜线分槽和 XOR1 内部 |
| **Fig. 5** | 同一规约核心如何同时承载 HDC 计数与 ECC 对角线奇偶？ | **Fig. 3 输出的已寄存 `Q`** | **HDC 行计数；ECC 的 `d[30:0]`** | 不画 CVA6、指令译码、VRF；不画 Karatsuba、模约简、XOR0、跨周期 PMUL 调度 |
| Fig. 6 | `d[30:0]` 如何进入流式 ECC 后端并完成完整点乘数据流？ | Fig. 5 的 16×16 子积对角线结果 | GF(2^233) 字段结果/调度状态 | 不重复 Fig. 3 的矩阵构造，不重复 Fig. 5 的 PC8 单元细节 |

### Fig. 5 的画面边界

- 左边界：`Registered Q (8×32)`，用一个寄存器框承接 Fig. 3。
- 右上边界：`HDC row counts`，可用小箭头标注“to group-distance accumulation”，不要展开完整 HDC 分类器。
- 右下边界：`ECC d[30:0]`，用小箭头标注“to streamed ECC backend (Fig. 6)”。
- 画内可以出现 `diag_mode` 的一根细虚线控制线，但不能扩展成控制器或状态机。

---

## 3. VV25 中必须遵守的硬件事实

验证文件：`core/hdec/rtl/hdec_lane_4x64.sv`；HDC 汇总位置：`core/hdec/rtl/hdec_top.sv`。

### 3.1 共享规约阵列

- `Q` 的尺寸为 `8×32 = 256 bit`。
- 它被固定划分成 `8 rows × 4 slots/row = 32 slots`，每槽 8 bit。
- 32 个槽与 32 个 PC8 一一对齐；所有 256 个 `Q` 位恰好进入一次同一套计数阵列。
- PC8 输出 4-bit 槽计数；每行的 4 个槽进一步形成一个 6-bit 行计数。
- HDC 顶层把 8 个行计数汇总为 9-bit group distance；Fig. 5 只需画到行计数或用一个小型汇总符号带过。
- 32 个 PC8 中：
  - 24 个采用平衡的 8-bit 计数树；
  - 8 个固定槽采用 `short_count + tail_count` 的分段计数，但二者仍共同产生正常的 8-bit 完整计数；
  - 因此不存在 ECC 专用 counter，也不存在第二套 32-bit POPCOUNT。

### 3.2 对角线分槽规则

定义：

- `D_k`：16×16 GF(2) 子乘积的第 `k` 条对角线，`k=0…30`；
- `H_k = D_k[0:7]`：长斜线按项序排列后的前 8 项；
- `T_k = D_k[8:]`：同一长斜线的剩余尾段；
- `S_r = D_r` 或其右侧镜像短斜线，长度均为 `r+1`。

不要只写“高位/低位”，因为图的左右方向可能改变含义；应写清 `D_k[0:7]` 与 `D_k[8:]`，再用 head/tail 作为简称。

对于 `r=0…6`，每行四个 8-bit 固定槽为：

| 槽 | 内容 |
|---|---|
| Slot 0 | `H_(14-r)` |
| Slot 1 | `D_r (r+1 bits) | T_(14-r) (7-r bits)` |
| Slot 2 | `H_(16+r)` |
| Slot 3 | `D_(30-r) (r+1 bits) | T_(16+r) (7-r bits)` |

最后一行 `r=7` 是直接行：

- Slot 0 = `D7`（8 项）；
- Slot 1 = `D23`（8 项）；
- Slot 2 = `D15[0:7]`；
- Slot 3 = `D15[8:15]`。

全图不应画完 8 行的所有位连线。推荐只展开三种代表性数据条：

1. `r=2`：`3-bit short + 5-bit tail`，代表“pair parity XOR short parity”闭合方式；
2. `r=4`：`5-bit short + 3-bit tail`，代表“head parity XOR tail parity”闭合方式；
3. `r=7`：`D7 / D23 / D15 head / D15 tail`，代表直接输出的特殊行。

右半组与左半组镜像，只需用对称括号或省略号说明，不要再画一套相同硬件。

### 3.3 POPCOUNT 与 XOR1 如何共同完成 ECC 对角线

PC8 不仅提供完整计数，也从已有计数树节点暴露奇偶摘要：

- 32 个 byte parity；
- 16 个 byte-pair parity；
- 14 个 short parity；
- 8 个 tail parity。

ECC 的 31 个输出位不是全部重算：

- **17 个直接对角线**：`D0…D7`、`D15`、`D23…D30`，由 PC8 的固定奇偶抽头直接汇集；
- **14 个重构对角线**：`D8…D14`、`D16…D22`，由现有 XOR1 阵列中的 14 个节点闭合。

14 个 XOR1 节点分为两类方程：

1. 对 `r∈{0,1,2,3,5}` 的左右两侧，共 10 个节点：

   `π_pair = π_H ⊕ π_S ⊕ π_T`

   `π_long = π_pair ⊕ π_S = π_H ⊕ π_T`

2. 对 `r∈{4,6}` 的左右两侧，共 4 个节点：

   `π_long = π_H ⊕ π_T`

因此，最准确的图形语言是：

> **PC8 完成槽内规约并给出奇偶抽头；XOR1 只完成跨槽长斜线的闭合。**

### 3.4 XOR1 复用事实

- RTL 中的 native XOR1 bank 有 224 个节点。
- 对角线模式只把固定的 14 组操作数映射到其中 14 个节点。
- 其他节点仍保留其既有用途；不能把整个 224-node bank 画成 ECC 私有或全部空闲。
- 推荐画法：长条形 `Native XOR1 bank (224 nodes)`，其中仅 14 个小单元用紫色高亮，其他单元用浅灰表达“existing functions”。
- 输入是固定 tap map 加模式选择，不是动态 crossbar，也不存在寄存后转置网络。

---

## 4. 推荐的总体结构

Fig. 5 应借鉴 Fig. 3 的“编号阶段 + 连续左到右主脊柱”，但内容从表示转换升级为硬件结构。

```text
0 Registered Q       1 Fixed slot view          2 Shared reduction fabric       3 Parity closure                 4 Semantic outputs

 Q register ───────► 8 rows × 4 slots ───────► 32 × PC8 aligned array ───────┬─► full counts ───────────────► HDC row counts
   8×32               data-shape ribbon          one PC8 enlarged              │
                      H / short / tail strips     count + parity taps           └─► fixed tap gather ─┬─────► 17 direct diagonals ─┐
                                                                                                      └─► 14 XOR1 nodes ──────┴─► ECC d[30:0]
```

### 4.1 五个阶段的画法

#### Stage 0 — Registered Q

- 缩小复用 Fig. 3 最右侧 `Q` 的点阵样式，外加双线寄存器边框。
- 标注 `From Fig. 3` 和 `Q∈{0,1}^{8×32}`。
- 不再重复 Native index、Index normalization、Replicate and align、Pointwise AND。

#### Stage 1 — Fixed slot view

- 把完整矩阵简化为 8 行、每行 4 个 8-cell 数据条。
- 在主体中保留三条代表行：`r=2`、`r=4`、`r=7`；其余行用省略号。
- 每个 slot 必须画成真实的 8 个小格，不能只用一根普通箭头代替数据。
- 用橙色实填表示 short fragment；用橙色斜线纹理表示 tail fragment；head/full slot 保持共享紫/灰色。
- 数据条旁只放简短标签，例如 `S:3 | T:5`、`S:5 | T:3`、`D15[0:7] | D15[8:15]`。

#### Stage 2 — Shared reduction fabric

- 画一个与 32 个槽对齐的 `8×4 PC8 array`，每个 PC8 用相同小矩形表示。
- 在阵列旁用虚线 zoom guide 放大一个 PC8：
  - 8 个输入位；
  - 4 个 pair sums；
  - 2 个 quad sums；
  - 1 个 4-bit count；
  - 在树的 LSB/中间节点放小实心圆表示 parity taps。
- 在放大图内用一个很小的 inset 表示固定 split-tap 变体：`short_count + tail_count = full count`。
- 必须把大标题写成 `Shared PC8 fabric (32×)`，不写 `HDC POPCOUNT`，避免把共享硬件误判为 HDC 私有。

#### Stage 3 — Fixed tap map and XOR1 closure

- 上方是一条 `Full-count path`，直接走向 HDC。
- 下方是 `Parity-tap path`，先进入固定汇集布线。
- 用两组明确数字块展示：`17 direct` 与 `14 reconstructed`。
- `14 reconstructed` 连接到 `Native XOR1 bank (224 nodes)` 中高亮的 14 个节点。
- 在旁边只放一个代表方程：`π_long = π_pair ⊕ π_short`；另一个小标签写 `or π_head ⊕ π_tail`。
- 布线使用正交总线与固定扇出，不画交叉密集的蜘蛛网。

#### Stage 4 — Semantic outputs

- HDC 端使用深灰/黑色：`8 row counts → group distance`。
- ECC 端使用蓝色：`17 direct + 14 reconstructed → d[30:0]`。
- 两个输出是在共享硬件之后的“语义分支”，不能画成从 Q 开始的两条平行流水线。

---

## 5. 颜色、线条与版式规范

### 5.1 推荐颜色：与当前 Fig. 3 连续

| 语义 | 填充 | 描边/文字 | 用法 |
|---|---|---|---|
| 共享矩阵、PC8 主体 | `#F1EFF7` | `#655F8C` | 延续 Fig. 3 的 shared/fixed-pack 紫色 |
| ECC 语义输出 | `#EAF1F5` | `#3F708E` | 延续 Fig. 3 的 ECC 蓝色 |
| 斜线 short/tail 片段 | `#F6DFCB` | `#D47E2F` | 全图最醒目的机制色；tail 再叠加 `/` 斜线纹理 |
| XOR1 被复用的 14 节点 | `#EEE7F5` | `#8064A2` | 与共享硬件同色族，但用更深紫强调“既有 XOR 资源” |
| HDC 输出 | `#F2F3F4` | `#2E3133` | 与 Fig. 3 的 HDC 黑/灰语言一致，不另造绿色通道 |
| 寄存器、非核心背景 | `#F2F2F2` | `#55585C` | 降低视觉竞争 |
| XOR1 其余既有节点 | `#E3E4E6` | `#9A9DA1` | 表示 bank 背景，不表示“全部空闲” |
| 主数据总线 | 无 | `#303236` | 所有共享数据主路径 |

颜色优先级应为：**橙色数据片段 → 紫色 PC8/XOR1 共享硬件 → 蓝色 ECC 输出与黑色 HDC 输出 → 灰色辅助元素**。

不要使用渐变、投影、发光、3D、彩虹色或大面积高饱和底色。黑白打印时仍应依靠实填/斜线纹理、线型和标签区分，而不是只靠颜色。

### 5.2 线条

| 类型 | 建议样式 |
|---|---|
| 主数据总线 | 实线，1.1–1.3 pt，箭头只放在阶段边界 |
| 单元内部连线 | 实线，0.7–0.8 pt |
| 控制线 `diag_mode` | 虚线，0.7 pt，灰色或蓝灰色 |
| zoom guide | 点线，0.6–0.7 pt |
| 固定映射 bundle | 正交线束，避免自由曲线与大量交叉 |
| 寄存器 | 双竖线或双边框 |
| parity tap | 小实心圆；必须连在真实树节点上 |

### 5.3 尺寸与字体

- 单栏不够，应按 IEEE 双栏通栏设计：宽约 `178–182 mm`，高约 `85–100 mm`。
- 白底、无内部大标题；长 caption 放在论文正文中。
- 字体优先 Helvetica/Arial；印刷尺寸下正文标签 7–8 pt，阶段标题 8.5–9 pt。
- 变量使用数学斜体，模块名/阶段名使用无衬线粗体。
- 所有 bus 宽度与数量必须标出来：`8×32`、`32×8-bit slots`、`32×PC8`、`17`、`14/224`、`d[30:0]`。
- 留足白空间。Fig. 5 的核心不是“把所有 RTL 线都画出来”，而是让读者追踪一条具体长斜线如何跨槽、如何由 PC8 tap 与 XOR1 闭合。

---

## 6. 参考图：上传哪些、分别学习什么

### 必选 1：当前 Fig. 3——学习整套论文的视觉连续性与接口交接

![Current Fig. 3](reference_images/01_current_fig3_style_and_handoff.png)

学习：

- 顶部 0–4 编号阶段；
- 连续左到右阅读顺序；
- 细竖向虚线分阶段；
- 点阵表示真实 bit-level 数据；
- HDC 黑灰、ECC 蓝、共享结构紫的语义体系；
- Fig. 5 左端直接承接 `Q`，使两图可以连续阅读。

不要复制：

- Fig. 3 的输入索引、归一化、复制对齐和 AND 过程；
- 上下两条 HDC/ECC 表示路径。Fig. 5 必须在共享硬件之后才分成两种结果语义。

### 必选 2：DUAL, MICRO 2020, Fig. 8——学习“全局构图母版”

论文：[DUAL: Acceleration of Clustering Algorithms using Digital-based Processing In-Memory](https://doi.org/10.1109/MICRO50266.2020.00039)

![DUAL MICRO 2020 Fig. 8](reference_images/02_dual_micro2020_fig8_global_composition.png)

学习：

- 一张通栏图里同时呈现 macro array、流水级、功能块和局部 callout；
- 主硬件阵列居中，输入/控制靠边，结果路径在右侧收束；
- 重复单元用规则阵列而不是画 32 份细节；
- 重点数据通路与非重点背景有明显视觉层级。

不要复制：

- PIM/crossbar/cluster 的具体拓扑；
- 论文原有字母分区、配色和模块名称；
- 将多个独立计算核照搬到 HDEC。

### 必选 3：Eggimann et al., TCAS-I 2021, Fig. 4——学习“重复阵列 + 共享规约树”

论文：[A 5 μW Standard Cell Memory-Based Configurable Hyperdimensional Computing Accelerator for Always-on Smart Sensing](https://doi.org/10.1109/TCSI.2021.3100266)

![Eggimann TCAS-I 2021 Fig. 4](reference_images/03_eggimann_tcas2021_fig4_repeated_reduction.png)

学习：

- 大量相同 bit cells 先规则排布，再汇入一套共享 popcount/adder tree；
- 用括号、省略号和“×N”表达规模，不展开全部连线；
- 规约树放在阵列旁边，读者自然看到“多数据、共享硬件”的关系；
- 结构图保持黑白也能读懂。

不要复制：

- SCM、associative search、minimum search 和 memory address 机制；
- 把 Fig. 5 画成存内搜索架构；
- 直接照搬其树规模或存储行组织。

### 必选 4：Peter and Langendörfer, DATE 2007, Fig. 2——学习“真实数据条穿过 XOR/寄存器”

论文：[An Efficient Polynomial Multiplier in GF(2^m) and Its Application to ECC Designs](https://doi.org/10.1109/DATE.2007.364469)

![DATE 2007 Fig. 2](reference_images/04_date2007_fig2_data_strips_xor_registers.png)

学习：

- 用具有实际长度和分段的矩形数据条，而不是抽象单线，说明部分结果如何经过 XOR 和寄存器；
- 数据条、运算单元、寄存器三种图形语法明确不同；
- 数据状态变化紧贴硬件块出现，算法和电路不是两个分离的小图；
- 适合借来表达 `H | S | T` 的 8-cell slot 以及跨槽闭合。

不要复制：

- IKM/Karatsuba 命令字、`c0…c7` 原拓扑、可变移位器或模多项式反馈；
- 任何暗示 Fig. 5 已经进入完整 ECC 模约简的结构；这些属于 Fig. 6。

### 可选 5：Datta et al., JETCAS 2019, Fig. 4——学习“unit → array → enlarged unit”的层级放大

论文：[A Programmable Hyper-Dimensional Processor Architecture for Human-Centric IoT](https://doi.org/10.1109/JETCAS.2019.2935464)

![Datta JETCAS 2019 Fig. 4](reference_images/05_datta_jetcas2019_fig4_unit_hierarchy.png)

学习：

- 先定义单个 unit，再展示 unit layer/array，最后嵌入数据依赖与 accumulator；
- 用 zoom callout 解释一个代表单元，避免把全部 32 个 PC8 展开；
- 单元图标、重复阵列与数据依赖共处一张结构图。

不要复制：

- HLU、3-gram、permute、delay 或 feedback network；
- 将 PC8 画成可编程 HDC 编码器。

### 可选 6：用户提供的数据流 + unit 示例——仅学习意图，不作为拓扑母版

![User dataflow-unit reference](reference_images/06_user_reference_dataflow_units.png)

可以学习：

- 左到右数据方向；
- 重复 unit 和流水级的表达；
- 数据、硬件单元和阶段编号在一张图中并存。

必须改进：

- 不要照搬 multiplier/shift/adder；
- 不要使用大量交叉箭头；
- 不要只画普通线，必须把斜线片段画成具体的 8-cell slot；
- 不要把 HDC 与 ECC 画成两套独立执行单元。

---

## 7. 最终应向 GPT 提供的素材清单

### 必须提供

- 当前 Fig. 3 PNG；
- DUAL MICRO 2020 Fig. 8 crop；
- Eggimann TCAS-I 2021 Fig. 4 crop；
- DATE 2007 Fig. 2 crop；
- 本文第 3 节的 VV25 事实；
- 本文第 2 节的图边界；
- 本文第 5 节的颜色和线型。

### 有空间时再提供

- Datta JETCAS 2019 Fig. 4 crop，用于强化 hierarchical zoom；
- 用户示例图，用于说明“数据流 + unit”的原始意图。

### 不要提供给 GPT 的内容

- 整个 RTL 文件；
- Fig. 4 的 CVA6 系统图；
- Fig. 6 的 ECC 调度草图；
- 过多综合报告或控制状态名。

这些内容会诱导模型把 Fig. 5 画成系统总图或信号级 netlist。

---

## 8. 可直接复制给 GPT 的主提示词

```text
Create a publication-grade, editable vector-style hardware architecture figure for an IEEE TCAS-I paper. The figure is Fig. 5 of an HDC+ECC co-designed accelerator. Use a clean white background, a single full-width horizontal composition (about 180 mm wide and 90–100 mm high), precise orthogonal routing, no gradients, no shadows, no 3-D effects, and no decorative illustration. The figure must remain readable in grayscale.

REFERENCE-IMAGE ROLES — learn the visual grammar, but never copy exact topology, labels, or colors:
1) Current Fig. 3: preserve its numbered 0–4 stage headers, left-to-right reading order, thin dotted stage separators, bit-matrix visual language, and the charcoal / steel-blue / muted-purple family. Fig. 5 must visually continue from its final Q matrix.
2) DUAL MICRO 2020 Fig. 8: learn global macro-array composition, pipeline grouping, restrained callouts, and visual hierarchy.
3) Eggimann TCAS-I 2021 Fig. 4: learn repeated-cell arrays feeding one shared reduction tree; use brackets, ellipses, and ×N instead of drawing every connection.
4) DATE 2007 Fig. 2: learn how concrete segmented data bars move through XOR/register hardware; use real 8-cell strips, not generic single-line arrows.
5) Optional Datta JETCAS 2019 Fig. 4: learn unit → repeated array → one enlarged unit hierarchy.
6) The user dataflow-unit example is only an intent reference; do not copy its multiplier, shift, adder, or crossed-arrow topology.

SCIENTIFIC CLAIM TO COMMUNICATE:
One registered Q∈{0,1}^{8×32} is evaluated exactly once by one shared array of thirty-two 8-bit POPCOUNT units (PC8). HDC consumes the full counts. ECC reuses parity taps already available in those same PC8 trees and uses only fourteen nodes in the existing native XOR1 bank to close long diagonals split across fixed slots. This is one physical reduction fabric with two semantic interpretations, not two parallel HDC and ECC datapaths.

STRICT FIGURE BOUNDARY:
- Start at “Registered Q (8×32) — from Fig. 3”.
- End at “HDC row counts” and “ECC d[30:0] — to streamed ECC backend (Fig. 6)”.
- Do not show CVA6, CV-X-IF, instruction decode, VRF, index normalization, replication, pointwise AND, Karatsuba scheduling, modular reduction, polynomial folding, XOR0, a 466-bit product buffer, or a PMUL controller.

COMPOSITION — use one dominant left-to-right spine with five numbered stages:
0. Registered Q
1. Fixed 8-bit slot view
2. Shared PC8 fabric
3. Fixed parity-tap map and native XOR1 closure
4. HDC / ECC semantic outputs

STAGE 0 — REGISTERED Q:
Draw a compact 8×32 bit matrix matching the style of the supplied Fig. 3, enclosed by a register/double-line boundary. Label it exactly “Registered Q (8×32)” and “from Fig. 3”. Do not redraw earlier Fig. 3 stages.

STAGE 1 — CONCRETE SLOT AND DIAGONAL SHAPES:
Show that Q is physically organized as 8 rows × 4 fixed slots per row, each slot exactly 8 bits. Draw every illustrated slot as eight visible square cells. Do not use a generic arrow as a substitute for data. Use three representative rows and ellipses for the rest:
- r=2: show a mixed slot “S:3 | T:5”; it represents a 3-bit short diagonal followed by the 5-bit tail of a long diagonal.
- r=4: show a mixed slot “S:5 | T:3”; it represents a 5-bit short diagonal followed by a 3-bit tail.
- r=7: show four direct slots “D7”, “D23”, “D15[0:7]”, “D15[8:15]”.
Define long-diagonal fragments by term order, not ambiguous high/low words: H_k = D_k[0:7], T_k = D_k[8:]. Show one small bracket indicating that the right half is a mirrored fixed rule, not a second hardware path.

STAGE 2 — SHARED HARDWARE ARRAY:
Place a regular 8×4 array labelled exactly “Shared PC8 fabric (32×)”, aligned one-to-one with the 32 input slots. The physical array is visually dominant. Show 24 units as balanced PC8 and mark only 8 fixed positions with a subtle split-tap corner marker; do not draw an ECC-only counter. Add one enlarged PC8 callout connected by dotted zoom guides. Inside the enlarged PC8 show: 8 input bits → 4 pair sums → 2 quad sums → one 4-bit full count. Place small solid tap dots on real LSB/intermediate nodes and label them “parity taps”. Add a tiny fixed variant inset stating “short_count + tail_count = full count”. The enlarged unit must make it obvious that count and parity are products of the same tree.

STAGE 3 — TWO READOUTS FROM THE SAME FABRIC:
From the shared PC8 fabric, make two short readouts only after the common array:
A) a full-count bus toward HDC;
B) a parity-tap bus toward ECC.
The ECC bus enters a compact “Fixed tap map”, then separates into “17 direct diagonals” and “14 reconstructed diagonals”. Draw a long thin block labelled exactly “Native XOR1 bank (224 nodes)”. Highlight exactly 14 small nodes in muted purple and keep the other bank cells light gray, labelled “existing XOR1 functions”; do not imply the whole bank is idle or ECC-private. Connect the 14 reconstructed path to only those 14 highlighted nodes. The routing is compile-time fixed with a small dashed “diag_mode” control line; do not draw a crossbar or post-AND transpose.

Include one concise equation callout near the highlighted nodes:
π_long = π_pair ⊕ π_short = π_head ⊕ π_tail
Optionally annotate below it: “PC8: within-slot reduction; XOR1: cross-slot closure”.

STAGE 4 — OUTPUTS:
Upper output in charcoal: “HDC: 8 row counts → group distance”.
Lower output in steel blue: “ECC: 17 direct + 14 reconstructed → d[30:0]”.
Add a small outgoing arrow “to streamed ECC backend (Fig. 6)”. The two outputs are semantic branches after one common fabric; never draw two complete pipelines from Q.

COLOR PALETTE:
- shared Q and PC8 hardware: fill #F1EFF7, border #655F8C;
- ECC semantics: fill #EAF1F5, border/text #3F708E;
- short/tail diagonal fragments: fill #F6DFCB, border #D47E2F; use solid orange for short and orange diagonal hatching for tail so grayscale still works;
- the 14 reused XOR1 nodes: fill #EEE7F5, border #8064A2;
- HDC semantics: fill #F2F3F4, border/text #2E3133;
- registers and secondary structures: fill #F2F2F2, border #55585C;
- other XOR1 bank cells: fill #E3E4E6, border #9A9DA1;
- primary data buses: #303236.
Do not introduce green, red, rainbow palettes, gradients, shadows, or saturated panel backgrounds.

LINE AND TYPE RULES:
- main data bus: solid 1.1–1.3 pt;
- internal wires: solid 0.7–0.8 pt;
- diag_mode control: dashed 0.7 pt;
- zoom guides: dotted 0.6–0.7 pt;
- use orthogonal bundled routing, minimal crossings, and arrows only at stage boundaries;
- Helvetica/Arial-like sans serif; 7–8 pt labels at final print size; 8.5–9 pt stage headers;
- italic mathematical variables and bold module/stage names;
- explicitly label 8×32, 32×8-bit slots, 32×PC8, 17, 14/224, and d[30:0].

HARD NEGATIVES:
No second ECC AND array, no second POPCOUNT tree, no ECC-only counter, no raw Q directly feeding a separate XOR tree, no dynamic crossbar, no transpose network, no duplicated left/right hardware, no CVA6 integration diagram, no instruction pipeline, no memory hierarchy, no Karatsuba/fold/XOR0/modular-reduction backend, no scheduling FSM, no photorealism, no isometric blocks, no icons, no dense netlist spaghetti, and no copied topology from the reference papers.

OUTPUT REQUIREMENTS:
Produce an editable SVG or equivalent vector figure first, with all text exactly spelled and selectable. Also export a 300-dpi PNG preview on white background. Do not place a long title or caption inside the artwork. Keep enough white space for an external IEEE caption. Before finalizing, verify the counts and labels: 8×32 bits, 32 slots, 32 PC8, 24 balanced + 8 fixed split-tap positions, 17 direct diagonals, 14 reconstructed diagonals, 14 highlighted nodes within a 224-node native XOR1 bank, and final ECC d[30:0].
```

---

## 9. 建议 caption 初稿

**Fig. 5. Shared slot-aware reduction architecture.** The registered `8×32` pointwise products are partitioned into 32 fixed 8-bit slots and evaluated once by a shared PC8 fabric. HDC consumes the complete slot and row counts, whereas ECC reuses parity taps of the same counting trees: 17 diagonal bits are gathered directly and 14 split long diagonals are closed by selected nodes in the native XOR1 bank.

中文含义：已寄存的 `8×32` 点积结果被分成 32 个固定 8-bit 槽，并由同一套 PC8 阵列完成规约。HDC 使用完整槽/行计数；ECC 复用这些计数树的奇偶抽头，其中 17 条对角线直接汇集，另 14 条跨槽长对角线由现有 XOR1 节点闭合。

---

## 10. 收图后的人工核对清单

- [ ] 是“一套共享硬件、两个结果解释”，而不是两条并行通道。
- [ ] Fig. 5 左端只承接 Fig. 3 的 `Q`，没有重复 Fig. 3。
- [ ] Fig. 5 右端停在 `d[30:0]`，没有侵入 Fig. 6。
- [ ] 32 个 8-bit 槽与 32 个 PC8 一一对齐。
- [ ] 数据不是普通线，而是可数的 8-cell strip。
- [ ] 代表性地画出 `3+5`、`5+3` 与 `D15` 两半。
- [ ] PC8 放大图同时表现 full count 与 parity taps。
- [ ] 17 direct 与 14 reconstructed 分开标明。
- [ ] XOR1 bank 标为 224 nodes，只有 14 个节点高亮。
- [ ] 没有把其余 210 个节点错误标成全部空闲。
- [ ] 没有 ECC 私有 counter、第二棵 XOR tree、crossbar 或 transpose。
- [ ] HDC 为黑灰、ECC 为蓝、共享为紫、机制强调为橙，且黑白打印可区分。
- [ ] 字号、线宽、bus 宽度和数学符号在双栏通栏尺寸下可读。
- [ ] 最终交付包含可编辑 SVG/PDF；PNG 只作为预览，不把 AI 生成的错误文字直接用于论文。
