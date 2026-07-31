# VV30 平方模约减共享结构试验报告

## 1. 结论

本阶段对五种不增加指令周期的平方模约减共享结构进行了功能验证及匹配 OOC 综合。五种候选均能保持 GF(2^233) 平方模约减结果正确，平方指令响应周期均为 5 个时钟周期，但没有一种候选同时满足面积及时序门槛。

最终决策为：

- VV30 主线继续保留原有私有平方模约减网络。
- 不将本报告中的 XOR1 或 XOR0 平方共享 RTL 合入主线。
- 第四章 C 删除“平方模约减复用 XOR1”及“平方模约减复用 XOR0”的声明。
- 平方模约减在论文中作为任务相关路径描述，不列入共享 GF(2) 后端的物理复用范围。

该结果不影响斜线系数到模贡献的融合映射，也不影响 PMUL 模贡献使用 XOR0 更新域状态的独立结论。

## 2. 试验边界

器件、约束及工具保持一致：

- Vivado 2024.2。
- `xc7z020clg400-2`。
- 5.000 ns 时钟约束。
- `hdec_top` OOC 综合。
- BRAM 及 DSP 统计纳入匹配比较。

每个候选均使用真实 HDEC 指令路径验证。测试通过 `HDEC_HPERM` 的自动 GF_SQR 操作启动平方模约减，同时实例化私有版及候选共享版，逐位比较两者的响应数据及响应周期。每个候选包含：

- 233 个单位基输入。
- 全零输入。
- 全一输入。
- 256 个由本次运行主种子生成的随机 233 位输入。

每个候选共执行 491 个用例。黄金值由测试平台中的独立数学平方及多项式约减模型产生，未调用 DUT 内部平方约减函数。

## 3. 候选结构

### S1，全部 153 条二输入关系复用 XOR1 节点 0 至 152

80 个单输入结果使用固定连线，153 个二输入结果全部映射到 XOR1 的前 153 个节点。该结构复用范围最大，但平方模式需要为大量 XOR1 节点增加输入选择。

### S2，全部 153 条二输入关系复用 XOR1 节点 14 至 166

该结构避开斜线恢复使用的 14 个节点，将平方关系整体后移。功能关系不变，目的是降低平方模式与斜线模式在节点位置上的重叠。

### S3，78 条关系复用 XOR1，75 条关系保留局部固定异或

该结构只将 78 条平方关系映射到 XOR1 节点 14 至 91，其余 75 条关系采用局部固定异或，减少多模式 XOR1 节点数量。

### S4，78 条关系复用当前有效 XOR1 节点

该结构将 14 条关系映射到斜线恢复节点 0 至 13，将 64 条关系映射到叶乘积低位异或节点 160 至 223，其余 75 条关系保留局部固定异或。它优先复用现有工作模式中实际使用的节点，是五个候选中最接近时序门槛的 XOR1 方案。

### S5，平方关系并入 XOR0 逐位归并逻辑

该结构不在 XOR0 前增加完整的 256 位结果选择器，而是把平方模约减条件直接写入每个 XOR0 输出位的组合关系。平方源位经过固定位置变换后，在 XOR0 所在逻辑中完成二输入异或及结果排列。

## 4. 功能及周期结果

| 候选 | 共享平面 | 功能结果 | 用例数 | 平方响应周期 |
|---|---|---:|---:|---:|
| S1 | XOR1 | PASS | 491 | 5 |
| S2 | XOR1 | PASS | 491 | 5 |
| S3 | XOR1 加局部异或 | PASS | 491 | 5 |
| S4 | 当前有效 XOR1 节点加局部异或 | PASS | 491 | 5 |
| S5 | XOR0 | PASS | 491 | 5 |

对应 PASS 标记为：

