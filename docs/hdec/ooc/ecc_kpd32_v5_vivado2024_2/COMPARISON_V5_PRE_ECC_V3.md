# HDEC ECC KPD32 V5 OOC 对比报告

日期：2026-06-09

## 本次口径

本报告对比三个点：

| 对比点 | 分支/提交 | 含义 | 数据来源 |
|---|---|---|---|
| pre-ECC HDC | `origin/hdec-p2-popcount-p3accum-v1 / 07bd8cbd` | 未加入 ECC 前，P2 popcount 已切到 P3 累加的纯 HDC 版本 | `docs/hdec/ooc/p2_borrow_timing_trials_v1/ooc_results/trial12_p2_partial_p3accum_200` |
| ECC V3 | `origin/hdec-ecc-diagonal-parallel-v3 / 51c4132b` | V3 分支只新增文档，RTL 等价 `2d44e9e3 hdec: register VRF commands for ECC scheduling` | `docs/hdec/ooc/ecc_vrf_control_v2` |
| ECC KPD32 V5 | `origin/hdec-ecc-kpd32-v5 / 62b7cb12` | Karatsuba + packed diagonal popcount ECC 乘法，且修正 HDC popcount issue 对齐 | 本次使用 Vivado 2024.2 重新 OOC，输出在本目录 `reports/` |

统一综合设置：

| 项目 | 值 |
|---|---|
| Vivado | 2024.2 |
| FPGA part | `xc7z020clg400-2` |
| Top | `hdec_top` |
| OOC clock | 5.000 ns / 200 MHz |
| BRAM/DSP | 三个版本均为 0 |

备注：仓库中已有 `docs/hdec/ooc/ecc_kpd32_v5_hdc_align`，但其中写的是 Vivado 2022.2，本报告最终对比使用本次新跑的 Vivado 2024.2 数据。

## 一、OOC 时序对比

| 版本 | WNS @200MHz | Worst delay | 估算 Fmax | 最差 endpoint | 简单理解 |
|---|---:|---:|---:|---|---|
| pre-ECC HDC | -0.051 ns | 4.701 ns | 197.981 MHz | `i_vrf/vrf_b0.../DP/I` | 还差一点到 200MHz，卡在 VRF 读端口/控制路径 |
| ECC V3 | +0.069 ns | 4.960 ns | 202.799 MHz | `lane_result_q_reg[1][23]/D` | 加入 ECC V1 后，通过 V2 的 VRF 命令寄存边界，已经过 200MHz |
| ECC KPD32 V5 | +0.232 ns | 4.765 ns | 209.732 MHz | `lane_result_q_reg[0][55]/D` | KPD32 加入后仍然过 200MHz，且余量比 V3 更大 |

时序结论：

- V5 没有把 ECC 乘法折叠路径推成关键路径。
- V5 的 top path 仍是普通 HDC lane result capture 控制/布线路径，不是 ECC Karatsuba fold，也不是 512-bit product accumulator。
- V5 第 13 条路径是 popcount partial 到 `group_dist_q`，data delay 4.700 ns，WNS +0.326 ns，说明 HDC popcount 聚合仍健康。
- V5 的前 12 条路径主要是 `FSM_onehot_st_q_reg[3] -> lane_result_q[*][55/59/63]`，route ratio 约 75%，偏布线主导。

## 二、资源对比

| 版本 | Slice LUT | Logic LUT | LUTRAM | FF | BRAM | DSP | F7 Mux | CARRY4 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| pre-ECC HDC | 4505 | 3817 | 688 | 2080 | 0 | 0 | 261 | 16 |
| ECC V3 | 5476 | 4788 | 688 | 3275 | 0 | 0 | 264 | 16 |
| ECC KPD32 V5 | 6946 | 6258 | 688 | 4125 | 0 | 0 | 64 | 16 |

相对 V3 的 V5 增量：

| 项目 | V5 - V3 |
|---|---:|
| Slice LUT | +1470 |
| Logic LUT | +1470 |
| LUTRAM | 0 |
| FF | +850 |
| BRAM | 0 |
| DSP | 0 |
| CARRY4 | 0 |
| Fmax | +6.933 MHz |

相对 pre-ECC HDC 的 V5 增量：

| 项目 | V5 - pre-ECC |
|---|---:|
| Slice LUT | +2441 |
| Logic LUT | +2441 |
| LUTRAM | 0 |
| FF | +2045 |
| Fmax | +11.751 MHz |

