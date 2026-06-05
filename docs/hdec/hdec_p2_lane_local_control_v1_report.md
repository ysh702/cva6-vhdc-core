# HDEC P2 Lane-local Control v1 Report

## 1. 基线

| Item | Value |
|---|---|
| 工作分支 | `hdec-p2-lane-local-control-v1` |
| 基线分支 | `hdec-p2p3-split-result-payload-v1` |
| base commit | `e0925738 docs: add OOC report for HDEC lane result split-path registers` |
| RTL baseline | `ec561b73 hdec: split narrow P2 payload registers` |

基线最近 3 个提交已确认：

```text
e0925738 docs: add OOC report for HDEC lane result split-path registers
099c04dd docs: add P2-P3 payload split optimization report
ec561b73 hdec: split narrow P2 payload registers
```

## 2. 本阶段目标

本阶段是控制信号瘦身阶段 1，只做 P2 Lane 控制删减与 Lane-local decode。

本阶段不修改 ISA，不增加 pipeline stage，不增加 cycles，不改变 VADDR/VWR64/VRD64 fast path，不改变 HCLR/HCNTCLR，不改变 P3 GLOBAL 语义，不改变 response 协议，不修改测试预期。

## 3. 删除/停用的旧控制信号

最终 RTL 中已删除或停用以下旧 P2 主控制：

| 旧控制 | 处理结果 |
|---|---|
| `uop.use_xor` | 从 `hdec_uop_t` 删除 |
| `uop.use_popcount` | 从 `hdec_uop_t` 删除 |
| `uop.use_counter` | 从 `hdec_uop_t` 删除 |
| `uop.use_clip` | 从 `hdec_uop_t` 删除 |
| `uop.use_shift` | 从 `hdec_uop_t` 删除 |
| `uop_lane_bool_valid` | 从 `hdec_top.sv` 删除 |
| `lane_cnt_valid` | 从 `hdec_top.sv` 删除 |
| `lane_shift_valid` | 从 `hdec_top.sv` 删除 |
| `lane_clip_valid` | 从 `hdec_top.sv` 删除 |
| `lane_shift_nibble` | 从 `hdec_top.sv` 删除 |
| `hperm_nibble_q` / `uop.perm_nibble` | 合并为 `lane_ctrl.perm` |
| P2 payload capture priority if/else | 改为 `lane_ctrl.capture_kind` case |

静态扫描结果：`use_*`、`uop_lane_bool_valid`、`lane_cnt_valid`、`lane_shift_valid`、`lane_clip_valid`、`lane_shift_nibble`、`uop.perm_nibble` 在最终 RTL 中不再出现。

## 4. 新增控制信号与替代关系

| 新信号 | 替代旧信号 | 是否减少真实控制数量 |
|---|---|---|
| `lane_ctrl.valid` | P2 lane issue 生效条件 | No，必要 stage valid |
| `lane_ctrl.op` | `use_xor/use_popcount/use_counter/use_clip/use_shift` 和 4 个 TOP direct lane valid | Yes |
| `lane_ctrl.capture_kind` | `lane_result_n/lane_popcnt_n/lane_clip_n` priority capture branch | Yes |
| `lane_ctrl.subgroup` | lane 侧 `hcntadd_subgroup_q/uop.subgroup_idx` 直接使用 | Yes |
| `lane_ctrl.threshold` | lane 侧 `hcntclip_threshold_q` 直接使用 | Yes |
| `lane_ctrl.perm` | `lane_shift_nibble/uop.perm_nibble/hperm_nibble_q` | Yes |

新增类型位于 `core/hdec/rtl/hdec_pkg.sv`：

- `hdec_lane_op_e`
- `hdec_lane_capture_kind_e`
- `hdec_lane_ctrl_t`

## 5. Lane-local decode 结构

新增 `core/hdec/rtl/hdec_lane_p2_local.sv`。

该 wrapper 接收 `lane_ctrl_i` 和 lane payload 输入，在 Lane 附近解码生成：

- `bool_valid`
- `cnt_valid`
- `shift_valid`
- `clip_valid`
- `cnt_subgroup`
- `shift_nibble`
- `clip_threshold`

然后实例化原有 `hdec_lane_4x64`。TOP 不再直接驱动这些 local valid。

## 6. TOP FSM 职责变化

修改后，`S_UOP_P2_LANE` 只负责：

- 把 `uop_p2_q` 推进到 `uop_p3_n`；
- 对 HPERM 准备 shift input payload；
- 根据 `lane_ctrl.capture_kind` 抓取 P2/P3 split payload；
- 推进到 `S_UOP_P3_GLOBAL`。

`S_UOP_P2_LANE` 不再根据 `use_*` 生成 Lane local valid，也不再用 `use_*` priority if/else 决定 payload 写入。

## 7. 控制信号数量变化

本表采用 `docs/hdec/top_control_signal_reduction_refactor_plan.md` 的同一信号组口径，但只统计阶段 1 已完成的 P2 Lane 控制删减；P3 global、WB/VRF/response 后续阶段未计入本次完成量。

| 项目 | 修改前 | 修改后 | 减少 |
|---|---:|---:|---:|
| TRUE_CONTROL | 69 | 61 | 8 |
| TOP_DIRECT_LANE_CONTROL | 15 | 6 | 9 |
| DUPLICATED_OR_DERIVED_CONTROL | 18 | 8 | 10 |

说明：

