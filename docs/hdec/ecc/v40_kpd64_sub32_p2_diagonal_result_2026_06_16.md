# V40 KPD64-sub32 P2 斜线模乘优化结果

日期：2026-06-16

工具：Vivado 2024.2，器件 `xc7z020clg400-2`，OOC 目标周期 5.000 ns。

分支：`hdec-ecc-pointmul-v40`

## 选中的 RTL 版本

V40 选中的是本轮 KPD64/P2 斜线实验里面积和周期综合最好的版本：

```text
顶层 KPD64 Karatsuba
+ 复用原来的 32-bit P2 斜线 leaf 引擎
+ 折叠到原始 512-bit product accumulator
+ 继续使用已有 GF(2^233) 约简
```

这版的算法变化是：顶层 Karatsuba 不再一直拆到 32-bit leaf，而是先拆到 64-bit leaf；每个 64-bit leaf 内部再用 3 次 32x32 子乘法完成。

V37 基线的一次域乘法结构是：

```text
256 -> 128 -> 64 -> 32
3^3 = 27 个 32-bit leaf
每个 32-bit leaf 使用现有 16 条斜线/发射的 P2 斜线引擎
每个 leaf 后面都要付一次 fold 调度开销
```

V40 的一次域乘法结构是：

```text
256 -> 128 -> 64
3^2 = 9 个顶层 64-bit leaf
每个 64-bit leaf = 3 个复用的 32x32 子乘法
每个 32x32 子乘法仍然使用现有 P2 斜线引擎
```

所以 V40 没有加真正的 64x64 乘法器，没有用 DSP，也没有跳过标量 `K` 的 0 bit。标量点乘仍然保持固定 233-bit 调度，只改变每次域乘法内部的 Karatsuba 分解和 fold 方式。

核心收益来自 leaf fold 数量下降：从 27 个顶层 32-bit leaf 变成 9 个顶层 64-bit leaf。32x32 子乘法之间的切换被塞进 `S_ECC_DIAG_WAIT`，避免额外增加多拍调度泡泡。

## RTL 实现要点

主要修改在 `core/hdec/rtl/hdec_top.sv`：

- `ecc_kpd64_path_inc`：遍历 9 个 64-bit Karatsuba leaf path。
- `ecc_kpd64_leaf_lowxor_pack`：一次读出 `{low ^ high, low}`，减少 operand selection 的 mux 面积。
- `ecc_kpd64_sub32_accum`：把 3 个 32x32 子乘法合成一个 64x64 Karatsuba leaf product。
- `ecc_leaf_prod_flush_value`：在 `S_ECC_DIAG_WAIT` 切换子乘法时，把最后一拍斜线流水结果一起算进去。
- `ecc_kpd64_fold_word_contrib`：把 64x64 leaf 的 128-bit 贡献折叠回已有 `ecc_product_pair`。

最终版保留“原始 product 累加 + 最终约简”的结构。直接 reduced accumulation 理论上能省最后约简，但 Vivado 2024.2 综合出来的固定 XOR 网络太大，因此没有选入 V40。

## 最终验证

ECC 点乘仿真：

```text
reports/hdec/kpd64_lowxor_pack_final_2026_06_16/xsim_ecc_pmul_profile_v27
[HDEC_ECC_PMUL_PROFILE_V27] PASS
PMUL_PROFILE_WALL_CYCLES=247945
PMUL_PROFILE_ST_ECC_DIAG_CYCLES=160380
PMUL_PROFILE_ST_ECC_LEAF_FOLD_CYCLES=42768
PMUL_PROFILE_ST_ECC_REDUCE_CYCLES=11284
PMUL_PROFILE_GF_MUL_STARTS=1188
PMUL_PROFILE_INV_STARTS=1
```

HDC 回归：

```text
reports/hdec/kpd64_lowxor_pack_final_2026_06_16/xsim_hdc_full_flow_v20
[HDEC_HDC_FULL_FLOW_V20] PASS
```

V40 OOC 综合：

```text
reports/hdec/kpd64_lowxor_pack_final_2026_06_16/ooc_kpd64_lowxor_pack_final
Logic LUT=6103
Slice LUT=6575
LUTRAM=472
FF=1998
DSP=0
CARRY4=13
WNS=0.247 ns
Fmax estimate=210.393 MHz
Worst endpoint=lane_result_q_reg[0][14]/D
```

## 跨版本对比