资源解释：

- LUTRAM 保持 688，没有因为 ECC 把 VRF 复制或者变成 BRAM。
- BRAM/DSP 仍为 0，说明 KPD32 仍是 LUT/FF + 现有 popcount 复用路线。
- V5 比 V3 多出来的面积主要来自两块：
  - ECC shadow/product/leaf 状态和 Karatsuba fold 逻辑。
  - `hdec_p2_pop_slice` 现在同时服务 HDC 和 ECC packed parity，`src_b_q` 被捕获，2x32 popcount 半片更完整地保留下来。
- V5 的 F7 Mux 从 V3 的 264 降到 64，说明虽然 LUT/FF 增加，但大 mux 结构反而更少。

## 三、层次资源

| 版本 | top-local LUT | pop slice LUT 合计 | VRF total LUT | top-local FF | pop slice FF 合计 | VRF FF |
|---|---:|---:|---:|---:|---:|---:|
| pre-ECC HDC | 643 | 412 | 3450 | 1503 | 312 | 265 |
| ECC V3 | 1241 | 129 | 4106 | 2695 | 312 | 268 |
| ECC KPD32 V5 | 1772 | 1493 | 3681 | 3288 | 568 | 269 |

这个表很关键：

- V5 的 VRF total LUT 比 V3 低了 425，不是 VRF 变差。
- V5 的主要 LUT 增量在 pop slice 和 top-local ECC 控制/折叠。
- pop slice LUT 上升明显，是后续最值得继续压面积的地方。它不是额外 ECC 专用引擎，而是共享 popcount slice 被扩展后综合出的成本。

## 四、V5 ECC 算法理解

原始 V3/V1 的想法是：

```text
256-bit A x 256-bit B
对 product[0..510] 的每一条大斜线：
  取 A[i] & B[k-i]
  把这一整条 256-bit 斜线喂给 4 个 64-bit lane
  popcount 的奇偶性就是 product[k]
```

这个方法很直观，也很有 HDC 复用味道，但问题是每次只能出 1 个 product bit，所以原始 512-bit 多项式乘法需要约 511 次斜线计算。

V5 的 KPD32 做法是：

```text
把 256-bit 拆成 8 个 32-bit limb
用三层 Karatsuba：
  256 -> 128 -> 64 -> 32
最终得到 27 个 32x32 叶子乘法
```

每个 32x32 叶子乘法仍然使用你的“斜线加法/奇偶校验”思想：

```text
leaf_p[k] = parity(a[i] & b[k-i])
k = 0..62
```

关键创新点是粒度对齐：

```text
HDEC 现有 popcount slice =
4 lanes * 每 lane 2 个 32-bit half
= 一拍可以提供 8 个 32-bit parity reducer
```

所以 V5 不是一拍算一条 256-bit 大斜线，而是一拍打包 8 条 32-bit 小斜线：

```text
lane0 = {diag1_partial[31:0], diag0_partial[31:0]}
lane1 = {diag3_partial[31:0], diag2_partial[31:0]}
lane2 = {diag5_partial[31:0], diag4_partial[31:0]}
lane3 = {diag7_partial[31:0], diag6_partial[31:0]}
```

然后读取每个 32-bit popcount 的最低 bit：

```text
popcount[0] = 奇偶性
```

也就是说，V5 的创新不是“另做一个 ECC 乘法器”，而是：

```text
Karatsuba 降低叶子乘法数量
+ 32-bit 叶子大小刚好匹配 HDEC popcount 半片
+ 每拍 8 条小斜线并行
+ GF(2) 的重组只需要 XOR fold
```

## 五、V5 硬件流程

V5 的 ECC multiply 当前仍输出 raw 512-bit polynomial product：

```text
dst     = product[255:0]
dst + 1 = product[511:256]
```

流程如下：

