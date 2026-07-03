# VV11-3 XOR 统一数据结构与统一算子结构改造目标

日期：2026-07-04
起点：`VV11-2 / 7396289c`
目标分支：`VV11-3`

## 1. 总目标

VV11-3 不是一次“尝试”，而是一次结构性改造。目标是在 HDEC 中建立严格统一的数据新结构和算子新结构，使 HDC 与 ECC 不再只是数学语义相似，而是在 RTL 物理计算资源上完成真实复用。

本轮必须围绕以下主线推进：

1. 统一数据结构：HDC 和 ECC 的位级计算必须尽量被组织成同一类位矩阵行和贡献包。
2. 统一算子结构：HDC 和 ECC 的 XOR 计算必须收敛到两个明确的物理 XOR 阵列。
3. 真实硬件复用：不允许只靠命名、语义解释或局部等价来声称复用；ECC 数据必须真实流经 HDC/ECC 共享的计算阵列。
4. 边算边模：将当前 PMUL 中的直接模折叠累加升级为边算边模贡献包累加，使全局模折叠累加进入 XOR0。

最终成功标准不是“部分可行”，而是完成完整故事闭环：

```text
AND 位矩阵产生斜线部分积
    ├── POPCOUNT 路线完成斜线奇偶
    └── XOR1 路线完成斜线行归约
          ↓
指数位置映射生成域内贡献包
          ↓
XOR0 完成全局 233-bit 贡献包累加
```

## 2. 两个 XOR 阵列的严格定义

### 2.1 XOR0：4x64 贡献包 XOR

XOR0 是全局向量合并与域贡献包累加阵列。

输入格式：

```text
base_packet[4x64]
contribution_packet[4x64]
```

输出格式：

```text
merged_packet[4x64] = base_packet ^ contribution_packet
```

XOR0 必须负责：

1. HDC 绑定。
2. ECC 模加 / 模减。
3. ECC 边算边模中的 233-bit 域贡献包累加。

XOR0 不负责斜线内部的 bit parity。XOR0 的定位是“全局贡献包累加器”，不是斜线归约器。

### 2.2 XOR1：8x32 位矩阵行归约 XOR

XOR1 是局部位矩阵行归约阵列。

输入格式应从当前“局部结果拆行”改造为真正的位矩阵输入：

```text
partial_product_rows[8x32]
local_fold_rows[8x32]
optional_acc_rows[8x32]
```

输出格式：

```text
row_fold_result[8x32] 或 row_parity_result[8]
```

XOR1 必须负责：

1. ECC 斜线 AND+XOR 路线。
2. 与 AND+POPCOUNT 并列接收同一份 AND 位矩阵部分积。
3. 必要的 leaf/sub32 局部行归约。

XOR1 不应继续承担全局模折叠累加。全局模折叠累加必须迁移到 XOR0。

## 3. AND+POPCOUNT 与 AND+XOR1 的统一斜线道路

当前 AND+POPCOUNT 路线已经较接近位矩阵化。VV11-3 必须把 XOR1 拉到同一数据层级，使它直接接收 AND 之后的斜线部分积。

目标数据流：

```text
bitmatrix_AND[8x32]
    ├── POPCOUNT -> count[8] -> parity[8]
    └── XOR1     -> row_xor/parity[8]
```

这里的重点不是新增一套 ECC 专属 XOR，而是让 XOR1 成为与 POPCOUNT 并列的共享斜线归约道路。

禁止路线：

```text
AND 结果 -> 先整理成 ECC 私有 leaf_prod -> 再送 XOR1
```

这只能算局部语义整理，不算完整的数据结构统一。

## 4. 边算边模取代当前直接模折叠累加

当前直接模折叠已经避免了完整 466-bit 乘积后置约减，但它仍有明显阶段边界：

```text
leaf 结果形成
-> fold/write 整理
-> 生成 ecc_direct_reduce_word
-> 本地 hdc_src0_q ^ ecc_direct_reduce_word
```

VV11-3 的目标是将其改造为：

```text
斜线/局部行贡献生成
-> 根据指数位置映射为 233-bit contribution_packet
-> XOR0(base_packet, contribution_packet)
-> 更新域累加包
```

若第一阶段只能做到 leaf 级贡献包进入 XOR0，也必须继续推进到更细粒度的斜线/行级边算边模。leaf 级贡献包可作为阶段性胜利提交，但不能作为最终目标终止。

## 5. 成功标准

最终成功必须同时满足以下条件：

1. XOR0 真实承载 HDC 绑定、ECC 模加/模减、ECC 边算边模贡献包累加。
2. XOR1 真实承载 ECC 斜线 AND+XOR 路线，并与 AND+POPCOUNT 共享同一份 AND 位矩阵部分积。
3. 当前直接模折叠中的全局累加不再通过本地私有 XOR 完成，而是通过 XOR0 贡献包累加完成。
4. RTL 报告中明确列出所有 XOR 使用点，并证明其归属到 XOR0 或 XOR1。
5. 不新增 ECC 专属 XOR 树来掩盖复用失败。
6. 不新增大量输入选择器来强行复用；数据结构必须让数据自然流入算子。

