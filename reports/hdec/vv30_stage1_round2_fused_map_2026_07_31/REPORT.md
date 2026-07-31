# VV30 融合映射第二轮结构优化报告

## 结论

本轮在独立工作树中镜像当前 VV30 的 H5 HPERM 修复与 F1d 模板映射，不修改主工作树。匹配入口为 4643 Logic LUT、1308 FF、4 BRAM、0 DSP、WNS 0.328 ns、估算 Fmax 214.041 MHz，ECC_MUL 为 184 周期。

最终候选 C5 将原来的“128 位叶乘积构造、四次分段折叠”改写为连续组合链：

1. 根据 32 位子乘积位置直接生成两个 64 位半字。
2. 一次生成八个全局乘积字。
3. 用平坦固定方程形成 233 位模贡献包。

C5 得到 4625 Logic LUT、1305 FF、4 BRAM、0 DSP、WNS 0.328 ns、估算 Fmax 214.041 MHz。相对本轮匹配入口减少 18 Logic LUT、3 FF，域乘、PMUL周期及时序不变。

## 候选比较

| 候选 | 结构 | Logic LUT | FF | WNS/ns | Fmax/MHz | 结论 |
|---|---|---:|---:|---:|---:|---|
| 入口 H5+F1d | 当前主 VV30 镜像 | 4643 | 1308 | 0.328 | 214.041 | 基线 |
| C1 | 显式 63 位流水边界 | 4705 | 1308 | 0.328 | 214.041 | 淘汰 |
| C2 | 八字一次生成、平坦模折叠 | 4627 | 1305 | 0.328 | 214.041 | 通过 |
| C3 | C2 加直接 leaf-lo/leaf-hi | 4625 | 1305 | 0.328 | 214.041 | 通过 |
| C4 | 八个字逐项显式选择 | 5093 | 1304 | 0.328 | 214.041 | 淘汰 |
| C5 | 子乘积位置与平坦折叠融合函数 | 4625 | 1305 | 0.328 | 214.041 | 最终候选 |

C1 表明 Vivado 已自动消除第 64 个恒零乘积位，显式缩位破坏了原有逻辑共享。C4 表明循环形式对综合器的跨字共享十分重要，逐项展开虽然数学等价，却复制了大量选择逻辑。

## 验证

最终 C5 已通过：

- 独立数学黄金模型的 4464 个单位基组合，覆盖 16 条路径编码、3 个子乘积位置、3 个局部组、31 个斜线系数基向量。
- 9 条有效路径与 7 条无效路径，所有无效路径均产生零贡献。
- 4096 组已有对角恢复与模映射回归。
- ECC 对角域乘回归。
- ECC_MUL 周期回归，184 周期。
- PMUL 功能回归。
- PMUL profile，166840 wall cycles。
- Vivado 2024.2、`xc7z020clg400-2`、5.000 ns 匹配 OOC 综合。

独立 4464 单位基测试直接调用最终的 `ecc_kpd64_subproduct_reduce_packet`，黄金结果由两级 Karatsuba 支持集合及 GF(2^233) 多项式约减定义生成，没有调用 DUT 映射函数生成期望值。

## 证据

工作树：

`E:\HDEC\cva6-vhdc-core\tmp\hdec_vv30_fused_round2_probe`

日志：

- 入口：`tmp/hdec_logs/vv30_fused_round2/baseline_h5_f1d`
- C1：`tmp/hdec_logs/vv30_fused_round2/c1_explicit63`
- C2：`tmp/hdec_logs/vv30_fused_round2/c2_flat8word`
- C3：`tmp/hdec_logs/vv30_fused_round2/c3_split_halves`
- C4：`tmp/hdec_logs/vv30_fused_round2/c4_explicit8word`
- C5：`tmp/hdec_logs/vv30_fused_round2/c5_fused_token_reduce`
- C5 独立单位基：`tmp/hdec_logs/vv30_fused_round2/c5_fused_token_reduce/direct_unit`
- C5 最终命名匹配 OOC：`tmp/hdec_logs/vv30_fused_round2/c5_subproduct_reduce_renamed/ooc`

## 合入边界

待合入 RTL 仅涉及 `core/hdec/rtl/hdec_top.sv` 中的模贡献映射函数及 `ecc_direct_reduce_word` 组合连接。主 VV30 的 HPERM、平方复用、状态机、CV-X-IF、VRF及通道模块均不在本轮修改范围内。

本轮没有删除 64 位流水寄存器。此前直接删除该边界会使 Fmax 降至 179.340 MHz。C5保留该流水边界，通过消除重复的分段选择与128位临时表示获得面积收益。

该结果可作为“斜线系数到模贡献的融合映射”的实现证据，但不应独立表述为新的数学理论或并列论文创新。
