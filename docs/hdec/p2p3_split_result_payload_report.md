# HDEC P2-P3 Split Result Payload Optimization Report

## 1. 修改背景

本次优化基于 Seven-Souls unified uop pipeline 架构。该架构把主要 HDC compute 指令统一到 P1/P2/P3/P4 uop 流水中，保持控制流集中、指令协议稳定，并在 P2 到 P3 之间使用 lane payload register 切断组合路径。

基准版本为：

- Base branch: `hdec-seven-souls-vmware-regression-v1`
- Base commit: `8f8774e9 test: refresh HDEC regression for VADDR protocol baseline`
- RTL base: `9f2485fc hdec: migrate HDC ops to unified uop pipeline`
- Baseline Verilator regression: 20/20 PASS

本次优化分支为：

- Optimized branch: `hdec-p2p3-split-result-payload-v1`
- Optimized commit: `ec561b73 hdec: split narrow P2 payload registers`
- Remote branch: `origin/hdec-p2p3-split-result-payload-v1`

优化目标是改善 P2 到 P3 阶段的时序路径，降低 `lane_result_q` 统一宽结果寄存器入口处的 mux、zero-extension 和 control fanout 压力。在不改变指令协议、不改变 uop pipeline 节拍、不增加 cycles 的前提下，尝试提升 FPGA Fmax，并为后续 Vivado OOC 对比约 134 MHz 到 200 MHz 目标做准备。

## 2. 原始问题分析

修改前，`lane_result_q/lane_result_n` 是统一的 `4 x 64-bit` P2-P3 payload register。不同指令在 P3 中按 `uop_p3_q.op_type` 解释同一个物理寄存器：

| 指令类别 | 实际 payload 需求 | 修改前承载方式 |
|---|---:|---|
| HBIND | 每 lane 64-bit XOR result | `lane_result_q[4][64]` |
| HPERM | 每 lane 64-bit shift-align result | `lane_result_q[4][64]` |
| HCNTADD | 每 lane 64-bit packed counter result | `lane_result_q[4][64]` |
| HSIM/HMATCH | 每 lane 7-bit popcount | zero-extend 后写入 `lane_result_q[4][64]` |
| HCNTCLIP | 每 lane 16-bit clip bits | zero-extend 后写入 `lane_result_q[4][64]` |

这种写法功能上正确，但对 FPGA 综合和布线不一定友好。7-bit popcount 被扩展成 64-bit，16-bit clip 被扩展成 64-bit，不同位宽 payload 共用同一个 4 x 64-bit 寄存器入口。Vivado 可能在 P2 结果寄存器 D 端生成较宽的 mux、zero-extension 和 priority selection 逻辑。控制信号也可能被迫驱动更多无意义的高位选择，造成 high fanout 和 routing delay。

这与当前 OOC 观察到的现象一致：逻辑延迟占比较低、布线延迟占比较高、高扇出控制信号较多。需要注意的是，这并不说明 `lane_result_q` 一定是唯一瓶颈；它只是一个明确、局部、低风险的优化点。最终 timing 效果仍需要 Vivado OOC 验证。

## 3. 本次修改内容

本次只修改：

- `core/hdec/rtl/hdec_top.sv`

没有修改：

- `core/hdec/rtl/hdec_pkg.sv`
- `core/hdec/rtl/hdec_cvxif_wrapper.sv`
- `core/hdec/rtl/hdec_vrf_64x256.sv`
- lane compute modules
- `corev_apu/src/ariane.sv`
- 指令编码
- VADDR/VWR64/VRD64 协议
- TAG/USE 控制语义
- pipeline stage 数量

新增和保留的 P2-P3 payload register 如下：

| Register | Width | 用途 |
|---|---:|---|
| `lane_result_q/lane_result_n` | `4 x 64-bit` | 保留，只用于真正需要 64-bit payload 的 HBIND、HPERM、HCNTADD 等操作 |
| `lane_popcnt_q/lane_popcnt_n` | `4 x 7-bit` | 新增，用于 HSIM/HMATCH 的 lane-local popcount payload |
| `lane_clip_q/lane_clip_n` | `4 x 16-bit` | 新增，用于 HCNTCLIP 的 lane-local clip payload |

P2 阶段修改：

