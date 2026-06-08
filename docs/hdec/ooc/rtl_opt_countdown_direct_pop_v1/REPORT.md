# HDEC RTL 优化 OOC 报告：direct popcount + HMATCH budget

## 结论

这轮最值得保留的是 **P2 direct popcount + HMATCH strict countdown budget + 保持 4-bank LUTRAM VRF**。

相对上一版已保存的 `hmatch_compare_split_p2keep_v1`，当前版本在 200MHz OOC 下：

| 项目 | 已保存 P2/HMATCH 版 | 当前 round7 | 变化 |
|---|---:|---:|---:|
| WNS @ 200MHz | -1.075 ns | -0.447 ns | +0.628 ns |
| 估算 Fmax | 164.609 MHz | 183.587 MHz | +18.978 MHz |
| Slice LUT | 5105 | 4562 | -543 |
| Logic LUT | 4417 | 3874 | -543 |
| LUTRAM | 688 | 688 | 不变 |
| FF | 2201 | 2160 | -41 |
| BRAM / DSP | 0 / 0 | 0 / 0 | 不变 |
| CARRY4 | 11 | 14 | +3 |

175MHz OOC 已通过，WNS `+0.267 ns`。200MHz 仍未完全过，当前 top1 是 P2 popcount capture，data delay `5.444 ns`。

## 本轮保留的 RTL 改动

1. P2 popcount 直接表达为 XOR + `$countones`。
   - 原来：`boolean_mask` + 通用 `hdec_lane_popcount_compressor(mode=0)`。
   - 现在：`bool_result = src_a_i ^ src_b_i; popcount_count = $countones(bool_result);`
   - 结果：Vivado 不再把 P2 popcount 实现成之前那条 `6.072 ns` 路径，P2 最坏降到 `5.444 ns`。

2. HMATCH 用 strict countdown budget 判断是否优于 best。
   - 原来：最后一组 popcount 后做 `hsim_total + group_dist < hmatch_best_dist`。
   - 现在：每个 chunk 消耗 `hmatch_budget_q`，最后只判断 `hmatch_budget_q > group_dist`。
   - 结果：HMATCH 不再是 top1，最坏 HMATCH 路径约 `5.233 ns`。

3. 删除 HMATCH candidate distance 寄存器。
   - `hsim_total_q` 在类切换/P4 响应时保留候选距离，不再额外保存 `hmatch_candidate_dist_q`。

4. HPERM/HCNTCLIP 的 VRF 地址选择提前到 uop 字段里。
   - 减少 P1 读地址阶段的 op_type 大 MUX。

5. VRF 保持 4 个 64-bit LUTRAM bank。
   - 宽 256-bit VRF + `ram_style="block"` 试验没有保留。

## 为什么没有把 VRF 改成 SRAM/BRAM

做过一个 64x256 wide VRF 试验，并加了 `ram_style="block"`，Vivado 2024.2 报告为 `Infeasible attribute ram_style = "block"`，最终仍映射为 LUTRAM `RAM64M/RAM64X1D`，没有变成 BRAM。

wide VRF 还引入了新的写口控制/写数据路径，200MHz top 变成 VRF 写口路径，WNS 只有 `-1.043 ns`，比当前 4-bank 版本差。

因此本轮判断：

- 当前 64-entry x 4-bank x 64-bit VRF 太小，强推 BRAM 不一定利于时序。
- 要真正用 BRAM，可能需要 XPM/primitive，代价是固定 BRAM 列、接口更硬、仿真/验证复杂度上升。
- 由于用户要求 LUTRAM 变 0 不能算真实 LUT 降低，本轮不把 BRAM 化作为主要优化成绩。

AMD UG901 也说明 dedicated block RAM 是同步读，而 distributed RAM 支持异步读风格；小容量、近计算逻辑的数据面不一定适合强行塞进 BRAM。

## 频率结果

| 频率 | Period | WNS | 最坏路径 | Data delay | Logic | Route | Fmax est |
|---:|---:|---:|---|---:|---:|---:|---:|
| 175 MHz | 5.714 ns | +0.267 ns | P2 popcount capture | 5.444 ns | 1.190 ns | 4.254 ns | 183.587 MHz |
| 200 MHz | 5.000 ns | -0.447 ns | P2 popcount capture | 5.444 ns | 1.190 ns | 4.254 ns | 183.587 MHz |

## 当前最长路径

