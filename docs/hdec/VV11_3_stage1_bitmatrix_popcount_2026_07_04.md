# VV11-3 第一阶段：位矩阵斜线乘积层收口记录

## 基线

- 起点提交：`acb4a86f`，`VV11-3 practice1 true XOR1 bitmatrix fabric`
- 基线数据：Logic LUT 4499，FF 1429，Fmax 207.684 MHz，PMUL 296332 cycles

## 阶段目标

第一阶段只处理“斜线乘积层”，不触碰 XOR0 贡献包累加，也不引入边算边模。目标是让 ECC 的 32x32 斜线乘积更自然地进入 HDC 共享位矩阵结构：

- HDC 的 `query AND prototype` 和 ECC 的 `a_i AND b_j` 使用同一个 4x64/8x32 位矩阵 AND 结构。
- ECC 的斜线奇偶尽量由同一位矩阵 popcount 的最低位给出。
- top 层不再承担短段/长段奇偶拼接语义，避免把斜线归约拆散成零散 ECC 专属逻辑。

## 实践记录

### 实践1：把短段/长段补奇偶移入 tile

- 做法：保留原 5 组压缩斜线，把 `full ^ edge`、`full ^ lo16` 等段奇偶从 top 层移入位矩阵 tile。
- 结果：功能通过，PMUL 296332 cycles，Logic LUT 4579，FF 1429，Fmax 202.799 MHz。
- 结论：故事更清楚，但多导出了不一定使用的段奇偶，面积增加 80 LUT，拒绝。

### 实践2：tile 只输出当前组两个段

- 做法：让 tile 根据当前斜线组只输出低段/高段两个结果，top 只负责摆放。
- 结果：功能通过，PMUL 296332 cycles，Logic LUT 4597，FF 1431，Fmax 207.684 MHz。
- 结论：每行引入 group 选择 mux，面积仍然增加，拒绝。

### 实践3：一行一斜线的纯 popcount-LSB 结构

- 做法：把 32x32 leaf 的 63 条斜线按 8 行一组展开为 8 组，每个 8x32 行只表示一条斜线；ECC 斜线奇偶直接取该行 popcount 的最低位。
- 结果：功能通过，HDC 全流程通过，PMUL 392560 cycles，Logic LUT 4459，FF 1433，Fmax 207.684 MHz。
- 结论：这是第一阶段的阶段性胜利。它用理论周期增加换取更干净的数据结构和更低 LUT：相比基线减少 40 Logic LUT，FF 增加 4，时序不变。

## 当前结论

实践3证明：如果不把两条斜线压缩进同一行，而是让“一个位矩阵行等于一条斜线”，ECC 斜线乘积层可以做到真正的 HDC AND+popcount 复用，且总 Logic LUT 下降。代价是斜线组从 5 组增加到 8 组，PMUL 周期从 296332 增加到 392560。

这个版本适合作为“第一阶段完成点”。第二阶段应在此基础上处理 XOR1 局部归约层，重点是把 leaf/Karatsuba 局部 XOR 统一为位矩阵局部归约，而不要提前触碰 XOR0 或边算边模。

