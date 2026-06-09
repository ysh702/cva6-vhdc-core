# ECC V3 diagonal multiply reuse note

## 背景

当前 V3 分支从 V2 保存点开始：

- V2 tag: `vrf-control-fmax-over-200mhz`
- V2 branch: `hdec-ecc-vrf-control-v2`
- V3 branch: `hdec-ecc-diagonal-parallel-v3`

截至本文档创建时，V3 RTL 与 V2 RTL 相同，尚未开始新的 RTL 修改。

V2 已经解决了一个关键结构问题：VRF 命令先寄存一拍，避免未来 ECC 调度逻辑直接拖到 VRF LUTRAM 端口。V3 接下来要解决的是 ECC 二元域乘法的核心计算效率问题。

## 当前 ECC V1 乘法做法

当前 `HDEC_ECC_MUL` 实现的是 256-bit GF(2) 乘法的原始 diagonal/斜线形式。

对于输出位 `C[k]`：

```text
C[k] = parity(sum over i+j=k of A[i] & B[j])
```

硬件上当前做法接近：

```text
第 k 条斜线
-> 构造 B_window
-> A[255:0] & B_window[255:0]
-> 分成 4 个 64-bit lane
-> 复用现有 popcount slice
-> 取 popcount 结果最低位作为奇偶性
-> 写入 ecc_word_q[k % 64]
-> k = k + 1
```

也就是说，当前基本是“一次算一条完整斜线”。

## 必须保持的研究故事

V3 不应该新增一个独立的 ECC 专用 parity engine。

原因是项目的核心故事不是“给 HDEC 旁边外挂一个 ECC 乘法器”，而是：

```text
HDC 的 popcount / lane / VRF 硬件
也能被二元域 ECC 复用
```

所以 V3 的优化方向必须尽量保持：

- 继续复用 HDC lane。
- 继续复用 HDC popcount 相关硬件。
- 不另起一个独立 ECC 乘法 datapath。
- 让 ECC 成为 HDEC 内部共享算子调度的一个使用者。

## Boolean + Popcount slice 的含义

现有 popcount slice 更偏向 HDC 距离计算：

```text
HDC HSIM/HMATCH:
A XOR B -> popcount
```

ECC diagonal multiply 需要的是：

```text
ECC diagonal:
A AND B_window -> popcount -> 只取最低位 parity
```

所以 V3 中所谓 “Boolean + Popcount slice” 不是新增一个新乘法器，而是把现有 popcount slice 前面的布尔输入模式扩展成共享入口：

```text
mode = XOR:
    bool = A XOR B
    用于 HBIND / HSIM / HMATCH

mode = AND:
    bool = A AND B_window
    用于 ECC diagonal multiply

共同后端:
    bool -> popcount
```

这样 ECC 仍然讲得通为“复用 HDC popcount 硬件”，而不是“额外添加 ECC 专用硬件”。

## 关于 4 条斜线并行的边界

一条 256-bit 斜线最坏需要处理 256 个部分积。

当前 HDEC 一拍可用的 popcount 能力大约是：

```text
4 lane * 64 bit = 256 bit
```

所以在不复制 popcount 硬件的前提下，理论上很难做到“一拍完成 4 条完整斜线”。因为 4 条完整斜线最坏需要：

```text
4 * 256 bit = 1024 bit
```

这会要求大约 4 倍 popcount/boolean 处理能力。这样虽然快，但会偏离“复用 HDC 硬件”的主线。

因此 V3 第一阶段不应该追求一拍 4 条完整斜线，而应该先追求：

```text
不复制 popcount 的前提下
让现有 4 lane popcount 尽量每拍都被 ECC 使用
```

## V3 第一目标：ECC diagonal pipeline

当前 ECC V1 控制大致是：

```text
ISSUE -> WAIT -> ACCUM
```

直观理解：

- `ISSUE`：把第 k 条斜线送入 popcount。
- `WAIT`：等待 popcount slice 里的寄存结果。
- `ACCUM`：收集结果，写入 `ecc_word_q`，准备下一条斜线。

这会让 popcount 不是每拍都满载。

V3 第一目标是把它改成流水推进：

```text
第 1 拍：送入 k
第 2 拍：送入 k+1，同时收 k 的结果
第 3 拍：送入 k+2，同时收 k+1 的结果
第 4 拍：送入 k+3，同时收 k+2 的结果
...
```

这样不是一拍算多条斜线，而是让现有 popcount 硬件每拍都有新任务。

目标效果：

