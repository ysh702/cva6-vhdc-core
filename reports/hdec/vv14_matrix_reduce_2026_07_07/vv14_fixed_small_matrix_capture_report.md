# VV14 固定小矩阵斜线捕获实验报告

## 基线

- Commit: `4416cac5` (`VV14 leaf matrix modular reduction checkpoint`)
- Logic LUT: 4677
- FF: 1436
- Fmax: 207.684 MHz
- PMUL wall cycles: 392560
- BRAM: 4
- DSP: 0

## 修改思想

本轮围绕“每组斜线的指数范围可预测，因此可以做成固定小矩阵”展开。

原先最后一个 8-row diagonal group 完成后，需要进入 `S_ECC_DIAG_WAIT`，再把 64-bit leaf product 折入 128-bit subproduct。该等待拍不是数学必须步骤，而是旧状态边界留下的调度空泡。

本轮将 group 7 的固定指数落点直接写成固定拼接：

```text
{1'b0, parity_row[6:0], leaf_prod[55:0]}
```

这等价于把最后一组斜线结果按已知指数范围放入固定小矩阵边界，并在 `S_ECC_DIAG_CAPTURE` 的最后一拍直接完成 sub32 accumulation。这样保留 leaf-level matrix modular reduction，不恢复完整乘积暂存。

同时，row tile 中的 32-bit popcount 从单个 `$countones(32)` 改成四个 8-bit 局部计数再相加。该修改保持 HDC/ECC 统一位矩阵行包格式和 popcount-LSB 语义不变，但让 Vivado 更容易形成局部规则计数网络，修复了 v3 的 popcount 路径时序近失效。

## 结果

| 版本 | Logic LUT | FF | Fmax | PMUL cycles | BRAM | DSP |
|---|---:|---:|---:|---:|---:|---:|
| VV14 leaf matrix baseline | 4677 | 1436 | 207.684 MHz | 392560 | 4 | 0 |
| fixed small-matrix capture | 4665 | 1422 | 207.297 MHz | 360484 | 4 | 0 |

相对基线变化：

- Logic LUT: -12
- FF: -14
- PMUL cycles: -32076
- Fmax: 仍高于 200 MHz

## 已验证

- `xsim_hdec_hdc_full_flow_v20`: PASS
- `xsim_hdec_ecc_pmul_profile_v27`: PASS, `PMUL_PROFILE_WALL_CYCLES=360484`
- `xsim_hdec_ecc_reduce_v1`: PASS
- `xsim_hdec_ecc_add_v1`: PASS
- OOC: Vivado 2024.2, `xc7z020clg400-2`, 5 ns, PASS

## 结论

这版是有效阶段胜利：它没有依靠新增寄存器或额外 ECC 专属硬件，而是利用斜线 group 的固定指数范围，把最后一组斜线捕获和 subproduct 折入合并为一个固定小矩阵边界操作。它同时降低面积和周期，并保持 200 MHz 时序。