| 版本 / 实验 | 功能 | 点乘周期 | Logic LUT | FF | WNS ns | 说明 |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| V35 selected 5M cross-product + selected double XZ | PASS | 341624 | 5921 | 1802 | 0.243 | 之前保留的点加公式优化版本 |
| V35 diagonal tail bypass | PASS | 363199 | 6006 | 1810 | 0.247 | 更早的斜线尾部旁路版本 |
| V35 D4 digit-serial | PASS | 126259 | 7798 | 2537 | 0.055 | 周期很快，但面积和时序代价过大 |
| V37 one-inversion baseline | PASS | 333481 | 6013 | 1815 | 0.247 | V40 的主要公平基线 |
| V37 Plan2 tail bypass | PASS | 309143 | 6051 | 1806 | 0.247 | fold 调度优化，收益中等 |
| V37 Plan3 KPD64-sub32 direct clean | PASS | 255008 | 6119 | 1940 | 0.247 | 之前的 KPD64-sub32 清理版 |
| V40 selected KPD64-sub32 P2 diagonal | PASS | 247945 | 6103 | 1998 | 0.247 | 本轮选中的 V40 |

相对 V37 one-inversion baseline：

```text
周期减少 = 333481 - 247945 = 85536
Logic LUT 增加 = 6103 - 6013 = 90
FF 增加        = 1998 - 1815 = 183
```

相对 V35 selected 5M cross-product 版本：

```text
周期减少 = 341624 - 247945 = 93679
Logic LUT 增加 = 6103 - 5921 = 182
FF 增加        = 1998 - 1802 = 196
```

相对 V37 Plan2 tail bypass：

```text
周期减少 = 309143 - 247945 = 61198
Logic LUT 增加 = 6103 - 6051 = 52
FF 增加        = 1998 - 1806 = 192
```

## 本轮 V1-V7 实验对比

| 尝试 | 主要思路 | 点乘周期 | Logic LUT | FF | WNS ns | 结论 |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| v1 | KPD64 + direct reduced accumulation | 257449 | 8092 | 2599 | 0.247 | 拒绝：直接约简网络面积过大 |
| v2 | 静态 direct-reduce fold table + 两拍写回 | 258637 | 7662 | 2080 | 0.162 | 拒绝：面积仍然过大 |
| v3 | 原始 512-bit fold + `DIAG_WAIT` 子乘法旁路 | 247945 | 7239 | 2086 | 0.242 | 周期好，但面积高 |
| v4 | 统一 KPD64 路径，去掉 old/new multiply 动态选择 | 247945 | 6494 | 2075 | 0.247 | 面积明显下降 |
| v5 | 去掉完整 64-bit leaf operand 寄存，只保留 32-bit 当前值和 xor-hold | 247945 | 6381 | 2008 | 0.247 | 面积继续下降 |
| v6 | `{low ^ high, low}` 打包读取 leaf operand | 247945 | 6103 | 1998 | 0.247 | 本轮最佳 |
| v7 | 静态 fold-enable table | 247945 | 6206 | 2001 | 0.247 | 拒绝：周期不变，LUT 增加 |
| final | 回退 v7 的 fold-enable table，保留 v6 动态 mask | 247945 | 6103 | 1998 | 0.247 | V40 RTL |

## 为什么 V40 值得保留

V40 的加速点不是增加一个大乘法器，而是减少每次域乘法中最浪费的 leaf fold 调度开销。

V37 one-inversion baseline：

```text
ST_ECC_DIAG       = 160380 cycles
ST_ECC_LEAF_FOLD  = 128304 cycles
ST_ECC_REDUCE     = 11284 cycles
```

V40：

```text
ST_ECC_DIAG       = 160380 cycles
ST_ECC_LEAF_FOLD  = 42768 cycles
ST_ECC_REDUCE     = 11284 cycles
```

斜线计算本身没有变少，因为底层仍然是同一个 32-bit P2 斜线引擎。真正减少的是顶层 leaf fold 次数：从 27 次一组的 32-bit leaf fold，变成 9 次一组的 64-bit leaf fold。

这也是 V40 比 D4 digit-serial 和完整 64-bit leaf 更适合作为当前主线的原因：它拿到了大部分周期收益，但没有把面积和时序推到不可接受的范围。

## 后续计划

1. 继续压 FF：检查 `ecc_leaf128_prod_q`、`ecc_leaf_xor_a_q`、`ecc_leaf_xor_b_q` 的生命周期，看能否和已有 leaf/product 寄存器合并。
2. 重新评估 direct reduced accumulation，但必须改成分阶段、分 bank 的 64-bit fold，不能再让综合器看到一个很大的组合约简网络。
3. 在 V40 上继续尝试小规模 fold/write-pair bypass，但前提是不能破坏 `ecc_product_pair` 的 LUTRAM 推断。
4. 检查点加调度，看看 V40 域乘结果能否更早被下一步点加消费，减少 writeback/readback 泡泡。
5. 保留 D4 digit-serial 作为高性能参考分支；除非能把它改成更小的 shared-lane 实现，否则不建议进入面积敏感主线。
