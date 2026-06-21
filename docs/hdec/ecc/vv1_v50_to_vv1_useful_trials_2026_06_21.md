# VV1: V50 到当前版本的有用尝试整理

日期：2026-06-21

当前交付版本：`VV1`

当前代码点：

- `3f1406f0 hdec: remove unused clip threshold state`
- 基础分支：`hdec-ecc-pointmul-v50-shared-mul-reduce`
- 远程交付目标：`origin/VV1` 和 tag `VV1`

## 最终状态

VV1 已经把 HDEC 的主要功能和创新点基本落到 RTL/验证流里：

- ECC：保留二元域 GF(2^233) 点乘主流程，PMUL wall cycles 保持 `190151`。
- HDC：保留训练/推理硬件原语，HSIM/HMATCH 的相似度语义改成 `popcount(query & prototype)`。
- 自学习：采用软件调度硬件执行。top-k 原型和 mistake-only 自学习策略由软件/testbench 决策，RTL 负责 VRF、AND-overlap、popcount 和写回。
- 面积：相对 V50 仍明显下降，同时保持 200 MHz 以上时序。

| 节点 | Total LUT | Logic LUT | LUTRAM | FF | Fmax | PMUL cycles |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| V50 best | 5557 | 5429 | 128 | 1715 | 210.261 MHz | 190151 |
| VV1 current | 5195 | 5067 | 128 | 1877 | 210.393 MHz | 190151 |

## 主要有效路线

### 1. V50：停止 Vivado 小修小补

V50 之前已经把很多显式无用信号、端口、tie-off 和简单 mux 清理过。V50 的结论是：继续删表面信号，Vivado 大多已经能优化掉，面积不会再明显下降。

有用点：

- 把 `0bfb4fbb` / `547af1aa` 作为可回退面积基线。
- 明确后续要从控制结构、product scratch、KPD fold、reduce source assembly、XOR 语义复用等结构层面入手。

### 2. VRF 边界保留

尝试过更激进的 VRF 写回和边界改造后，发现直接把 VRF 写数据源集中化，常常会制造更宽的 256-bit mux 和更高 fanout。

保留下来的判断：

- VRF 边界不能随便拆。
- 更好的方向是减少写回来源、减少 owner 控制，而不是在 top 层再包一层大选择器。

对应主线提交：

- `e4dd6521 hdec: keep vrf boundary for lower area`
- `73f03f9f hdec: write ecc product rows with full-row owner`

### 3. 控制层从多位比较转成更局部的状态/owner

V50 后大量面积来自控制译码和跨阶段 payload。有效做法不是把所有控制集中，而是让关键状态更局部、更可推断。

保留下来的修改包括：

- 主 FSM one-hot 编码，减少多位状态比较锥。
- PMUL subop one-hot 编码，降低 ECC 点乘子阶段译码复杂度。
- spread 写回 base 统一，避免多处重复地址组合。
- result owner、copy writeback、常量写入等控制变成更窄的派生信号。

对应主线提交：

- `709f03a3 hdec: encode main control fsm one-hot`
- `46160b2d hdec: encode pmul subop fsm one-hot`
- `00262cda hdec: unify spread writeback base control`
- `1bd83a21 hdec: reuse ecc destination for copy writeback`
- `bd6d7f53 hdec: derive pmul const write value from destination`
- `88187687 hdec: drop transient ecc result owners`

### 4. ECC 乘法局部化：KPD、diagonal、product scratch

ECC 面积优化里，最有价值的不是把所有 XOR 拉到中央，而是让 GF(2) 乘法/折叠/累加留在 field engine 和 lane-local 位置。

保留下来的修改：

- field leaf 初始化集中化。
- final KPD subproduct 在 product assembly 前折叠。
- diagonal operand 预旋转，降低后续选择压力。
- diagonal parity reorder 合并进 pack。
- product scratch 首叶写入时，把 `old/zero` 选择并入 XOR 输入门控。

对应主线提交：

- `b13eb3a1 hdec: centralize field leaf initialization`
- `ce4a41b7 hdec: fold final kpd subproduct before product assembly`
- `ba7049f1 hdec: prerotate ecc diagonal operands`
- `de535858 hdec: fold diagonal parity reorder into pack`
- `fab0eaf1 hdec: gate product scratch xor input`

### 5. XOR 统一的最终结论

这一轮最重要的结论是：数学上都叫 GF(2) XOR，不代表硬件上应该做成一个中央 XOR。

保留下来的判断：

- HDC HBIND 的 4x64 bitwise XOR 可以和 ECC ADD 的逐 bit GF(2) 加法共享。
- ECC reduce 的 bitwise XOR 可以保持 lane-local，不要绕到 top-level。
- ECC diagonal parity 是 `AND terms + parity`，本质是乘法斜线奇偶，不适合强塞进 HDC bitwise XOR。
- KPD/product fold 是乘法局部累加，应该留在 field engine 内部。