```text
[VV30:SQUARE_DIFF] PASS variant=1 cases=491 square_cycles=5 seed=37f1b3304a035397
[VV30:SQUARE_DIFF] PASS variant=2 cases=491 square_cycles=5 seed=b459e287528a4f25
[VV30:SQUARE_DIFF] PASS variant=3 cases=491 square_cycles=5 seed=316e2e14ab87a5d2
[VV30:SQUARE_DIFF] PASS variant=4 cases=491 square_cycles=5 seed=5a14b455ac5f1475
[VV30:SQUARE_DIFF] PASS variant=5 xor0=1 cases=491 square_cycles=5 seed=5f882acdbb874d68
```

## 5. 匹配 OOC 综合结果

S1 至 S4 使用同一私有平方控制版本作为基线。S5 增加了 XOR0 模式描述，因此单独使用该源状态下参数关闭的私有版本作为匹配基线。

| 版本 | LUT | FF | BRAM | DSP | WNS，ns | 估算 Fmax，MHz |
|---|---:|---:|---:|---:|---:|---:|
| S1 至 S4 私有基线 | 4661 | 1304 | 4 | 0 | 0.328 | 214.041 |
| S1，共享 | 4868 | 1304 | 4 | 0 | -0.476 | 182.615 |
| S2，共享 | 4884 | 1307 | 4 | 0 | -0.927 | 168.719 |
| S3，共享 | 4800 | 1302 | 4 | 0 | -0.474 | 182.682 |
| S4，共享 | 4795 | 1306 | 4 | 0 | -0.019 | 199.243 |
| S5 匹配私有基线 | 4658 | 1304 | 4 | 0 | 0.328 | 214.041 |
| S5，共享 | 4953 | 1305 | 4 | 0 | -0.218 | 191.644 |

相对各自匹配私有基线：

| 候选 | LUT 变化 | FF 变化 | WNS 变化，ns | Fmax 变化，MHz | 验收 |
|---|---:|---:|---:|---:|---|
| S1 | +207 | 0 | -0.804 | -31.426 | FAIL |
| S2 | +223 | +3 | -1.255 | -45.322 | FAIL |
| S3 | +139 | -2 | -0.802 | -31.359 | FAIL |
| S4 | +134 | +2 | -0.347 | -14.798 | FAIL |
| S5 | +295 | +1 | -0.546 | -22.397 | FAIL |

S4 虽然最接近 200 MHz，但仍未达到“Logic LUT 严格低于私有版”的首要门槛，同时估算 Fmax 为 199.243 MHz。因此不能因为接近时序门槛而保留该结构。

## 6. 失败原因分析

私有平方模约减是固定的 GF(2) 线性网络。它没有运行时模式选择，综合器可以跨固定异或关系进行化简及 LUT 打包。

XOR1 共享候选删除了私有网络中的显式二输入关系，但也为被复用节点引入平方模式输入选择及结果选择。综合结果表明，部分逻辑上存在的 XOR1 节点在原工作模式下可以被剪除或与相邻逻辑合并。平方模式激活这些节点后，增加的选择逻辑及布线代价超过了被删除私有网络的面积。S2 的更差时序也说明，单纯避开斜线节点不能消除模式选择路径。

S3 及 S4 缩小了共享范围。S4 优先复用当前有效节点后，时序明显接近基线，但仍增加 134 个 LUT。该结果说明节点在功能名称上的“共用”不等于综合后获得物理面积复用。

S5 将平方条件直接并入 XOR0 逐位关系，避免了独立宽结果选择器，但平方模式仍改变 XOR0 的输入关系及 LUT 打包。其结果增加 295 个 LUT，同时将估算 Fmax 降至 191.644 MHz，因此 XOR0 也不适合作为本实现中的平方共享平面。

## 7. 与 F1d 及 H5 的累计交互检查

为排除单项探针与前两阶段组合后可能出现不同物理结果的情况，将五个候选中最接近门槛的 S4 叠加到包含 F1d 融合映射及 H5 HPERM 修复的隔离累计 probe。该检查未修改 VV30 主工作树中的 RTL。

累计 probe 继续执行 491 个真实平方指令用例，结果为：

```text
[VV30:SQUARE_DIFF] PASS variant=4 xor0=0 cases=491 square_cycles=5 seed=d05b749cdcb6d4ed
```

匹配 OOC 结果为：

