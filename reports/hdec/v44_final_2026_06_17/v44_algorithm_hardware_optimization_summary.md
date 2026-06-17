# V44 算法到硬件优化记录

日期：2026-06-17

目标：沿着“先从算法语义减少重复动作，再映射成更小硬件选择网络”的路线，尝试在周期不增加、时序不低于 200MHz 的前提下降低面积。

## 结论

这轮在当前架构上拿到了稳定有效的面积下降，但还没有达到 300 LUT 以上的“几百 LUT”级别：

| 版本 | Slice LUT | 逻辑 LUT | LUTRAM | FF | WNS | 估算频率 | PMUL 周期 |
|---|---:|---:|---:|---:|---:|---:|---:|
| V43 baseline | 6330 | 5858 | 472 | 2009 | 0.250ns | 210.526MHz | 183793 |
| V44 final | 6132 | 5660 | 472 | 2008 | 0.247ns | 210.393MHz | 183793 |
| 变化 | -198 | -198 | 0 | -1 | -0.003ns | -0.133MHz | 0 |

所以，答案是：不改周期、不牺牲 200MHz 的情况下，当前这些局部算法/控制优化可以稳定降低约 200 LUT；想继续降低到 300 LUT 以上，不能只做局部 clean-up，需要继续动 VRF 读写选择、P2/P3 边界、ECC 中间结果存放方式这些更大的结构。

## 本轮保留的优化

### 1. HPERM 移位算法落成两个 64 位移位

原来硬件写法是先拼成 128 位：

```systemverilog
{src_b_i, src_a_i} >> bit_shift_i
```

算法上它真正需要的只是：

```text
低 64 位 = 当前 word 右移 s，再叠加下一个 word 左移 (64 - s)
```

所以硬件改成两个 64 位移位后再或起来。这样把一个 128 位大移位选择网络拆小，V44 单独这一步从 6330 降到 6240，少 90 LUT，时序不变。

### 2. HPERM 先取 5 个连续 word，再分给 4 个 lane

HPERM 每次不是任意取 8 个 word，而是取一个连续窗口：

```text
lane0 用 word0/word1
lane1 用 word1/word2
lane2 用 word2/word3
lane3 用 word3/word4
```

算法上承认这个“连续窗口”之后，硬件就不需要每个 lane 都各自调用一次独立选择函数。改成先生成 5-word window，再接到 lane shift A/B。该方向从 6240 降到 6218，少 22 LUT。

### 3. P3 写回按结果类型合并

HBIND、HPERM、HCNTADD 在 P3 的核心差别不是“写不写 VRF”，而是“写入 lane_bool_result 还是 lane_result_q”，以及后续状态跳转不同。

因此先把写回数据路径按两类合并：

```text
HBIND      -> 写 lane_bool_result
HPERM/CNT  -> 写 lane_result_q
```

状态跳转再用 case 处理。这样减少了重复的写使能、写地址、写数据控制分支。最终从 6218 降到 6132，又少 86 LUT。

## 被否掉的尝试

| 尝试 | Slice LUT | WNS / 频率 | 结论 |
|---|---:|---:|---|
| VRF 改 BRAM | 6264 | -0.681ns / 176.025MHz | LUTRAM 下降，但读写路径和 BRAM 代价让时序失败，逻辑 LUT 反而上升 |
| 给 uop 增加显式 tag 位 | 6337 | 0.308ns / 213.129MHz | 时序略好，但寄存器和控制位增加，面积高于 V43 |
| payload 寄存器去 reset | 6224 | 0.247ns / 210.393MHz | 有下降，但不如 P3 写回合并后的 6132 |
| 用 op_type bit 直接解码 | 6349 | 0.328ns / 214.041MHz | 解码更“巧”，但综合后面积更大 |
| HSIM/HMATCH 直接 XOR 后 popcount，不存 diff | 6535 | -0.838ns / 171.292MHz | 算法上少一次写入，硬件上破坏流水边界，XOR+popcount+控制变成长路径 |
| ecc_product_pair 改寄存器 | 6279 | -0.057ns / 197.746MHz | LUTRAM 少了，但 512 个左右 FF 和读选择网络变大，且低于 200MHz |

## 算法到硬件的判断规则

这轮最清楚的规律是：

1. 算法上能证明“输入是连续窗口”，硬件就能减少独立多路选择器。
2. 算法上能证明“多个操作写回形态相同”，硬件就能合并控制分支。
3. 算法上少一次中间写入，不一定省硬件；如果这个中间寄存器本来是流水边界，删掉会把路径拉长，面积和时序都会变坏。
4. 小容量存储不一定寄存器更省。`ecc_product_pair` 这种 4x128 的中间结果，分布式 RAM 在当前读写模式下比 FF 更适合。

## 下一步建议

如果继续追求 300 LUT 以上下降，并保持周期不变和 200MHz，建议优先看两个方向：

1. 继续压 VRF 周围的读写选择网络。当前最终层级里 `i_vrf` 是 3550 LUT，是最大的面积源。
2. 保留 P2/P3 流水边界，但继续把“写回类别”和“下一状态类别”做成更少的共享控制，而不是给每种操作单独铺控制信号。

不建议继续做的方向：

1. 直接把 diff 向量去掉并把 XOR 接到 popcount。
2. 把小容量 ECC 中间结果强行改成 FF。
3. 只为了 tag 故事给 uop 增加新控制位。

## 验证

功能回归：

- `xsim_hdec_hdc_full_flow_v20` PASS
- `xsim_hdec_hperm_bit_align` PASS
- `xsim_hdec_ecc_pmul_profile_v27` PASS，`PMUL_PROFILE_WALL_CYCLES=183793`
- `xsim_hdec_ecc_reduce_v1` PASS

OOC：

- 脚本：`scripts/hdec/ooc_hdec_p2_popcount_local_keep_v1.tcl`
- 器件：`xc7z020clg400-2`
- 约束：5.0ns
- 报告目录：`reports/hdec/v44_final_2026_06_17/ooc_v44_final`

