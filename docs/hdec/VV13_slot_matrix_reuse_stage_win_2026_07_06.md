# VV13 slot 矩阵化模约减阶段胜利

## 结论

这一版是 VV13 的一个阶段胜利，不是最终高速版本。

核心结果如下：

| 版本 | LUT | FF | BRAM | DSP | 200 MHz WNS | 估计 Fmax | PMUL cycles | 定位 |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| VV13 leaf packet reference | 4677 | 1436 | 4 | 0 | positive | 207.684 MHz | 392560 | 快速参考版 |
| VV13 slot-matrix reuse | 4357 | 1255 | 4 | 0 | -0.019 ns | 199.243 MHz | 848752 | 面积胜利版 |

和 VV13 leaf packet reference 相比，这一版少了 320 LUT 和 181 FF。它不仅低于 5000 LUT 硬门槛，而且已经低于原先预期的 4700 到 4800 LUT 区间。代价也很明确：PMUL 周期从 392560 增加到 848752。

这个结果证明了一件很重要的事：模约减也可以被写成统一的位矩阵/贡献包形式，并且可以通过 slot 复用显著降低 LUT。

## RTL 做了什么

上一版 VV13 已经把 leaf 级模约减整理成 contribution packet，但模约减仍然更像 leaf/word 级的直接贡献生成。这一版继续往前推，把模约减放进斜线计算后的细粒度数据流里，用 slot 级贡献包来表达。

主要 RTL 改动：

- 在 ECC 斜线状态机里加入 `S_ECC_DIAG_REDUCE`，作为 diagonal capture 之后的真实 reduction drain 状态。
- 新增 `ecc_reduce_parity_q`、`ecc_reduce_group_q`、`ecc_reduce_slot_q`，保存当前待 drain 的斜线奇偶行、group 和 slot。
- 用更紧凑的矩阵化 packet 函数替代原来的大规模固定映射 case：
  - `ecc_field233_bit_packet`
  - `ecc_mod233_exp_packet`
  - `ecc_kpd64_diag_reduce_packet`
- 新增 leaf offset mask 到 slot 的辅助函数：
  - `ecc_kpd64_leaf_mask_count`
  - `ecc_kpd64_leaf_mask_slot_valid`
  - `ecc_kpd64_leaf_mask_slot_mid`
- 更新 `tb_hdec_ecc_diag_reduce_map_v1`，让 golden check 把所有 slot 的贡献 XOR 起来，再和原 leaf reduction 结果比较。
- 暂时关闭旧的 `ecc_leaf_fast_prefetch`，因为 slot 串行 drain 改变了原来的 VRF 预取节奏。

新的数据流可以概括为：

```text
diagonal parity row
-> 从 leaf offset mask 中选择一个有效 slot
-> 把每个有效 parity bit 映射到 GF(2^233) 贡献坐标
-> 按 x^233 = x^74 + 1 完成指数折叠
-> 生成一个 4x64 contribution packet
-> 通过共享 packet/XOR0 路径累加
-> 进入下一个 slot
```

## 为什么面积下降这么多

面积下降主要来自两个原因。

第一，模约减不再展开成一个覆盖所有 leaf offset 的并行大映射网络。现在硬件每次只生成一个 slot 的 contribution packet，同一个 packet generator 在不同有效 slot 之间复用。这样删掉了大量重复 LUT。

第二，模约减的输出数据结构仍然是统一的 4x64 packet：

```systemverilog
logic [LANE_NUM-1:0][LANE_WIDTH-1:0]
```

这意味着 ECC reduction 的结果不需要进入一个 ECC 私有的 233-bit 大 XOR 网络，而是继续走 HDEC 已有的共享 packet 累加路径。也就是说，模乘和模约减都被翻译成同一种 contribution packet 语言。

这就是为什么这一版可以降到 4357 LUT，同时 ECC PMUL 和 HDC full flow 仍然通过。

## 是否完成了硬件复用

这一版完成了当前阶段所需要证明的硬件复用。

已经完成的复用：

- 模约减结果被表达成和 HDC/ECC 共享 vector path 一致的 4x64 packet。
- slot 级 reduction packet generator 在多个有效 offset slot 之间复用，不再为所有 offset 并行实例化独立硬件。
- reduction packet 继续通过共享 packet/XOR 累加路径进入结果。
- `i_vec` 仍然是 HDC 和 ECC 共用的位矩阵数据边界。

还没有完成的部分：

- 这一版没有恢复 slot-aware prefetch。
- 这一版还没有加入双 slot 或流水化 reduction engine。
- 这一版是面积优先的证明版，不是最终性能版。

所以结论应该这样讲：硬件复用和统一数据结构这个阶段目标已经成立，但高吞吐调度还需要下一阶段恢复。