- `use_popcount` 时，只写 `lane_popcnt_n`，不再写 zero-extended `lane_result_n`。
- `use_clip` 时，只写 `lane_clip_n`，不再写 zero-extended `lane_result_n`。
- `use_counter` 时，继续写 `lane_result_n`。
- `use_shift` 时，继续写 `lane_result_n`。
- XOR/vector result 继续写 `lane_result_n`。
- reset 清零。
- 默认 hold。
- 不新增 pipeline stage。

P3 阶段修改：

- HSIM/HMATCH 直接读取 `lane_popcnt_q`。
- HCNTCLIP 直接读取 `lane_clip_q`。
- HBIND/HPERM/HCNTADD 继续读取 `lane_result_q`。
- 不在 P3 重新构造统一大 payload mux。

## 4. 修改前后数据通路对比

修改前：

```text
P2 lane result selection
  popcount -> zero extend to 64-bit
  clip     -> zero extend to 64-bit
  vector   -> 64-bit
  counter  -> 64-bit
  shift    -> 64-bit
        |
        v
  lane_result_q[4][64]
        |
        v
P3 consume lane_result_q
```

修改后：

```text
P2 popcount
        |
        v
  lane_popcnt_q[4][7]
        |
        v
P3 HSIM/HMATCH

P2 clip
        |
        v
  lane_clip_q[4][16]
        |
        v
P3 HCNTCLIP

P2 vector/counter/shift/xor
        |
        v
  lane_result_q[4][64]
        |
        v
P3 HBIND/HPERM/HCNTADD
```

对比表：

| Payload 类型 | 修改前 | 修改后 |
|---|---|---|
| popcount | `{57'b0, popcount[6:0]}` 写入 `lane_result_q` | `popcount[6:0]` 写入 `lane_popcnt_q` |
| clip | `{48'b0, clip[15:0]}` 写入 `lane_result_q` | `clip[15:0]` 写入 `lane_clip_q` |
| 64-bit vector/counter/shift/xor | 写入 `lane_result_q` | 继续写入 `lane_result_q` |
| P3 消费 | 全部分支从 `lane_result_q` 取数 | 各分支直接读取对应 payload register |

## 5. 预期收益

### Timing

本次优化预期减少 P2 结果寄存器入口处的宽 mux、zero-extension 和 routing 压力。如果原 critical path 或 high fanout 的主要来源确实与 `lane_result_n` 统一选择网络有关，则可能带来：

- WNS 改善；
- Fmax 提升；
- P2-P3 payload path 缩短；
- high fanout nets 数量或 fanout 数下降；
- routing delay 占比降低。

但如果 Vivado 报告中的 high fanout 主要来自 uop next-state 或 P3 global control，而不是 `lane_result` mux，则本优化可能只能改善一部分。最终是否达到 200 MHz 需要 Vivado OOC 验证。

### Area

预期 FF 增加：

- `lane_popcnt_q`: `4 x 7 = 28 FF`
- `lane_clip_q`: `4 x 16 = 64 FF`
- 合计理论新增约 `92 FF`

LUT 预期：

- 由于减少 64-bit 统一结果 mux 和窄数据 zero-extension 选择，LUT 有机会下降；
- 如果综合器本来已经充分优化常量高位，LUT 可能只是小幅变化；
- 如果控制 hold/enable 逻辑带来额外开销，也可能出现小幅 LUT 增加；
- 最终以 Vivado utilization report 为准。

### Latency / Cycles

本次修改不增加 pipeline stage，不改变 P1/P2/P3/P4 节拍，理论上不增加 cycles。Verilator 20/20 PASS 说明当前软件可见功能行为保持一致。

## 6. 功能验证结果

当前验证结果：

- `make verilate NUM_JOBS=16`: PASS
- Verilator regression: 20/20 PASS
- `git diff --check`: PASS / no output
- 初次沙箱 testharness 因 `remote_bitbang failed to make socket: Operation not permitted` 失败，属于环境权限问题；脱沙箱后回归通过。
- 未跟踪 `verif/core-v-verif` 未加入提交。

回归覆盖类别：

- VRF smoke tests；
- VADDR/VWR bank tests；
- HCLR/HCNTCLR/HCNTADD/HCNTCLIP/HBIND/HPERM/HSIM/HMATCH 算子测试；
- pipeline/inference/e2e 集成测试。

