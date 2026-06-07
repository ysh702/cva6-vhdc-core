# HDEC P2 popcount local KEEP V1 OOC 综合报告

## 1. 本次范围

本分支用于固定当前 P2 popcount local control 修复版，作为后续 HMATCH 优化前的新基线。

- 基线分支：`origin/hdec-p2-popcount-microtag-p1`
- 基线提交：`9f1142cfed4e99a894c486368107b6bd3785d22b`
- RTL 修改文件：`core/hdec/rtl/hdec_p2_pop_slice.sv`
- Vivado：2024.2
- FPGA part：`xc7z020clg400-2`
- Top：`hdec_top`
- 综合模式：`synth_design -mode out_of_context`
- 时钟约束：`5.000 ns`
- RTL 仿真：未运行

原始 OOC 证据放在：

`docs/hdec/ooc/p2_popcount_local_keep_v1/`

复现用 Tcl 放在：

- `scripts/hdec/ooc_hdec_p2_popcount_local_keep_v1.tcl`
- `scripts/hdec/query_hdec_p2_pop_path.tcl`

## 2. RTL 修改内容

上一版 P2 popcount microtag 已经把 `pop_q/xor_q` 放进 lane slice，但 Vivado 仍然把 4 个 lane 的等价寄存器合并成 1 份 shared register。本次修复只做窄范围保护，并移除 `pop_q/xor_q` 对 64-bit 数据路径的门控。

修改 1：只保护 lane slice 内的本地控制寄存器。

```systemverilog
(* keep = "true", dont_touch = "true", equivalent_register_removal = "no" *)
logic pop_q;

(* keep = "true", dont_touch = "true", equivalent_register_removal = "no" *)
logic xor_q;
```

修改 2：去掉 `pop_q/xor_q` 对 64-bit 输入和 popcount diff 的 gating。

```systemverilog
assign bool_src_a = src_a_i;
assign bool_src_b = src_b_i;
...
.diff_i(bool_result)
```

现在 `pop_q` 只作为每个 lane 内部的 popcount capture enable，不再进入 64-bit boolean mux 或 popcount 数据输入锥。

## 3. 关键结论

本版本解决了 P2 fanout/timing 问题。

- Vivado 保留了 4 份 `pop_q_reg`，每个 lane 一份。
- Vivado 保留了 4 份 `xor_q_reg`，每个 lane 一份。
- 每个真实 `pop_q/Q` 扇出为 8，且局限在本 lane。
- 每个真实 `xor_q/Q` 扇出为 1，且局限在本 lane。
- 旧的跨 lane P2 数据关键路径 `pop_q -> popcount_q_o/D` 已不存在。
- 当前全局关键路径已转移到 P3 HMATCH best-distance update enable。

## 4. 时序和资源对比

| 指标 | 原 P1 microtag | Local KEEP V1 | 变化 |
|---|---:|---:|---:|
| WNS | -1.930 ns | -1.541 ns | +0.389 ns |
| TNS | -99.512 ns | -80.836 ns | +18.676 ns |
| 失败 setup endpoints | 316 | 312 | -4 |
| 保守 Fmax | 144.300 MHz | 152.882 MHz | +8.582 MHz |
| Slice LUT | 5001 | 4918 | -83 |
| Logic LUT | 4313 | 4230 | -83 |
| LUTRAM | 688 | 688 | 0 |
| FF | 2184 | 2190 | +6 |
| CARRY4 | 11 | 11 | 0 |
| BRAM | 0 | 0 | 0 |
| DSP | 0 | 0 | 0 |

FF 增加 6 个符合预期：原网表只保留了 1 个 `pop_q` 和 1 个 `xor_q`，本版本保留 4+4 份本地寄存器，因此净增 6 个 FF。

LUT 减少 83 个，主要来自移除 `pop_q/xor_q` 对 64-bit 数据路径的宽门控，少了一批 mux/gating 逻辑。

## 5. 当前最长 10 条路径

最长路径都属于同一类 HMATCH best-distance update-enable cone，只是落到 `hmatch_best_dist_q[10:0]` 的不同比特。

| Rank | 小白版路径名 | 从哪里来 | 到哪里去 | Delay | Logic | Route | Slack | 保守 Fmax |
|---:|---|---|---|---:|---:|---:|---:|---:|
| 1 | HMATCH 当前距离到最佳距离 bit0 写使能 | 当前累计距离 | 最佳距离 bit0 CE | 6.330 ns | 3.206 ns | 3.124 ns | -1.541 ns | 152.882 MHz |
| 2 | HMATCH 当前距离到最佳距离 bit10 写使能 | 当前累计距离 | 最佳距离 bit10 CE | 6.330 ns | 3.206 ns | 3.124 ns | -1.541 ns | 152.882 MHz |
| 3 | HMATCH 当前距离到最佳距离 bit1 写使能 | 当前累计距离 | 最佳距离 bit1 CE | 6.330 ns | 3.206 ns | 3.124 ns | -1.541 ns | 152.882 MHz |
| 4 | HMATCH 当前距离到最佳距离 bit2 写使能 | 当前累计距离 | 最佳距离 bit2 CE | 6.330 ns | 3.206 ns | 3.124 ns | -1.541 ns | 152.882 MHz |
| 5 | HMATCH 当前距离到最佳距离 bit3 写使能 | 当前累计距离 | 最佳距离 bit3 CE | 6.330 ns | 3.206 ns | 3.124 ns | -1.541 ns | 152.882 MHz |
| 6 | HMATCH 当前距离到最佳距离 bit4 写使能 | 当前累计距离 | 最佳距离 bit4 CE | 6.330 ns | 3.206 ns | 3.124 ns | -1.541 ns | 152.882 MHz |
| 7 | HMATCH 当前距离到最佳距离 bit5 写使能 | 当前累计距离 | 最佳距离 bit5 CE | 6.330 ns | 3.206 ns | 3.124 ns | -1.541 ns | 152.882 MHz |
| 8 | HMATCH 当前距离到最佳距离 bit6 写使能 | 当前累计距离 | 最佳距离 bit6 CE | 6.330 ns | 3.206 ns | 3.124 ns | -1.541 ns | 152.882 MHz |
| 9 | HMATCH 当前距离到最佳距离 bit7 写使能 | 当前累计距离 | 最佳距离 bit7 CE | 6.330 ns | 3.206 ns | 3.124 ns | -1.541 ns | 152.882 MHz |
| 10 | HMATCH 当前距离到最佳距离 bit8 写使能 | 当前累计距离 | 最佳距离 bit8 CE | 6.330 ns | 3.206 ns | 3.124 ns | -1.541 ns | 152.882 MHz |

