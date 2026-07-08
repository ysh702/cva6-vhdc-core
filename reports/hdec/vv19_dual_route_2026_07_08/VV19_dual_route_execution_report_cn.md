# VV19 dual-route execution report

## 结论

VV19 保留为 adjacent diagonal-pair capture 的正式候选版本。

它没有通过跳过 `K=0`、跳过零子操作、减少 field multiplication 次数来降周期。最终 PMUL profile 仍然是：

```text
GF_MUL_STARTS = 1188
SUB_ZERO      = 0
```

真正变化发生在 GF(2^233) multiply 内部的 diagonal capture 吞吐：生产 autoreduce 路径从一次 capture 一个 8-bit diagonal group，改成一次 capture 相邻两个 group。

最终结果：

```text
VV17 baseline:
  PMUL cycles     = 286828
  ST_ECC_DIAG     = 257796
  Logic LUT       = 4751
  FF              = 1490
  Fmax            = 214.041 MHz

VV19 final:
  PMUL cycles     = 189412
  ST_ECC_DIAG     = 160380
  GF_MUL_STARTS   = 1188
  SUB_ZERO        = 0
  Logic LUT       = 4914
  FF              = 1489
  Fmax            = 214.041 MHz
```

周期下降：

```text
286828 - 189412 = 97416 cycles
```

面积增加：

```text
4914 - 4751 = 163 Logic LUT
```

因此它不是“几十 LUT 小涨”的纯低面积版本，但它满足用户定义的高收益条件：小幅面积上涨换取 PMUL 进入 20 万 cycles 以内，并且减少接近 10 万 cycles。

## Route A: diagonal-level compute-while-mod story

Route A 的目标是延续 VV14/VV16/VV17 主线：让 modular folding 更贴近 diagonal/sub/leaf 生成过程，以增强论文故事。

本轮没有把 Route A 作为最终保留改动，原因是前期试探已经说明：

1. group-token streaming fold 可以让故事更像“边算边模”，但 direct group/sub folding mux 偏重，面积超过收益。
2. shift-pack leaf product 这类小整理没有带来周期下降，反而让 Vivado 综合面积上升。
3. 单纯把 folding 提前或隐藏，只能消掉小头 leaf-fold/drain，无法攻击 `ST_ECC_DIAG` 主体。

所以 VV19 的最终选择是：保留 VV17 已经完成的 sub-shadow / leaf-boundary overlap 作为 Route A 基础，不再加入面积变差的 group-token folding 逻辑。论文故事可以表述为：

```text
VV17/VV19 已经把 leaf-fold 与 diagonal/sub 调度重叠；
VV19 进一步把 diagonal capture 的粒度从 group 推进到 adjacent group-pair。
```

这比继续增加 direct folding packet 更符合低面积目标。

## Route B: adjacent diagonal-pair capture

### 思路

原 VV17/VV16 主体仍然是：

```text
每个 sub: 8 个 diagonal group capture
每个 leaf: 3 个 sub
每次 GF_MUL: 9 个 leaf
```

因此 `ST_ECC_DIAG` 占比最大：

```text
257796 / 286828 = 约 89.9%
```

但重点不是“谁最大就优化谁”，而是它有可利用结构：

```text
group 0/1, 2/3, 4/5, 6/7 是相邻 diagonal band
同一个 A leaf、同一个 B leaf 下，两个 group 的 B window 可以同时生成
```

VV19 没有复制完整 8x32 row tile。它保留原 row tile 生成 even group 的 8-bit parity row，同时在 `hdec_vector_payload_4x64` 内增加一个 adjacent-pair parity observer，用同一个 `bitband_src_a_i` 和相邻 odd group 的 B windows 生成第二个 8-bit parity row。

这样每个 pair capture 形成：

```text
even group parity: 原 bit-matrix row tile / payload_q path
odd group parity : lane 内 adjacent parity observer
```

然后两组 parity 一起写入 64-bit sub product：

```text
group 0 + 1
group 2 + 3
group 4 + 5
group 6 + 7
```

每个 sub 从 8 次 capture 降到 4 次 capture。

### 调度

pair mode 下：

```text
S_ECC_DIAG_ISSUE:
  issue group 0/2/4/6 pair

S_ECC_DIAG_CAPTURE:
  capture even parity from original tile
  capture odd parity from pair observer
  group += 2
```

sub boundary 仍保留一个 `S_ECC_DIAG_ISSUE` 间隙。这个间隙不是空泡，而是继续用于：

```text
1. fold previous sub-token through XOR0
2. issue next pair product
3. execute next-leaf A/B prefetch
```

### 预取修正

