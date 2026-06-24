# VV5 HDEC 架构叙事与下一步建议

> 分支：`hdec-vv5-vector-fabric`
> RTL commit：`c3d364f5 hdec: add VV5 vector payload fabric`
> 日期：2026-06-24

## 1. 这次 VV5 到底改了什么

VV5 不是只改了 HPERM。

最后一刀看起来和 HPERM 关系很大，是因为我们删掉了 HPERM payload 的冗余清零逻辑；但 VV5 的主体修改，是把 HDC 侧多个分散的结果通道合并成了一个统一的 `vector payload fabric`。

现在进入统一 payload 边界的内容包括：

| 算子 | 进入统一 payload 的内容 |
|---|---|
| HBIND | 4x64 bitwise XOR 结果 |
| HSIM / HMATCH | AND-overlap 后的 popcount 分数 |
| HCNTADD | 训练计数器更新结果 |
| HCNTCLIP | clip 后的原型 bit |
| HPERM | 置换后的 4x64 写回结果 |

所以 VV5 的本质不是“只优化 HPERM”，而是把 HDC 中大部分“lane 算完以后要写回 VRF 的结果”都收敛到了一个统一的 256-bit payload 边界里。

## 2. 为什么没有把所有算子都强行合并

硬件合并必须看数据形态是否相同。

HDC 这些算子有一个共同点：读出 4 个 64-bit chunk，做局部计算，然后产生一个 4x64 结果，或者产生一个可以打包进 payload 的分数/bit 结果，最后写回 VRF。它们天然适合进入同一个 vector payload fabric。

ECC 多项式乘法则不同。它不是简单的“一拍输入、一拍输出”向量算子，而是一个多周期 field engine：里面有部分积、斜线奇偶、popcount 辅助、Karatsuba fold、边算边约减、product scratch、ITA 求逆和 PMUL 微调度。它的数据会在 ECC 内部反复流动。

如果把 ECC 乘法也强行拉进 HDC 的 payload fabric，就会产生很多跨层宽 MUX、跨 VRF 选择和额外控制，面积大概率增加，论文叙事也会变成“为了复用而复用”。

因此当前结构采用的是：

| 部分 | 是否进入统一 payload |
|---|---|
| HDC 向量写回类算子 | 进入 |
| ECC 简单 GF(2) 加法 / XOR 语义 | 可以复用 HDC lane XOR 语义 |
| ECC 多项式乘法 / 约减核心 | 保持 product-local |
| VRF / BRAM 全局访问 | 保持全局存储层 |
| popcount 内部 compressor | 保持专门结构，不强行合并 |

## 3. 这是不是只是把 top 控制搬到合并 lane 层

如果只是把 4 个 lane 包进一个模块，那确实只是搬家，面积不会真正下降，甚至可能变差。

VV5 有效的地方在于：原来 top 层有很多分散的语义结果寄存和选择网络，例如 bool result、pop result、clip result、HPERM result。现在这些被收敛成一个统一的 payload 寄存边界。top 不再分别关心每一种结果怎么保存，只关心“这条指令最终写回什么 payload”。

所以 VV5 不是单纯移动控制，而是把“多个结果通道”改成了“一个结果载荷协议”。

这也是为什么 FF 下降非常明显：

| 指标 | VV4 | VV5 | 变化 |
|---|---:|---:|---:|
| Total LUT | 4722 | 4675 | -47 |
| Logic LUT | 4722 | 4675 | -47 |
| FF | 1747 | 1382 | -365 |
| Fmax | 207.684 MHz | 207.727 MHz | 基本不变 |
| PMUL cycles | 135952 | 135952 | 不变 |
| BRAM / DSP | 4 / 0 | 4 / 0 | 不变 |

## 4. 期刊论文中可以如何介绍 HDEC 整体架构

HDEC 不是一个传统的单功能加速器，也不是把 HDC 和 ECC 两个模块简单拼在一起。

更准确的说法是：

HDEC 是挂在 CVA6 旁边的共享向量计算底座。CPU 通过自定义指令调度 HDC 训练、推理和 ECC 标量点乘。HDEC 内部用 256-bit 超向量寄存器保存 HDC hypervector 和 ECC GF(2^233) 域元素，但物理计算不是一个笨重的 256-bit 大 ALU，而是 4 个 64-bit 计算切片并行工作。

可以把整体结构讲成四层：