| 累计版本 | LUT | FF | BRAM | DSP | WNS，ns | 估算 Fmax，MHz |
|---|---:|---:|---:|---:|---:|---:|
| F1d 加 H5，私有平方 | 4640 | 1308 | 4 | 0 | 0.328 | 214.041 |
| F1d 加 H5 加 S4 | 4774 | 1299 | 4 | 0 | -0.019 | 199.243 |

在同一累计 probe 源状态及相同约束下，S4 仍增加 134 个 LUT，WNS 下降 0.347 ns，估算 Fmax 低于 200 MHz。FF 减少 9 个不能抵消 LUT 及时序退化。该结果与单项探针一致，说明 F1d 及 H5 没有改变 S4 的验收结论。

累计 probe 为了支持参数化 A/B，包含关闭状态下的平方试验描述，因此其私有版绝对 LUT 数不作为 VV30 主线最终资源数字。此处只使用同一源状态下参数关闭及开启的匹配差值判断平方共享结构。

## 8. 兼容性检查

在平方共享参数关闭，继续使用私有平方网络时，以下现有测试通过：

```text
[VV25_NATIVE_XOR1] PASS legacy_cycles=2048 diag_cycles=2048 native_nodes=224 diag_nodes=14
[HDEC_ECC_REDUCE_V1] PASS
[HDEC_HDC_FULL_FLOW_V20] PASS
```

这表明关闭试验结构后，原 XOR1 工作模式、ECC 约减流程及 HDC 完整流程保持可用。

## 9. 证据位置

试验工作树：

```text
E:\HDEC\cva6-vhdc-core\tmp\hdec_vv30_square_probe
```

功能日志：

```text
E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\square_probe\diff_s1
E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\square_probe\diff_s2
E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\square_probe\diff_s3
E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\square_probe\diff_s4
E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\square_probe\diff_s5_xor0
```

综合报告：

```text
E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\square_probe\ooc_s1_private\reports
E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\square_probe\ooc_s1_shared\reports
E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\square_probe\ooc_s2_shared\reports
E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\square_probe\ooc_s3_shared\reports
E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\square_probe\ooc_s4_shared\reports
E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\square_probe\ooc_s5_private\reports
E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\square_probe\ooc_s5_xor0_shared\reports
E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\square_probe\ooc_cumulative_h5_f1d_s4_private\reports
E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\square_probe\ooc_cumulative_h5_f1d_s4_shared\reports
```

兼容性日志：

```text
E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\square_probe\default_compat
E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\square_probe\cumulative_h5_f1d_diff_s4
```

## 10. 主线处理

本报告只记录试验事实及设计决策。VV30 主工作树未接收任何平方共享 RTL 修改。后续联合回归及最终消融综合应以私有平方模约减网络为准。

## 附录 A：独立结构交叉检查

为避免五个主候选的具体编码方式影响结论，另在两个独立 worktree 中，从逐位条件融合及器件原语打包两个角度进行交叉检查。两个探针均未修改 VV30 主工作树，也不作为待合入候选。

### A.1 XOR0 逐位条件融合探针

该探针将 233 位平方模约减关系直接并入现有 XOR0 输出位。每一位采用如下二选一组合关系：

```text
square_mode ? (square_lhs ^ square_rhs)
            : (state_bit ^ contribution_bit)
```

其中，80 个单输入结果以固定连线接入，153 个二输入结果使用平方源位之间的异或关系。该写法用于检查条件选择及两个异或关系能否被 Vivado 融入单个 LUT，而不在 XOR0 前显式建立两层宽输入选择器。

功能测试通过，日志包含：

```text
[HDEC_ECC_REDUCE_V1] PASS
```

该测试覆盖真实指令路径中的 GF_SQR、GF_SQRMAC、GF_SQRN 及 GF_SQRNMAC。

匹配 OOC 结果如下：

