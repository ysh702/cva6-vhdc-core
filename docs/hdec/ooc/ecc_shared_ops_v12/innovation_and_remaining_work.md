# HDEC-ECC V12 创新点与未完成内容

日期：2026-06-10

分支：`hdec-ecc-shared-ops-v12`

当前提交：`fe455f9f hdec: add shared ECC add and align ops`

基线提交：`2d23b592 hdec: add shared HSPREAD square layout primitive`

## 一句话结论

V12 的核心价值不是“额外加了一个 ECC 模块”，而是把 ECC 二元域运算拆解成 HDC 已经擅长的 Boolean、Permutation、Popcount 类操作，并让 ECC 尽量复用 HDEC 原有算子。

更稳妥的论文表述是：

> 面向 HDC-ECC 混合加速器的共享 Boolean/Permutation/Popcount 数据通路架构。

## 值得作为创新点描述的设计

### 1. HDC-native GF(2) 算子映射

二元域 ECC 的很多基础运算本质上是位级操作：

- GF(2) 加法/减法等价于 XOR；
- 平方可以转化为 bit spread；
- 约减需要大量移位、对齐、窗口抽取和 XOR；
- 多项式乘法可以从斜对角线部分积的奇偶性理解。

V12 的设计方向是把这些 ECC 操作映射到 HDEC 已有 HDC 算子：

| ECC 操作需求 | HDEC 复用方式 | 是否新增大 datapath |
|---|---|---|
| GF(2) 加法/减法 | 复用 `HBIND` / XOR lane | 否 |
| field copy | 复用 `ECC_ALIGN` 的 shift=0 模式 | 否 |
| field align / shift window | 复用 `HPERM` shift-align lane | 否 |
| square spread | 复用 `HSPREAD` 子模式 | 否 |
| raw polynomial multiply | 复用 Boolean + Popcount 斜线奇偶路径 | 少量 ECC 控制与暂存 |

这使得 ECC 不是旁挂的专用模块，而是 HDC 算子系统上的一种新调度模式。

### 2. `ECC_ALIGN`：字段对齐原语，而不是单纯 copy

V12 新增的 `HDEC_ECC_ALIGN` 不只是搬运 256-bit 数据。

它的语义是从两个 256-bit VRF row 形成的连续窗口中，抽取一个新的 256-bit 对齐结果：

`{lane_base[25:24], bit_shift[23:18], dst[17:12], src1[11:6], src0[5:0]}`

其中：

- `bit_shift=0, src0=src1` 时就是 field copy；
- `bit_shift!=0` 时可以作为 field shift/align；
- `lane_base` 可以选择跨 lane 的窗口起点；
- 后续 REDUCE 可以用它抽取高半部分折叠回低半部分的窗口。

创新点在于：

> 把 HDC 中的超向量置换/对齐能力，提升为 ECC 二元域约减和平方折叠可以复用的 field alignment primitive。

这比单独给 ECC 加 copy 电路、256-bit shifter 或 reduction window extractor 更符合“强复用”叙事。

### 3. Popcount-assisted diagonal GF(2) multiplication

当前 ECC raw multiply 的核心思想是：

多项式乘法 `C = A x B` 中，每个 `C[k]` 等于所有满足 `i+j=k` 的 `A[i]&B[j]` 的无进位和。这个无进位和在 GF(2) 中就是奇偶性。

因此，每条斜对角线可以看成：

1. 生成这一条斜线上的部分积；
2. 用 popcount 统计 1 的个数；
3. 取 popcount 最低位作为该斜线结果。

这正好复用 HDC 已经有的 popcount 资源。

这个点最有“算法-架构结合”的创新味道，因为它不是简单说 ECC 也能 XOR，而是把二元域多项式乘法重写成 HDC 友好的 popcount/奇偶结构。

### 4. 共享算子带来的面积/时序证据

V12 round02 OOC 结果：

| 版本 | 新增内容 | WNS ns | Fmax est MHz | Slice LUT | Logic LUT | LUTRAM | FF | BRAM | DSP |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| V11 round06 | HSPREAD square layout | 0.177 | 207.340 | 5531 | 5059 | 472 | 2024 | 0 | 0 |
| V12 round02 | ECC_ADD + ECC_ALIGN | 0.324 | 213.858 | 5511 | 5039 | 472 | 2032 | 0 | 0 |

这不能过度解读为所有综合环境下都“面积免费”，但至少说明：

- `ECC_ADD` 和 `ECC_ALIGN` 没有造成新的时序墙；
- 没有引入 BRAM/DSP；
- LUTRAM 没变；
- FF 只小幅变化；
- 在 Vivado 2024.2 OOC 下仍然稳定超过 200 MHz。

## 需要避免的夸大表述

不建议直接声称：

- “完全原创 ECC 算法”；
- “ECC 几乎零面积”；
- “所有 ECC 运算已经完整实现”；
- “任意综合器都会得到相同面积结果”。

更合适的说法是：

- 本项目提出一种 HDC/ECC 共享数据通路；
- 将 GF(2) 运算映射到 HDC-native Boolean、Permutation 和 Popcount 原语；
- 用 popcount-assisted diagonal parity 方式实现二元域原始多项式乘法；
- 初步 OOC 结果显示新增基础 ECC 操作不会破坏 200 MHz 目标。

## 当前已经实现的 ECC/HDC 共享能力

