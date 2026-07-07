# VV14 后续计划：斜线组级固定模折叠矩阵流水

## 1. 当前定位

当前 VV14 最终提交为：

```text
0102133d VV14 fixed small-matrix diagonal capture
```

当前版本不是完整的“斜线组级固定模折叠矩阵流水”，而是该方向的阶段性铺垫：

```text
已完成：
1. AND+popcount / AND+XOR 斜线路线已经进入统一位矩阵行包。
2. leaf-level matrix reduce 已经替代一部分旧式局部折叠。
3. group7 利用固定指数范围完成固定小矩阵捕获，删除了一个等待状态。
4. 32-bit popcount 改成 4 个 8-bit 局部计数，保持 200 MHz 时序。

未完成：
1. 每组斜线奇偶还没有在产生后立刻转成模后贡献包。
2. leaf product 仍然作为中间形态存在。
3. 后续 leaf fold / writeback 仍然承担主要周期。
4. 还没有实现“斜线组级模折叠”和“下一斜线组计算”的流水重叠。
```

因此，当前 VV14 是：

```text
固定小矩阵思想的可行性验证
+ leaf-level 矩阵化约减稳定版本
+ 小幅周期下降
+ 面积和时序保持良好
```

下一步要做的是一步到位实现：

```text
斜线组级固定模折叠矩阵流水
```

## 2. 当前 VV14 数据

### 2.1 面积与时序

| 版本 | Logic LUT | FF | Fmax | PMUL cycles | BRAM | DSP |
|---|---:|---:|---:|---:|---:|---:|
| VV14 leaf matrix baseline | 4677 | 1436 | 207.684 MHz | 392560 | 4 | 0 |
| VV14 final fixed small-matrix capture | 4665 | 1422 | 207.297 MHz | 360484 | 4 | 0 |

当前 final 相比 leaf matrix baseline：

```text
Logic LUT: -12
FF       : -14
PMUL     : -32076 cycles
Fmax     : 仍超过 200 MHz
```

### 2.2 当前 PMUL 周期占比表

当前 profile 来自：

```text
xsim_diag_capture_fold_v4_popfixed_pmul
PMUL_PROFILE_WALL_CYCLES = 360484
```

注意：`tb_hdec_ecc_pmul_profile_v27.sv` 中部分 `ST_ECC_*` 数字标签继承自旧状态枚举。由于 RTL 已删除/调整部分状态，下面表格中的状态名称用于定位大致区域，不能机械理解为精确 RTL 状态名。`PMUL wall cycles` 和各计数数值本身仍然可用于判断瓶颈方向。

| 操作区域 | 周期 | 占比 | 含义 |
|---|---:|---:|---|
| 取操作数 | 3564 | 0.99% | 从 VRF 读 ECC 操作数 |
| 斜线计算 | 33264 | 9.23% | AND+popcount / AND+XOR 计算斜线奇偶 |
| 叶级折叠/组合区域 | 256608 | 71.18% | 斜线之后的 leaf product 组合、矩阵折叠和相关等待，是当前最大头 |
| 写部分结果 | 42768 | 11.86% | 中间贡献或部分结果写入/整理 |
| 写回排空 | 1188 | 0.33% | 尾部写回排空 |
| 独立约减相关 | 2821 | 0.78% | 其他 reduce 路径 |
| 微操作开销 | 4242 | 1.18% | 状态和调度开销 |
| 其他缝隙 | 16029 | 4.45% | 状态切换、等待、未归类周期 |
| 总计 | 360484 | 100% | 当前 VV14 final PMUL |

核心判断：

```text
现在不是斜线计算本身最慢。
真正该砍的是斜线之后的 leaf fold / 组合 / 写结果区域。
```

## 3. 核心思想

当前路径接近：

```text
斜线组奇偶
-> 先攒成 leaf product
-> 再把 leaf product 组合成 subproduct
-> 再进入 leaf-level fold/reduce
-> 再写回或累加
```

下一步目标路径应改成：

