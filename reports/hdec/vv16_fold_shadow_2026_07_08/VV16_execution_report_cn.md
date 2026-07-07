# VV16 执行报告：低面积 PMUL 前导零调度

## 0. 结论

VV16 没有新增第二套 ECC 乘法器、没有新增独立 reduction 单元，也没有加宽 diagonal datapath。它保留 VV15 的 HDC/ECC 共享 bit-matrix 计算底座，只在 PMUL 标量循环调度上做了一个低面积改动：当 `R0` 仍然是无穷远点、当前 scalar bit 为 0 时，跳过这一轮没有实际贡献的 ladder add/double 计算。

最终保留 checkpoint:

```text
Branch                 : VV16
RTL change             : PMUL leading-zero ladder trim + cheaper scalar-bit select
PMUL profile cycles    : 10849
VV15 profile cycles    : 339100
Cycle reduction         : -328251 cycles, 当前 profile 约 31.26x
Logic LUT              : 4668
VV15 Logic LUT          : 4655
Delta                  : +13 Logic LUT
FF                     : 1425
Fmax estimate           : 207.297 MHz
BRAM / DSP              : 4 / 0
Hard area gate          : PASS, Logic LUT < 4700
```

这版值得保留：它让当前 PMUL profile 进入 1 万 cycle 级别，同时面积只比 VV15 增加 13 个 Logic LUT，仍然低于 `Logic LUT < 4700` 的硬门槛。

需要诚实说明的边界是：当前 PMUL profile 的 scalar 是 `3`。所以这次大幅降周期主要来自消除前导零 scalar bit 对应的无效 ladder 轮次。它是当前 workload/profile 下真实有效的调度优化，但不能被表述成“所有满宽随机 scalar 都天然 31x 加速”。

## 1. VV16 相比 VV15 改了什么

VV15 对 scalar 的每一位都会进入完整 PMUL add/double ladder 轮次。对于当前测试 scalar `3`，最高有效位很低，前面大量高位都是 0；但 VV15 仍然会为这些前导零位发射 field add/mul/sqr/reduce/writeback 工作。由于 `R0` 仍然是无穷远点，这些轮次对最终累积点没有有效贡献。

VV16 在 `S_ECC_PMUL_READ_SCALAR` 增加了以下调度：

```text
if R0 仍为无穷远点
and 当前 scalar bit 为 0
and bit index 非 0:
    bit index 减 1
    重新读取 scalar row
    回到已有 scalar-read wait states
else:
    latch scalar bit
    进入正常 PMUL 子操作
```

这不是 datapath 并行堆硬件，而是 scheduler 避免发射无用工作：

```text
没有第二个 GF multiplier
没有第二个 diagonal product plane
没有新的独立 ECC accumulator
没有新的 VRF port
XOR0、VRF、bit-matrix field engine 仍然是共享底座
```

## 2. 为什么面积没有失控

最开始尝试过组合式 scalar MSB scan。它能把周期降得更低，但是面积和时序都不可接受：

```text
Combinational MSB scan:
  PMUL profile cycles : 9491
  Logic LUT           : 5150
  Fmax estimate        : 60.617 MHz
  Verdict              : rejected
```

最终 VV16 没有保留这个宽优先编码器，而是用串行 skip：每次只跳过一个 leading-zero bit，复用现有 VRF scalar row 读取路径和已有 wait state。这样周期仍然大幅下降，但控制逻辑很小。

另外两个很小但关键的面积处理：

1. `ecc_scalar_bit_from_row` 从四路 `unique case` 改成直接二维索引：

   ```text
   row[bit_idx[7:6]][bit_idx[5:0]]
   ```

   这让 Vivado 对 scalar-bit mux 的映射小很多。

2. bit index 非零判断从显式比较改成 reduction OR：

   ```text
   |ecc_pmul_bit_q
   ```

   在当前综合上下文里，这个写法比 `ecc_pmul_bit_q != 8'd0` 更省 LUT。

这些表达式优化不是创新主线本身，它们的作用是让 PMUL leading-zero 调度可以通过面积门槛。

## 3. 最终周期 profile

来自 `xsim_vv16_final_pmul_profile_v1`:

```text
PMUL_PROFILE_WALL_CYCLES              10849
PMUL_PROFILE_PHASE_INV_SQR_CYCLES       939
PMUL_PROFILE_PHASE_INV_MUL_CYCLES      2690
PMUL_PROFILE_PHASE_PMUL_FIELD_CYCLES   6224
PMUL_PROFILE_PHASE_PMUL_ADD_CYCLES      112
PMUL_PROFILE_PHASE_PMUL_COPY_CYCLES      12

PMUL_PROFILE_SUB_INIT_CYCLES            711
PMUL_PROFILE_SUB_ADD_CYCLES            2762
PMUL_PROFILE_SUB_DBL_CYCLES              83
PMUL_PROFILE_SUB_AFFINE_CYCLES         7293
PMUL_PROFILE_SUB_ZERO_CYCLES              0

PMUL_PROFILE_ST_ECC_LOAD_CYCLES          99
PMUL_PROFILE_ST_ECC_DIAG_CYCLES         330
PMUL_PROFILE_ST_ECC_LEAF_FOLD_CYCLES   7128
PMUL_PROFILE_ST_ECC_WRITE_PAIR_CYCLES  1188
PMUL_PROFILE_ST_ECC_WRITE_DRAIN_CYCLES   33
PMUL_PROFILE_ST_ECC_REDUCE_CYCLES       280
PMUL_PROFILE_ST_ECC_UOP_CYCLES           84
```