RTL 上对应的是 `hsim_total_n < hmatch_best_dist_q` 这个判断。bit0、bit1、bit10 是最佳距离寄存器的 bit index，不是 lane 编号。

## 6. P2 fanout 保留情况

| 对象 | 数量 | 真实 Q 扇出 | 范围 |
|---|---:|---:|---|
| `gen_lane[0].i_p2_pop_slice/pop_q_reg` | 1 | 8 | lane-local |
| `gen_lane[1].i_p2_pop_slice/pop_q_reg` | 1 | 8 | lane-local |
| `gen_lane[2].i_p2_pop_slice/pop_q_reg` | 1 | 8 | lane-local |
| `gen_lane[3].i_p2_pop_slice/pop_q_reg` | 1 | 8 | lane-local |
| `gen_lane[0].i_p2_pop_slice/xor_q_reg` | 1 | 1 | lane-local |
| `gen_lane[1].i_p2_pop_slice/xor_q_reg` | 1 | 1 | lane-local |
| `gen_lane[2].i_p2_pop_slice/xor_q_reg` | 1 | 1 | lane-local |
| `gen_lane[3].i_p2_pop_slice/xor_q_reg` | 1 | 1 | lane-local |

共享输入 fanout：

| 信号 | Fanout | 含义 |
|---|---:|---|
| `p1_pop_d` | 4 | 只驱动 4 个 lane-local `pop_q` |
| `p1_xor_d` | 4 | 只驱动 4 个 lane-local `xor_q` |

注意：`high_fanout_hdec_filtered.csv` 中仍有 `pop_q_reg_0` 这类 Vivado 派生网显示大 fanout。这不是 `pop_q_reg/Q` 的真实 lane-local 输出，而是 Vivado 重建网名时产生的 reset/control 派生网。真实 Q fanout 以上表为准。

## 7. 旧 P2 关键路径精确查询

旧问题路径是：

`pop_q -> popcount_q_o/D`

本次修改后，精确 from-to 查询对 `pop_q_to_popcount_D` 返回 `NO_PATH`，说明旧的 P2 数据关键路径已经被消掉。

剩下的本地 P2 控制路径很短：

| 路径 | Slack | Delay | Logic | Route | 保守 Fmax |
|---|---:|---:|---:|---:|---:|
| `pop_q -> popcount_q_o/CE` | +3.932 ns | 0.730 ns | 0.433 ns | 0.297 ns | 936.330 MHz |

因此，P2 fanout 当前不再是最高时序的瓶颈。

## 8. 下一步优化对象

当前瓶颈是 P3 HMATCH 全局 best update：

```text
lane popcount 结果
  -> group distance 累加
  -> 当前 class 的 total distance
  -> 与历史 best distance 比较
  -> best distance / best index 写使能
```

建议下一步：

1. 优先尝试 HMATCH countdown budget，把 `current_total < best_distance` 转换成剩余 budget/borrow 判断。
2. 如果 countdown 改善 CE 锥，再考虑 early bailout，减少 HMATCH 平均周期。
3. 如果精确算法和结构优化仍然过不了时序，再考虑给 compare/update 多打一拍流水。

## 9. 本分支保留的原始报告

本分支只提交非重复的关键原始报告：

- `docs/hdec/ooc/p2_popcount_local_keep_v1/timing_summary.rpt`
- `docs/hdec/ooc/p2_popcount_local_keep_v1/timing_top10.rpt`
- `docs/hdec/ooc/p2_popcount_local_keep_v1/utilization.rpt`
- `docs/hdec/ooc/p2_popcount_local_keep_v1/high_fanout_hdec_filtered.csv`
- `docs/hdec/ooc/p2_popcount_local_keep_v1/run_summary.txt`
- `docs/hdec/ooc/p2_popcount_local_keep_v1/ooc_config.txt`
- `docs/hdec/ooc/p2_popcount_local_keep_v1/p2_exact_manifest.txt`
- `docs/hdec/ooc/p2_popcount_local_keep_v1/p2_exact_popq_to_popcnt_any.csv`
- `docs/hdec/ooc/p2_popcount_local_keep_v1/p2_exact_popq_to_popcnt_D.csv`
- `docs/hdec/ooc/p2_popcount_local_keep_v1/p2_exact_popq_to_popcnt_CE.csv`
- `docs/hdec/ooc/p2_popcount_local_keep_v1/timing_top10_compact.csv`
- `docs/hdec/ooc/p2_popcount_local_keep_v1/p2_local_ff_fanout_summary.csv`

重复的 targeted timing dump、Vivado log/journal、QoR suggestion dump、失败的临时 top10 CSV 均未提交。