```text
S_ECC_LOAD_A / S_ECC_LOAD_B
  从 VRF 读入 256-bit A/B

S_ECC_KPD32_FORM
  根据 leaf_id 生成一个 32-bit Karatsuba leaf pair
  leaf operand 是 A/B 的 32-bit limb 或 limb XOR 组合

S_ECC_DIAG_ISSUE
  对当前 leaf 的 diag_base, diag_base+1, ..., diag_base+7
  生成 8 个 32-bit diagonal partial
  打包进 4 个 HDEC popcount lane

hdec_p2_pop_slice
  用现有 2x32 popcount half 算每条小斜线的 1 的个数
  取 LSB 当 parity bit

S_ECC_DIAG_ACCUM
  把返回的 8 个 parity bit 写入 64-bit ecc_leaf_prod_q

S_ECC_LEAF_FOLD
  按 Karatsuba 线性重组，把 64-bit leaf product XOR 到 512-bit ecc_product_q

S_ECC_WRITE_WORD
  把 512-bit raw product 分 8 个 64-bit word 写回 VRF
```

V5 现在还没有做 modular reduction，也还不是完整 scalar multiplication。它完成的是一个很关键的底层乘法核验证：KPD32 raw GF(2) product。

## 六、为什么说 V5 方法有创新度

已知元素分别是：

- Karatsuba：经典二元域乘法降复杂度方法。
- diagonal parity：GF(2) 乘法中按斜线求奇偶性也很自然。
- popcount：HDC 的相似度计算核心算子。

V5 的创新点在组合方式：

```text
不是把 ECC 乘法硬塞给 HDEC，
而是选择 32-bit Karatsuba leaf，
让 leaf diagonal 的宽度刚好等于 HDEC popcount half slice，
从而让 ECC 的关键非线性乘法复用 HDC 的 popcount 数据通路。
```

这个比“移位 + 累加”更贴近 HDEC：

- shift-accumulate 主要需要移位器、条件 XOR、循环累加。
- KPD32 diagonal parity 主要需要 AND partial + popcount parity。
- HDEC 已经有高价值的 popcount slice，所以 KPD32 更符合“ECC/HDC 算子复用”的故事。

## 七、当前问题和下一步

当前 V5 是一个很好的研究点，但还不是最终 PPA 最优点。

最明显的问题：

1. `hdec_p2_pop_slice` 的 LUT 从 V3 的 129 合计涨到 V5 的 1493 合计，需要继续看是否有冗余综合。
2. V5 保留了 512-bit raw product accumulator，后续如果直接做 modular reduction，可以尝试不保存完整 512-bit，而是边 fold 边 reduction 到 256-bit。
3. `ecc_kpd32_fold_leaf` 现在是大 case + 多个 64-bit shift mask XOR，虽然没有成为关键路径，但面积可能还能压。
4. 当前最差路径仍偏 route-dominated HDC lane result capture，说明 ECC 没破坏主频，但布线仍是最终上限之一。

建议下一步：

| 方向 | 目标 | 预期影响 |
|---|---|---|
| KPD32 fold 直接模约简 | 去掉或缩小 512-bit product accumulator | FF 可能明显下降，LUT 取决于 reduction map |
| pop slice parity sideband 明确化 | 让 ECC 只消费 parity，不把 full count 逻辑强迫保留在 ECC 用途中 | 有机会降低 pop slice LUT |
| leaf fold map 表驱动压缩 | 把 27 个 leaf 的重复 shift/XOR mask 结构整理成更稀疏的 XOR target 更新 | 降 LUT，避免后续 reduction 后爆炸 |
| 分离 HDC count 模式与 ECC parity 模式的控制 | 同一个 slice，两个 mode，但让综合器能删掉 ECC 不需要的 count 高位路径 | 降 LUT，需谨慎避免影响 HDC HSIM/HMATCH |

## 八、结论

V5 成立，而且结果比预期健康：

- 200MHz OOC 通过，WNS +0.232 ns，估算 Fmax 209.732 MHz。
- KPD32 没有把 ECC fold 或 product accumulator 推成关键路径。
- LUTRAM 不变，BRAM/DSP 仍为 0，说明没有偏离 LUTRAM VRF + popcount reuse 架构。
- 面积相对 V3 增加 +1470 LUT、+850 FF，代价不小，但这是在加入 Karatsuba-packed ECC raw multiply 后的代价。
- 这版的算法路线比 V1/V3 “一条 256-bit 大斜线一次”更有研究价值，因为它把 Karatsuba 的叶子大小主动调到 HDEC popcount 半片的物理粒度上。

一句话总结：

```text
V3 是“用 HDEC popcount 算 ECC 斜线”；
V5 是“把 ECC 乘法改造成适合 HDEC popcount 半片吞吐的 Karatsuba-packed 斜线算法”。
```

这就是 V5 的核心价值。
