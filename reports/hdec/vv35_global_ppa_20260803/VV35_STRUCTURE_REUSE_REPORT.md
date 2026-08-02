# VV35 结构复用检查报告

## 1. 网表层级证据

最终候选 DCP 的综合校验和为 `e9217b8f`。层级利用率直接确认：

| 层级 | 实例数 | LUT | FF | BRAM |
|---|---:|---:|---:|---:|
| `hdec_top` | 1 | 4694 | 1513 | 4 |
| `i_vrf` | 1 | 0 | 256 | 4 |
| `i_vec` | 1 | 2883 | 304 | 0 |
| `i_gf2_contribution_row_tile` | 1 | 576 | 0 | 0 |

总资源中 LUTRAM 为 0，DSP 为 0。由此可直接确认 VV35 仍保持唯一 VRF、唯一向量处理核心、唯一 GF(2) 贡献 tile 及 4-BRAM 存储结构。

## 2. 共同连接检查

RTL 唯一实例及输入连接表明，HDC product、POPCOUNT、XOR 事件与 ECC diagonal product、XOR1 输入、XOR0 模贡献均进入同一个 `i_vec`。`hdec_lane_4x64.sv` 中的同一矩阵入口在 HDC 与 ECC 操作数间选择，并只实例化一个 GF(2) tile、一个 XOR1 结构及一个 XOR0 归并结构。

因此，本轮修改没有复制位矩阵、AND、完整 POPCOUNT、XOR1、XOR0 或宽 payload，也没有改变统一 8x32 位矩阵及融合模贡献映射。

## 3. 证据边界

Vivado 会在综合时扁平化和重命名部分细粒度逻辑。现有关键路径审计无法按原 RTL 名称逐门计数 XOR0、AND 与 POPCOUNT。因此最准确的结论是：

> 唯一共享结构及 HDC/ECC 的共同连接由 RTL 唯一实例、综合网表层级及运行时零冲突事件联合支持。

不将现有脚本的 `direct_map=0` 或 `xor0=0` 误读为相应逻辑不存在，也不宣称已经完成逐门物理等价证明。

## 4. 证据路径

- DCP：`tmp/hdec_logs/vv35/final_structure_ooc/vivado/vv35_final_structure.dcp`
- 层级利用率：`tmp/hdec_logs/vv35/final_structure_ooc/reports/utilization_hier.rpt`
- 总体利用率：`tmp/hdec_logs/vv35/final_structure_ooc/reports/utilization.rpt`
- 关键路径单元审计：`tmp/hdec_logs/vv35/final_structure_audit/cpath_cells.txt`
