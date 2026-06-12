# V24 ECC 面积占比再拆账

## 目的

上一版 V24 报告用 `V23 HDC+ECC - V24 仅 HDC` 得到 ECC 增量：

- +2168 LUT
- +2040 Logic LUT
- +128 LUTRAM
- +267 FF

这个数字是“加入 ECC 后总设计多出来多少资源”，但不等于“ECC 独占了多少计算资源”。因为当前设计的目标本来就是 ECC 复用 HDC 的 VRF、HPERM、popcount、XOR 等资源，Vivado 会把一部分共享接入 mux/control 归到 VRF 或 lane 层级里。

所以本文件重新拆账，把增量分成三类：

- ECC 硬独占资源：只有 ECC 会用，HDC 不需要。
- 共享接入代价：HDC 原本有这个硬件，但为了让 ECC 也能复用，新增了选择、地址、写回、调度控制。
- Vivado 重映射差异：同一类硬件在两个版本中的映射变化，不应简单归为 ECC 专属面积。

## 总量不变

| 指标 | V24 仅 HDC | V23 HDC+ECC | 物理增量 |
|---|---:|---:|---:|
| LUT | 4090 | 6258 | +2168 |
| Logic LUT | 3746 | 5786 | +2040 |
| LUTRAM | 344 | 472 | +128 |
| FF | 1846 | 2113 | +267 |
| CARRY4 | 16 | 20 | +4 |

## 层级报告再解释

Vivado `report_utilization -hierarchical` 的直接差值：

| 层级/桶 | V24 仅 HDC LUT | V23 HDC+ECC LUT | 增量 | 重新归因 |
|---|---:|---:|---:|---|
| top/control/local memory | 401 | 1252 | +851 | 主要是 ECC 控制、job 状态、product LUTRAM、点乘/求逆/约减调度 |
| i_vrf | 1796 | 3105 | +1309 | VRF 存储本体是 HDC 资源；这部分更像 ECC 复用 VRF 带来的读写 mux/control 接入代价 |
| P2 popcount slices total | 1130 | 1018 | -112 | popcount 本体属于 HDC，共享后没有面积增长；负值是 Vivado 重映射差异 |
| lane shift/align total | 763 | 883 | +120 | HPERM 基础属于 HDC；增量来自 ECC 平方/对齐复用造成的 1-bit shift 接入压力 |
| lane shift + popcount 合计 | 1893 | 1901 | +8 | 共享计算算子本体几乎没有增加 |

## Cell bucket 近似分桶

为了避免只看层级名误判，我又跑了一次综合网表 cell bucket 统计。这个统计不是精确 Slice LUT 口径，而是按 cell 名称和层级粗分，用来判断资源性质。

| Bucket | V24 仅 HDC LUT cells | V23 HDC+ECC LUT cells | Delta LUT cells | Delta FF | Delta RAM cells | 判断 |
|---|---:|---:|---:|---:|---:|---|
| explicit_ecc_named | 0 | 1166 | +1166 | +267 | +256 | 明确 ECC 命名逻辑，属于 ECC 硬独占或强 ECC 控制 |
| vrf_hierarchy_or_mux | 2513 | 3703 | +1190 | 0 | 0 | VRF 本体是 HDC 资源，增量主要是 ECC 接入 VRF 的 mux/control |
| hperm_shift_shared | 796 | 1251 | +455 | -7 | 0 | HPERM 是 HDC 资源，但 1-bit 泛化和 ECC square/spread 复用带来额外选择 |
| p2_popcount_shared | 663 | 988 | +325 | 0 | 0 | 名称分桶显示增加，但 hierarchy 汇总反而减少；这里更适合视为 Vivado 重映射和共享接入，不是新增 ECC popcount |
| top_control_or_other | 361 | 560 | +199 | +14 | 0 | 顶层控制混合区，包含 HDC/ECC mux 和状态选择 |
| lane_shared_other | 3 | 4 | +1 | 0 | 0 | 可忽略 |

注意：`LUT cells` 和 Vivado `Slice LUT/Logic LUT` 不是同一个计数方式，不能直接相加替代最终利用率表。它的价值是看“资源落在哪类名字和层级下面”。

## 更合理的叙述口径

### 口径 A：严格物理增量

这是最保守、最严格的说法：

| 指标 | ECC 增量 | 占 HDC+ECC 总量 |
|---|---:|---:|
| LUT | +2168 | 34.6% |
| Logic LUT | +2040 | 35.3% |
| LUTRAM | +128 | 27.1% |
| FF | +267 | 12.6% |

这个口径适合说明“加入 ECC 后芯片总面积多了多少”。

### 口径 B：ECC 硬独占资源

如果把 HDC 本来就用得上的 VRF、popcount、HPERM 基础算子回归 HDC，只把明确 ECC 控制和 ECC product storage 算作 ECC 硬独占，则大致为：

| 指标 | ECC 硬独占估算 | 占 HDC+ECC 总量 |
|---|---:|---:|
| LUT | 约 +851 | 约 13.6% |
| Logic LUT | 约 +723 | 约 12.5% |
| LUTRAM | +128 | 27.1% |
| FF | +267 | 12.6% |

这个口径更适合讲“ECC 独立增加了多少专属硬件”。

### 口径 C：共享接入代价

剩下的大头不是独立 ECC 算子，而是为了复用 HDC 资源产生的接入网络：

| 类别 | Logic LUT 估算 | 说明 |
|---|---:|---|
| VRF 共享接入 | 约 +1309 | ECC 复用 HDC VRF 后，地址、写使能、写数据和状态选择变复杂 |
| HPERM/shift 共享接入 | 约 +120 | HDC HPERM 基础算子升级后也服务 ECC square/spread |
| popcount/重映射 | 约 -112 到 +325 | 不是新增 ECC popcount，主要是映射和接入方式变化 |

## 最重要结论

当前 `+2040 Logic LUT` 不应该全部被叙述成 ECC 独占面积。

更准确的说法是：

- ECC 硬独占 Logic LUT 大约是 723 左右，占总 Logic LUT 约 12.5%。
- ECC 让共享资源接入网络多出来约 1300 到 1500 Logic LUT，这是真实总面积增量，但不是独立 ECC 算子。
- popcount 本体、VRF 存储本体、HPERM 基础算子都可以算 HDC 资源；ECC 是复用这些资源。
- 目前最需要优化的是 ECC 接入 VRF/HPERM/popcount 的控制网络，而不是 popcount 计算本体。

## V25 优化方向

V25 应专门压 ECC 资源占比，不做泛泛的 HDC 全局优化：

1. 把 ECC 对 VRF 的读写接入改得更像 HDC uop，减少特化 mux。
2. 减少 ECC job/phase/subop 状态寄存器和宽 case 控制。
3. 把 ECC product/reduction 临时路径并入已有 HDC 数据搬运节奏，减少 ECC-only local storage。
4. 继续保持 popcount、XOR、HPERM 作为共享算子，不额外复制专用 ECC engine。
5. 每轮 OOC，四轮后跑 ECC/HDC xsim 和周期检查。