- `TOP_DIRECT_LANE_CONTROL` 从旧的 `use_*`、TOP direct valid、shift nibble、priority capture，收缩为 `lane_ctrl.valid/op/capture_kind/subgroup/threshold/perm` 6 个语义字段。
- `TRUE_CONTROL` 仍保留 P3 global loop、VRF/writeback、response 相关旧控制，因为这些属于后续阶段。
- `DUPLICATED_OR_DERIVED_CONTROL` 本阶段删除了 `use_*`、TOP direct valid、旧 shift nibble/perm 参数路径和旧 P2 capture priority chain。

## 8. Verilator 验证结果

| Check | Result |
|---|---|
| `make verilate NUM_JOBS=16` | PASS |
| HDEC 20/20 regression | PASS |
| `git diff --check` | PASS |

20/20 回归使用 `docs/hdec/vmware_ubuntu22_seven_souls_regression_baseline.md` 中的测试清单和命令模板。每个测试 fresh build ELF，完整仿真日志保存在 `tmp/hdec_logs/<test>.log`。

| # | Test | Result | Cycles |
|---:|---|---|---:|
| 1 | `min_test_current_protocol` | PASS | 2902 |
| 2 | `vrw_current_protocol_test` | PASS | 2933 |
| 3 | `va_test` | PASS | 2891 |
| 4 | `va4_test` | PASS | 3092 |
| 5 | `multi_index_test` | PASS | 3041 |
| 6 | `bank0_test` | PASS | 2955 |
| 7 | `bank1_test` | PASS | 3008 |
| 8 | `bank2_test` | PASS | 3008 |
| 9 | `bank3_test` | PASS | 3008 |
| 10 | `hclr_test` | PASS | 3035 |
| 11 | `hcntclr_test` | PASS | 3246 |
| 12 | `hcntadd_test` | PASS | 5091 |
| 13 | `hcntclip_test` | PASS | 5309 |
| 14 | `hbind_test` | PASS | 3141 |
| 15 | `hperm_test` | PASS | 35849 |
| 16 | `hsim_test` | PASS | 5026 |
| 17 | `hmatch_test` | PASS | 3936 |
| 18 | `hdc_pipeline_test` | PASS | 3869 |
| 19 | `hdc_inference_test` | PASS | 5487 |
| 20 | `hdc_e2e_train_infer_test` | PASS | 130358 |

所有 20 个当前 fresh log 均包含 `*** SUCCESS ***`，且不包含 `FAILED/FAIL/Fatal/ASSERT/Aborted/core dumped/Segmentation fault` 失败标记。

第一次在沙箱内运行仿真时，testharness 因 `remote_bitbang failed to make socket: Operation not permitted (1)` 失败。该失败属于环境/工具权限层，不是 RTL 层。随后在非沙箱环境按相同命令重跑，20/20 PASS。

## 9. Vivado OOC 结果

本环境未运行 Vivado OOC。原因：

- `command -v vivado` 无结果；
- `/tools`、`/opt`、`/home/ysh` 常见路径下未找到 `vivado` 可执行文件。

因此本报告不伪造 OOC timing/utilization/power 数据。

已有 `ec561b73` OOC baseline 来自 `docs/hdec/hdec_lane_result_split_path_registers_ooc_synthesis_report.md`：

| Metric | ec561b73 baseline |
|---|---:|
| Estimated Fmax | ~143.3 MHz |
| WNS @150MHz | -0.312 ns |
| WNS @200MHz | -1.979 ns |
| LUT @150MHz | 4709 |
| Logic LUT @150MHz | 4021 |
| LUTRAM | 688 |
| FF | 2177 |
| CARRY4 | 13 |

当前分支的 OOC Fmax/WNS/LUT/FF/uop fanout 需要在有 Vivado 2022.2 的环境中补跑。

## 10. Critical path 分析

`ec561b73` baseline 的 OOC worst path 是：

```text
FSM_onehot_st_q_reg[6] / S_UOP_P2_LANE
  -> lane_popcnt_q_reg[0][4]
```

当前分支未能在本环境生成 Vivado netlist，因此不能给出新的真实 worst path。

从 RTL 结构看，本阶段已经移除该路径上的旧控制来源：

- `use_popcount` 不再存在；
- TOP 不再生成 `uop_lane_bool_valid`；
- TOP 不再生成 `lane_cnt_valid/lane_shift_valid/lane_clip_valid`；
- `lane_popcnt_q` capture 不再由 `use_popcount` priority branch 控制，而由 `lane_ctrl.capture_kind == HDEC_CAPTURE_POP7` 控制。

这说明控制下沉在 RTL 结构上已经生效。但是否把 OOC worst path 从 `FSM_onehot_st_q_reg[6] -> lane_popcnt_q_reg[*]` 移走，必须以 Vivado OOC 报告为准。

## 11. 风险和后续阶段

剩余风险：

- `lane_ctrl.capture_kind` 仍在 TOP 中用于 split payload capture；本阶段已去掉 priority if/else，但 capture register 仍在 TOP P2/P3 边界。
- HPERM 的 shift input payload 选择仍在 TOP 中完成；它是 payload source selection，不再生成 shift valid/nibble，但后续若要进一步下沉 perm source select，需要单独评估面积和 timing。
- OOC 未运行，不能确认真实 Fmax、WNS、fanout 和 critical path 改善。

后续阶段建议：

- P3 global control 瘦身；
- WB/VRF/Response command 整理；
- TOP FSM 状态压缩；
- 在 Vivado 2022.2 环境补跑 `hdec_top` OOC sweep，并重点检查 `FSM_onehot_st_q_reg[6] -> lane_popcnt_q_reg[*]` 是否仍为 worst path。
