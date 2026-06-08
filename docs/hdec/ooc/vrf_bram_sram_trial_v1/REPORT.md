# HDEC VRF BRAM/SRAM trial V1 OOC report

## 结论

这次已经把 VRF 真正变成了 BRAM/SRAM 风格，而不是只写 `ram_style="block"`：

- VRF 由 4 份 64x64 distributed LUTRAM 改为 4 个 XPM simple dual-port block RAM bank。
- Vivado 2024.2 最终映射确认：`RAMB36E1 = 4`。
- `LUTRAM = 0`。
- xsim HMATCH compare-split 测试通过。

但是当前一拍接口下，BRAM 版不建议替代上一版 LUTRAM 版。原因很直白：BRAM 固定在器件的 BRAM 列，读出来的数据到 lane popcount 的布线变长，200MHz OOC 的最坏 data delay 从 `5.444 ns` 变成 `6.864 ns`，估算 Fmax 从 `183.587 MHz` 降到 `145.645 MHz`。

也就是说：VRF 可以变成 SRAM/BRAM，但如果不在 BRAM 输出后再切一拍，它会省掉 LUTRAM，却明显伤害 P2 时序。

## 环境

| 项目 | 值 |
|---|---|
| 分支 | `hdec-vrf-bram-sram-trial-v1` |
| 基础版本 | `1ccc3236 hdec: optimize P2 popcount and hmatch budget timing` |
| Vivado | 2024.2 |
| FPGA part | `xc7z020clg400-2` |
| Top | `hdec_top` |
| OOC 约束 | `create_clock -period 5.000 [get_ports clk_i]` |
| RTL 仿真 | xsim HMATCH compare-split PASS |

## 资源对比

| 指标 | 上一版 LUTRAM VRF | 本次 BRAM VRF | 变化 | 说明 |
|---|---:|---:|---:|---|
| Slice LUT | 4562 | 4006 | -556 | 总 LUT 下降主要来自 LUTRAM 搬到 BRAM |
| Logic LUT | 3874 | 4006 | +132 | 真实逻辑没有减少，反而增加 |
| LUTRAM | 688 | 0 | -688 | VRF 不再占 LUTRAM |
| FF | 2160 | 1905 | -255 | 原 LUTRAM 周边/读出寄存器减少，BRAM 内部寄存器不算 Slice FF |
| BRAM Tile | 0 | 4 | +4 | 4 个 64x64 bank，各用 1 个 RAMB36E1 |
| DSP | 0 | 0 | 0 | 无变化 |
| CARRY4 | 14 | 14 | 0 | 无变化 |

注意：这次 Slice LUT 降低不能算作算法/逻辑优化收益，因为它主要是把 `688` 个 LUTRAM 换成了 `4` 个 BRAM tile。更公平地看，Logic LUT 从 `3874` 增到 `4006`，说明周边控制和 XPM BRAM 接口逻辑反而更重。

## 200MHz 时序

| 版本 | WNS | 最坏 data delay | Logic | Route | Route ratio | 估算 Fmax | 最坏路径 |
|---|---:|---:|---:|---:|---:|---:|---|
| 上一版 LUTRAM VRF | -0.447 ns | 5.444 ns | 1.190 ns | 4.254 ns | 0.782 | 183.587 MHz | VRF/LUTRAM 读数据到 P2 popcount |
| 本次 BRAM VRF | -1.866 ns | 6.864 ns | 2.755 ns | 4.109 ns | 0.599 | 145.645 MHz | BRAM 读出口到 P2 popcount |

表面上 route ratio 下降了，但不是好事：BRAM 版的逻辑延迟从 `1.190 ns` 增到 `2.755 ns`，而绝对布线延迟仍有 `4.109 ns`。总路径更长。

## 当前最长路径，用白话命名

| Rank | 简单路径名 | Delay | Logic | Route | Route ratio | 说明 |
|---:|---|---:|---:|---:|---:|---|
| 1 | VRF bank0 的 BRAM 读数据 -> lane0 popcount 高位结果 bit5 | 6.864 ns | 2.755 ns | 4.109 ns | 0.599 | 当前 top1 |
| 2 | VRF bank0 的 BRAM 读数据 -> lane0 popcount 高位结果 bit6 | 6.864 ns | 2.755 ns | 4.109 ns | 0.599 | 同一类路径 |
| 3 | VRF bank1 的 BRAM 读数据 -> lane1 popcount 高位结果 bit5 | 6.864 ns | 2.755 ns | 4.109 ns | 0.599 | 同一类路径 |
| 4 | VRF bank1 的 BRAM 读数据 -> lane1 popcount 高位结果 bit6 | 6.864 ns | 2.755 ns | 4.109 ns | 0.599 | 同一类路径 |
| 5 | VRF bank2 的 BRAM 读数据 -> lane2 popcount 高位结果 bit5 | 6.864 ns | 2.755 ns | 4.109 ns | 0.599 | 同一类路径 |
| 6 | VRF bank2 的 BRAM 读数据 -> lane2 popcount 高位结果 bit6 | 6.864 ns | 2.755 ns | 4.109 ns | 0.599 | 同一类路径 |
| 7 | VRF bank3 的 BRAM 读数据 -> lane3 popcount 高位结果 bit5 | 6.864 ns | 2.755 ns | 4.109 ns | 0.599 | 同一类路径 |
| 8 | VRF bank3 的 BRAM 读数据 -> lane3 popcount 高位结果 bit6 | 6.864 ns | 2.755 ns | 4.109 ns | 0.599 | 同一类路径 |
| 9-12 | VRF BRAM 读数据 -> 各 lane popcount 高位结果 bit4 | 6.821 ns | 2.755 ns | 4.066 ns | 0.596 | 同一类路径 |
| 13-16 | VRF BRAM 读数据 -> 各 lane popcount 中高位结果 bit3 | 6.629 ns | 2.755 ns | 3.874 ns | 0.584 | 同一类路径 |
| 17-20 | VRF BRAM 读数据 -> 各 lane popcount 中位结果 bit2 | 6.163 ns | 2.650 ns | 3.513 ns | 0.570 | 同一类路径 |

