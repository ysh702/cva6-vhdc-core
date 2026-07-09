# VV22 下一步计划：VRF / payload lifetime / writeback fan-in 结构优化

## 结论先行

ECC 和 HDC 共享同一套存储是一条很好的论文叙事，但必须说得准确：

```text
HDEC 不是把 HDC accelerator 和 ECC accelerator 并排放在一起，
而是在同一个 CV-X-IF accelerator 内复用同一套 VRF、4x64 packet 表示、
payload 写回路径、bit-matrix row tile 和 XOR0 packet accumulator。
```

这比单纯说“共享计算单元”更强，因为分立实现里 HDC 与 ECC 往往各自需要一套接口壳、寄存器状态、临时数据存储和写回路径。VV22 的 wrapper-level 对比已经证明：

| Configuration | Logic LUT | FF | BRAM | DSP |
|---|---:|---:|---:|---:|
| Full HDEC + CV-X-IF wrapper | 4836 | 1610 | 4 | 0 |
| Standalone HDC + CV-X-IF wrapper | 2458 | 1150 | 4 | 0 |
| Standalone ECC + CV-X-IF wrapper | 3482 | 1385 | 4 | 0 |
| Standalone HDC + standalone ECC | 5940 | 2535 | 8 | 0 |

因此 HDEC 相比两个分立加速器节省：

```text
1104 Logic LUT
925 FF
4 BRAM
```

其中 `4 BRAM` 的节省尤其适合作为“真实复用”的证据：HDEC 保留一套共享 VRF / packet storage，而不是给 HDC 和 ECC 各自复制一套局部存储。

## 需要避免的错误表述

不要把共享存储说成“ECC 完全没有私有逻辑”。VV22 目前严格记录的 ECC-only area 是：

```text
ECC-only area = about 608 Logic LUT equivalent
ECC-only FF   = 413 FF
```

这部分包括 ECC PMUL/job/field control 与 ECC matrix/folding integration，因为 HDC 不使用这些逻辑。

也不要暗示 HDC 与 ECC 可以同时无冲突地并发访问同一块 VRF。当前更准确的说法是：

```text
同一个 accelerator 指令流下，HDC 和 ECC 以统一 4x64 packet 数据结构
复用同一套 VRF/packet 存储和写回路径。
```

也就是说，这是结构复用和时间复用，不是两个独立 accelerator 的并行多租户存储。

## 为什么下一步应转向 VRF / payload lifetime / writeback fan-in

VV14 到 VV22 已经围绕 diagonal product、folding、pair-token、row tile 做了大量工作。继续在 folding 旁路上局部压缩，容易出现两个问题：

1. 面积收益变小。
2. 容易重新长出 ECC-only 旁路逻辑，削弱真实复用故事。

下一轮更值得打穿的是：

```text
结果在 4x64 packet / VRF 里怎么活
payload 什么时候需要保留
哪些 lane 真正需要进入写回 mux
ECC 的临时值是否可以复用 HDC 已有 packet lifetime
```

这条路线的价值在于：它不需要新增 ECC 计算单元，也不改变统一数据结构，却可能同时降低面积、降低写回扇入、减少控制壳选择器，并进一步强化“ECC 是跑在 HDC bit-matrix substrate 上”的论文故事。

## 硬约束

下一轮 RTL probe 必须满足：

- 不破坏真实复用：继续使用同一套 VRF、4x64 packet、bit-matrix row tile、payload packet 和 XOR0 accumulator。
- 不破坏统一数据结构：ECC 中间结果不能退回独立 233/466-bit datapath。
- 不新增独立 ECC BRAM、ECC accumulator、ECC row tile 或 ECC-only wide datapath。
- `PMUL_PROFILE_WALL_CYCLES <= 189412`。
- `PMUL_PROFILE_GF_MUL_STARTS == 1188`。
- `PMUL_PROFILE_SUB_ZERO_CYCLES == 0`。
- `Fmax_est >= 200 MHz`。
- 面积不增加；优先目标是 hdec_top 级别进入 `< 4700 Logic LUT`，wrapper 级别继续记录。

## Probe A：VRF lifetime map

先不改 RTL，先做一张生命周期表，枚举 PMUL 中所有长期存在的 packet：

| Class | Example | Lifetime question | Optimization target |
|---|---|---|---|
| HDC vector packet | normal HDC src/dst | 是否和 ECC 临时寄存器共享同一写回 mux | 不扩大 HDC fast path |
| ECC field operand | x/z/t/u/v style packet | 是否只需要 4x64 packet 视图 | 不引入 233-bit side storage |
| ECC product/fold token | diagonal/pair/fold packet | 是否可以短生命周期流过 XOR0 | 减少保留寄存器与选择器 |
| PMUL scalar/control token | scalar bit / step state | 是否进入数据写回路径 | 避免污染 payload mux |

