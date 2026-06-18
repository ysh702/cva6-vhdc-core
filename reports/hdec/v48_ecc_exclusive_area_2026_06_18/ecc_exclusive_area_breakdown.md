# V48 Current ECC Exclusive Area Breakdown

Date: 2026-06-18

## 口径

本报告统计当前工作区 RTL，也就是包含 V48 optional AND-overlap 修改后的版本。

这里的“ECC 专属面积”只统计现在仍然只能服务 ECC 的资源。已经被 HDC/ECC 共用的资源不再算进 ECC 专属，包括：

- lane 内融合 XOR / 归约 XOR。
- lane 内 bool 结果寄存器和 popcount。
- lane 内共享 AND / product 入口。
- VRF BRAM 和 VRF 顶层读写控制。
- HPERM / shift-align 这类 HDC 与 ECC 都会走的共享数据通路。

Vivado 综合会把部分状态机和地址选择逻辑合并到顶层控制中，所以本报告采用 strict name-based lower bound：凡是仍然带有 `ecc_*` / `kpd` / `product_pair` 等清晰名字的资源算 ECC 专属；名字已经被综合进通用 top control 的资源不强行算给 ECC。

特别注意：这里的 ECC 专属计算不是指 lane 里的 AND/XOR 算子。HDC overlap 已经使用 lane 内 `bool_product_word -> bool_result_q -> popcount` 这条共享路径，所以这部分不计入 ECC 专属。下面算入 ECC 专属的是 `ecc_product_pair`、`ecc_leaf_prod_q`、`ecc_leaf128_prod_q`、KPD fold/mask、ECC reduce source assembly 等仍然只服务 GF(2^233) 乘法/约减的状态和周边逻辑。

## 当前 OOC 总面积

OOC 目录：

`reports/hdec/v48_ecc_exclusive_area_2026_06_18/ooc_ecc_area_bucket`

| Metric | Value |
|---|---:|
| Slice LUT | 5656 |
| Logic LUT | 5528 |
| LUTRAM | 128 |
| FF | 1720 |
| BRAM tile | 4 |
| DSP | 0 |
| CARRY4 | 15 |
| WNS | 0.244 ns |
| Estimated Fmax | 210.261 MHz |

## ECC 专属面积汇总

`Logic LUT` 是把 bucket 原始 LUT cell 按当前 Vivado 最终 Logic LUT 总数归一后的估计值，用于和 `5528 Logic LUT` 对齐。

| 类别 | 组成 | Est. Logic LUT | 占总 Logic LUT | FF | 占总 FF | LUTRAM |
|---|---|---:|---:|---:|---:|---:|
| ECC 专属计算/数据通路 | ECC 私有乘法状态、约减映射、product scratch 周边 | 857 | 15.50% | 384 | 22.33% | 128 |
| ECC 专属控制/调度 | 逆元、点乘、ECC job 调度状态 | 121 | 2.18% | 74 | 4.30% | 0 |
| ECC 专属总计 | 上面两项相加 | 978 | 17.68% | 458 | 26.63% | 128 |

补充说明：

- `LUTRAM=128` 基本都来自 `ecc_product_pair` 乘积 scratch。bucket CSV 中会看到 256 个 RAM16 级别 cell，但 Vivado 最终映射为 128 个 RAMS32，因此正式口径按最终 `LUT as Memory=128`。
- ECC 专属 BRAM 为 0。当前 4 个 BRAM tile 都是共享 VRF。
- ECC 专属 DSP 为 0。

## ECC 专属计算部分

| Bucket | Raw LUT cell | Est. Logic LUT | FF | LUTRAM | 说明 |
|---|---:|---:|---:|---:|---|
| `ecc_exclusive_mul_reduce_datapath` | 819 | 691 | 384 | 0 | ECC 私有 leaf/diag/pipe/accum、KPD fold/mask、GF(2^233) reduce source assembly 等；不包含 lane 里的共享 AND/XOR/popcount |
| `ecc_exclusive_product_scratch` | 196 | 166 | 0 | 128 | `ecc_product_pair` 乘积暂存和 fold scratch；HDC 当前不读写这块 scratch，最终 LUTRAM 为 128 |
| 计算小计 | 1015 | 857 | 384 | 128 | 仍属于 ECC 私有的乘法状态和乘积存储下界 |

## ECC 专属控制部分

| Bucket | Raw LUT cell | Est. Logic LUT | FF | 说明 |
|---|---:|---:|---:|---|
| `ecc_exclusive_inv_pmul_schedule` | 143 | 121 | 74 | ECC inversion、point multiplication、ECC job/status/后台调度等控制状态 |
| 控制小计 | 143 | 121 | 74 | 仍带 ECC 名字的控制下界 |

## 不再算 ECC 专属的共享部分