```text
斜线组奇偶刚产生
-> 根据该组固定指数范围，直接进入固定 GF(2) 模折叠矩阵
-> 生成 233-bit 域内贡献包
-> 交给共享 XOR0 / GF(2) 累加
-> 同时下一组斜线继续进入共享 AND+popcount / AND+XOR
```

一句话概括：

```text
不再让 ECC 多项式乘法先形成局部乘积再后置约减，
而是把每组斜线奇偶直接变换为模后域内贡献包，
并和下一组斜线计算交织执行。
```

数学基础：

GF(2^233) 使用不可约多项式：

```text
f(x) = x^233 + x^74 + 1
```

因此：

```text
x^233 = x^74 + 1
```

对于任意乘积项 `x^k`：

```text
若 k < 233:
    x^k 直接落入结果坐标 k

若 k >= 233:
    x^k = x^(k-233+74) + x^(k-233)
```

如果折叠后仍然超过 232，则继续按同一规则折回。由于每个 diagonal group 的指数范围固定，例如某组只覆盖 `k = base ... base+7`，所以每组的落点集合也是固定的。这样可以提前生成固定小矩阵，而不是运行时做动态大 mux。

## 4. 为什么不是 leaf 级流水线

leaf 级流水线的形式是：

```text
一个 leaf 算完
-> 对这个 leaf 的结果做流水约减
-> 同时准备下一个 leaf
```

这个收益有限，因为 leaf 内部已经积累了较多中间形态，后续仍然需要处理完整 leaf product。

真正要做的是更早一层：

```text
每个 diagonal group 刚产生 8 个奇偶 bit
-> 立即进入固定模折叠矩阵
```

这样可以减少：

```text
leaf product 暂存压力
subproduct 组合压力
leaf fold 循环次数
部分写回/排空压力
```

## 5. 一步到位实现方案

### 步骤 1：建立 diagonal group 描述

每个 32x32 leaf 的 diagonal group 已经按 8 条斜线一组组织：

```text
group0: diag 0  ... 7
group1: diag 8  ... 15
...
group7: diag 56 ... 62，有效 7 条
```

对于每个 group，需要得到：

```text
leaf_path
sub_idx
group_idx
parity_row[7:0]
```

其中 `parity_row` 来自共享位矩阵行包：

```text
共享 AND 生成部分积
共享 popcount-LSB 得到部分斜线奇偶
共享 XOR parity 得到另一部分斜线奇偶
```

### 步骤 2：计算每个斜线 bit 的全局指数

每个 diagonal bit 对应一个局部指数：

```text
local_k = group_idx * 8 + row_id
```

但它属于 Karatsuba / sub32 / leaf path 的某个位置，还需要加上 leaf offset：

```text
global_k = leaf_base(leaf_path, sub_idx) + local_k
```

这里不要做动态大加法器和动态索引。应把 `leaf_path`、`sub_idx`、`group_idx` 的组合看成有限状态，预先压缩成固定小表或固定 case。

推荐结构：

```text
case ({leaf_path, sub_idx, group_idx})
    固定组合 A: 使用矩阵模板 A
    固定组合 B: 使用矩阵模板 B
    ...
endcase
```

注意：矩阵模板输出不是动态 `result[global_k] ^= bit`，而是固定连线生成贡献包。

### 步骤 3：实现固定 GF(2) 模折叠矩阵

输入：

```text
parity_row[7:0]
leaf_path
sub_idx
group_idx
```

输出：

```text
contribution_packet[3:0][63:0]
```

贡献包是 233-bit 域内结果的 4x64 承载形式：

```text
packet[0] -> result[63:0]
packet[1] -> result[127:64]
packet[2] -> result[191:128]
packet[3] -> result[232:192]，高位补零
```

实现原则：

```text
1. 不使用动态位索引。
2. 不使用大规模 variable shift。
3. 不使用完整 466-bit product。
4. 不保留旧 leaf product 后置 reduce 作为主路径。
5. 尽量使用固定拼接、固定 XOR、固定小 case。
```

