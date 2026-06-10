# HDEC V11 HPERM/HSPREAD OOC 摘要

日期：2026-06-10

Vivado：2024.2

Part：xc7z020clg400-2

约束：200 MHz，5.000 ns，hdec_top OOC

## 修改内容

- HPERM 的 lane shift-align 从 4bit 粒度升级为 1bit 粒度。
- 旧 HPERM 4bit/nibble 用法保持兼容：原来的 `operand[9:8]=00` 仍然等价于 4bit 移位。
- 新增 HSPREAD 子模式，复用 HPERM 指令入口：
  - `operand[18]=1`
  - `operand[11:6]=src_idx`
  - `operand[5:0]=dst_idx`
  - 一次操作读取 1 个 256bit VRF entry。
  - 低 32bit 展开写 `dst_idx`，高 32bit 展开写 `dst_idx+1`。
- HSPREAD 提供 `256bit -> 512bit` GF(2) 平方展开的共享基础能力，同时也是 HDC 可调用的稀疏 bit-layout/置换能力。

## OOC 结果

| 版本 | 说明 | LUT | Logic LUT | LUTRAM | FF | WNS ns | Fmax MHz | 结论 |
|---|---|---:|---:|---:|---:|---:|---:|---|
| round03 | 1bit HPERM，仅 bit-align | 5311 | 4839 | 472 | 2023 | 0.124 | 205.086 | 低面积基线 |
| round04 | 动态 spread 接入 lane shift mux | 5797 | 5325 | 472 | 2022 | -0.222 | 191.498 | 已回退 |
| round05 | HSPREAD 单次半展开 | 5480 | 5008 | 472 | 2030 | 0.112 | 204.583 | 可用但需要两次操作 |
| round06 | HSPREAD 一次写 low/high 两个 entry | 5531 | 5059 | 472 | 2024 | 0.177 | 207.340 | 当前保留 |

## 验证

- Python shift-align golden：PASS
- Vivado xsim `tb_hdec_shift_align_bit`：PASS
- Vivado xsim `tb_hdec_hperm_bit_align`：PASS
- Vivado xsim `tb_hdec_hmatch_compare_split`：PASS
- Vivado xsim `tb_hdec_ecc_diag_mul_v1`：PASS

## 结论

round06 相比 round05 多约 51 LUT，但一次 HSPREAD 就能完成完整平方展开，FF 更少，Fmax 更高。相比 round03，多约 220 LUT、1 FF，换来 HDC/ECC 共享的 `256bit -> 512bit` 平方展开能力，且仍稳定超过 200 MHz。

因此 V11 当前保留 round06，作为后续 ECC GF square / reduction / scalar point multiplication 的共享算子基础。
