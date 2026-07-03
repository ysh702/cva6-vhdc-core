# VV11 双 4x64 XOR 阵列与 GF(2) 双级流水计划

## 1. 基线选择

VV11 从 VV10 try1 开始：

- Commit: `ed042cfc`
- Logic LUT: 4477
- FF: 1426
- Fmax: 207.684 MHz
- PMUL: 296332 cycles

try31 不作为 VV11 基线：

- Logic LUT: 4478
- FF: 1426
- Fmax: 208.030 MHz
- PMUL: 296332 cycles
- 结论：try31 只让小窗口 parity 表达更清楚，但没有真正完成双 XOR 阵列统一，也没有 PPA 收益；后续仅作为结构化表达探针记录。

## 2. 两个 XOR 阵列的严格定义

### XOR0：4x64 向量贡献合并 XOR

功能：

```text
base_packet[4x64] XOR contribution_packet[4x64]
-> merged_packet[4x64]
```

负责：

- HDC HBIND。
- ECC 域加法 / 域减法。
- ECC 点加、点倍中的 GF(2) 加法。
- ECC 直接模折叠贡献包累加。
- ECC 显式 reduce 的结果累加。
- ECC product pair accumulator。
- 可整理成贡献包的 Karatsuba 子积合并。

核心原则：

- 只接收统一的 4x64 位贡献包。
- 不在 XOR0 前加入大型模式 MUX。
- ECC 数据必须提前整理成 contribution packet。

### XOR1：4x64 位矩阵折叠 XOR

功能：

```text
bitmatrix / local fold input
-> parity / folded contribution
```

负责：

- ECC AND+XOR 斜线归约。
- ECC 模平方固定指数折叠。
- Karatsuba `lo ^ hi`。
- leaf lowxor pack。
- leaf / subproduct 局部折叠。

核心原则：

- XOR1 处理局部折叠，不负责全局结果累加。
- AND+POPCOUNT 路线不额外使用 XOR1，因为 popcount 最低位已经是 parity。
- 不把 XOR1 做成万能可编程归约网络，避免面积和时序爆炸。

## 3. 直接模折叠的数据流

直接模折叠拆成两步：

```text
步骤 1：指数位置映射
高位贡献按照 f(x)=x^233+x^74+1 映射成 4x64 contribution packet

步骤 2：贡献包累加
XOR0 执行 acc ^= contribution_packet
```

要求：

- 指数位置映射尽量使用固定连线和轻量选择。
- 不让直接模折叠抢占 XOR1。
- 保留边算边模折叠的算法创新，不恢复完整 466-bit 乘积暂存后统一约减。

## 4. GF(2) 双级流水调度

目标流水：

```text
Cycle/group n:
XOR1 处理当前斜线组 / 局部折叠

Cycle/group n+1:
XOR1 处理下一组斜线
XOR0 同时累加上一组贡献包
```

也就是：

```text
前级：位矩阵斜线归约 / 局部折叠
后级：指数感知贡献包累加
```

这样形成：

```text
XOR1 -> contribution packet register -> XOR0
```

设计要求：

- 只允许 1 级贡献包寄存器。
- 不新增深队列。
- 不给 4 个 lane 添加独立控制状态。
- HDC 前台和 ECC 后台同时请求 XOR0 时，HDC 优先，ECC 等待一拍。
- PMUL 独占执行时，XOR0/XOR1 按流水持续推进。

## 5. 面积控制原则

必须避免之前失败尝试中的问题：

- 不做 top-level 中央大 XOR。
- 不做 4x64 大输入 MUX。
- 不把 ECC 数据硬塞进 HDC 原始格式。
- 先统一数据格式，再进入 XOR 阵列。
- 4 个 lane 只作为固定计算切片，不添加 lane 私有控制。
- 模平方和模折叠优先用固定连线，不做可编程 barrel shift。
- 若某个局部 XOR 接入两个阵列后导致 LUT 增加或周期明显增加，则保留局部实现并记录失败原因。