| Bucket | Est. Logic LUT | FF | BRAM | 为什么不算 ECC 专属 |
|---|---:|---:|---:|---|
| `shared_lane_operator` | 742 | 305 | 0 | lane 内 XOR、AND/product、popcount、clip、shift、diag parity 已经被 HDC/ECC 共同使用 |
| `shared_vrf_bram` | 3217 | 0 | 4 | VRF 是 HDC/ECC 共享存储，不是 ECC 私有存储 |
| `shared_vrf_top_control` | 116 | 14 | 0 | VRF 顶层读写控制服务 HDC/ECC 双方 |
| `shared_shift_spread_operator` | 7 | 1 | 0 | shift/spread 路径服务 HPERM 和 ECC square/spread |
| `hdc_or_host_control` | 303 | 298 | 0 | HDC/host/uop 控制，不算 ECC 专属 |
| `unattributed_top_control` | 166 | 644 | 0 | 综合后名字已经泛化，不能可靠归到 ECC |

## 结论

当前版里，ECC 专属资源已经主要剩下两块：

1. ECC 私有乘法状态/约减映射/乘积 scratch：约 857 Logic LUT、384 FF、128 LUTRAM。
2. ECC 私有点乘/逆元/job 调度控制：约 121 Logic LUT、74 FF。

因此当前严格下界口径下：

- ECC 专属 Logic LUT 约 978，占总 Logic LUT 17.68%。
- ECC 专属 FF 约 458，占总 FF 26.63%。
- ECC 专属 LUTRAM 为 128，占当前 LUTRAM 100%，主要来自 product scratch。
- ECC 专属 BRAM/DSP 为 0。

这个结果说明：XOR、AND、popcount、VRF 这些大块已经不能再写成 ECC 私有面积。现在 ECC 私有面积真正的大头是 `ecc_product_pair` 这类乘积 scratch，以及只服务 GF(2^233) 乘法/约减的 KPD fold、leaf/diag/accum、reduce source assembly 周边逻辑；其次才是点乘/逆元控制。

## 当前真实复用边界

需要把“当前真实共享”和“未来可以改成共享”分开说：

| 资源 | 当前 HDC 是否真实使用 | 当前口径 |
|---|---:|---|
| lane 内融合 XOR / 归约 XOR | 是 | HDC/ECC 共享 |
| lane 内 AND / `bool_product_word` | 是 | HDC/ECC 共享 |
| lane 内 `bool_result_q` 和 popcount | 是 | HDC/ECC 共享 |
| VRF BRAM | 是 | HDC/ECC 共享 |
| `ecc_product_pair` / product scratch | 否 | 当前仍是 ECC 专属计算暂存 |
| `ecc_leaf_prod_q` / `ecc_leaf128_prod_q` | 否 | 当前仍是 ECC 专属乘法状态 |
| KPD fold/mask / GF(2^233) reduce source assembly | 否 | 当前仍是 ECC 专属乘法/约减数据通路 |

因此，如果按当前 RTL 真实连线统计，乘法/约减数据通路和 product scratch 仍然属于 ECC 专属计算面积。它们不是控制 LUT，而是下一版最应该攻克的计算 LUT 大头。

## 下一版第二阶段目标

V48 已经完成了第一阶段和第三阶段：

- 第一阶段：XOR/归约 XOR 合并到 lane 内共享 XOR。
- 第三阶段：HDC AND-overlap 算法落 RTL，并复用 lane 内 AND + popcount。

第二阶段还没有完成。之前第二阶段尝试把 HDC/ECC 的中间寄存器硬合并成同一条小流水线，但 LUT/MUX 增长太大，说明不能只从寄存器名字合并入手。

下一版应把第二阶段重新定义为“乘法/约减数据通路和 product scratch 的真实共享化”：

1. 将 `ecc_product_pair` 泛化为共享 scratch，而不是 ECC 私有 scratch。HDC 需要有真实读写路径，否则不能说它已经共享。
2. 将 KPD fold 中的移位 XOR 累加抽象成通用 fold-accum 单元。ECC 模式做二元域乘法/约减，HDC 模式尝试做 overlap/mask/bit-plane/prototype update 的分块累加。
3. 重新设计第二阶段流水线。用 tag/valid/payload 表示数据归属，让数据自然经过同一条流水线，而不是在每个寄存器前加大 MUX。
4. 面积验收重点看计算 bucket：`ecc_exclusive_mul_reduce_datapath` 和 `ecc_exclusive_product_scratch` 必须下降；控制 LUT 不是本阶段主要指标。

目标是在保持 200 MHz、周期不变或小幅可解释增加的前提下，把当前约 857 Logic LUT、384 FF、128 LUTRAM 的 ECC 专属计算下界往共享 bucket 中迁移，并且总面积不能因为控制/MUX 暴涨而抵消收益。
