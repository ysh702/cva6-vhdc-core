# V42 Lane-Fused ECC Checkpoint

## 版本目的

V42 的目标不是单独堆一个更快的 ECC 乘法器，而是在 V41U 的共享 lane 结构上继续压缩 ECC 点乘周期，同时保持面积低于 V41U。当前保留下来的 V42 点满足这个目标：

| Version | PMUL cycles | Slice LUT | Logic LUT | LUTRAM | FF | WNS | Fmax |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| V40 | 247945 | 6575 | 6103 | 472 | 1969 | 0.250 ns | 210.526 MHz |
| V41U | 247945 | 6374 | 5902 | 472 | 2001 | 0.250 ns | 210.526 MHz |
| V42 | 183793 | 6336 | 5864 | 472 | 2012 | 0.250 ns | 210.526 MHz |

V42 相比 V41U 少了 64152 个点乘周期，Slice LUT 少 38，Logic LUT 少 38，仍然满足 200 MHz。

## V42 做了什么

### 1. 32 位斜线一次打包

V40/V41 的二元域乘法已经不是普通乘法器，而是按斜线计算部分积。V42 把每个 32 位叶子乘法的斜线输出从更窄的分组扩成每个 lane 一次产生 8 个奇偶位，4 个 lane 合起来一次给出 32 个斜线结果。

这样一个 32x32 叶子乘法只需要两个 issue 槽完成 64 条斜线，而不是更多细粒度 issue。硬件上它仍然是 AND 后做 XOR 奇偶归并，没有引入 DSP，也没有普通整数乘法器。

### 2. 64 位叶子仍用 Karatsuba 分裂

64x64 乘法没有直接做大乘法器，而是分成三个 32x32 叶子：

```text
A = A0 + A1*x^32
B = B0 + B1*x^32

P0 = A0*B0
P1 = A1*B1
Pm = (A0 + A1)*(B0 + B1)

A*B = P0 + (P0 + P1 + Pm)*x^32 + P1*x^64
```

在二元域里，加法就是 XOR，所以这里的 `+` 全部是 XOR。V42 只是让每个 32x32 叶子更快地产生斜线奇偶结果，Karatsuba 的数学结构没有变。

### 3. 斜线 TAG 从宽槽号压成 1 bit

32 位打包以后，斜线槽只剩低半区和高半区两个选择。V42 把原来的多 bit 槽号压成 1 bit half tag，再在 top 层还原成 lane 需要的 `{half, 2'b00}`。

这个修改的意义是少让大范围控制位穿过顶层和 lane 边界。结果是 V42 的第一次 32 位打包尝试周期已经下降，但面积略高；压 TAG 后，面积降到 V41U 以下。

## ECC 当前计算原理

### 1. 二元域加法

当前曲线计算在 `GF(2^233)` 上。一个域元素就是 233 个 bit。二元域里每一位只有 0 和 1，所以加法不需要进位：

```text
c_i = a_i XOR b_i
```

这就是为什么 HDC 的绑定、相似度差分、ECC 模约减、ECC 斜线归并都能讲成同一类 XOR 资源复用。

### 2. 二元域乘法

乘法先看成多项式乘法：

```text
C_k = XOR over all i+j=k of (A_i AND B_j)
```

也就是说，第 `k` 个输出 bit 是一条斜线上的所有 `A_i & B_j` 的 XOR。硬件里的“斜线计算”就是按这个公式做：对齐 B，和 A 做 AND，然后规约 XOR 得到一个 bit。

V42 的 lane 一次算多个斜线 bit，本质仍然是这个公式，只是把多个 `k` 并排算出来。

### 3. 模约减

233 位曲线使用的二元域不可约多项式是：

```text
f(x) = x^233 + x^74 + 1
```

所以高位可以按下面的关系折回低位：

```text
x^233 = x^74 + 1
```

乘法得到的原始结果最高接近 466 位，需要把高于 232 的项折回。因为二元域加法是 XOR，模约减也就是若干移位后的 XOR。V41/V42 已经把这部分规约 XOR 放入 lane 的共享 XOR 路径，而不是在 lane 外保留 ECC 专属规约 XOR。

### 4. 标量点乘

点乘保持固定 233 bit 调度，不依赖标量是否有前导零，也不因为某一位是 0 就跳过计算。这样更适合安全实现，也方便做公平周期统计。

当前点乘使用 x/z 投影坐标，只跟 x 坐标和 z 坐标打交道。每个 bit 做一次差分点加和一次倍点：

点加的核心数据流是：

```text
T0 = X0 * Z1
T1 = X1 * Z0
T4 = T0 + T1
Zadd = T4^2
T6 = T0 * T1
T7 = Xp * Zadd
Xadd = T7 + T6
```

这里 `+` 是 XOR，平方在二元域里是插零再模约减，所以它很适合复用已有的 HSPREAD 和 lane 内规约 XOR。

倍点的核心数据流是：

```text
Xdbl = X^4 + Z^4
Zdbl = (X * Z)^2
```

因此当前两个最大周期来源很清楚：

| Counter | V42 cycles | Meaning |
| --- | ---: | --- |
| ST_ECC_DIAG | 96228 | 二元域乘法的斜线奇偶计算 |
| ST_ECC_LEAF_FOLD | 42768 | Karatsuba 叶子结果折叠进 128 位/256 位乘积布局 |
| ST_ECC_REDUCE | 11284 | 模约减 XOR 写回 |
| ST_HSPREAD | 3266 | 二元域平方前的 bit spread |
| ST_ECC_UOP | 4949 | 点加里的普通 XOR 微操作 |

## 验证结果

回归通过：

| Test | Result |
| --- | --- |
| xsim_ecc_diag_mul_v1 | PASS |
| xsim_ecc_reduce_v1 | PASS |
| xsim_hdc_full_flow_v20 | PASS |
| xsim_ecc_pmul_profile_v27 | PASS |

OOC 综合报告路径：

```text
reports/hdec/v42_slot1_tag_2026_06_17/ooc_v42_slot1_tag/reports/
```

关键 OOC 数据：

```text
Slice LUTs     = 6336
LUT as Logic   = 5864
LUT as Memory  = 472
Slice Registers= 2012
WNS            = 0.250 ns
Fmax estimate  = 210.526 MHz
```

## 不保留的实验

`waitissue` 尝试把斜线 flush 周期拿来发下一次 issue，PMUL 周期能降到 162409，但面积涨到 7259 Slice LUT。问题不是数学错误，而是 lane 输入和 VRF 周边 mux 被扩大，违背 V42 的面积目标。

`ADD Z direct` 尝试删掉点加最后一次 Z 拷贝，理论上可省约 932 周期，但 PMUL profile 结果错误，没有进入 checkpoint。

## V43 起点

V43 应该继续围绕两个大头做面积优先优化：

1. 斜线计算：保持 32 位打包收益，但避免 `waitissue` 那种扩大输入 mux 的做法。
2. 叶子折叠：减少 `ST_ECC_LEAF_FOLD` 周围的控制和选择网络，优先砍 LUT，周期可保持不变或小幅下降。