## 数据形式是否统一

是的。这一版最重要的故事点就是：模约减也变成了 packet/matrix 形式。

之前的工作已经把多项式模乘整理成位矩阵行、斜线奇偶、4x64 contribution packet。这一版把模约减也接入同一套表示：

```text
bit-matrix diagonal parity
-> field-coordinate contribution packet
-> shared 4x64 GF(2) accumulation
```

这比单纯说“复用了乘法器”更强。更好的论文故事是：乘法和模约减都被统一成 contribution packet 数据结构，然后用同一条共享 GF(2) 累加路径处理。

## 为什么周期增加这么多

周期增加的根本原因是 slot 串行化。

旧的快速参考版在一次 diagonal capture 后，可以更快地形成较完整的 reduction contribution。这一版为了省面积，只保留一个 slot-level reducer。只要 leaf mask 里有多个有效 offset，就必须在 `S_ECC_DIAG_REDUCE` 里分多个周期 drain。

同时，这一版暂时关闭了 fast leaf prefetch。旧 prefetch 节奏假设 capture/reduce cadence 不插入 slot drain 周期；现在直接沿用会导致 VRF 数据节奏风险。关闭 prefetch 保证了正确性，但也暴露了完整的串行化成本。

实测结果：

```text
VV13 reference PMUL cycles:     392560
slot-matrix reuse PMUL cycles:  848752
increase:                      456192 cycles
ratio:                         about 2.16x
```

因此，这一版慢不是因为矩阵化模约减理论上一定慢，而是因为我们选择了最省面积的 single-slot 实现。

## 理论上能不能把周期降回来

可以。周期增加不是数学必然，而是当前调度和并行度选择的结果。

后续可以尝试：

- 恢复 slot-aware prefetch，让下一片 leaf 数据在当前 slot reducer drain 时提前进入。
- 只对 dense mask 打开小规模双 slot 路径，稀疏 mask 仍走 single-slot。
- 做 diagonal capture 和 slot reduction 的双级流水：前一级捕获下一条 parity row，后一级 drain 上一条 row 的 reduction packet。
- 继续保持 4x64 packet 数据格式不变，让新增并行度仍然进入同一条共享累加路径。
- 根据 mask density 更早跳过空 slot 或低价值 slot。

下一阶段比较合理的目标是：仍然保持 LUT 低于 5000，同时把 PMUL cycle 从 848752 明显拉回去。

## 时序解释

200 MHz OOC 结果几乎收敛：

```text
WNS:             -0.019 ns
Estimated Fmax:  199.243 MHz
Failing endpoints: 4
Worst endpoint:  i_vec/popcount_part_q_reg[2][0][3]/D
```

最差路径在现有 vector popcount capture 路径里，不在新的 modular-reduction packet generator 里。这一点很重要：新的矩阵化模约减显著省面积，但没有变成新的主时序墙。当前只差 19 ps，更像物理布局或综合细节问题，而不是架构方向错误。

## 验证证据

功能验证：

- `reports/hdec/vv13_diag_pipeline_slotreduce_2026_07_06/xsim/xsim_ecc_diag_reduce_map_v1/xsim.log`
  - `[HDEC_ECC_DIAG_REDUCE_MAP_V1] PASS`
- `reports/hdec/vv13_diag_pipeline_slotreduce_2026_07_06/xsim_noprefetch/xsim_ecc_pmul_profile_v27/xsim.log`
  - `PMUL_PROFILE_WALL_CYCLES=848752`
  - `[HDEC_ECC_PMUL_PROFILE_V27] PASS`
- `reports/hdec/vv13_diag_pipeline_slotreduce_2026_07_06/xsim_noprefetch/xsim_hdc_full_flow_v20/xsim.log`
  - `[HDEC_HDC_FULL_FLOW_V20] PASS`

OOC 综合证据：

- `reports/hdec/vv13_diag_pipeline_slotreduce_2026_07_06/ooc_200/reports/run_summary.txt`
- `reports/hdec/vv13_diag_pipeline_slotreduce_2026_07_06/ooc_200/reports/utilization.rpt`
- `reports/hdec/vv13_diag_pipeline_slotreduce_2026_07_06/ooc_200/reports/timing_summary_top50.rpt`

## 阶段定位

这一版应该作为 VV13 的 clean milestone 保留下来。它证明了主线想法：

```text
modular reduction can be matrix-shaped,
slot-reused,
and accumulated through the same unified 4x64 packet datapath.
```

面积结果足够漂亮，可以成为论文故事里的强证据。周期结果不是终点，但它给出了下一章：在保留矩阵化模约减和统一 packet 数据结构的前提下，恢复 prefetch、恢复部分并行度、再做双级流水。
