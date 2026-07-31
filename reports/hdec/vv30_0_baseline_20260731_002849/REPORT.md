# VV30-0 精确基线报告

## 结论

VV30 的比较基线已在独立的只读工作树中锁定到提交
`a3ba6f4b6289d7cef4dd9bdfe08cb8e6da361ad8`。使用 Vivado 2024.2、
`xc7z020clg400-2`、5 ns 时钟约束进行匹配 OOC 综合，结果如下。

| 指标 | 精确基线 |
|---|---:|
| Logic LUT | 4661 |
| FF | 1304 |
| BRAM | 4 |
| DSP | 0 |
| WNS | 0.328 ns |
| 估算 Fmax | 214.041 MHz |
| ECC_MUL 周期 | 184 |

该结果与既有 VV25 R31 记录一致。后续每一项候选结构均须使用相同器件、
约束、Vivado 版本以及匹配测试向量进行比较。

## 基线功能检查

以下测试在精确提交快照上通过。

- 本地 XOR1 结构测试。
- ECC 斜线乘法测试。
- ECC 斜线到模贡献映射测试，4096 个旧向量。
- ECC 域乘测试，184 周期。
- 旧 PMUL 功能测试。
- 旧 HPERM 位对齐测试。
- HDC 完整流程测试。

旧 PMUL 测试仍使用固定 `K=3`，其日志中的 `PMUL_CYCLES=0` 不能作为周期
证据。旧 HPERM 测试也只覆盖过时的位对齐行为。两项缺口均由新的 VV30
随机向量、逐 K 周期监视以及 4 位粒度 HPERM 契约测试替代，旧测试仅保留
为兼容性保护。

## 证据位置

- 精确 OOC：
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_vv30_baseline_worktree\tmp\hdec_logs\vv30\20260731_002849_exact_baseline_ooc`
- 精确功能检查：
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_vv30_baseline_worktree\tmp\hdec_logs\vv30\20260731_003023_exact_baseline_functional`
- 初次竞态检查：
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_vv30_three_structures_worktree\tmp\hdec_logs\vv30\20260731_002631_baseline_ooc`

初次综合期间主工作树开始写入阶段一 RTL，因此该目录只作为交叉检查。
正式基线仅采用独立精确提交快照的结果。

## 叙事边界

本报告只建立工程比较基线，不产生论文创新结论。HPERM 后续改动属于功能
正确性修复。融合映射与平方约减复用只有在功能、周期、网表、面积及时序
证据共同成立后，才可作为共享 GF(2) 后端的实现机制写入论文。
