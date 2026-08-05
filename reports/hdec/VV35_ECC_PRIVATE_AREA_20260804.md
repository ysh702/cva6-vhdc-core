# VV35 HDEC中ECC专属资源归属报告

## 1. 归属口径

ECC专属资源从VV35最终布局布线检查点中直接提取。若一个物理LUT同时承载ECC逻辑与HDC逻辑、公共逻辑或无法唯一归属的逻辑，则该LUT不计入ECC专属部分。VRF、统一位矩阵、AND、POPCOUNT、XOR及公共载荷路径只要被HDC使用，均不计入ECC专属面积。

## 2. 结果

| 指标 | HDEC总量 | ECC专属资源 | 占HDEC比例 |
|---|---:|---:|---:|
| 物理Logic LUT | 4694 | 538 | 11.46% |
| FF | 1513 | 248 | 16.39% |
| BRAM | 4 | 0 | 0% |
| DSP | 0 | 0 | 0% |

538个物理Logic LUT是在考虑LUT5、LUT6打包及混合所有权排除后的严格物理归属结果。该值描述ECC私有结构下界，不等同于关闭ECC功能前后的面积差。

一次独立复测在4690个物理Logic LUT中识别出539个ECC专属LUT，占11.49%。两次布局结果仅相差1个LUT，主结果采用冻结VV35检查点的538/4694。

## 3. 证据位置

- 冻结VV35检查点归属结果：`reports/hdec/vv35_ecc_private_frozen_final_20260804/`
- 独立布局复测结果：`reports/hdec/vv35_ecc_private_full_20260804/`
- HDEC匹配综合结果：`reports/hdec/vv35_full_after_gates_synth_20260804/`

器件为`xc7z020clg400-2`，时钟约束为5 ns，工具为Vivado 2024.2。