| XOR0 独立探针 | LUT | FF | BRAM | DSP | WNS，ns | 估算 Fmax，MHz |
|---|---:|---:|---:|---:|---:|---:|
| 参数关闭，私有平方 | 4658 | 1304 | 4 | 0 | 0.328 | 214.041 |
| 参数开启，XOR0 条件融合 | 4998 | 1310 | 4 | 0 | -0.462 | 183.083 |
| 变化 | +340 | +6 | 0 | 0 | -0.790 | -30.958 |

条件表达式虽然局部满足 LUT6 输入数量限制，但综合后的物理代价并不只由单个输出位决定。平方写回连接使正常 XOR0 贡献路径也可结构性到达 VRF 写数据端，关键路径从 `ecc_leaf_path_q` 经正常贡献逻辑及 XOR0 进入 BRAM 数据输入。由此产生的逻辑保留、状态选择及布线代价明显大于被删除的私有平方网络。因此，该探针功能正确，但面积及时序均不满足门槛，不合入主线。

证据位置：

```text
E:\HDEC\cva6-vhdc-core\tmp\hdec_vv30_square_xor0_probe
E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\square_xor0_probe\functional\xsim_ecc_reduce_v1\xsim.log
E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\square_xor0_probe\ooc_private\reports
E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\square_xor0_probe\ooc_shared\reports
```

### A.2 LUT6_2 双输出物理打包探针

该探针不使用运行时平方模式输入选择器，而是将 153 个平方二输入异或分别与 XOR1 的节点 32 至 184 配对。每个 `LUT6_2` 的 O6 保持原 XOR1 关系，O5 同时产生一个平方异或结果，80 个单输入结果继续使用固定连线。两个结果始终并行计算，平方路径与原 XOR1 路径之间不存在模式 MUX。

该结构是面向 Xilinx 7 系列双输出 LUT 的器件专用探针，不是可移植的通用 RTL 方法，也不作为论文中的架构机制。

功能测试通过，日志包含：

```text
[HDEC_ECC_REDUCE_V1] PASS
```

匹配 OOC 结果如下：

| LUT6_2 独立探针 | LUT | FF | BRAM | DSP | WNS，ns | 估算 Fmax，MHz |
|---|---:|---:|---:|---:|---:|---:|
| 同源参数关闭，保留强制原语 | 4686 | 1304 | 4 | 0 | 0.328 | 214.041 |
| 参数开启，双输出平方路径 | 4902 | 1307 | 4 | 0 | 0.328 | 214.041 |
| 同源变化 | +216 | +3 | 0 | 0 | 0.000 | 0.000 |
| 原始私有平方参考 | 4661 | 1304 | 4 | 0 | 0.328 | 214.041 |
| 相对原始参考的最终变化 | +241 | +3 | 0 | 0 | 0.000 | 0.000 |

双输出结构消除了平方模式 MUX，因而完全保持了基线时序。然而，显式 `LUT6_2` 阻止 Vivado 将原 XOR1 关系及其上游选择逻辑吸收到相邻 LUT 中。参数关闭时，强制原语本身已使 LUT 从原始参考的 4661 增至 4686。参数开启后，`i_native_xor1` 层级被保留为 753 个 LUT，最终面积增至 4902 LUT。因此，该探针只能证明消除模式 MUX 可以恢复时序，不能获得面积复用，并且其 Xilinx 专用性不符合主线 RTL 的可移植性要求，不合入主线。

证据位置：

```text
E:\HDEC\cva6-vhdc-core\tmp\hdec_vv30_square_duallut_probe
E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\square_duallut_probe\functional3\xsim_ecc_reduce_v1\xsim.log
E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\square_duallut_probe\ooc_private\reports
E:\HDEC\cva6-vhdc-core\tmp\hdec_logs\vv30\square_duallut_probe\ooc_shared\reports
```

### A.3 交叉检查结论

两个独立探针分别检验了综合器推断的条件共享及器件原语级并行打包。前者同时损失面积及时序，后者恢复时序但仍增加面积。结果与 S1 至 S5 的主试验一致，即逻辑名称上的 XOR 复用不等于综合后的物理资源缩减。VV30 因此继续保留固定私有平方模约减网络，并且不在第四章 C 中声明平方约减复用 XOR1 或 XOR0。
