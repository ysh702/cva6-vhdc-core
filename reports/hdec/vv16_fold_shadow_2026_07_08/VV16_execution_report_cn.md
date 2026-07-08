# VV16 execution report: fixed-schedule leaf-tail overlap

## 结论

VV16 已经从错误的 scalar leading-zero trim 版本回退，并重新实现为固定 233-bit scalar 调度下的低面积调度优化版本。

最终保留版本不是通过跳过 K=0 或跳过 scalar bit 0 的操作降周期，而是在每个 GF(2^233) field operation 内部做两件事：

1. diagonal capture 尾部提前发出下一 leaf 的 A/B VRF 读请求；
2. autoreduce 路径把 leaf-fold 的等待拍压缩，并折叠无数据依赖的 write-drain 调度空拍。

## 保留版本指标

对比 VV15 计划基线：

| 版本 | PMUL cycles | Logic LUT | FF | Fmax | BRAM | DSP |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| VV15 baseline | 339100 | 4655 | 1422 | 207.297 MHz | 4 | 0 |
| VV16 final | 315340 | 4678 | 1426 | 207.297 MHz | 4 | 0 |
| delta | -23760 | +23 | +4 | unchanged | 0 | 0 |

这版周期下降约 7.0%，LUT 增量 23，仍低于 `Logic LUT < 4700` 门槛，Fmax 保持 200 MHz 以上。

## RTL 改动

核心 RTL 文件：

```text
core/hdec/rtl/hdec_top.sv
```

改动点：

1. `ecc_autoreduce_fast`

   只在 autoreduce 且 `ECC_DEBUG_FIELD_OPS == 0` 时启用 fast path。debug/raw-product 路径仍保留原来的四拍 leaf fold。

2. diagonal capture 尾部预取

   在最后一个 sub 的 group5/group6，提前向 VRF 发出下一 leaf 的 A/B 读请求：

```text
group5: prefetch next leaf A
group6: prefetch next leaf B
```

   由于 VRF 是两级读延迟，数据会在后续 `S_ECC_LEAF_FOLD` 的前两拍可用。

3. autoreduce fast leaf-fold

   原 VV15 每个 leaf 固定走 4 个 `S_ECC_LEAF_FOLD` cycle。VV16 final 改为：

```text
non-last leaf: 2 cycles
last leaf:     1 cycle
```

   `hdc_src0_acc_we` 仍然只对当前 leaf 的 full reduced packet 做一次 XOR0 累加，不新增 accumulator。

4. write-drain 折叠

   autoreduce 写回后，如果后续只是 job phase 调度跳转，则直接进入：

```text
ECC_PHASE_INV_SQR    -> S_ECC_INV_AFTER_SQR
ECC_PHASE_INV_MUL    -> S_ECC_INV_AFTER_MUL
ECC_PHASE_PMUL_FIELD -> S_ECC_PMUL_STEP_NEXT
```

   对普通前台 ECC op、sqr-repeat、MAC 路径保持原行为。

## 明确没有做的事情

VV16 final 没有修改 scalar 读取和 PMUL 外层 bit loop：

```text
S_ECC_PMUL_READ_SCALAR
S_ECC_PMUL_STEP
S_ECC_PMUL_STEP_NEXT
```

因此没有 leading-zero trim，没有 scalar bit 0 early skip。scalar bit 为 0 时仍会进入固定的 `ECC_PMUL_SUB_ADD -> ECC_PMUL_SUB_DBL` 调度；K=0 也不会被当成可跳过的乘法。

## 验证

功能仿真：

| test | result |
| --- | --- |
| `xsim_hdec_ecc_reduce_v1.tcl` | PASS |
| `xsim_hdec_ecc_add_v1.tcl` | PASS |
| `xsim_hdec_hdc_full_flow_v20.tcl` | PASS |
| `xsim_hdec_ecc_pmul_profile_v27.tcl` | PASS |

PMUL profile:

```text
PMUL_PROFILE_WALL_CYCLES=315340
PMUL_PROFILE_SAMPLED_CYCLES=315340
PMUL_PROFILE_PHASE_PMUL_FIELD_CYCLES=297748
PMUL_PROFILE_ST_ECC_LEAF_FOLD_CYCLES=256608
PMUL_PROFILE_ST_ECC_WRITE_PAIR_CYCLES=20196
PMUL_PROFILE_ST_ECC_REDUCE_CYCLES=1633
```

注意：当前 profile testbench 的 state label 和 RTL enum 有历史偏移。这里最重要的判断是 PMUL wall cycles、PASS，以及相对 VV15 的总周期变化。

OOC synthesis:

```text
Label=vv16_prefetch_drain_v1
Logic LUT=4678
FF=1426
BRAM=4
DSP=0
WNS=0.176 ns
Fmax=207.297 MHz
```

## 拒绝的尝试

### direct same-cycle group0 issue

思路：在 fold 拍直接用 `vrf_rd -> bitrev -> bitband window` 发下一 leaf 的 group0。

结果：

```text
PMUL cycles=296332
Logic LUT=4812
Fmax=182.749 MHz
```

结论：周期更低，但面积和时序都不合格，拒绝。

### registered-tail same-cycle

思路：提前把 next A/B 装入现有 leaf register，再在 fold 拍发 group0，避免 VRF 直通热路径。

结果：

```text
PMUL cycles=297520
Logic LUT=5067
Fmax=207.297 MHz
```

结论：功能正确、时序可行，但控制和 leaf register 选择显著膨胀，面积不合格，拒绝。

## 还没有突破 10W-20W 的原因

VV16 final 主要压掉的是 leaf-tail 和 drain 空拍。真正的大头仍然是 diagonal capture 主体：

```text
9 leaf * 3 sub * 8 group = 216 capture slots / field op
```

在不复制 bit-matrix row tile 的前提下，单纯调度很难把这 216 个 capture slots 砍半。same-cycle group0 已经证明可以继续降周期，但当前写法会让 mux 和控制扇入变大。

下一步若要进入 10W-20W，需要继续做“固定模板化的 diagonal-pair / group-pair”，而不是动态直通 mux：

```text
fixed legal path template
+ one small registered pair-token
+ no VRF-to-bitband same-cycle dynamic path
+ XOR0 accumulator unchanged
+ bit-matrix row tile unchanged or minimally time-multiplexed
```

这会是下一版值得继续攻的方向。