## 6. 实施顺序

### 阶段 A：建立 XOR0 向量贡献合并入口

目标：

- 把 HBIND 和 ECC 域加法继续统一到 XOR0。
- 把直接模折叠累加从局部 `acc ^ contribution` 改成 XOR0 的 contribution packet 累加。

验收：

- ECC reduce / PMUL 正确。
- Logic LUT 不高于 4477。
- Fmax >= 200 MHz。
- PMUL 不高于 296332 cycles。

### 阶段 B：建立 XOR1 位矩阵折叠入口

目标：

- 保持 try1 的 8x32 位矩阵 AND+POPCOUNT。
- 将 AND+XOR 斜线 parity、Karatsuba lowxor、局部 leaf fold 尽量整理到 XOR1。
- 不影响 AND+POPCOUNT 路线。

验收：

- `xsim_hdec_ecc_diag_mul_v1` 通过。
- Logic LUT 不高于 4477。
- 若只提升叙事但面积增加，则保存为 rejected patch。

### 阶段 C：双级流水重叠

目标：

- XOR1 处理当前斜线/局部折叠。
- XOR0 同时处理上一组贡献包累加。
- 形成 `XOR1 -> packet register -> XOR0` 的双级流水。

验收：

- PMUL 周期低于或等于 296332。
- Fmax >= 200 MHz。
- HDC full flow 不受影响。
- 背景 PMUL + HDC 前台测试通过。

## 7. 测试计划

快速测试：

- `xsim_hdec_ecc_diag_mul_v1`
- `xsim_hdec_ecc_reduce_v1`
- `xsim_hdec_ecc_add_v1`
- `xsim_hdec_hdc_full_flow_v20`
- `xsim_hdec_ecc_pmul_profile_v27`

OOC 综合：

- Vivado 2024.2。
- Part: `xc7z020clg400-2`。
- Clock: 5 ns。

最终补测：

- `xsim_hdec_ecc_align_v1`
- `xsim_hdec_ecc_pmul_bg_idle_v27`
- `xsim_hdec_ecc_pmul_bg_hdc_loop_v31`
- `xsim_hdec_hdc_selflearn_v1`

## 8. 最终验收门槛

硬门槛：

- Logic LUT <= 4477。
- FF <= 1426。
- Fmax >= 200 MHz。
- PMUL cycles <= 296332。

优先目标：

- Logic LUT 下降。
- ECC-only XOR 逻辑下降。
- PMUL 周期下降或不变。
- HDC 自学习准确率不变。

## 9. 论文叙事口径

建议表述：

> HDEC 将 HDC 与 ECC 中的算法级 GF(2) XOR 收敛到两个 4x64 XOR 阵列。XOR0 负责向量贡献合并，承载 HDC 绑定、ECC 域加法和直接模折叠累加；XOR1 负责位矩阵折叠归约，承载 ECC 斜线奇偶和局部 Karatsuba 折叠。两个阵列构成 GF(2) 双级流水，使斜线归约与指数感知贡献包累加能够交织执行，从而在保持 HDC 训练/推理和 ECC 标量点乘完整性的同时降低重复 GF(2) 逻辑。

注意：

- 不说“综合后所有 XOR 门只剩两个”。
- 说“所有算法级 GF(2) XOR 收敛到两个 4x64 XOR 阵列”。
- HDC 计数器加法内部 XOR 和 popcount 压缩树内部 XOR 不纳入该口径。

## 10. 结论

VV11 应从 try1 开始。

try31 可作为参考，但不作为正式基线。它更接近 XOR1 的表达方式，但没有完成双 XOR 阵列，也没有 PPA 收益。

真正的 VV11 目标是：

```text
XOR0：贡献包累加 / 向量合并
XOR1：斜线归约 / 局部折叠
二者形成 GF(2) 双级流水
```
