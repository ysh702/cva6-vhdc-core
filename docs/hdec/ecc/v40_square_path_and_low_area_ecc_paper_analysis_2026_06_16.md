# V40 平方路径与低面积二元域 ECC 论文分析

日期：2026-06-16

分支：`hdec-ecc-pointmul-v40`

范围：只新增分析报告，不修改 RTL。

## 1. 简短结论

V40 现在已经处在一个比较好的折中点：

```text
GF(2^233) 标量点乘周期 = 247945 cycles
Logic LUT = 6103
FF        = 1998
WNS       = 0.247 ns，Vivado 2024.2 OOC
```

不能简单说“论文里 ECC 只有几千 LUT，我们有 6000 多 LUT，所以我们面积大”。原因是 HDEC 的 6000 多 Logic LUT 不是一个独立 ECC core，而是包含了：

```text
HDC 全流程
共享 VRF
4x64-bit lane
HDC XOR / popcount / counter / clip / permute
ECC 调度和临时存储
```

更合理的比较方式是看它们怎么处理四件事：

```text
乘法
平方
约简
点乘调度
```

三篇论文给出的启发可以这样理解：

1. 第一篇极低面积方案：一个很小的串行乘法器反复用，面积很低，但点乘非常慢。
2. 第二篇 Booth 方案：还是移位加法思想，但一次看 2 个 bit，让乘法周期约减半；同时单独做平方，所以点乘快很多。
3. 第三篇 BPB-mRnIM 方案：一次处理一组 bit，并且边乘边约简，速度很快，但硬件已经比纯串行方案强不少。
4. V40 已经靠 `KPD64-sub32` 把周期降到和第二篇 Booth 方案接近的量级，同时还保留 HDC 全流程硬件。
5. 下一步最自然的优化点不是再重做整个乘法器，而是把平方和约简做得更直接、更像 HDC 可复用的线性变换算子。

最关键的一点：二元域平方本来非常便宜，我们现在数学上已经没有用乘法器做平方，但调度上还要写出 512-bit spread 结果再做通用约简，所以一次平方大约还是 9 拍。如果做一个直接的：

```text
A -> A^2 mod (x^233 + x^74 + 1)
```

有希望把平方压到 2 到 4 拍，并且面积不会像“直接 reduced multiplication”那样爆炸。

## 2. V40 当前 ECC 设计

### 2.1 二元域运算

当前 ECC 使用的是：

```text
GF(2^233)
f(x) = x^233 + x^74 + 1
```

在二元域里：

```text
加法 / 减法 = XOR
乘法 = 多项式乘法 + 模约简
平方 = bit spread + 模约简
求逆 = 固定平方/乘法链
```

这里的“模约简”就是利用：

```text
x^233 = x^74 + 1
```

把高于 232 次的项折回低位。

### 2.2 标量点乘算法

当前标量点乘是固定 233-bit 调度，不会因为 scalar 里 0 多就跳过操作。这样周期更稳定，也更适合 constant-time 叙述。

V37 的主要算法优化是最后阶段的批量求逆：

```text
原来：最后需要多个逆元
现在：把几个逆元合并成 1 次求逆 + 若干次乘法
```

这节省了一些尾部周期，但主循环仍然被每个 bit 的点加/倍点里的域乘法支配。

V40 的主要优化不是高层点乘公式，而是域乘法内部结构。

### 2.3 V40 域乘法结构

V40 把域乘法的 Karatsuba 拆分从：

```text
256 -> 128 -> 64 -> 32
3^3 = 27 个顶层 32-bit leaf fold
```

改成：

```text
256 -> 128 -> 64
3^2 = 9 个顶层 64-bit leaf fold
每个 64-bit leaf 内部 = 3 个复用的 32x32 子乘法
```

也就是说，V40 不是加了真正的 64x64 大乘法器，也没有用 DSP。它只是让上层看起来是 64-bit leaf，内部仍然复用原来的 32-bit 斜线引擎。

收益来自：

```text
leaf fold 次数从 27 组降到 9 组
```

V40 保留结果：

```text
PMUL cycles        = 247945
ST_ECC_DIAG        = 160380 cycles
ST_ECC_LEAF_FOLD   = 42768 cycles
ST_ECC_REDUCE      = 11284 cycles
Logic LUT          = 6103
FF                 = 1998
```

相对 V37 one-inversion baseline：

```text
周期减少 = 333481 - 247945 = 85536
Logic LUT 增加 = 6103 - 6013 = 90
FF 增加        = 1998 - 1815 = 183
```

