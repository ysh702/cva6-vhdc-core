# VV14 结构化矩阵模约减阶段报告

## 目标

本轮不再采用复制寄存器、镜像寄存器或人为拆扇出的方式换时序，而是从模约减本身的结构入手，把 GF(2^233) 的模约减看成固定的 GF(2) 线性矩阵变换。

目标是：小面积增加、大幅减少 PMUL 周期、恢复 200 MHz 以上时序，并保留“矩阵化模约减”这一条论文可讲的结构路线。

## 当前保留候选：leaf-level fixed GF(2) fold matrix

当前 RTL 将此前的 slot 串行约减状态删除，不再对每个 8-bit 斜线行按多个 slot 逐个生成贡献包。

新的数据流为：

```text
32x32 叶乘法
-> 斜线奇偶行
-> 叶级局部系数向量
-> 固定 GF(2) 模折叠矩阵
-> 4x64 位贡献包
-> XOR0 / 向量累加路径
```

这不是完全逐斜线级别的边算边模，但它把模约减从“动态 slot 串行映射”改成了“叶级固定矩阵映射”。因此它仍然是结构层面的矩阵模约减，而不是时序修补。

## 对比数据

| 版本 | Logic LUT | FF | Fmax | PMUL cycles | 结论 |
|---|---:|---:|---:|---:|---|
| VV14 slot-matrix baseline | 4357 | 1255 | 199.243 MHz | 848752 | 面积低，但周期过高且 200 MHz 未过 |
| row matrix reduce v1 | 5337 | 1258 | 156.177 MHz | 功能过但未保留 | 行级矩阵过宽，综合成大 mux |
| pair-slot matrix v1 | 5747 | 1256 | 164.826 MHz | 506608 | 两个 slot 并行导致矩阵逻辑复制，面积和时序失败 |
| dense hybrid v1 | 5198 | 1445 | 184.060 MHz | 506608 | 周期下降但面积和时序失败 |
| matrix mirror keep v1 | 5341 | 1510 | 180.865 MHz | 未保留 | 属于复制寄存器换时序，且数据更差 |
| leaf matrix reduce v1 | 4677 | 1436 | 207.684 MHz | 392560 | 当前最好结构性候选 |

## 当前候选验证结果

Vivado OOC:

```text
Logic LUT = 4677
Total LUT = 4677
LUTRAM = 0
FF = 1436
BRAM = 4
DSP = 0
Fmax = 207.684 MHz
WNS = 0.185 ns
Worst endpoint = i_vec/popcount_part_q_reg[0][0][4]/D
```

Vivado 仿真:

```text
xsim_hdec_hdc_full_flow_v20          PASS
xsim_hdec_ecc_pmul_profile_v27       PASS, PMUL_PROFILE_WALL_CYCLES=392560
xsim_hdec_ecc_reduce_v1              PASS
xsim_hdec_ecc_add_v1                 PASS
xsim_hdec_ecc_align_v1               PASS
xsim_hdec_ecc_pmul_bg_idle_v27       PASS, PMUL_BG_IDLE_WALL_CYCLES=392561
xsim_hdec_ecc_pmul_bg_hdc_loop_v31   PASS, PMUL_BG_HDC_LOOP_WALL_CYCLES=393658
```

旧的 `xsim_hdec_ecc_diag_reduce_map_v1` 当前会 elaboration 失败，因为该测试直接调用旧的 `ecc_kpd64_diag_reduce_packet` slot 函数；当前结构已经删除该函数。该项需要后续改成验证 leaf-level fixed fold matrix 的新参考模型。

## 结构判断

当前版本比 slot-matrix baseline 多约 320 Logic LUT、181 FF，但换来了：

- PMUL 从 848752 cycles 降到 392560 cycles，减少 456192 cycles。
- Fmax 从 199.243 MHz 恢复到 207.684 MHz。
- Logic LUT 仍低于 4700 的硬门槛。
- 仍保持 4 BRAM、0 DSP。

因此这版不是“用寄存器换时序”，而是把模约减从细粒度动态 slot 串行，改成叶级固定 GF(2) 线性矩阵。它牺牲少量面积，换回周期和时序，是目前更合理的矩阵模约减结构。

## 后续建议

1. 将 `diag_reduce_map` 旧测试改为 leaf-level 矩阵参考模型，不再调用已删除的旧 slot 函数。
2. 若继续优化，优先压缩 leaf fold/write drain 周期，而不是增加寄存器镜像。
3. 若继续追求更强“边算边模”故事，应以当前 leaf matrix 作为安全点，逐步把部分固定矩阵提前到斜线组边界，而不是回到逐 slot 动态映射。
