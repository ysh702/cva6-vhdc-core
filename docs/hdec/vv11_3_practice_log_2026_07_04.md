# VV11-3 统一数据-算子结构实践日志

基线：VV11-2，Logic LUT=4501，FF=1430，Fmax=207.684 MHz，PMUL=296332 cycles。

目标：在不退回语义复用的前提下，把 ECC 斜线计算中使用的 XOR1 变成位矩阵切片内部的真实行归约结构，并保持 HDC/ECC 共享的 4x64 载荷结构。

## 实践1：独立 XOR1 子模块前移到 payload

修改：

- 将原本在 top 层的 XOR1 fold 逻辑前移到 `hdec_vector_payload_4x64` 内。
- XOR1 同时读取位矩阵 AND 产物，输出低半段斜线奇偶和边缘斜线奇偶。
- 删除未被使用的完整 32-bit 行奇偶输出后重新综合。

结果：

| 项目 | 结果 |
|---|---:|
| ECC diag xsim | PASS |
| HDC full flow xsim | PASS |
| PMUL profile xsim | PASS |
| PMUL cycles | 296332 |
| Logic LUT | 4534 |
| FF | 1430 |
| Fmax | 207.684 MHz |

结论：失败，不作为阶段性胜利。原因是 XOR1 作为单独子模块读取 `matrix_product_q`，使位矩阵产物在 payload 内部被 bitmatrix tile 和 XOR1 两处消费，综合后增加了额外扇出/边界面积，Logic LUT 超过硬门槛 4520。

## 实践1b：XOR1 嵌入 8x32 位矩阵切片

修改：

- 不再单独实例化 XOR1 子模块。
- 将 XOR1 的低半段斜线奇偶、边缘斜线奇偶和 8x32 fold 归约并入 `hdec_bitmatrix_tile_8x32`。
- 让 AND、popcount-LSB 和 XOR1 行归约共享同一个位矩阵输入与同一个 payload 切片边界。
- 删除未实例化的旧 `hdec_xor1_matrix_8x32` 模块，避免代码中出现两个 XOR1 结构。

结果：

| 项目 | 结果 |
|---|---:|
| ECC diag xsim | PASS |
| HDC full flow xsim | PASS |
| PMUL profile xsim | PASS |
| 清理后 ECC diag xsim | PASS |
| PMUL cycles | 296332 |
| Logic LUT | 4499 |
| FF | 1429 |
| Fmax | 207.684 MHz |
| BRAM / DSP | 4 / 0 |

结论：阶段性胜利。相比 VV11-2，Logic LUT -2，FF -1，周期不变，时序不变。更重要的是，ECC 斜线 XOR 路线不再是 top 层局部语义复用，而是与 AND 位矩阵和 popcount 路线共同落在同一个 8x32 payload 切片中，符合“先统一数据结构，再统一算子结构”的 VV11-3 主线。

下一步：在该阶段性胜利上推进 XOR0 边算边模贡献包累加，把当前 direct fold 的局部 `hdc_src0_q ^ ecc_direct_reduce_word` 改造成指数映射后的贡献包，并由 XOR0 完成全局 GF(2) 累加。
