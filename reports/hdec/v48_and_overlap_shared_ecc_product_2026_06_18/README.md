# V48 HDC AND-overlap / ECC Product Sharing Report

Date: 2026-06-18

## 目标

本轮目标是把 HDC 的创新版匹配算法落到 RTL 中：支持 `query & prototype` 后再 popcount 的 overlap 分数，同时不能新增一套 HDC 私有 AND 阵列，应尽量复用 lane 内已有的 ECC 乘积结构。

## 关键结论

当前 ECC 的所谓 AND 阵列并不是 64 位普通 `A & B` 输出。它在 `hdec_lane_4x64` 中用于二元域乘法的斜线乘积奇偶归并：

- 输入是 32 位 `ecc_diag_a_i/ecc_diag_b_i`。
- lane 输出的是 8 位斜线 parity。
- 这个 parity 已经把多个 AND 项异或折叠掉，不能直接给 HDC popcount 使用。

所以 HDC overlap 不能直接拿 `ecc_diag_parity_o` 当作 AND 结果。正确做法只能是把 lane 内乘积结构扩成共享布尔乘积入口：ECC 模式继续做斜线 parity，HDC overlap 模式把同位乘积写入原来的 `bool_result_q`，再走已有 popcount 捕获寄存器。

## 当前保留实现

当前 RTL 保留的是 optional overlap 模式：

- 默认 `HDEC_HMATCH` 仍保持旧语义：XOR 后 popcount，距离越小越好。
- `operand_a[16] = 1` 时启用新语义：AND 后 popcount，overlap 分数越大越好。
- lane 内没有新增 HDC 私有 AND 模块；AND 写入复用原来的 `bool_result_q` 和 popcount 捕获路径。
- 周期保持不变：2 个 class 的 HMATCH 仍为 75 cycles。

修改文件：

- `core/hdec/rtl/hdec_lane_4x64.sv`
- `core/hdec/rtl/hdec_top.sv`
- `verif/hdec/tb_hdec_hmatch_compare_split.sv`

## OOC 数据

基线：`reports/hdec/v47_stage3_combo_all_a_2026_06_18/ooc_combo_all_a`

| 版本 | Logic LUT | Slice LUT | FF | BRAM | DSP | WNS | Fmax |
|---|---:|---:|---:|---:|---:|---:|---:|
| V47 combo baseline | 5476 | 5604 | 1719 | 4 | 0 | 0.247 ns | 210.393 MHz |
| V48 optional overlap | 5528 | 5656 | 1720 | 4 | 0 | 0.244 ns | 210.261 MHz |
| V48 hardwired overlap, rejected | 6674 | 6802 | 1723 | 4 | 0 | 0.048 ns | 201.939 MHz |

当前最好结果相对基线：

- Logic LUT: +52
- Slice LUT: +52
- FF: +1
- Fmax: 基本不变，仍超过 200 MHz
- HMATCH 周期：不变

## 尝试与判断

### 尝试 1：optional overlap

做法：

- lane 的布尔前端增加一个 product 写入选择。
- top 用 `operand_a[16]` 控制 HMATCH 是旧距离模式还是新 overlap 模式。
- 新增 HMATCH overlap 仿真用例。

结果：

- 功能正确。
- 周期不变。
- 面积小涨 52 Logic LUT。

判断：

这是当前可用的安全点，但还没有达到“面积不涨”的目标。

### 尝试 2：hardwired overlap

做法：

- 把 HMATCH 直接改成 overlap 分数最大。
- 删除旧距离模式的预算减法逻辑。

结果：

- 功能正确。
- 周期不变。
- 但 Logic LUT 涨到 6674，MUXF7 明显暴涨。

判断：

这条路不保留。它说明“算法语义更简单”不一定让 Vivado 综合结构更小，控制和写回周围被重排后反而恶化。

### 尝试 3：lane 写法改成 if/case

做法：

- 把 `bool_compute_word = mode ? product : xor` 改成寄存器写入时的 `if` 分支。

结果：

- OOC 与 optional overlap 完全相同。

判断：

Vivado 已经把两种写法合成到同一个结构，单纯语法改写不能降低这 52 LUT。

