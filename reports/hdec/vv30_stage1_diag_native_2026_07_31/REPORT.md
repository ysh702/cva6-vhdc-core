# VV30 斜线系数原生模贡献映射阶段报告

## 结论

本阶段保留 A4 变体。生产路径不再先寄存 63 位局部组乘积，而是仅保留
31 位斜线系数，并利用 `CAP0`、`CAP1`、`CAP2` 的固定状态关系恢复组位置，
随后进入既有的子乘积位置映射、路径模板映射及共享 XOR0 余数更新。

该修改属于第四章 C 中“斜线系数到模贡献的融合映射”的实现强化，不是独立
的有限域乘法算法。

## 多变体筛选

| 变体 | LUT | FF | WNS/ns | Fmax/MHz | 结论 |
|---|---:|---:|---:|---:|---|
| F1d+C5 匹配基线 | 4636 | 1299 | 0.328 | 214.041 | 比较基线 |
| A1 | 4650 | 1265 | 0.328 | 214.041 | 功能成立，LUT 增加 |
| A2 | 4711 | 1264 | 0.328 | 214.041 | 淘汰 |
| A3 | 4664 | 1267 | 0.165 | 206.825 | 面积及时序均退化 |
| A4 | 4619 | 1266 | 0.328 | 214.041 | 保留 |

A4 相对匹配的 ECC 基线减少 17 LUT、33 FF，WNS 与周期不变。网表中的
`ecc_leaf_prod_q` 由 63 个物理寄存器减少至 31 个。

合入包含既有 HPERM 修改的 VV30 主工作树后，累计结果为 4623 LUT、1269 FF、
4 BRAM、0 DSP、WNS 0.328 ns、估算 Fmax 214.041 MHz。相对合入前主树的
4625 LUT、1305 FF，累计减少 2 LUT、36 FF，时序不变。

## 功能与周期

| 验证 | 结果 |
|---|---|
| 原生映射单位基 | 4464/4464 PASS |
| 既有融合映射单位基 | 4464/4464 PASS |
| 平方单位基与随机向量 | PASS |
| Shift-Align 单位基 | PASS |
| 四组全随机点与全随机合法 K 的 PMUL | PASS |
| PMUL 周期 | 每组均为 166840 |
| HDC 完整流程 | PASS |

最终统一回归的随机向量主种子为
`dbb690fc797e58a57fcdc97b330d9427f08253dc14a692818b21ed1cbc21a7b4`。
四个 K 的 Hamming weight 分别为 100、116、113、121，执行周期完全一致。

首次主树 HDC 回归暴露出此前 HPERM 地址修改误用于 HBIND 的旧污染，使 HBIND
从第 5 个 64 位字开始读取错误的第二源。修正仅恢复 HBIND 两个独立源流的逐行
递增，未继续修改 HPERM 功能。修正后的 HDC 完整流程通过。

## 证据

- 隔离 A4 探针：
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_vv30_diag_native_probe`
- 隔离探针报告：
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_vv30_diag_native_probe\reports\hdec\vv30_diag_native_probe_2026_07_31\REPORT.md`
- 主树最终统一 PASS 回归：
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\main_a4_stage1_pass2_20260731`
- 修正后 HDC 回归：
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\main_a4_hdc_fix_20260731`
- 主树 OOC：
  `E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\main_a4_ooc_20260731`

本阶段未提交、未推送。禁止修改文件未触碰。
