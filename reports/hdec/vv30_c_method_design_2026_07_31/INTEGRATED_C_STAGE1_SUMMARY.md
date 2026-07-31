# VV30 Section IV-C 主工作树集成摘要

日期：2026-07-31
分支：`VV30`
工作树：`E:\HDEC\cva6-vhdc-core\tmp\hdec_vv30_three_structures_worktree`
起点：`a3ba6f4b6289d7cef4dd9bdfe08cb8e6da361ad8`
状态：未提交，未推送

## 方法

建议将 Section IV-C 统一为：

> 面向共享模余数状态的 GF(2) 数据流重构。

该方法以斜线系数到 233 位模贡献的融合映射为入口，以连续余数更新为
共同状态语义，并依据代数依赖与状态生存期进一步收缩 PMUL 计算图。
正文代表结构包括：

- 仿射恢复公共因子收缩。
- 求逆平方链的伴随行重定向。
- 基于 Frobenius 线性的倍点平方链收缩。
- 点加 Z 模余数的最终目的地前递。

这些是同一方法的连续实现机制，不作为四项并列论文创新。

## 集成

ECC 改动通过 VV25 共同起点执行三方合并。主工作树已有的 HPERM 地址
与预取改动得到保留，未被探针版本覆盖。

## 正式 stage1

主种子：

`885b248c31a01bda00842cbe82496065a15631749d670fc153bf62d039b8998f`

以下七项全部通过：

- `fused_map_unit`。
- `diag_native_map`。
- `square_basis`。
- `shift_align_basis`。
- `inv_redirect_contract`。
- `pmul_random_k`。
- `hdc_full_flow`。

四个随机 K 均与独立 K-233 黄金模型一致，周期均为 159221。

三方合并后的 HPERM 完整性保护也通过：

- 新契约测试覆盖 256 个合法四位对齐旋转，768 个非法编码，
  256 组源目的槽组合，PASS。
- 旧 `HDEC_HPERM_BIT_ALIGN`，PASS。

这些结果只证明合并保留了既有 HPERM 行为，HPERM 不进入本节创新。

## 匹配综合

器件：`xc7z020clg400-2`
时钟约束：5 ns
Vivado：2024.2

| 配置 | LUT | FF | WNS/ns | Fmax/MHz | PMUL 周期 |
|---|---:|---:|---:|---:|---:|
| A7=0，A8=0 | 4673 | 1270 | 0.328 | 214.041 | 163648 |
| A7=1，A8=1 | 4651 | 1274 | 0.328 | 214.041 | 159221 |

最终配置相对匹配基础配置：

- LUT 减少 22。
- FF 增加 4。
- PMUL 减少 4427 周期，下降 2.705%。
- WNS 与 Fmax 保持不变。

## 全方法累计消融

下表使用同一个随机 K：

`0000001d75a3c5817938cfbe205af4142d603045054dd77f5628b7d4d1ef1f02`

主种子：

`46a7f3dabc5aa3b774535772db9c6d5565ea917fd7ca8e41ccaccded41bafae3`

| 累计配置 | LUT | FF | WNS/ns | Fmax/MHz | PMUL 周期 |
|---|---:|---:|---:|---:|---:|
| 融合映射后的基础图 | 4726 | 1276 | 0.328 | 214.041 | 163811 |
| 加入模余数初始化 | 4724 | 1275 | 0.328 | 214.041 | 163789 |
| 加入仿射公共因子收缩 | 4651 | 1271 | 0.328 | 214.041 | 163666 |
| 加入求逆伴随行重定向 | 4673 | 1270 | 0.328 | 214.041 | 163648 |
| 加入 Frobenius 倍点收缩 | 4644 | 1274 | 0.328 | 214.041 | 160386 |
| 加入 Z 状态前递，完整方法 | 4651 | 1274 | 0.328 | 214.041 | 159221 |

从基础图到完整方法：

- LUT 减少 75。
- FF 减少 2。
- PMUL 减少 4590 周期，下降 2.802%。
- WNS 与 Fmax 保持不变。

面积并非逐级单调。求逆重定向及 Z 前递增加了地址选择，后续计算图收缩
又消除了更多组合逻辑。因此正文应强调完整数据流重构的联合结果，逐级
数据用于消融，不把每个中间点单独包装为面积创新。

## 证据

集成回归与综合：

`E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\vv30_integrated_c_stage1_20260731`

HPERM 合并保护：

`E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\vv30_integrated_hperm_guard_20260731`

全方法消融：

`E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\vv30_method_ablation_20260731`

全方法消融向量：

`E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\vv30_method_ablation_vectors_20260731`

可重放运行清单：

`E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\vv30_integrated_c_stage1_20260731\regression\run_manifest.json`

详细演进，失败变体，消融与旧 19 项回归：

`E:\HDEC\cva6-vhdc-core\tmp\hdec_vv30_diag_native_probe\reports\hdec\vv30_diag_native_probe_2026_07_31\PMUL_GF2_GRAPH_RESTRUCTURE_STAGE_REPORT.md`

## 论文边界

- 不把 GF(2) 恒等式本身宣称为新数学。
- 不把融合映射，公共因子，求逆重定向，倍点收缩，Z 前递拆成并列贡献。
- 不在本节声称平方复用 XOR0 或 XOR1，相关物理探针已被拒绝。
- HPERM 属于功能修复，不进入 Section IV-C 创新叙事。