这个收益非常划算。

## 3. 当前 lane RTL 是什么样

HDEC lane 是 4 条 64-bit lane。每条 lane 里有这些基础算子：

```text
XOR / boolean
popcount
counter update
clip
shift-align
```

当前 HDC 和 ECC 的复用关系大概是：

```text
HDC 绑定 / 相似度      -> XOR / popcount
HDC 计数 / clip        -> counter / clip
HDC permutation        -> shift-align

ECC 加法              -> XOR
ECC 乘法              -> AND 之后按斜线做 XOR/奇偶规约
ECC 平方              -> bit spread + XOR fold
ECC 约简              -> 固定位置 XOR fold
```

所以目前 ECC 不是一个完全独立的 ECC datapath，而是把二元域运算拆成 HDC 风格的 bit-vector 操作。

这也是后续论文叙述里最重要的一点：

```text
HDEC 不是简单把 ECC 塞进 HDC 旁边。
HDEC 是把 HDC 的 bit-vector substrate 扩展到可以承载二元域 ECC。
```

## 4. 我们现在的平方

### 4.1 二元域平方为什么便宜

二元域平方有一个特殊性质：

```text
(a0 + a1*x + a2*x^2 + ...)^2
= a0 + a1*x^2 + a2*x^4 + ...
```

中间的交叉项会消失，因为在 GF(2) 里：

```text
2ab = 0
```

所以平方不是普通乘法。它只是：

```text
1. 每个 bit 中间插一个 0
2. 把超过 232 次的高位按 x^233 = x^74 + 1 折回低位
```

### 4.2 V40 当前平方路径

当前 RTL 已经没有用乘法器算 `A*A`。它使用：

```text
hspread_half64()
    把 32-bit 扩成 64-bit，原 bit 放到偶数位

ecc_reduce233()
    把 512-bit spread/raw product 约简成 233-bit field result
```

但是现在的完整平方流程还是：

```text
读 256-bit 源操作数
写 512-bit spread 低半部分
写 512-bit spread 高半部分
进入通用 reduce 流程
读回 512-bit 低半部分
读回 512-bit 高半部分
写回 233-bit 结果
```

所以它的数学计算很轻，但调度不够轻。

V37 同源路径里，求逆阶段有：

```text
PMUL_PROFILE_SQR_STARTS_INV_SQR = 232
inverse-square phase = 2099 cycles
平均每次平方约 2099 / 232 = 9.05 cycles
```

V40 继承的是同类 square/spread/reduce 路径，所以平方大概仍然是 9 拍级别。

### 4.3 和第二篇论文的平方对比

第二篇 Booth 论文里，平方是专门的 square block，所以它把平方当成很轻的操作：

```text
field square = 2 cycles
field add    = 2 cycles
field mul    = about 121 cycles
```

这说明一个重要方向：

```text
二元域平方应该明显比乘法便宜。
```

我们现在乘法已经优化到 V40，但平方还可以继续从约 9 拍往 2 到 4 拍压。

## 5. 第一篇论文：bit-serial schoolbook，面积极低

论文：

```text
Aljaedi et al.,
"Area-Efficient Realization of Binary Elliptic Curve Point Multiplication
Processor for Cryptographic Applications",
Applied Sciences 2023.
https://doi.org/10.3390/app13127018
```

GF(2^233) Virtex-7 结果：

```text
PM cycles = 716459
Slices = 391
LUTs = 2346
Fmax = 161 MHz
Latency = 4.45 ms
```

### 5.1 原理

它使用最朴素的串行乘法：

```text
for B 的每一位 i:
    如果 B[i] 是 1:
        result ^= A << i
```

也就是每次只看乘数的 1 个 bit。硬件只需要：

```text
一个小的移位器
一个 XOR 累加器
一个控制器
```

所以面积非常低。

### 5.2 为什么周期很长

对 `m = 233` 来说，一次乘法大概要看 233 个 bit。更重要的是，它为了极低面积，把平方、乘法、求逆都放到同一个小算术路径上复用。

这样一来：

```text
乘法慢
平方也慢
求逆更慢
```

所以点乘到了 716459 cycles。

这个方案适合作为面积下限参考，但不适合作为 HDEC 下一步主线，因为我们的目标还要求 ECC 标量点乘不能太长。

## 6. 第二篇论文：Booth，把移位叠加提速

论文：

```text
Aljaedi et al.,
"FPGA implementation of elliptic-curve point multiplication over GF(2^233)
using booth polynomial multiplier for area-sensitive applications",
IEEE Access 2024.
https://doi.org/10.1109/ACCESS.2024.3403771
```