输出物：

```text
reports/hdec/<next>/VV23_vrf_lifetime_map_cn.md
```

接受标准：

- 明确哪些值必须落 VRF。
- 明确哪些值只是短生命周期 payload token。
- 明确哪些 mux 是由“过长 lifetime”导致的。

## Probe B：payload lifetime 收缩

目标不是减少 packet 数据结构，而是减少 packet 被保存、被选择、被写回的时间。

候选方向：

1. 把 ECC fold-token 尽量限制在 XOR0 accumulation 窗口内。
2. 将只用于下一拍的 packet 标记为 transient token，不进入长期 payload mux。
3. 保持最终 VRF writeback 不变，避免破坏 `dst == src` alias 语义。
4. 对 HPERM/HBIND 类 HDC 路径保持原语义，不为了 ECC 改坏 HDC。

预期收益：

```text
减少 payload_q / hdc_src*_q / writeback select 周围的选择器 LUT
降低 top shell 和 i_vec 的边界 glue
```

风险：

```text
如果综合器因为 token 分类生成更多 mux，立即回退。
```

## Probe C：writeback fan-in 收窄

当前值得审计的是“谁有资格写回 VRF / payload”。

候选方向：

1. 将 ECC-only writeback case 和 HDC writeback case 拆成 lane-local enable，而不是共享一个大动态选择器。
2. 对永远不会由 ECC 写入的 packet lane 做静态屏蔽。
3. 对只在 PMUL terminal 阶段写回的字段，避免进入普通 HDC 每拍写回选择。
4. 保持一个统一 VRF writeback 端口语义，不新增 ECC 私有写回端口。

接受标准：

```text
Logic LUT 下降
FF 不明显上升
PMUL cycle 不增加
HDC full-flow PASS
ECC PMUL profile PASS
```

## Probe D：shared-storage 证据增强

这一步是论文证据，不一定改 RTL。

建议补充两张图：

1. `Standalone HDC + Standalone ECC` 图：

```text
CVA6 -> CV-X-IF HDC shell -> HDC VRF -> HDC compute
CVA6 -> CV-X-IF ECC shell -> ECC VRF -> ECC compute
```

2. `HDEC` 图：

```text
CVA6 -> one CV-X-IF HDEC shell
          -> one shared VRF / 4x64 packet storage
          -> shared bit-matrix row tile
          -> shared XOR0 packet accumulator
          -> small ECC-only PMUL/control/folding integration
```

这两张图可以直接解释为什么分立实现是 `8 BRAM`，而 HDEC 是 `4 BRAM`。

## 推荐执行顺序

1. 在 VV22 上保留当前测量与文档，不继续修改 RTL。
2. 新建 VV23，只做 `VRF lifetime map + writeback fan-in` 一个结构方向。
3. 第一轮 RTL probe 只动 `hdec_lane_4x64.sv` 与必要的 `hdec_top.sv` glue。
4. 每个候选都跑：

```text
HDC full-flow simulation
ECC PMUL profile
Vivado OOC 5 ns
hierarchy / name-bucket diff
```

5. 如果 `< 4700 Logic LUT` 且周期不增，保留为 VV23 checkpoint。
6. 如果三轮候选都无法下降，停止 RTL 微调，转向论文证据整理，不继续消耗时间。

## 论文表述建议

推荐表述：

```text
HDEC amortizes the storage and packet datapath cost of HDC and ECC by mapping
both workloads onto a unified 4x64 packet VRF and shared bit-matrix execution
substrate. Compared with two standalone CV-X-IF accelerators, HDEC avoids a
second VRF and interface shell, reducing the standalone total by 1104 Logic LUT,
925 FF, and 4 BRAM, while the ECC-private logic inside HDEC is limited to about
608 Logic-LUT equivalent.
```

中文论文表述：

```text
HDEC 的关键并不是把一个 ECC 加速器简单挂到 HDC 旁边，而是让 ECC 的域运算
以统一 4x64 packet 形式进入 HDC 已有的 VRF、bit-matrix row tile 与 XOR0
累加路径。相比 HDC/ECC 两个分立 CV-X-IF 加速器，HDEC 避免复制第二套
VRF 和接口壳，节省 1104 Logic LUT、925 FF 和 4 BRAM；同时 HDEC 内严格
ECC-only 逻辑约为 608 Logic-LUT equivalent。
```

## 最终判断

下一轮最值得做的不是继续扩大 diagonal pair，也不是重新加 direct folding packet，而是打穿：

```text
VRF lifetime
payload transient token
writeback fan-in
```

这条路线最符合当前硬约束：

```text
面积下降
周期不增加
真实复用更强
统一数据结构不破坏
不新增 ECC 独立计算资源
```

