# VV20 RTL最终版相对VV19的说明

## 分支和提交基准

- 远程VV19基准：`origin/VV19 = f1c34ba8fdc3b28893415fb5892863bdcc4e4349`
- 本次清理前的远程VV20：`origin/VV20 = d95a6bc628f0d78d87bf844cad15260c8786d071`
- 本文记录的是VV20在最终bit-matrix parity复用清理之后的RTL版本。

## VV19已经完成了什么

VV19完成的是`adjacent diagonal-pair capture`。它的主要作用发生在GF(2^233)乘法内部：

- diagonal capture粒度从一次捕获一个8-bit diagonal group，推进到一次捕获相邻两个group。
- 每个sub内部按`group 0/1`、`2/3`、`4/5`、`6/7`成对捕获。
- PMUL周期降到`189412 cycles`。
- 在VV20工作区重跑的VV19基线结果为：
  - `4914 LUT`
  - `1489 FF`
  - `4 BRAM`
  - `WNS 0.328 ns`
  - `Fmax 214.041 MHz`

所以VV19解决的是主要周期问题：它提高了diagonal capture吞吐。但在结构故事上，modular folding仍然更像是diagonal product capture之后的下游处理。

## VV20相对VV19改变了什么

VV20保留VV19的相邻diagonal-pair capture，但把故事从“捕获更快”推进到“pair-token modular folding”：

1. 相邻diagonal-pair结果不再只是后续leaf product的一部分，而是被看作一个modular token。
2. 这个token不进入新的独立reducer，而是复用已有的modular contribution路径。
3. delayed pair-token pipeline复用`ecc_direct_reduce_word`和XOR0 contribution path。
4. 这样ECC modular contribution仍然进入HDC/ECC共用的XOR0通路，保留了统一vector payload数据结构和硬件复用故事。

结构上，VV20可以讲成：

```text
bit-matrix diagonal stream
  -> adjacent diagonal-pair token
  -> modular delta token
  -> shared XOR0 contribution path
```

这比单纯的调度优化更强，因为diagonal-pair结果已经可以被解释为modular folding的基本token，而不是只能解释为leaf product中的中间片段。

本次清理前，VV20已接受的pair-token版本结果为：

- `4874 LUT`
- `1450 FF`
- `4 BRAM`
- `WNS 0.086 ns`
- `Fmax 203.500 MHz`
- `PMUL_PROFILE_WALL_CYCLES = 189412`

也就是说，VV20相对VV19保持了周期，同时减少了面积，并且仍然满足200 MHz。

## 本次最终RTL清理做了什么

本次push的最终RTL版本只增加一个集中清理，修改文件为：

- `core/hdec/rtl/hdec_lane_4x64.sv`

清理前，bit-matrix row tile里存在两条逻辑等价的parity路径：

- `matrix_parity_o`：来自`matrix_count_o[row][0]`
- `matrix_xor_parity_o`：来自对row做XOR reduction

在GF(2)里二者等价：

```text
popcount(row)[0] == ^row
```

因此最终VV20 RTL删除了单独的XOR parity输出，让ECC diagonal parity直接复用HDC bit-matrix popcount的最低位。

具体修改包括：

- 删除`hdec_gf2_contribution_row_tile_8x32`里的`matrix_xor_parity_o`端口。
- 删除单独的`^matrix_product_q_i[rid]` XOR-reduction路径。
- 删除`hdec_vector_payload_4x64`里的`matrix_xor_parity`中间线。
- `bitband_parity_o[ROW_LO/ROW_HI]`统一改成来自`matrix_parity`。
- 保留统一的bit-matrix product/count/parity结构。
- `hdec_popcount32_fixed`改写为`$countones(bits)`表达；本轮综合中它和原显式tree面积一致，主要让代码更直接。

这不是单纯代码整理，而是真正的硬件复用：

```text
HDC count path: matrix_count_o[row]
ECC parity path: matrix_count_o[row][0]
```

同一个bit-matrix row结果同时服务HDC count和ECC diagonal parity。

## 最终测量结果

最终接受的VV20 RTL结果：

- PMUL profile：PASS
- `PMUL_PROFILE_WALL_CYCLES = 189412`
- `PMUL_PROFILE_STATUS_LOW16 = 0`
- `PMUL_PROFILE_GF_MUL_STARTS = 1188`
- `PMUL_PROFILE_ST_ECC_DIAG_CYCLES = 160380`
- `PMUL_PROFILE_ST_ECC_LEAF_FOLD_CYCLES = 1188`
- `PMUL_PROFILE_ST_ECC_WRITE_PAIR_CYCLES = 1188`
- OOC 200 MHz综合：
  - `4858 LUT`
  - `1450 FF`
  - `4 BRAM`
  - `WNS 0.086 ns`
  - `Fmax 203.500 MHz`

相对VV19基线重跑结果：

```text
LUT: 4914 -> 4858  (-56 LUT)
FF : 1489 -> 1450  (-39 FF)
PMUL cycles: 189412 -> 189412  (不变)
Timing: 仍然通过200 MHz
```

相对VV20第一版pair-token接受版本：

```text
LUT: 4874 -> 4858  (-16 LUT)
FF : 1450 -> 1450  (不变)
PMUL cycles: 不变
```

## 没有并入的内容

X-only output实验没有并入本次RTL版本。

当前Montgomery ladder主体本来就已经是X/Z-only，主循环不维护Y坐标。Y只在最后输出尾部恢复，因为当前PMUL接口和测试仍然要求输出`out_x/out_y`。

临时X-only-output实验把profile从`189412`降到`188159 cycles`，但OOC面积为`4872 LUT`，高于最终保留版本的`4858 LUT`。因此它只作为负例数据保留，没有进入最终VV20 RTL。

## 故事总结

VV20最终版可以概括为：

```text
统一bit-matrix数据结构
  + adjacent diagonal-pair modular tokenization
  + shared XOR0 modular accumulation
  + popcount LSB复用ECC parity路径
```

重点是：VV20没有增加一条ECC专用reducer，而是把diagonal-pair结果推进成modular token，同时把folding保留在HDC/ECC共用的XOR0 contribution fabric里。最终清理进一步删除了冗余ECC parity路径，让ECC diagonal parity复用HDC bit-matrix count结果。
