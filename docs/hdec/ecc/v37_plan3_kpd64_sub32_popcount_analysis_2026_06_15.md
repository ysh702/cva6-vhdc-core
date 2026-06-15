# V37 Plan3 KPD64 子叶子优化记录

日期：2026-06-15

分支：`hdec-ecc-pointmul-v37`

基线：V35，`4193f204 hdec: select V35 5M point-add optimization`

工具：
- 仿真：`scripts/hdec/xsim_hdec_ecc_pmul_profile_v27.tcl`
- 综合：`scripts/hdec/run_ooc_200.ps1`
- Vivado：2024.2
- 器件：`xc7z020clg400-2`
- OOC 约束：5.000 ns

## 背景

Plan3 的原始方向是把 V35 的 27 个 32-bit leaf 改成 9 个 64-bit leaf：

```text
256 -> 128 -> 64
两层 Karatsuba
9 个 64-bit leaf
```

这样 leaf 数和 fold 次数会大幅下降，但原始 64-bit leaf 需要更宽的 diagonal 规约树，面积和时序压力都很大。

这一轮尝试了一个折中版本：仍保留 9 个 64-bit leaf，但每个 64-bit leaf 内部拆成三个 32-bit 子叶子：

```text
P0 = A0 * B0
P1 = (A0 ^ A1) * (B0 ^ B1)
P2 = A1 * B1
A * B = P0 ^ ((P0 ^ P1 ^ P2) << 32) ^ (P2 << 64)
```

最终候选版本没有单独保存 64-bit 子叶子积，而是把每拍产生的 16 个 32-bit diagonal parity 直接异或累加到 128-bit 大叶子积里。

## 结果对比

| 方案 | 仿真 | PMUL 周期 | 比 V35 少 | Logic LUT | 比 V35 多 | FF | 比 V35 多 | WNS(ns) | Fmax(MHz) | 判断 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| V35 基线 | PASS | 341624 | 0 | 5921 | 0 | 1802 | 0 | 0.243 | 210.217 | baseline |
| Plan3 原始 64-bit leaf | PASS | 190046 | 151578 | 6677 | 756 | 1951 | 149 | -0.063 | 197.511 | 周期很好，但面积大且 200MHz 不通过 |
| Plan3 halfdiag8 | PASS | 276662 | 64962 | 6181 | 260 | 1945 | 143 | -0.431 | 184.128 | 面积下降，但时序更差 |
| Plan3 halfdiag8 + max_fanout16 | 同 halfdiag8 | 276662 | 64962 | 6465 | 544 | 1938 | 136 | -0.022 | 199.124 | 接近 200MHz，但面积不划算 |
| KPD64 sub32，先存 64-bit 子叶子积 | PASS | 255008 | 86616 | 6190 | 269 | 1997 | 195 | 0.243 | 210.217 | 可行，但 FF 偏高 |
| KPD64 sub32 direct accumulation | PASS | 255008 | 86616 | 6119 | 198 | 1940 | 138 | 0.247 | 210.393 | 记录，后续可考虑保留 |

最终候选版本的内部周期：

| 项目 | 周期 |
|---|---:|
| `PMUL_PROFILE_WALL_CYCLES` | 255008 |
| `PMUL_PROFILE_ST_ECC_DIAG_CYCLES` | 162405 |
| `PMUL_PROFILE_ST_ECC_LEAF_FOLD_CYCLES` | 43308 |

原始报告路径：
- 仿真：`reports/hdec/v37_plan3_kpd64_sub32_direct_clean_2026_06_15/xsim_ecc_pmul_profile_v27/xsim.log`
- OOC：`reports/hdec/v37_plan3_kpd64_sub32_direct_clean_2026_06_15/ooc_kpd64_sub32_direct_clean`

## 判断

`KPD64 sub32 direct accumulation` 的周期收益很大，比 V35 少 86616 周期；Logic LUT 只增加 198，200MHz OOC 通过。

它的问题是 FF 增加 138，比 `ADD 5M cross-product + selected double XZ` 这种算法级优化更重，而且仍然是乘法器结构改动，验证面比点加调度要大。

所以这版先作为“可回头考虑保留”的 Plan3 面积友好记录，不作为当前工作树最终基线。后续如果继续追求更低周期，它比原始 64-bit leaf 更值得从面积和时序角度继续优化。