| 层次 | 作用 |
|---|---|
| 软件调度层 | RISC-V 程序安排 HDC 训练、推理、自学习流程，也启动 ECC PMUL |
| 共享存储层 | VRF 保存 256-bit hypervector，也保存 ECC 域元素 |
| 共享向量计算层 | 4x64 物理切片形成统一 vector payload fabric，承接 HDC XOR、AND-overlap、counter、clip、permute 等结果 |
| ECC 专用域运算层 | 多项式乘法、约减、ITA 求逆、Montgomery LD 点乘保持 product-local 微调度 |

论文中可以这样表述：

> HDEC is organized as a shared 4x64 vector substrate rather than two isolated accelerators. HDC operations are exposed as software-scheduled vector primitives, while ECC scalar multiplication is executed by a micro-scheduled GF(2^m) field engine. Both domains share the VRF, vector payload boundary, and GF(2)-oriented low-level logic when the data semantics match, while product-local ECC multiplication remains specialized to avoid control and routing inflation.

中文解释就是：

我们不是把 HDC 和 ECC 生硬拼起来，而是用一套 4x64 向量底座承载两类算法。HDC 走软件调度硬件原语，ECC 走硬件微调度域运算；能共享的共享，不能共享的保持局部专用，这样既保留复用故事，也避免为了复用导致面积更大。

## 5. 相比目标，VV5 达到了什么

VV5 达到了第一阶段结构目标：

- 原来 4 个 lane 各自暴露结果，top 层到处选择数据。
- 现在变成一个统一 vector payload 边界。
- 内部仍保持 4x64 物理计算，避免 256-bit 大算子带来的宽逻辑代价。
- 面积没有因为合并而上升，反而 Total / Logic LUT 和 FF 都下降。
- HDC 语义、ECC 语义、PMUL 周期、Fmax 都没有被破坏。

但 VV5 还没有达到“整个 HDEC 所有控制全部统一”的最终形态。

目前仍然独立的大块包括：

- ECC PMUL 微调度控制；
- ECC field engine 内部乘法 / 约减 / ITA 控制；
- VRF 全局仲裁和访存控制；
- product scratch 和 field-local 数据流。

这些没有强行合并，是因为它们和 HDC vector payload 的数据形态不同。强行合并很容易增加宽 MUX 和控制 fan-in。

## 6. 下一步建议

我的建议是：不要立刻继续无目标地做 RTL 小优化。

VV5 已经证明“统一 payload 边界”这个结构方向有效。下一步更适合先做一次论文级收敛，把现在已有的创新、面积、周期、准确率和复用口径整理完整。

推荐下一步按优先级执行：

### 第一优先级：冻结 VV5，补齐论文级数据

需要补齐：

- Vivado synthesis 数据；
- Vivado implementation / bitstream 后数据；
- strict ECC-only 面积统计；
- shared substrate 面积统计；
- HDC 自学习准确率；
- ECC PMUL cycles；
- DC / ASIC synthesis 数据；
- 与 HDC-only、ECC-only、普通 HDC、普通 Montgomery LD + ITA 的对比表。

这一步对 TCAS-I 更重要。因为现在继续多扣几十 LUT，不一定比一张清楚可信的架构表、复用表、准确率表和 ASIC 数据更有价值。

### 第二优先级：如果继续开 VV6，只碰 ECC field-engine 内部

如果还要继续优化 RTL，我建议下一轮不要再围绕 HDC lane shell 做文章，而是集中在 ECC 内部：

- product scratch 的读写形态；
- ECC field-op descriptor；
- PMUL / ITA 微调度状态压缩；
- direct-reduced multiplication 的中间寄存与选择路径；
- ECC-only FF 和 ECC-only control LUT。

原因是 VV5 已经把 HDC vector payload 层压得比较干净了，剩下的大头更可能在 ECC field-local 控制和存储。

### 第三优先级：论文叙事先定稿，再决定是否继续优化

当前 HDEC 的论文主线可以是：

1. HDC 自学习算法：固定 1 数量原型 + AND-overlap 推理；
2. HDC / ECC 共享 4x64 向量底座；
3. ECC 使用适配共享底座的 GF(2^m) 乘法路径，包括 AND+XOR、AND+popcount、边算边约减；
4. VV5 进一步把 HDC 结果通道统一为 vector payload fabric，降低控制和寄存面积；
5. 系统层面体现软硬件协同：HDC 由软件调度硬件原语，ECC PMUL 由硬件微调度完成。

我的判断是：现在最值得做的是“论文验证闭环”，不是继续盲目优化。

如果验证闭环暴露出某个数据不好看，例如 ECC-only FF 仍然太高、ASIC DC 面积不理想、post-implementation Fmax 有压力，再开 VV6 针对那个问题做结构优化。这样后续每一轮修改才有明确目标，不会回到无限 try 的状态。
