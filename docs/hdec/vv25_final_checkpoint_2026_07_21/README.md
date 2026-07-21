# VV25最终检查点索引（2026-07-21）

本目录把VV25最终RTL、数学说明、论文图3、功能验证和PPA证据连接成一个可复查入口。VV25最终实现仍为 **R31 hybrid57 split-CAP**；本次归档只补充说明、图源和精简证据，不改变任何RTL行为。

## 1. 冻结对象

- 分支：`VV25`
- RTL基准提交：`3d641383613969f5fbf6c53ee25f539e5a833a08`
- 选择实现：R31 hybrid57 split-CAP
- 主要RTL：
  - [`hdec_lane_4x64.sv`](../../../core/hdec/rtl/hdec_lane_4x64.sv)
  - [`hdec_top.sv`](../../../core/hdec/rtl/hdec_top.sv)
- 位精确模型：[`vv25_byte_equation_model.py`](../../../scripts/hdec/vv25_byte_equation_model.py)
- 结构检查：[`vv25_reuse_structure_check.py`](../../../scripts/hdec/vv25_reuse_structure_check.py)

RTL基准提交已经包含唯一共享16×16 AND、8×32统一位矩阵、32个共享8位POPCOUNT槽、14个原生二输入XOR1复用节点、三次16×16 Karatsuba调度以及完整PMUL控制。本次文档提交位于该RTL基准之上。

## 2. 文档与图

- 总体算法、硬件与论文表述边界：[`VV25_unified_bitmatrix_partitioned_reduction_2026_07_19.md`](../VV25_unified_bitmatrix_partitioned_reduction_2026_07_19.md)
- Stage 2复制对齐、Stage 3固定打包与Stage 4逐位AND的真实映射：[`VV25_STAGE2_TO_STAGE4_EXACT_MAPPING.md`](VV25_STAGE2_TO_STAGE4_EXACT_MAPPING.md)
- 图3归档与再生成说明：[`vv25_unified_bitmatrix_2026_07_21/README.md`](../figures/vv25_unified_bitmatrix_2026_07_21/README.md)
- 图3可编辑SVG：[`HDEC_Fig3_unified_bitmatrix_python_v8.svg`](../figures/vv25_unified_bitmatrix_2026_07_21/HDEC_Fig3_unified_bitmatrix_python_v8.svg)
- 图3Python源：[`build_fig3_unified_bitmatrix_python_v8.py`](../figures/vv25_unified_bitmatrix_2026_07_21/build_fig3_unified_bitmatrix_python_v8.py)

图3的边界止于统一操作数矩阵和唯一逐位AND输出。POPCOUNT、XOR1、斜线消元、Karatsuba、模约减与调度属于后续架构图；逐槽映射文档解释这些后续需求如何反向决定Stage 3的固定排列，但不把硬件归约模块画入图3。

## 3. 最终数据

| 版本 | Logic LUT | FF | BRAM | DSP | Fmax (MHz) | PMUL wall cycles |
|---|---:|---:|---:|---:|---:|---:|
| VV22 | 4734 | 1442 | 4 | 0 | 214.041 | 189412 |
| VV23 | 4840 | 1375 | 4 | 0 | 204.290 | 188224 |
| VV24 | 4822 | 1370 | 4 | 0 | 204.040 | 188224 |
| **VV25 R31** | **4661** | **1304** | **4** | **0** | **214.041** | **166840** |

相对VV22，VV25 R31减少73 Logic LUT、138 FF和22572个PMUL周期，并保持相同的214.041 MHz估算Fmax。完整候选比较、源文件SHA-256及回归清单见[`SELECTION.md`](../../../reports/hdec/vv25_r31_final_ooc_20260719/SELECTION.md)。

机器可读指标和精简原始证据位于[`vv25_final_evidence_2026_07_21`](../../../reports/hdec/vv25_final_evidence_2026_07_21/README.md)。

## 4. 关键功能与结构结论

- 一个16×16 leaf覆盖256个唯一部分积，所有\((i,j)\)恰好出现一次。
- 8位穷举65536对和至少100000组随机32位无进位乘法通过。
- 原生XOR1旧模式与ECC模式各2048周期通过；原生节点总数224，ECC复用其中14个。
- RTL结构检查8/8通过：只有一套共享AND、完整32槽共享POPCOUNT、原生二输入XOR1，无ECC私有AND+XOR归约旁路。
- 19项正式XSim回归全部通过，包含ECC乘法/约减/求逆/PMUL、HDC完整流程、自学习、HMATCH、HPERM、移位对齐与CV-X-IF smoke。

## 5. 提交边界

本检查点有意不包含：

- R01到R36的被否决探针目录；
- Vivado/XSim数据库、DCP、`.Xil`、`xsim.dir`和仿真日志；
- `Microsoft/`缓存和其他本机临时文件；
- 早期32槽动画与预览图。

仓库只保存可复现源文件、当前论文图、精简PPA/层级证据和经核对的回归摘要。