本次 20/20 回归测试清单：

| # | Test | Result |
|---:|---|---|
| 1 | `min_test_current_protocol` | PASS |
| 2 | `vrw_current_protocol_test` | PASS |
| 3 | `va_test` | PASS |
| 4 | `va4_test` | PASS |
| 5 | `multi_index_test` | PASS |
| 6 | `bank0_test` | PASS |
| 7 | `bank1_test` | PASS |
| 8 | `bank2_test` | PASS |
| 9 | `bank3_test` | PASS |
| 10 | `hclr_test` | PASS |
| 11 | `hcntclr_test` | PASS |
| 12 | `hcntadd_test` | PASS |
| 13 | `hcntclip_test` | PASS |
| 14 | `hbind_test` | PASS |
| 15 | `hperm_test` | PASS |
| 16 | `hsim_test` | PASS |
| 17 | `hmatch_test` | PASS |
| 18 | `hdc_pipeline_test` | PASS |
| 19 | `hdc_inference_test` | PASS |
| 20 | `hdc_e2e_train_infer_test` | PASS |

## 7. 潜在风险

1. Timing 风险：
   - 如果真实高扇出来自 `uop_p3_n` / uop control 本身，而不是 `lane_result` mux，本次优化可能不足以达到 200 MHz。
   - 后续可能还需要 stage-local control 或 control fanout replication。

2. P3 新 mux 风险：
   - 如果后续修改中又把 `lane_popcnt_q`、`lane_clip_q`、`lane_result_q` 合并成统一 payload mux，会重新引入大 mux。
   - 当前实现应保持 P3 各分支直接读取对应 payload。

3. 数据错拍风险：
   - `uop_p3_q` 必须和 `lane_result_q/lane_popcnt_q/lane_clip_q` 同拍对齐。
   - 当前 Verilator 回归已覆盖，但后续修改仍需注意。

4. 面积风险：
   - FF 理论增加约 92。
   - LUT 是否下降不保证。
   - 需要 Vivado `report_utilization` 验证。

5. 功耗风险：
   - 默认 hold 可以降低无意义翻转。
   - 但新增寄存器仍可能带来少量时钟翻转开销。
   - 后续可以通过 power report 评估。

6. 适用范围风险：
   - 本优化只处理 P2-P3 payload split。
   - 不处理 VRF operand capture。
   - 不处理 TAG/USE 语义压缩。
   - 不处理 banked VRF。
   - 不处理 Query/Prototype 分区。

## 8. 后续 Vivado OOC 验证计划

后续需要在 Windows/Vivado 或指定 OOC 环境中对比：

Baseline:

- Branch: `hdec-seven-souls-vmware-regression-v1`
- Commit: `8f8774e9`

Optimized:

- Branch: `hdec-p2p3-split-result-payload-v1`
- Commit: `ec561b73`

需要记录：

| Metric | Baseline 8f8774e9 | Optimized ec561b73 | Delta | Comment |
|---|---:|---:|---:|---|
| Fmax | | | | |
| WNS @ target clock | | | | |
| LUT | | | | |
| FF | | | | |
| High fanout max | | | | |
| Critical path start | | | | |
| Critical path end | | | | |
| Logic delay % | | | | |
| Routing delay % | | | | |

重点判断：

- 是否从约 134 MHz 接近 200 MHz；
- high fanout 是否明显下降；
- P2-P3 path 是否仍是 worst path；
- LUT 是否下降或小幅变化；
- FF 是否接近 +92；
- 是否出现新的关键路径。

## 9. 结论

本次修改是一个局部、低风险、功能等价的 P2-P3 payload physical split 优化。它保持 Seven-Souls 统一 uop pipeline 控制流不变，只拆分不同宽度 lane result payload 的物理寄存器承载方式，目的是减少不必要的 zero-extension mux 和控制扇出，从而改善 FPGA 布线时序。

Verilator 20/20 PASS 证明当前功能行为未被破坏。最终 timing 和 area 收益需要 Vivado OOC 进一步验证，尤其需要关注 Fmax、WNS、high fanout nets、LUT、FF、critical path 起点/终点以及 routing delay 占比。