调试过程中发现，top 层有 `vrf_ra_q` 加 VRF 两级读等待，因此 pair mode 下 next leaf 的 A/B 预取必须提前三拍，而不是沿用旧 group5/group6 的直觉。

最终调度是：

```text
sub2 S_ECC_DIAG_ISSUE:
  request next leaf A

sub2 group0 capture:
  request next leaf B

sub2 group4 capture:
  capture next leaf A

sub2 group6 capture:
  capture next leaf B
```

这个修正后 PMUL 正确通过。

## 面积控制

本轮拒绝了两个看起来合理但综合变差的方向：

1. finite odd-pair window template

   目标是把 pair B-window 从通用动态函数变成固定 `1/3/5/7` group 模板。结果 Vivado 对原通用函数优化更好，模板版本面积变为：

   ```text
   Logic LUT = 5025
   ```

   因此撤回。

2. top-level direct parity

   目标是把 odd parity 从 lane observer 移到 top 直接函数，让 lane 侧 pair 输出被剪掉。结果面积和时序都差：

   ```text
   Logic LUT = 4956
   Fmax      = 207.297 MHz
   ```

   因此撤回。

最终保留两个低面积处理：

1. production pair-mode constant propagation

   生产参数 `ECC_DEBUG_FIELD_OPS=0` 下，raw/debug ECC field op 不实现，PMUL/INV 内部 field multiply 都是 autoreduce。因此：

   ```systemverilog
   ecc_diag_pair_mode = ECC_DEBUG_FIELD_OPS ? ecc_autoreduce_fast : 1'b1;
   ```

   这样 Vivado 可以剪掉旧 non-pair group7 调度 mux。debug 参数下仍保留旧路径。

2. pair parity register no-reset split

   odd parity 只在 issue 后的 capture 使用，不需要 reset。将它从大 reset always_ff 中拆出来，最终 OOC 为：

   ```text
   Logic LUT = 4914
   FF        = 1489
   Fmax      = 214.041 MHz
   ```

## 验证

最终功能回归：

```text
xsim_pmul_final_v1:
  [HDEC_ECC_PMUL_PROFILE_V27] PASS
  PMUL_PROFILE_WALL_CYCLES              = 189412
  PMUL_PROFILE_ST_ECC_DIAG_CYCLES       = 160380
  PMUL_PROFILE_ST_ECC_LEAF_FOLD_CYCLES  = 1188
  PMUL_PROFILE_GF_MUL_STARTS            = 1188
  PMUL_PROFILE_SUB_ZERO_CYCLES          = 0

xsim_diag_reduce_map_final2_v1:
  [HDEC_ECC_DIAG_REDUCE_MAP_V1] PASS

xsim_reduce_final2_v1:
  [HDEC_ECC_REDUCE_V1] PASS

xsim_add_final2_v1:
  [HDEC_ECC_ADD_V1] PASS

xsim_hdc_full_final2_v1:
  [HDEC_HDC_FULL_FLOW_V20] PASS
```

最终 OOC：

```text
ooc_final_v1:
  Logic LUT = 4914
  FF        = 1489
  BRAM      = 4
  DSP       = 0
  Fmax      = 214.041 MHz
```

## 论文叙事意义

VV19 的重点不是新增独立 ECC multiplier，而是更深入地利用统一 bit-matrix 结构：

```text
HDC/ECC 共享 bit-matrix AND/parity substrate
ECC diagonal product 由 group-level bit-matrix 产生
VV17 把 sub/leaf folding 与 diagonal 调度重叠
VV19 把 diagonal capture 吞吐提升到 adjacent group-pair
XOR0 accumulator 仍作为 reduced-field GF(2) accumulator
```

这条路线比单纯加大并行硬件更适合论文表达：它是从 diagonal 结构和调度关系中挖吞吐，而不是复制一套完整 ECC 单元。

## 后续建议

VV19 已经进入 20 万 cycles 内。下一步如果继续压周期，最值得做的不是再挤 leaf-fold，而是两个方向：

1. 更低面积的 pair parity packing

   当前 +163 LUT 的主要代价来自 odd group parity observer。后续可以尝试 LUT6_2 或分半 XOR packing，让 two-row / two-diagonal parity 更接近 FPGA primitive，而不是普通 RTL XOR tree。

2. 减少 GF_MUL_STARTS

   当前 `GF_MUL_STARTS=1188` 未变。若借鉴 Lopez-Dahab/Montgomery/x-only ladder 的公式调度，把乘法次数合法降低 10%-20%，可再减少约 25k-50k cycles。但这会触碰 PMUL 主流程和常数时间叙事，需要单独开分支做等价性验证，不能用跳过 `K=0` 的方式实现。