有效接受项：

- `product_pair_gate`：把 product scratch 的 first-leaf zero-select 吸收到本地 XOR/AND 累加锥里。

被拒绝但有价值的结论：

- 中央统一 XOR、direct top reduce、staged reduce、KPD64 lowxor preselect、KPD64 sub32 slice 在当前基线上会增加 mux/fanout，面积变差或无收益。
- 因此论文表述应叫 “lane-local GF(2) XOR fabric / GF(2) semantic reuse”，不要说成一个中央万能 XOR。

### 6. 删除过时 KPD32 路线

后期确认当前 ECC 乘法主线已经是 KPD64/field-engine 路径，旧 KPD32 helper 已经不再是有效主路径。

对应提交：

- `3927dfbd hdec: remove stale kpd32 helpers`

意义：

- 清理算法叙事，避免同一个 ECC 乘法同时出现两套位宽故事。
- 让后续文档聚焦当前实际 RTL，而不是旧实验痕迹。

### 7. HDC 创新算法落地：AND-overlap 相似度

原始二值 HDC 常用 Hamming distance：

```text
dist(q, p) = popcount(q XOR p)
```

VV1 的创新 HDC 推理使用固定密度 prototype，并计算：

```text
score(q, p) = popcount(q AND p)
```

由于每个 prototype 固定只有 top-k 个 1，raw AND overlap 可以直接作为匹配分数，不再需要传统 XOR 距离。

对应提交：

- `9f75e0db hdec: implement hdc and-overlap similarity`

硬件变化：

- HSIM/HMATCH 的相似度输入改为 `query & prototype`。
- popcount 继续复用原来的 popcount compressor。
- HBIND 的 XOR 路径保留，因为绑定仍然需要 bitwise XOR。

### 8. HDC 自学习验证流落地

VV1 的自学习不是纯 RTL 自治控制器，而是软件调度硬件执行：

- Python 生成初始 top-k prototype。
- 软件/testbench 逐样本把 query 写入 VRF。
- RTL HSIM 逐类计算 `popcount(query & prototype[class])`。
- 软件/testbench 判断预测、真实标签、是否 mistake-only 更新。
- 若更新，则软件重新 top-k，并把新 prototype 写回 VRF。

对应提交：

- `c9e4e644 hdec: add hdc self-learning vivado flow`

已验证结果：

| Dataset | Model | Accuracy | Updates |
| --- | --- | ---: | ---: |
| UCI HAR | `L_diffmax_topk256_self_mistake` | 0.881574483 | 349 |
| WISDM AR user split | `K_own_topk256_self_mistake` | 0.656116859 | 565 |

意义：

- 这证明创新算法可以用软件库/指令调度方式落到硬件上。
- 不需要为了 top-k 排序器在 RTL 里增加大量 LUT。

### 9. 最后清理：lane shell 和 clip threshold

功能落地后，又做了两次不改变面积的清理：

- 删除 lane 里已经不用的 command-shell 端口和 top 层 tie-off。
- 删除当前低面积 clip 模式不用的 threshold 状态。

对应提交：

- `dc7c7e89 hdec: prune unused lane shell ports`
- `3f1406f0 hdec: remove unused clip threshold state`

结果：

- 面积、时序、PMUL 周期不变。
- RTL 语义更清楚，警告减少。

## 被拒绝但应保留为经验的路线

这些尝试没有进入 VV1，但很重要：

- direct AND-popcount：减少少量 FF，但组合锥变大，LUT 增加。
- bool tag 2-bit 压缩：控制看起来更窄，但 Vivado 映射更差。
- hmatch slot 缩到 3 bit：理论更窄，实际增加 LUT。
- hdc_src0 lane clock-enable：FF 略降，但 LUT 增加。
- lane_result direct writeback / split / nohold：多次证明会放大 mux 或破坏时序。
- KPD64 lowxor/sub32 在旧基线有局部希望，但在当前基线上都变差。

## VV1 论文表述建议

可以这样描述 VV1：

- ECC 创新：面向 GF(2^233) 的 diagonal/KPD64/product-scratch 局部乘法架构，配合 LD+ITA 标量点乘调度。
- HDC 创新：固定密度 top-k prototype + AND-overlap similarity + mistake-only edge self-learning。
- HDEC 结合创新：不是把所有算子硬塞成一个中央单元，而是在 lane-local GF(2) 线性语义、VRF 存储、软件调度硬件执行三个层面复用。
- 面积策略：避免中央大 mux，保留 VRF 边界，控制层局部化，product-local 计算局部化。

VV1 是功能和创新基本闭环的版本；后续若继续做面积优化，应以新的结构问题为起点，而不是继续小修 Vivado 优化规则。