Virtex-7 结果：

```text
PM cycles = 174457
Slices = 1343
LUTs = 3761
FF = 1664
Fmax = 393 MHz
Latency = 443.91 us
```

### 6.1 原理

它还是移位/XOR 累加的思想，但不是每次看 1 个 bit，而是每次看 2 个 bit。

可以简单理解为：

```text
看当前两个 bit：
    00 或 11 -> 这一步不用变
    01       -> 累加 A
    10       -> 按 Booth 规则累加 A
然后移位，进入下一组 bit
```

在普通整数里 Booth 需要加法和减法；但在二元域里，减法和加法都是 XOR，所以硬件仍然不复杂。

它的核心收益是：

```text
普通 bit-serial: 约 m 拍
Booth bit-serial: 约 m/2 拍
```

对 `m = 233`，论文里一次模乘约：

```text
m/2 + 4 = 121 cycles
```

### 6.2 为什么比第一篇快很多

第二篇不是只改了乘法。它还单独做了平方器。

在它的调度里：

```text
field multiplication -> about 121 cycles
field square         -> 2 cycles
field addition       -> 2 cycles
```

这就是点乘从 716k cycles 降到 174k cycles 的主要原因。

也就是说，第二篇真正值得我们学的不是“照搬 Booth”，而是：

```text
乘法仍然可以低面积串行
但平方不能再走慢乘法路径
平方必须单独做成很便宜的线性操作
```

### 6.3 对 HDEC 的启发

我们的 V40 域乘法已经做到 247945 cycles 的点乘，比第二篇慢一些，但已经在同一量级。考虑到我们还包含 HDC 全流程硬件，这个结果并不差。

所以现在比起立刻把乘法换成 Booth，更值得先做：

```text
把平方从约 9 拍压到 2-4 拍
```

这个方向风险更小，也更符合二元域数学特性。

## 7. 第三篇论文：BPB-mRnIM，多 bit 一组并边乘边约简

论文：

```text
Zeghid et al.,
"Power/Area-Efficient ECC Processor Implementation for Resource-Constrained
Devices",
Electronics 2023.
https://doi.org/10.3390/electronics12194110
```

GF(2^233) Virtex-7 结果：

```text
KP time = 17 us
Fmax = 356 MHz
约等效 cycles = 17 us * 356 MHz ~= 6052 cycles
Slices = 1527
LUTs = 5548
FF = 1626
```

### 7.1 原理

第三篇不是一位一位看，也不是两位一组看，而是把多项式拆成小块，一次处理一组 bit。

可以简单理解为先准备一些小组合：

```text
0
1
x
x + 1
x^2
x^2 + 1
x^2 + x
x^2 + x + 1
```

每一轮做：

```text
accumulator 移位
按当前 bit group 选择一个小组合
XOR 进 accumulator
顺手做约简
```

所以它比 bit-serial 少很多轮。

### 7.2 为什么周期很低

它快不是因为用了神奇的标量算法，而是因为三件事叠在一起：

```text
一次处理多个 bit
乘法过程中直接穿插约简
点加/倍点调度里让乘法、平方、加法尽量连续工作
```

硬件上它也比第二篇更强：

```text
1 个 BPB-mRnIM multiplier
2 个 square blocks
1 个 adder
register file
2-stage pipeline
```

所以它不是“极小面积”的路线，而是“面积还可以接受，但速度明显更高”的路线。

### 7.3 对 HDEC 的启发

第三篇值得学的是思想，不建议直接照搬整个架构。

可借鉴的思想：

```text
group-wise partial contribution
小组合预计算
边累加边约简
平方和加法不要被乘法路径拖慢
```

不建议直接照搬的原因：

```text
它已经形成较强的 ECC 专用算术岛
可能削弱 HDC/ECC 复用叙述
也可能让 V40 已经控制住的面积重新上涨
```

## 8. 和 HDEC V40 的对比

| 设计 | 主要乘法思路 | 点乘周期 | 面积说明 |
| --- | --- | ---: | --- |
| 第一篇 | 1-bit schoolbook 移位/XOR | 716459 | 391 slices, 2346 LUT |
| 第二篇 | 2-bit Booth 移位/XOR | 174457 | 1343 slices, 3761 LUT |
| 第三篇 | digit-serial BPB-mRnIM | 约 6052 | 1527 slices, 5548 LUT |
| HDEC V40 | KPD64-sub32 斜线 Karatsuba，复用 HDC 风格 lane | 247945 | 6103 Logic LUT，包含 HDC+ECC |

