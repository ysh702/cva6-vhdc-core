# V50 最佳面积节点记录

日期：2026-06-19

分支：`hdec-ecc-pointmul-v50-shared-mul-reduce`

最佳代码节点：

- `0bfb4fbb hdec: remove dead vrf request write enables`

## 最佳综合数据

该节点相对当前 V50 探索中后续控制清理尝试更稳，面积和时序如下：

| 项目 | 数值 |
| --- | ---: |
| PMUL 周期 | 190151 |
| Slice LUT | 5557 |
| Logic LUT | 5429 |
| LUTRAM | 128 |
| FF | 1715 |
| BRAM | 4 |
| DSP | 0 |
| CARRY4 | 15 |
| WNS | 0.244 ns |
| 估算频率 | 210.261 MHz |
| 最差路径终点 | `lane_result_q_reg[0][14]/D` |

## 本轮控制逻辑尝试结论

`try30_lane_shell_slim` 删除了 lane 外壳里已经不用的老端口和若干常量 tie-off，仿真通过，周期不变，但 OOC 面积完全不变：

| 尝试 | PMUL 周期 | Slice LUT | Logic LUT | LUTRAM | FF | WNS | 结论 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `0bfb4fbb` 基线 | 190151 | 5557 | 5429 | 128 | 1715 | 0.244 ns | 当前最佳 |
| `try30_lane_shell_slim` | 190151 | 5557 | 5429 | 128 | 1715 | 0.244 ns | 无面积收益，未保留到 RTL |

判断：这些老端口虽然在源码里存在，但 Vivado 已经能把常量和未使用逻辑优化掉，所以继续沿这个方向压控制壳层，很难得到大幅面积下降。

## 后续更可能的大面积方向

1. 算法级降低 ECC 斜线并行度：减少每周期 lane 内 AND/XOR 斜线项数量，用更多周期换更小算子。这个方向最可能降低真实计算 LUT，但会增加 PMUL 周期，需要用周期和面积共同评估。
2. product scratch 存储结构重做：当前 128 LUTRAM 不是最大头，但它是 ECC 乘法/约减路径的独立暂存。直接换 FF 历史上会变差，更值得尝试的是按调度流式化或借 VRF/BRAM 节拍做读改写。
3. VRF 周边入口瘦身：`i_vrf` 仍是最大层级之一，但前几轮直接加 tag 或换写数据选择方式会把 128 位 mux 做大。后续应从“减少写入口来源数量/状态气泡复用”入手，而不是再包一层选择器。

当前保存策略：保留 `0bfb4fbb` 作为 V50 面积最佳可回退代码节点；`try30_lane_shell_slim` 只保存 patch 和报告证据，不并入 RTL。