```text
从接近 3 拍 / 1 条斜线
优化到流水稳定后接近 1 拍 / 1 条斜线
```

这最符合“低面积增加 + 高硬件复用”的方向。

## V3 第二目标：4 diagonal in-flight batch

“4 条斜线在飞”容易误解。它不是：

```text
lane0 独立算完整 C[k]
lane1 独立算完整 C[k+1]
lane2 独立算完整 C[k+2]
lane3 独立算完整 C[k+3]
```

因为每个 lane 只有 64 bit，而一条完整斜线最坏需要 256 bit。那样每个 lane 只能算 1/4 条斜线，不完整。

更合理的意思是控制层面的 batch：

```text
连续 issue k, k+1, k+2, k+3
每条斜线仍然使用 4 lane 完整计算
结果按流水返回
最后打包进同一个 64-bit ecc_word
```

这样做的作用不是突破“1 拍 1 条斜线”的硬件上限，而是：

- 简化写回打包。
- 简化后续多项式乘法控制。
- 为将来更高并行度实验保留接口。
- 让 ECC 调度看起来像 HDC chunk pipeline，而不是孤立 FSM。

## 推荐 V3 实现顺序

### Step 1: 扩展 popcount slice 输入模式

给 popcount slice 增加一个布尔模式选择：

```text
XOR mode: bool = src_a ^ src_b
AND mode: bool = src_a & src_b
```

ECC 使用 AND mode，HSIM/HMATCH/HBIND 继续使用 XOR mode。

这一步应该尽量小心控制 mux 位置，避免重新制造 P2 关键路径。

### Step 2: ECC issue/result pipeline

增加 ECC 内部的 pending/result 对齐寄存器，例如：

```text
ecc_issue_valid_q
ecc_result_valid_q
ecc_k_pipe_q
```

让第 k 条斜线的结果回来的时候，还知道它对应哪个 `k`。

目标是取消明显的 `ISSUE -> WAIT -> ACCUM` 空泡，让 ECC 每拍都可以 issue 下一条斜线。

### Step 3: 结果打包

继续使用 64-bit `ecc_word_q` 打包输出位。

每收到一个斜线结果：

```text
ecc_word_q[k[5:0]] = parity
```

当 `k[5:0] == 63` 或 `k == 510` 时写回 VRF。

### Step 4: 保留 V2 VRF command boundary

V3 不应该绕开 V2 的 VRF command register。

ECC 写回仍然通过：

```text
vrf_we / vrf_wa / vrf_wd
-> vrf_we_q / vrf_wa_q / vrf_wd_q
-> VRF
```

这样后续标量点乘调度变复杂时，VRF 端口路径仍然被保护。

## 预期收益

在不复制 popcount 硬件的前提下：

- 主要收益来自去掉 ECC 控制空泡。
- ECC raw multiply 周期数预计明显下降。
- 理想情况下接近 1 条斜线 / cycle 的吞吐。
- LUT 增加应主要来自布尔 mode mux 和 ECC pipeline control。
- FF 增加应主要来自 `k` 对齐、valid 对齐和少量控制寄存器。

粗略预期：

| 项目 | 预期 |
|---|---:|
| ECC multiply cycle | 明显减少 |
| LUT | 小幅增加 |
| FF | 小幅增加 |
| BRAM/DSP | 不变，仍为 0 |
| Fmax | 目标保持 200 MHz 以上 |

## 不建议的方向

### 不建议 1：新增独立 ECC parity engine

虽然这会更快，但会削弱“复用 HDC popcount 硬件”的故事。

### 不建议 2：一上来做 4 条完整斜线/拍

这本质上需要约 4 倍 256-bit boolean/popcount 能力，面积和布线压力都会上来。

### 不建议 3：一上来做完整 scalar point multiplication FSM

标量点乘外层控制不是当前最大风险。最大风险是 GF(2) multiply 的吞吐、面积和时序。如果乘法核没有先定稳，完整标量点乘会把问题埋得更深。

## 下一步

V3 第一轮 RTL 应该只做：

```text
共享 Boolean + Popcount slice
ECC diagonal pipeline
```

先验证：

- ECC diagonal multiply 功能正确。
- OOC 200 MHz 仍然通过。
- LUT/FF 增加可控。
- HSIM/HMATCH/P2 popcount 路径没有被 mode mux 明显拖慢。

通过后，再考虑 4 diagonal in-flight batch 的控制整理，以及后续 Montgomery LD / ITA 标量点乘 FSM。