判断：

1. 第一篇面积极低，但太慢。
2. 第二篇是最接近我们目标的低面积参考。
3. 第三篇很快，但算术硬件更强，不适合直接复制到 HDEC。
4. V40 已经靠 Karatsuba 64-bit leaf 把乘法瓶颈降了很多。
5. 当前最自然的下一步是优化平方/约简路径。

## 9. 建议下一步：直接 FSQR233，共享为 HDC 线性变换算子

### 9.1 当前问题

当前平方是：

```text
A
-> 512-bit bit-spread temporary
-> ecc_reduce233
-> 233-bit result
```

这条路径功能正确，也比 `A*A` 便宜很多，但调度上仍然要写/读中间 512-bit 结果，所以一次平方约 9 拍。

### 9.2 建议新算子

做一个直接平方：

```text
direct_fsqr233(A) = A^2 mod (x^233 + x^74 + 1)
```

实现逻辑：

```text
输入 bit A[i] 先映射到 raw 位置 2*i
如果 2*i >= 233，就按 x^233 = x^74 + 1 折回低位
如果折回后仍然超过 232，再继续折一次
最后把所有贡献 XOR 到 233-bit 输出
```

这个网络应该比 direct reduced multiplication 小很多，因为平方没有交叉项：

```text
乘法有 a[i] & b[j]
平方只有 a[i] -> 固定几个输出 bit
```

所以直接平方是线性映射，不是大规模 AND/XOR 乘法网络。

### 9.3 不要叫 ECC 专用 squarer

建议把它包装成 HDC 也能用的算子：

```text
BV_SPREAD_FOLD
或
BV_LINEAR_FOLD
```

ECC 用它做：

```text
field square
inversion 里的 square chain
point double 里的 square
```

HDC 可以用它做：

```text
bit projection
bit spreading / compression
线性 hash-like projection
结构化 permutation / fold
```

这样它不是“为了 ECC 新增专用平方器”，而是“HDC lane 增加一种线性 bit-vector 变换能力，ECC 正好复用”。

### 9.4 第一轮 RTL 实验目标

建议目标：

```text
周期：2 到 4 cycles / field square
面积：尽量控制在 +100 Logic LUT 以内
存储：不要新增大 256-bit FF bank
时序：按 64-bit 或 128-bit 分 bank/stage，避免一个巨大 XOR cone
验证：ECC PMUL profile + HDC full flow + OOC
```

推荐分阶段：

```text
stage 0: 从 VRF 读 256-bit 输入
stage 1: 计算低输出 word 的 fold 贡献
stage 2: 计算高输出 word 的 fold 贡献
stage 3: 写回 233-bit 结果
```

如果这个方向 Vivado 映射得干净，它会比继续大改乘法器更适合做 V40 后续优化。

## 10. 暂时不建议的方向

1. 不建议把 V40 乘法直接换成纯 bit-serial schoolbook。它太慢。
2. 不建议直接复制第三篇 BPB-mRnIM 完整架构。它速度很强，但会形成 ECC 专用算术岛。
3. 不建议再做一个大组合 direct reduced multiplication。V40 已经证明直接 reduced accumulation 很容易把 XOR 网络做大。
4. 不建议只做 ECC 私有 squarer。最好把它设计成 HDC 可见的线性变换 primitive。

## 11. 来源

本地报告：

- `docs/hdec/ecc/v40_kpd64_sub32_p2_diagonal_result_2026_06_16.md`
- `docs/hdec/ecc/v37_affine_batch3_inv_ita_result_2026_06_15.md`
- `reports/hdec/v27_ecc_operator_reuse_survey/README.md`
- `reports/hdec/v27_ecc_operator_area_2026_06_13/README.md`

论文：

- Aljaedi et al., "Area-Efficient Realization of Binary Elliptic Curve Point
  Multiplication Processor for Cryptographic Applications", Applied Sciences
  2023, https://doi.org/10.3390/app13127018
- Aljaedi et al., "FPGA implementation of elliptic-curve point multiplication
  over GF(2^233) using booth polynomial multiplier for area-sensitive
  applications", IEEE Access 2024, https://doi.org/10.1109/ACCESS.2024.3403771
- Zeghid et al., "Power/Area-Efficient ECC Processor Implementation for
  Resource-Constrained Devices", Electronics 2023,
  https://doi.org/10.3390/electronics12194110