| 功能 | 当前状态 | 说明 |
|---|---|---|
| `ECC_MUL` raw multiply | 已实现 | 256-bit GF(2) 原始多项式乘法，输出未约减结果 |
| `ECC_ADD` | 已实现 | GF(2) add/sub，复用 HBIND/XOR |
| `ECC_ALIGN` | 已实现 | 256-bit copy/align/shift window，复用 HPERM shift-align |
| `HSPREAD` | 已实现 | 平方展开前半步，把 bit spread 成平方布局 |
| HPERM 1-bit shift | 已实现 | 从原 4-bit/nibble 语义升级为 bit-granular shift-align |
| Vivado xsim | 已通过关键测试 | ADD、ALIGN、HPERM/HSPREAD、ECC raw multiply |
| Vivado OOC | 已通过 200 MHz | V12 round02 Fmax est 213.858 MHz |

## 还未完成的内容

### 1. GF(2^m) 模约减 REDUCE

这是下一步最关键的缺口。

当前 `ECC_MUL` 产生的是 512-bit 原始多项式乘积，还不是域元素。要得到真正的 GF(2^m) 乘法结果，必须根据具体不可约多项式把高位折叠回低位。

尚未完成：

- 固定二元域曲线和不可约多项式；
- 设计 REDUCE 调度；
- 判断 REDUCE 是否完全用 `ECC_ALIGN + ECC_ADD` 实现；
- 评估 REDUCE 的周期数、LUT、FF 和 Fmax。

### 2. 完整 GF 乘法 MUL

完整域乘法应为：

`GF_MUL = ECC_MUL_RAW + REDUCE`

当前只有 raw multiply，还没有封装成完整域乘法。

### 3. 完整 GF 平方 SQR

完整平方应为：

`GF_SQR = HSPREAD + REDUCE`

当前 `HSPREAD` 已经能做平方展开，但展开后的结果仍需要模约减。

### 4. 模逆 INV / Itoh-Tsujii Algorithm

ITA 需要大量平方和少量乘法组合。

尚未完成：

- 平方链调度；
- 乘法插入点；
- 中间变量存储策略；
- 周期数估算；
- 与 HDC idle/算子占用的调度关系。

### 5. Montgomery LD 点乘状态机

完整标量点乘 `Q = kP` 还未实现。

尚未完成：

- 点坐标表示选择；
- Montgomery ladder / LD 主 FSM；
- 点加、点倍、条件选择的调度；
- 与 GF_MUL、GF_SQR、GF_ADD、REDUCE 的微操作序列衔接。

### 6. 条件交换 CSWAP 或等价 constant-time 控制

如果采用 Montgomery ladder，通常需要和标量 bit 相关的条件交换或等价控制。

需要注意：

- 直接加 256-bit/多寄存器 CSWAP mux 可能增加面积；
- 可以先研究是否用 VRF 地址重命名、角色交换、控制映射替代真实数据交换；
- 目标是 constant-time，同时尽量不引入 ECC 专用大 mux。

### 7. ECC 临时变量和 VRF/寄存器分配

后续完整 ECC 需要多个 256-bit 临时变量，例如：

- 点坐标；
- 乘法输入输出；
- 平方输入输出；
- ITA 中间值；
- Montgomery LD 中间变量。

尚未完成：

- 哪些变量放 VRF；
- 哪些变量用 shadow register；
- 是否需要寄存器重命名；
- 如何避免 VRF 读写 mux 重新成为时序墙。

### 8. 完整 CPU 自定义指令接口

当前只是逐个基础 ECC op 暴露。

后续需要决定：

- 是 CPU 发一条 `ECC_POINTMUL_START`，内部 FSM 跑完整点乘；
- 还是 CPU 发多个微指令；
- 如何读取状态、结果和错误码；
- 如何和 HDC 任务抢占/等待策略配合。

### 9. HDC 与 ECC 的共享调度策略

项目最终故事不是“ECC 独占 HDEC”，而是：

> ECC 在 HDC 不使用某个算子时见缝插针复用；如果 HDC 需要该算子，ECC 等待或让出。

当前还未完成：

- 算子占用表；
- ECC 微操作 issue/retire 规则；
- HDC 优先级；
- ECC stall/resume 状态保存；
- 不同 ECC 阶段对 Boolean、Popcount、Permutation、VRF 端口的压力评估。

### 10. 完整功能验证和系统级性能评估

当前验证集中在基础 op。

后续还需要：

- Python golden model 对比；
- GF_MUL/GF_SQR/REDUCE 独立测试；
- ITA 测试；
- Montgomery LD 点乘测试；
- 随机标量与边界标量测试；
- 周期数、Fmax、LUT、FF、ECC 专属面积占比统计；
- 与未加入 ECC 的 HDC-only 版本对比。

## 推荐的下一步顺序

1. 先确定二元域曲线和不可约多项式。
2. 用 `ECC_ALIGN + ECC_ADD` 实现 REDUCE V1。
3. 封装 `GF_MUL = raw multiply + reduce`。
4. 封装 `GF_SQR = HSPREAD + reduce`。
5. 测 REDUCE/MUL/SQR 周期和 OOC PPA。
6. 再进入 ITA。
7. 最后实现 Montgomery LD 点乘控制。

## 对论文故事的建议

当前最强的叙事不是“我们做了完整 ECC”，而是：

1. HDC 与二元域 ECC 都高度依赖位级 Boolean/Permutation/Popcount；
2. HDEC 将这些共性抽象成共享算子；
3. ECC 多项式乘法采用 popcount-assisted diagonal parity；
4. ECC 加法、对齐、平方展开、乘法都逐步映射到 HDC 原有结构；
5. OOC 结果显示在保持 200 MHz 的同时，基础 ECC 能力没有引入新的大面积专用模块。

等 REDUCE、GF_MUL、GF_SQR 和 Montgomery LD 完成后，论文故事可以升级为：

> 面向边缘设备的 HDC-ECC 统一位级计算加速器，在一个共享 HDEC 数据通路中同时支持 HDC 推理/检索与二元域 ECC 标量点乘。