和 VV15 相比，这次最大变化不是“每一个 field operation 都变快了很多”，而是 scheduler 不再发射前导零阶段的无效 field operation。换句话说，VV16 降周期的核心是减少无用工作，而不是用面积换并行度。

## 4. 最终 OOC 结果

最终 OOC 目录：

```text
reports/hdec/vv16_fold_shadow_2026_07_08/ooc_vv16_final_v1
```

结果：

```text
Label          vv16_final_v1
WNS            0.176
FmaxMHz        207.297
LUT            4668
LogicLUT       4668
LUTRAM         0
FF             1425
BRAM           4
DSP            0
CARRY4         12
WorstEndpoint  i_vec/popcount_part_q_reg[0][0][4]/D
```

面积对比：

```text
VV15 Logic LUT : 4655
VV16 Logic LUT : 4668
Delta          : +13
```

这不是常规意义上的“用面积换周期”：只增加 13 个 Logic LUT，却在当前 profile 中删除了超过 32 万个 cycle 的无效 ladder 工作。

## 5. 回归证据

最终检查全部通过：

```text
xsim_vv16_final_reduce_v1        [HDEC_ECC_REDUCE_V1] PASS
xsim_vv16_final_add_v1           [HDEC_ECC_ADD_V1] PASS
xsim_vv16_final_hdc_full_v1      [HDEC_HDC_FULL_FLOW_V20] PASS
xsim_vv16_final_pmul_profile_v1  [HDEC_ECC_PMUL_PROFILE_V27] PASS
xsim_vv16_final_pmul_v18_v1      [HDEC_ECC_PMUL_V18] PASS
xsim_vv16_final_pmul_wall_v1     [HDEC_ECC_PMUL_WALL_V27] PASS
xsim_vv16_final_bg_idle_v1       [HDEC_ECC_PMUL_BG_IDLE_V27] PASS
xsim_vv16_final_bg_hdc_loop_v1   [HDEC_ECC_PMUL_BG_HDC_LOOP_V31] PASS
```

相关 wall-cycle 结果：

```text
PMUL_BLOCKING_WALL_CYCLES        10849
PMUL_BG_IDLE_WALL_CYCLES         10850
PMUL_BG_HDC_LOOP_WALL_CYCLES     11947
HDC_FULL_FLOW_STANDALONE_CYCLES   1095
```

## 6. 本轮拒绝的尝试

本轮不是只做了一次小 patch，而是筛掉了几类看起来合理但不值得保留的方案：

```text
vv16_prefetch2_v1
  Idea     : next leaf/sub prefetch + faster fold path.
  Result   : PMUL 316528, Logic LUT 4672.
  Verdict  : 周期收益太小，不足以作为 VV16 主版本。

write-drain collapse
  Idea     : selected PMUL field path bypass write drain.
  Result   : PMUL 313949.
  Verdict  : 只消掉小部分 writeback 开销，离 10W-20W 目标太远。

combinational scalar MSB scan
  Idea     : 用一个宽组合优先编码器直接找最高 set bit.
  Result   : PMUL 9491, Logic LUT 5150, Fmax 60.617 MHz.
  Verdict  : 周期好，但面积和时序完全不可取。

serial MSB trim with heavier wait-state read drive
  Idea     : 串行 leading-zero skip，但 wait state 里显式驱动更多 VRF read.
  Result   : PMUL 10184, Logic LUT 4735.
  Verdict  : 功能正确，但超过面积门槛。

direct-index no-zero-early
  Idea     : 去掉 early ZERO_OUT 分支。
  Result   : Logic LUT 4743.
  Verdict  : 综合后更差，拒绝。

ternary subop select
  Idea     : 把 if/else subop select 改成 ternary expression.
  Result   : Logic LUT 4680.
  Verdict  : 不如最终 4668。
```

## 7. VV16 应该如何讲故事

VV16 不是 VV16 计划里的最终 diagonal-pair 或 fold-token 架构。它更像一个很强的低面积调度 checkpoint：

```text
VV15: 小的 diagonal/sub lookahead，面积低，但 PMUL 仍为 339100 cycles。
VV16: 仍然复用同一套 field engine，但不再发射前导零阶段的无效 ladder 工作。
```

论文故事可以这样讲：

```text
HDC/ECC 统一 bit-matrix 引擎不仅在 datapath 上复用；
ECC controller 也开始具备 operand-aware scheduling，
在没有有效 accumulated point 之前避免发射无用的 matrix field operation。
```

这比单纯加硬件更符合当前工程主线：速度来自对共享引擎的更好调度，而不是旁路加一套独立 ECC fast path。

## 8. 下一步建议

VV16 应该作为一个好版本保留。下一步不应该再回到宽组合 MSB scan，也不应该简单加倍 diagonal datapath。

建议下一分支继续做：

```text
1. 保留 VV16 leading-zero trim。
2. 增加 full-width scalar profile，避免只对 scalar=3 优化。
3. 回到 finite-template fold-token / hidden leaf-fold 方向，优化第一位 set bit 之后的真实 field-operation body。
4. 继续保持 XOR0、VRF、bit-matrix field engine 复用，不新增独立 ECC 大单元。
```

总结来说：VV16 解决了当前 PMUL profile 中最大的无效工作问题。剩下的研究问题，是如何在 scalar 进入非零区域后继续降低真实 field operation 的成本。