### 步骤 4：把贡献包送入 XOR0 累加

当前 HDEC 已有 `xor0_contribution_packet` / `xor0_field_packet` 思路。下一步应让 diagonal group matrix 输出直接进入这个累加边界：

```text
hdc_src0_q <= hdc_src0_q XOR contribution_packet
```

这一步必须保持真实复用故事：

```text
HDC HBIND / ECC 模加 / ECC 斜线组贡献累加
都使用统一 GF(2) 向量累加结构。
```

### 步骤 5：与下一组斜线计算重叠

理想调度：

```text
cycle N:
    共享 AND+popcount / AND+XOR 计算 group g 的斜线奇偶

cycle N+1:
    group g 进入固定模折叠矩阵并累加到 XOR0
    同时共享 AND+popcount / AND+XOR 计算 group g+1
```

这才是“流水”的关键，而不是简单把 fold 逻辑切一拍。

需要增加的控制应尽量少：

```text
parity_valid_q
leaf_path_q
sub_idx_q
group_idx_q
```

这些寄存器只是保存一个 diagonal group token，不应该引入每 lane 独立控制。

### 步骤 6：删除旧主路径

如果只加新矩阵，不删旧路径，面积一定涨。完整实现后必须删除或旁路：

```text
ecc_leaf_prod_q 主路径
ecc_leaf128_prod_q 主路径
ecc_kpd64_sub32_accum 主路径
ecc_kpd64_leaf_reduce_packet 主路径
S_ECC_LEAF_FOLD 中逐 fold_word 的主循环
不必要的 product pair / fold_word 写回路径
```

保留原则：

```text
debug raw product 可以单独保留，也可以降低优先级。
PMUL autoreduce 主路径必须走 diagonal group matrix pipeline。
```

## 6. 需要特别注意的点

### 6.1 不要做成动态 result[k] 写入

错误方向：

```text
packet[dynamic_index] ^= parity_bit
```

这会产生大 mux、动态移位、长路由，面积和时序都会变差。

正确方向：

```text
每个 group 的指数范围固定
-> 每个 parity bit 的模后落点固定
-> 用固定小矩阵模板生成 packet
```

### 6.2 不要只做 leaf 级流水

leaf 级流水线只能减少少量等待，不能解决当前最大头。真正目标是：

```text
diagonal group 级别的边算边模
```

### 6.3 不要重新加 ECC 专属大硬件

允许增加少量矩阵模板逻辑，但不能退回早期“ECC 自己有一套完整快速乘法器”的结构。否则复用故事会被削弱。

### 6.4 profile 状态名要校准

下一轮实现前，应同步更新 `tb_hdec_ecc_pmul_profile_v27.sv` 的状态编号或改成层次化信号统计。否则 `ST_ECC_LEAF_FOLD_CYCLES` 等标签会因为 RTL 枚举变化而失真。

建议新增更准确计数：

```text
DIAG_PRODUCT_CYCLES
GROUP_MATRIX_FOLD_CYCLES
XOR0_ACCUM_CYCLES
OLD_LEAF_FOLD_CYCLES
WRITEBACK_CYCLES
```

### 6.5 面积目标

当前 VV14 final：

```text
Logic LUT = 4665
FF        = 1422
Fmax      = 207.297 MHz
PMUL      = 360484 cycles
```

下一步目标：

```text
Logic LUT <= 4800: 理想目标
Logic LUT <= 4900: 如果完整流水实现且周期明显下降，可以接受
Logic LUT > 5000 : 原则上拒绝，除非周期接近 18W 且结构故事非常完整

FF <= 1600
Fmax >= 200 MHz
PMUL 目标 180000 到 250000 cycles
```

### 6.6 周期目标

理论上，斜线组级固定矩阵流水应主要减少：

```text
叶级折叠/组合区域
写部分结果区域
写回排空区域
```

目标不是让斜线计算本身更快，而是让斜线结果不再排队等待 leaf fold。

预期：

