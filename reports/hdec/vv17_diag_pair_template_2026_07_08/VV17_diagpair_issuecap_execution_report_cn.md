# VV17 finite-template diagonal-pair issue/capture 执行报告

## 版本定位

VV17 是从 VV16 sub-shadow diagonal folding checkpoint 继续推进的一版有限模板调度尝试。

这一版没有复制 HDC/ECC 共享的 `8x32` bit-matrix row tile，也没有新增独立 ECC 乘法器或宽动态 reducer。核心变化是把 leaf 边界处的最后一条 diagonal group 与下一 leaf 的第一条 diagonal group 做寄存器级调度重叠：

```text
旧 leaf group7 capture
+ 同拍 issue 下一 leaf group0 product

下一拍 capture 下一 leaf group0 product
+ 同拍 fold 旧 leaf sub2 delta into XOR0
```

因此它不是“同拍产生两组 parity row”的 datapath 加倍方案，而是有限状态模板上的 `group7/group0` diagonal-pair 调度。

## 接受版本

接受版本为 `diagpair_issuecap_v3`。

关键 RTL 文件：

```text
core/hdec/rtl/hdec_top.sv
```

主要修改：

1. 将下一 leaf 的 A/B 预取窗口前移：

   ```text
   group2: request next leaf A
   group3: request next leaf B
   group5: capture next leaf A into pending-A shadow
   group6: capture next leaf B，同时把 pending-A 换入主 A 寄存器
   ```

2. 在旧 leaf 的 `group7/sub2` capture 周期允许发射下一 leaf 的 `group0` product。

3. 用 `sub == 3` 作为一个 one-cycle sentinel：下一拍处于 `group0/sub3` 时，capture 新 leaf group0，同时将旧 leaf 的 sub2 delta 通过已有 XOR0 accumulator 折叠进去。

4. 为了避免在 bit-matrix 输入前加入高扇出 mux，采用 pending-register 方法：

   ```text
   ecc_leaf_a_next_q
   ecc_leaf_xor_a_next_q
   ```

   旧 leaf 的 group7 发射仍然使用主 `ecc_leaf_a_q/ecc_leaf_b_q`；下一拍 group7 发射下一 leaf group0 时，主寄存器已经自然换成下一 leaf 的 A/B。

## 为什么不是直接 group-pair datapath

真正同拍产生两个 diagonal group 需要两组 8-row parity source，等价于再增加一批 AND/parity 项。相邻 diagonal group 的 AND 项并不共享到足以免费生成第二组 parity row。因此直接 `16 rows per issue` 会走向面积换周期，不符合本阶段目标。

VV17 采用的是调度级 pair：不增加第二套 bit-matrix row tile，只把 leaf 边界处原本串行的 `group7 -> issue -> group0` 压成 `group7(issue group0) -> group0(capture group0 + fold old sub2)`。

## 结果对比

| 版本 | PMUL cycles | ST_ECC_DIAG | ST_ECC_LEAF_FOLD | SUB_ZERO | GF_MUL_STARTS | Logic LUT | FF | Fmax |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| VV16 baseline | 305836 | 267300 | 10692 | 0 | 1188 | 4718 | 1426 | 207.297 MHz |
| VV17 issue-fold fallback | 296332 | 267300 | 1188 | 0 | 1188 | 4773 | 1426 | 207.297 MHz |
| VV17 diagpair issue/capture v3 | 286828 | 257796 | 1188 | 0 | 1188 | 4751 | 1490 | 214.041 MHz |

相对 VV16：

```text
PMUL cycles: 305836 -> 286828  (-19008)
Logic LUT:   4718   -> 4751    (+33)
FF:          1426   -> 1490    (+64)
Fmax:        207.297 -> 214.041 MHz
```

这说明周期下降不是来自 K=0 或 zero case skip。`SUB_ZERO=0`，`GF_MUL_STARTS=1188` 均保持不变。

## 通过的验证

功能仿真：

```text
reports/hdec/vv17_diag_pair_template_2026_07_08/xsim_pmul_diagpair_issuecap_v3
reports/hdec/vv17_diag_pair_template_2026_07_08/xsim_diag_reduce_map_diagpair_issuecap_v3
reports/hdec/vv17_diag_pair_template_2026_07_08/xsim_reduce_diagpair_issuecap_v3
reports/hdec/vv17_diag_pair_template_2026_07_08/xsim_add_diagpair_issuecap_v3
reports/hdec/vv17_diag_pair_template_2026_07_08/xsim_hdc_full_diagpair_issuecap_v3
```

结果：

```text
[HDEC_ECC_PMUL_PROFILE_V27] PASS
[HDEC_ECC_DIAG_REDUCE_MAP_V1] PASS
[HDEC_ECC_REDUCE_V1] PASS
[HDEC_ECC_ADD_V1] PASS
[HDEC_HDC_FULL_FLOW_V20] PASS
```

OOC：

```text
reports/hdec/vv17_diag_pair_template_2026_07_08/ooc_diagpair_issuecap_v3
```

结果：

```text
LogicLUT=4751
FF=1490
Fmax=214.041 MHz
WNS=0.328
BRAM=4
DSP=0
```

## 被拒绝的探针

### same-cycle parity tap

尝试把当前组合 parity 直接用于 capture/fold，周期可到：

```text
PMUL cycles = 295144
```

但 OOC 失败：

```text
LogicLUT=4815
Fmax=187.688 MHz
WNS=-0.328
```

原因是 current parity -> delta/fold 进入关键路径，不符合 200 MHz 门槛。

### deferred same-cycle

尝试把 same-cycle capture 与 deferred fold 结合，功能可过，但面积和时序更差：

```text
LogicLUT=5105
Fmax=186.081 MHz
```

因此拒绝。

### direct old-A mux

为了让 group6 仍发射旧 leaf group7，曾尝试在 bitband source A 前放一个 old-A mux。

功能和周期正确：

```text
PMUL cycles = 286828
```

但面积不可接受：

```text
LogicLUT=4963
FF=1458
```

原因是 mux 位于 bit-matrix 输入前，综合成高扇出选择网络。该探针直接给出了 v3 的设计原则：不要在 AND/parity 面前放动态 mux，改用寄存器换入。

## 结论

VV17 完成了一版可保留的有限模板 diagonal-pair 调度：

```text
不跳 K=0
不复制 bit-matrix row tile
不新增独立 ECC datapath
继续复用 XOR0 accumulator
用 pending register 避免 bit-matrix 输入 mux
以 +33 LUT 换取 -19008 PMUL cycles
```

这版还没有进入 10W-20W 周期区间，但它比 VV16/VV16 issue-fold 更接近主线目标：周期下降来自 leaf-boundary diagonal scheduling，而不是面积换取的并行 row tile。

下一步如果继续压周期，优先方向应是继续找类似 `group7/group0` 的无气泡边界，而不是在 bit-matrix 输入前添加 mux，或者直接复制第二套 group datapath。
