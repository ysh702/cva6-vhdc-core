# VV11-4 practiceB15 复用链阶段性记录

## 目标约束

- Logic LUT 必须小于 4700。
- HDC/ECC 统一数据结构必须保留：位矩阵行包用于斜线部分积与奇偶归约，位贡献包用于 GF(2) 累加与写回。
- ECC 多项式模乘必须继续走真实复用链，而不是只做语义复用。
- PMUL 周期保持不变或仅小幅浮动，Fmax 保持 200 MHz 以上。

## 本次修改

- 保留位矩阵行包路径：ECC 斜线乘积继续进入 payload 内的 8x32 行包结构。
- 保留双斜线路线：低行走 AND + popcount LSB，高行走 AND + row XOR parity。
- 保留 XOR0 位贡献包累加：ECC 直接模折叠贡献通过 payload 的 4x64 XOR0 合并后写回 233-bit 域结果。
- 删除非核心的 xor1_fold 宽端口网络：Karatsuba 局部 32-bit fold 回到 top 内固定公式，避免为了包装复用故事引入额外宽端口和控制面积。

## 结果

| 指标 | practiceB15 |
|---|---:|
| Total LUT | 4645 |
| Logic LUT | 4645 |
| LUTRAM | 0 |
| FF | 1434 |
| BRAM | 4 |
| DSP | 0 |
| Fmax | 207.684 MHz |
| PMUL cycles | 392560 |

## 已跑验证

- `xsim_hdec_hdc_full_flow_v20`: PASS
- `xsim_hdec_ecc_add_v1`: PASS
- `xsim_hdec_ecc_align_v1`: PASS
- `xsim_hdec_ecc_diag_mul_v1`: PASS
- `xsim_hdec_ecc_reduce_v1`: PASS
- `xsim_hdec_ecc_pmul_profile_v27`: PASS, `PMUL_PROFILE_WALL_CYCLES=392560`
- OOC: Vivado 2024.2, `xc7z020clg400-2`, 5 ns

## 论文叙事状态

这版可以讲成：ECC 多项式模乘被重排为 HDC 位级计算资源可承载的数据流。斜线部分积进入共享位矩阵行包，奇偶归约分别使用 popcount LSB 与行 XOR，模折叠贡献再通过统一位贡献包进入共享 GF(2) 合并边界。局部 Karatsuba fold 没有强行中央化，因为它不是 HDC 热点算子；删除宽端口后，复用链更集中，面积也满足硬门槛。
