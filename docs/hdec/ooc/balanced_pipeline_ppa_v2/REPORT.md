# HDEC balanced pipeline PPA v2 OOC report

## 结论

本轮在 `origin/hdec-second-stage-optimization` 的基础上新建分支 `hdec-balanced-pipeline-ppa-v2`，目标是继续减少 HDEC 控制/地址搬运冗余，并让内部流水线的近关键路径更均衡。

最终保留的 RTL 修改是功能等价的控制/地址流瘦身：

- 从 `hdec_uop_t` 去掉重复随流水线传播的 `arch_op`、`class_count`、`src0_base/src1_base/dst_base`。
- HMATCH class index 从 8 bit 缩到 3 bit，并把 class 总数改成 3 bit `last_idx`。
- HMATCH 后续 chunk 的 class 地址直接由 `hmatch_class_slot_q` 生成，不再依赖 uop 里重复保存的 base。
- `res_q` 非结果周期默认清零，减少 `res_q/CE` 复杂保持逻辑。

最终结论：资源明显下降，但最高 Fmax 没有提升。当前最高时序仍被 P2 lane popcount 捕获路径限制。也就是说，这轮把旁路/控制冗余清掉了，但真正要继续抬 Fmax，需要继续处理 P2 popcount 数据路径。

## 环境

| 项目 | 值 |
|---|---|
| Vivado | 2024.2 |
| Part | `xc7z020clg400-2` |
| Top | `hdec_top` |
| OOC period | 5.000 ns / 200 MHz |
| 基线提交 | `02b1c26e HDEC second stage RTL optimization` |
| 当前分支 | `hdec-balanced-pipeline-ppa-v2` |

## 资源对比

| 版本 | Slice LUT | Logic LUT | LUTRAM | FF | BRAM | DSP | CARRY4 |
|---|---:|---:|---:|---:|---:|---:|---:|
| baseline 200 MHz | 4553 | 3865 | 688 | 2155 | 0 | 0 | 14 |
| final trial09 | 4471 | 3783 | 688 | 2051 | 0 | 0 | 14 |
| delta | -82 | -82 | 0 | -104 | 0 | 0 | 0 |

说明：VRF 仍为 LUTRAM，未把 LUTRAM 伪装成 LUT 下降。所以下降的 82 个 Logic LUT 是真实逻辑减少，不是存储实现迁移造成的。

## Timing 对比

| 版本 | WNS @200MHz | Worst delay | Fmax 估计 | Worst endpoint |
|---|---:|---:|---:|---|
| baseline | -0.447 ns | 5.444 ns | 183.587 MHz | lane0 popcount result bit |
| final trial09 | -0.447 ns | 5.444 ns | 183.587 MHz | lane0 popcount result bit |

最高 Fmax 没变，因为前 16 条路径仍然是 4 个 lane 的 P2 popcount capture。优化控制/uop/mux 不会改变这条纯数据路径。

## Top path atlas

| 类别 | baseline 近似 slack | final 近似 slack | 变化 |
|---|---:|---:|---|
| P2 lane popcount capture | -0.447 ns | -0.447 ns | 不变，仍是 top1 |
| HMATCH budget/update | -0.236 ns | -0.236 ns | 不变 |
| scalar response / `res_q/CE` | -0.053 ns | 消失 | 改善 |
| HSIM/HMATCH control CE | 不突出 | -0.022 ns | 新近路径，但比原 `res_q/CE` 更轻 |
| VRF write/control | +0.219 ns | +0.205 ns | 仍为正 slack |

用小白能理解的话说：现在最长路径还是“VRF 读出来的数据进入 lane，做 XOR 和 popcount，然后写进 popcount 结果寄存器”。HMATCH 那边排第二。原来那串 response 结果寄存器使能路径已经不再挡路。

## Trial 保留/回退记录

| Trial | 内容 | 结论 |
|---|---|---|
| trial01 | 删除 uop 中重复的 `arch_op/class_count` | 保留，LUT/FF 降低 |
| trial02 | P4 response kind 缩码 | 回退，scalar response path 变差 |
| trial04 | 64-bit popcount 改 2x32 | 回退，WNS 变到 -0.864 ns，CARRY4 增到 22 |
| trial05 | HMATCH class slot 4 bit 缩 3 bit | 回退，VRF 控制路径变差 |
| trial06 | 删除 uop 中三组 base 字段 | 保留，但补修 HMATCH class base bug |
| trial07 | HMATCH num 改 last_idx | 保留，小幅降资源 |
| trial08 | `res_q` 默认清零，减少 CE 保持 | 保留，移除 `res_q/CE` 近路径 |
| trial09 | HMATCH 后续 chunk 地址由 class slot 生成 | 保留，xsim 通过，控制近路径改善 |

## 功能检查

Vivado xsim:

- `single class max distance`: PASS
- `second class exact match`: PASS
- `tie keeps first class`: PASS
- `illegal num_classes zero`: PASS

日志已归档到 `xsim_trial09.log`。

## 文献/设计启发

本轮没有引入会改变模型精度边界的算法级稀疏化，只借鉴 HDC 硬件优化里的两个方向：

- SparseHD 强调算法/硬件协同减少无效维度和存储/计算压力，后续可作为“跳过维度/稀疏原型”的单独实验方向：https://cseweb.ucsd.edu/~bkhalegh/papers/FCCM19-SparseHD.pdf
- Hypervector Design for Efficient HDC 说明降低维度和硬件成本存在 Pareto 设计空间，适合后续做精度-面积-频率联合探索：https://arxiv.org/abs/2103.06709
- Dense Binary HDC hardware optimization 提到 rematerialization 和组合式 associative memory，启发本轮优先减少重复状态搬运，而不是盲目复制/缓存：https://arxiv.org/abs/1807.08583

## 下一步建议

1. 下一轮重点处理 P2 popcount capture。简单拆成 2x32 已经证明会变差，不能走这个方向。
2. 如果允许多一拍，最稳的是把 P2 popcount 数据路径切开；如果不允许多一拍，需要考虑更 FPGA 友好的 popcount primitive/tree，并用 OOC 逐个验证。
3. HMATCH 当前不是 top1，但仍是第二类路径；在 P2 解决后，需要继续追踪 `lane_popcnt_q -> hmatch_budget_q/hmatch_update_q`。
4. 算法级稀疏/跳维度值得单独开实验分支，因为它会影响结果精度和指令语义，不应混入这条功能等价 PPA 分支。