## 6. 约束目标

基线为 VV11-2：

| 指标 | VV11-2 |
|---|---:|
| Logic LUT | 4501 |
| FF | 1430 |
| Fmax | 207.684 MHz |
| PMUL cycles | 296332 |

VV11-3 约束：

| 指标 | 目标 | 硬上限 |
|---|---:|---:|
| Fmax | >= 200 MHz | 不可低于 200 MHz |
| Logic LUT | <= 4501 | <= 4520 |
| FF | <= 1430 | <= 1450 |
| PMUL cycles | 接近 296332 | <= 330000 |

周期不是本轮第一优先级，但不能失控。面积和时序必须被按住。

## 7. 实践命名与推进规则

本轮所有实现不称为 try，统一称为“实践”。

命名规则：

```text
实践1：...
实践2：...
实践3：...
```

推进规则：

1. 每轮实践都必须说明数据结构如何变化、算子结构如何变化、复用是否更真实。
2. 只要出现阶段性胜利，必须记录并 commit。
3. 后续实践若失败，必须回退到最近的阶段性胜利，再继续推进。
4. 失败实践必须保存 rejected patch 或报告，说明失败原因。
5. 轻度失败不能作为最终目标终止。

## 8. 轻度失败定义

轻度失败只允许作为中途记录，不允许作为最终终止状态。

轻度失败包括：

1. XOR0 已承载贡献包累加，但 XOR1 仍未完全直接接收 AND 位矩阵部分积。
2. XOR1 已前移到位矩阵层，但仍有少量 leaf/sub32 局部 XOR 未统一。
3. 边算边模只做到 leaf 级贡献包，而未推进到斜线/行级贡献包。
4. 面积、时序、周期达标，但数据结构统一故事不完整。

这些情况必须继续推进，不得停止。

## 9. 硬失败定义

以下情况视为硬失败，必须回退：

1. Fmax < 200 MHz。
2. Logic LUT > 4520。
3. FF > 1450。
4. PMUL cycles > 330000。
5. 新增 ECC 专属 XOR 树。
6. 只是重命名信号，没有真实共享计算阵列。
7. 为了复用引入宽 mux，导致面积上涨且无结构收益。
8. 破坏 HDC 自学习语义、ECC Montgomery LD/ITA/PMUL 数学流程或 ISA 可见行为。

## 10. 必跑测试

每个阶段性胜利至少通过：

```text
xsim_hdec_ecc_diag_mul_v1
xsim_hdec_ecc_pmul_profile_v27
xsim_hdec_hdc_full_flow_v20
Vivado OOC 200 MHz
```

最终成功版本补跑：

```text
xsim_hdec_ecc_reduce_v1
xsim_hdec_ecc_add_v1
xsim_hdec_ecc_align_v1
xsim_hdec_ecc_pmul_bg_idle_v27
xsim_hdec_ecc_pmul_bg_hdc_loop_v31
xsim_hdec_hdc_selflearn_v1
```

## 11. 最终报告必须回答的问题

最终报告必须用表格回答：

1. HDEC 中所有 XOR 计算分别属于 XOR0、XOR1，还是已删除。
2. HDC 哪些算子真实经过 XOR0。
3. ECC 哪些算子真实经过 XOR0。
4. ECC 哪些斜线计算真实经过 XOR1。
5. AND+POPCOUNT 与 AND+XOR1 是否共享同一份 AND 位矩阵部分积。
6. 当前直接模折叠是否已经被边算边模贡献包累加取代。
7. 仍未统一的数据结构和算子结构是否存在；如果存在，为什么不能作为最终终止。

## 12. 论文故事约束

VV11-3 的设计必须服务于以下论文主线：

```text
HDEC 不是把 HDC 与 ECC 并排放在一个系统里，
而是把两类算法共同重写到统一 GF(2) 位级数据结构中：
位矩阵行用于局部斜线和重叠计算，
贡献包用于全局向量合并和域内累加。
```

最终可写成：

```text
XOR1 converts bit-matrix partial products into local GF(2) row contributions,
whereas XOR0 accumulates vector-domain contribution packets for both HDC binding
and ECC in-field modular folding.
```

对应中文表述：

```text
XOR1 负责位矩阵局部行归约，XOR0 负责域向量贡献包累加；
由此，HDC 的绑定、ECC 的模加和 ECC 的边算边模累加共享同一类向量 XOR，
而 ECC 斜线乘法与 HDC 重叠计数共享同一类位矩阵输入结构。
```