## 后续方向

如果必须做到面积不涨，有两条更有希望的路线：

1. 固定密度 HDC 数学等价路线。
   如果 query 和 prototype 的 1 的个数都固定，那么最大化 `popcount(query & prototype)` 与最小化 XOR 汉明距离是等价的。这样可以在算法论文中讲 AND-overlap 的数学意义，但 RTL 仍使用已有 XOR+popcount，不新增 AND 选择，面积理论上不涨。

2. 时间折叠乘积路线。
   用更窄的共享乘积结构分两拍或多拍算 overlap，减少每拍的 64 位选择压力。代价是 HMATCH 周期上升，需要重新评估端侧推理吞吐是否接受。

当前结论：精确 AND-overlap 如果要求周期不变，在现有 lane 宽度下会带来约 52 Logic LUT 的成本；这不是新建独立 HDC AND 阵列导致的，而是共享布尔结果寄存器前的 XOR/AND 选择和综合重排成本。

## 下一版计划：回到第二阶段的数据通路共享

V48 已经完成了两个阶段的可落地点：

- 第一阶段：lane 内融合 XOR/归约 XOR，ECC 约减和 HDC XOR 类操作共用同一套 lane XOR 资源。
- 第三阶段：HDC 新增 AND-overlap 匹配语义，使用 lane 内 `bool_product_word -> bool_result_q -> popcount` 路径，没有新增 HDC 私有 AND 阵列。

但第二阶段还没有真正完成。之前第二阶段尝试的是“把 HDC/ECC 寄存器塞进同一条小流水线”，结果 LUT/MUX 增长太多，说明方向不能是简单合并寄存器名字，而要从数据流本身重新做共享。

下一版目标应该是：把当前仍然属于 ECC 私有计算大头的乘法/约减数据通路和 `product scratch` 改造成 HDC/ECC 真实共用资源。这里的重点不是控制 LUT，而是计算 LUT：

- 当前 HDC 已真实使用 lane 内 AND/XOR/popcount。
- 当前 HDC 还没有真实使用 `ecc_leaf_prod_q`、`ecc_leaf128_prod_q`、`ecc_product_pair`、KPD fold/mask、GF(2^233) reduce source assembly 这条完整乘法/约减数据流。
- 因此 V49 的核心问题是让 HDC 在 RTL 连线上真实读写或占用这些资源，而不是只在面积统计口径上把它们叫成共享。

建议 V49 从三条路线依次尝试：

1. 共享 scratch 重命名和端口泛化。
   先把 `ecc_product_pair` 从 ECC 私有 scratch 改成 `shared_product_scratch` 一类的通用中间结果缓存，增加轻量 tag 表示当前 scratch 内容属于 ECC fold 还是 HDC overlap/mask/更新。目标是让 HDC 至少有一条真实路径可以写入和读出这块 scratch。

2. 共享 fold/accum 单元。
   把 KPD fold 中的“移位后 XOR 累加”抽成更通用的 fold-accum 操作。ECC 模式解释为二元域模乘/约减，HDC 模式解释为 bit-plane/mask/overlap 的分块累加或 prototype 更新。目标是复用计算 LUT，而不是只共用最终的 64 位 AND。

3. 第二阶段流水线重做。
   不再做单个 `small_pipe_q` 强塞多种寄存器，而是让每级流水线只携带统一的 payload/tag/valid。寄存器是否属于 HDC 或 ECC 由 tag 解释，不在数据入口前堆大 MUX。成功标准是 FF 下降或不涨，LUT 不超过 V48，最好下降。

V49 的验收标准：

- 200 MHz 时序不掉，WNS 仍为正。
- HDC full-flow、HMATCH overlap、ECC diag mul、ECC reduce、ECC PMUL 回归通过。
- HMATCH 周期保持 75 cycles，ECC 周期尽量不增加；如果增加，必须换来明确的面积下降。
- 重点观察 `ecc_exclusive_mul_reduce_datapath` 和 `ecc_exclusive_product_scratch` 两个 bucket 是否下降，而不是只看控制 LUT。