```text
当前 PMUL: 360484 cycles
第一目标: < 300000 cycles
理想目标: 180000 - 250000 cycles
```

## 7. 建议实现顺序

### 实现 1：profile 校准

先更新测试统计，不改变 RTL 主逻辑：

```text
1. 校准状态编号。
2. 新增 group matrix 相关计数信号。
3. 确认当前 360484 cycles 的真实瓶颈分布。
```

产出：

```text
一张可信的 PMUL cycle breakdown 表。
```

### 实现 2：单 group 固定矩阵模板

先选一个最简单 group，例如 group0 或 group7：

```text
parity_row -> fixed reduced packet
```

目标：

```text
证明 group-level contribution packet 与旧 leaf-level reduce 输出一致。
```

注意：

```text
这一步只验证数学映射，不以面积/周期为最终目标。
```

### 实现 3：全 group 模板覆盖

覆盖：

```text
group0 ... group7
sub_idx 0 ... 2
leaf_path 所有有效组合
```

输出统一为：

```text
contribution_packet[3:0][63:0]
```

### 实现 4：接入 XOR0 累加

把 group matrix 输出接入共享 XOR0：

```text
packet -> XOR0 -> hdc_src0_q
```

此时旧 leaf reduce 仍可保留用于对照，但主路径开始切换。

### 实现 5：删除旧 leaf fold 主路径

确认功能一致后，删除旧主路径：

```text
leaf product -> sub32 accumulation -> leaf reduce -> fold_word loop
```

此时面积才会回收。

### 实现 6：重叠流水

加入一拍 diagonal group token：

```text
本拍算 group g+1 的斜线
上一拍 group g 做矩阵折叠并 XOR0 累加
```

这一步是周期大幅下降的关键。

### 实现 7：OOC 与回归

每个阶段至少跑：

```text
xsim_hdec_ecc_reduce_v1
xsim_hdec_ecc_add_v1
xsim_hdec_hdc_full_flow_v20
xsim_hdec_ecc_pmul_profile_v27
Vivado OOC 5ns
```

最终补跑：

```text
xsim_hdec_ecc_pmul_bg_idle_v27
xsim_hdec_ecc_pmul_bg_hdc_loop_v31
xsim_hdec_hdc_selflearn_v1
```

## 8. 最终论文表述方向

推荐命名：

```text
diagonal-group modular folding matrix pipeline
斜线组级模折叠矩阵流水
```

论文故事：

```text
HDEC 不是把 ECC 乘法简单串行化到 HDC 单元上，
而是根据 GF(2^233) 不可约多项式的固定折叠关系，
把二元域乘法中的斜线奇偶项重排为固定模折叠贡献包。
该贡献包与 HDC 的位级重叠/绑定路径共享统一 GF(2) 向量执行结构，
从而在保持真实硬件复用的同时减少后置约减和写回开销。
```

这一点比单纯“边算边模”更准确：

```text
不是动态地边算边写 result[k]，
而是用固定小矩阵把每组斜线结果直接变成域内贡献包。
```

## 9. 成功判据

只有同时满足以下条件，才算完成该计划：

```text
1. 每组斜线奇偶可以直接生成模后贡献包。
2. 主 PMUL 路径不再依赖旧 leaf product 后置约减。
3. 贡献包通过共享 XOR0 累加。
4. diagonal group 矩阵折叠与下一组斜线计算形成流水重叠。
5. HDC full flow、ECC reduce/add、PMUL profile 全部通过。
6. Fmax >= 200 MHz。
7. Logic LUT 尽量 <= 4800，硬上限原则上不超过 5000。
8. PMUL 周期明显低于 360484，第一目标小于 300000。
```

如果只做到“增加矩阵模板，但旧 leaf fold 还在主路径”，不算完成。

如果只做到“删除等待状态，小幅降周期”，也不算完成。

真正完成标志是：

```text
斜线组结果 -> 固定模折叠矩阵 -> 域内贡献包 -> XOR0 累加
```

成为 ECC 模乘主路径。
