# VV25论文图3：统一位矩阵构建

本目录冻结2026-07-21审阅通过的图3 v8。图的单一结论是：HDC载荷和一次16×16 GF(2) ECC leaf可归一化为同形的两张8×32操作数位矩阵，并进入唯一的任务无关逐位AND。

## 文件

- `build_fig3_unified_bitmatrix_python_v8.py`：可编辑Python绘图源。
- `verify_fig3_v8.py`：布局、数值、矢量文本和导出规格检查。
- `HDEC_Fig3_unified_bitmatrix_python_v8.svg`：可继续编辑的矢量主文件。
- `HDEC_Fig3_unified_bitmatrix_python_v8.pdf`：论文矢量输出。
- `HDEC_Fig3_unified_bitmatrix_python_v8.tiff`：600 dpi投稿输出。
- `HDEC_Fig3_unified_bitmatrix_python_v8_300dpi.png`：300 dpi预览/插稿输出。
- `HDEC_Fig3_unified_bitmatrix_python_v8_grayscale_300dpi.png`：灰度审查。
- `HDEC_Fig3_unified_bitmatrix_python_v8_review_150dpi.png`：快速审阅图。
- `FIGURE_CONTRACT.md`：图的结论、证据链和边界。
- `CAPTION_DRAFT.md`：英文图注草案及中文释义。
- `QA_REPORT.md`：数学与导出QA结果。
- `SHA256SUMS.txt`：原始图包文件哈希。

## 再生成与检查

需要Python 3.10+以及`matplotlib`、`Pillow`和`pypdf`。请先在当前Python环境中安装这些依赖，再从本目录运行：

```powershell
python build_fig3_unified_bitmatrix_python_v8.py
python verify_fig3_v8.py
```

验证脚本会重新生成灰度审查PNG，然后同时检查数学映射、SVG/PDF矢量属性、分辨率和版面碰撞。

验证脚本同时读取仓库中的[`scripts/hdec/vv25_byte_equation_model.py`](../../../../scripts/hdec/vv25_byte_equation_model.py)，用以确认图中256个位置与VV25冻结布局逐项一致。

## 语义边界

- 黑色方块表示1，空心圆表示0；靛紫描边只追踪指定源位的复制位置。
- ECC示例使用`A=0xB35D`、`B=0xD6A7`。
- 图3中的反转、移位和补0是卷积斜线的数学推导视图；最终8×32中的256格全部为真实且唯一的部分积配对。
- 图3不画POPCOUNT、XOR1、模约减或调度，它们属于后续架构图。
- Stage 2复制对齐、Stage 3固定打包与Stage 4逐位AND的完整逐槽索引见[`VV25_STAGE2_TO_STAGE4_EXACT_MAPPING.md`](../../vv25_final_checkpoint_2026_07_21/VV25_STAGE2_TO_STAGE4_EXACT_MAPPING.md)。