换成人话：现在最慢的不是 HMATCH，也不是 P2 控制扇出，而是“BRAM 里读出来的 64-bit 数据，要在同一拍里送到 XOR/popcount，再写进 popcount 结果寄存器”。

## P2 扇出和 local pop_q

P2 本地控制没有退化：

| Lane | pop_q FF 是否存在 | 真实 pop_q fanout | 是否跨 lane |
|---:|---|---:|---|
| 0 | 是 | 8 | 否 |
| 1 | 是 | 8 | 否 |
| 2 | 是 | 8 | 否 |
| 3 | 是 | 8 | 否 |

所以之前 P2 扇出修复仍然有效。当前 timing wall 是数据路径，不是 shared P2 控制。

## HMATCH 状态

在本次 BRAM 版 top200 中，HMATCH 相关路径最早约在 rank151：

| 类别 | Delay | Slack @ 200MHz | 说明 |
|---|---:|---:|---|
| popcount 结果 -> HMATCH budget/update | 5.228 ns | -0.231 ns | 已不是 top1，但仍略超 200MHz |

HMATCH countdown / compare split 没有重新成为主瓶颈。当前瓶颈被 BRAM VRF 输出路径盖过去了。

## 为什么 BRAM 版变慢

LUTRAM 版的 VRF 读出寄存器更容易贴近 lane 逻辑，Vivado 可以把数据寄存器和 popcount 逻辑放得比较近。

BRAM 版的存储实体变成固定位置的 `RAMB36E1`。BRAM 输出要横向走到 lane popcount 逻辑，且同一拍还要完成 XOR 和 popcount 高位归约，所以路径变长。Vivado 也提示：

`implemented as a Block RAM might be sub-optimal as no optional output register could be merged into the ram block. Providing additional output register may help in improving timing.`

这基本印证了我们的判断：要让 BRAM 版跑快，需要在 BRAM 输出后加额外寄存器，把“读 SRAM”和“做 popcount”拆成两拍。

## 是否建议保留

不建议把这个 BRAM VRF 试验作为当前主线替代版本。

建议保留该分支和报告，原因是它回答了一个关键问题：

- 可以把 VRF 做成真正 BRAM/SRAM。
- 代价是当前一拍 P2 数据路径严重变慢。
- 总 Slice LUT 下降不等于真实逻辑减少。
- 如果后续必须省 LUTRAM，可以继续做 BRAM 输出后一拍寄存的架构版，但那会增加延迟和大约 256 个操作数 FF。

## 下一步建议

1. 当前主线仍应以 `1ccc3236` 的 LUTRAM VRF 版本为准。
2. 如果目标优先是 200MHz/更高 Fmax，不建议强推 BRAM VRF。
3. 如果目标优先是释放 LUTRAM，可以新做 “BRAM VRF + P2 operand register” 架构：
   - 新增一拍 `src1_q` 或每 lane BRAM 输出寄存器。
   - 预计增加约 `4 lane x 64 bit = 256 FF`，如果 src0/src1 都重整可能更多。
   - P2 popcount 路径理论上可从 `6.864 ns` 降回 5ns 以下，但每个 chunk 多一拍。
4. 更好的方向仍是优化 P2 popcount 数据路径和布局，而不是把很小的 64x64 bank 强制塞进 BRAM。

## 附件

本目录已保存：

- `run_summary_200mhz.txt`
- `timing_top200_200mhz.csv`
- `timing_top1000_200mhz.csv`
- `timing_summary_top50_200mhz.rpt`
- `utilization_200mhz.rpt`
- `utilization_hier_200mhz.rpt`
- `high_fanout_200mhz.csv`
- `high_fanout_hdec_filtered_200mhz.csv`
- `local_ff_preservation_200mhz.csv`
- `timing_p2_targeted_200mhz.csv`
- `qor_suggestions_200mhz.rpt`
- `xsim_hmatch_compare_split.log`