| Rank | 简单名字 | Vivado path class | Delay | Logic | Route | 说明 |
|---:|---|---|---:|---:|---:|---|
| 1-12 | P2 输入数据到 popcount 结果寄存器 | P2 popcount capture | 5.444 ns | 1.190 ns | 4.254 ns | 当前真正 top1，主要是布线 |
| 13-16 | 另一组 P2 popcount 位 | P2 popcount capture | 5.390 ns | 1.190 ns | 4.200 ns | 同类路径 |
| 17-26 | P2/HMATCH 局部预算相关路径 | P2/HMATCH mixed | 5.233 ns | 2.540 ns | 2.693 ns | 已低于 top1 |
| 27-34 | VRF 读/写控制路径 | VRF/read/writeback | 4.770 ns | 1.085 ns | 3.685 ns | 不是当前瓶颈 |
| 35+ | scalar response | scalar response | 约 4.8 ns | 约 1.95 ns | 约 2.9 ns | 接近但未超 200MHz |

## P2 扇出结论

`pop_q` 没有被 Vivado 合并成一份 shared register。

local FF 查询显示：

| Lane | pop_q FF | pop_q fanout | 是否跨 lane |
|---:|---|---:|---|
| 0 | `gen_lane[0].i_p2_pop_slice/pop_q_reg` | 8 | 否 |
| 1 | `gen_lane[1].i_p2_pop_slice/pop_q_reg` | 8 | 否 |
| 2 | `gen_lane[2].i_p2_pop_slice/pop_q_reg` | 8 | 否 |
| 3 | `gen_lane[3].i_p2_pop_slice/pop_q_reg` | 8 | 否 |

`p1_pop_d` 仍然是一个上游广播控制，fanout 4，只负责喂 4 个本地 `pop_q`；真正驱动 popcount enable 的是每个 lane 自己的 `pop_q`。所以 P2 的问题已经不是“一个 shared P2 控制扇出 90+”，而是 “P2 数据到 popcount 的布线距离/布局”。

local FF 脚本里有一些 `pop_q_reg_0` 高扇出项，但 driver 是 `i_vrf/FSM_onehot_st_q[0]_i_3/O`，是模式匹配误抓到的复位/控制相关网，不是 `pop_q_reg/Q` 真实本地输出。真实 `pop_q` net 如上表，fanout 8 且 lane-local。

## 功能验证

Vivado xsim 已跑 `tb_hdec_hmatch_compare_split.sv`：

| 用例 | 结果 |
|---|---|
| single class max distance | PASS |
| second class exact match | PASS |
| tie keeps first class | PASS |
| illegal num_classes zero | PASS |

没有跑 Verilator。

## 资料依据

- AMD/Xilinx UG901: Vivado RAM HDL coding 里 distributed RAM 与 dedicated block RAM 的读写风格不同，block RAM 读为同步，`RAM_STYLE` 只是指导综合，具体能否映射仍取决于 RTL 形态。
- HDC FPGA/硬件论文通常把 associative search 描述为 query hypervector 与 class hypervectors 做 similarity/Hamming distance，再找 closest match；这支持本轮重点优化 XOR/popcount、距离归约、best-update，而不是继续堆复杂控制。
- Dense binary HDC 硬件优化论文提出通过简单逻辑和避免不必要存储搬运来优化 HDC，这和本轮 direct popcount、保留 lane-local 数据路径的方向一致。

参考链接：

- AMD UG901 Vivado Synthesis: https://www.xilinx.com/support/documents/sw_manuals/xilinx2022_2/ug901-vivado-synthesis.pdf
- Hardware Optimizations of Dense Binary Hyperdimensional Computing: https://arxiv.org/abs/1807.08583
- Accelerating Hyperdimensional Computing on FPGAs by Exploiting Computational Reuse: https://www.researchgate.net/publication/341198744_Accelerating_Hyperdimensional_Computing_on_FPGAs_by_Exploiting_Computational_Reuse

## 下一步建议

当前如果继续冲 200MHz，最该处理的是 P2 popcount capture 的 route-dominated 路径。RTL 层面已经比较干净，下一步可以试：

1. 对 P2 popcount 做 32+32 半宽分段再合并，但这会加寄存器或加一拍，需要权衡吞吐/延迟。
2. 尝试给 P2 lane/VRF output 做轻量 pblock 或综合/布局策略实验，目标是降 route delay，不改变 RTL 功能。
3. 继续简化 scalar response/VRF writeback MUX，但它们现在不是第一瓶颈。
4. 如果未来必须上 BRAM，建议用单独分支做 XPM/primitive VRF，并把“BRAM 节省的 LUTRAM”与“真实 Logic LUT 降低”分开统计。

本轮建议保留当前 RTL。
