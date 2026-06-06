# HDEC P2 One-hot Per-lane Local Slice Plan

## 1. 基线确认

| 项目 | 结果 |
|---|---|
| 当前计划分支 | `hdec-p2-onehot-local-slice-plan-v1` |
| 分支起点 | `e0925738 docs: add OOC report for HDEC lane result split-path registers` |
| RTL baseline | `ec561b73 hdec: split narrow P2 payload registers` |
| 基线分支 | `hdec-p2p3-split-result-payload-v1` |
| 失败实验分支 | `hdec-p2-lane-local-control-v1` |
| 失败实验 RTL commit | `a010fdf9 hdec: move P2 lane control to local decode` |

当前分支从 `hdec-p2p3-split-result-payload-v1 / e0925738` 创建，明确不是从 `a010fdf9` 或其后续 OOC 文档 commit 创建。

确认的基线历史：

```text
e0925738 docs: add OOC report for HDEC lane result split-path registers
099c04dd docs: add P2-P3 payload split optimization report
ec561b73 hdec: split narrow P2 payload registers
8f8774e9 test: refresh HDEC regression for VADDR protocol baseline
9f2485fc hdec: migrate HDC ops to unified uop pipeline
```

本计划只讨论下一版 P2 timing 实验，不修改 RTL、测试、ISA、pipeline stage、cycles、P3 GLOBAL、VRF fast path 或 response 协议。

## 2. 上一版 lane_ctrl.op 方案失败原因

`a010fdf9` 删除了 `use_*`，但用共享的 encoded `lane_ctrl.op` 和 `lane_ctrl.capture_kind` 替代。每个 lane wrapper 再执行：

```systemverilog
lane_ctrl.op == HDEC_LANE_POPCOUNT_DIFF
lane_ctrl.capture_kind == HDEC_CAPTURE_POP7
```

该结构存在四个问题：

1. encoded op 必须经过相等比较器和结果选择逻辑，增加 LUT。
2. 四个 lane 共享同一份 `uop_p2_q.lane_ctrl.op`，共享控制扇出仍然存在。
3. wrapper 只有组合 decode，没有每 lane 独立的 local control register。
4. payload capture register 仍在 `hdec_top`，控制到 `lane_popcnt_q` 的长路径没有被真正切断。

失败实验 OOC 数据：

| Metric | `ec561b73` split-path baseline | `a010fdf9` encoded lane control | Change |
|---|---:|---:|---:|
| Estimated Fmax | ~143.3 MHz | ~142.2 MHz | -1.1 MHz |
| WNS @150MHz | -0.312 ns | -0.365 ns | -0.053 ns |
| WNS @200MHz | -1.979 ns | -2.032 ns | -0.053 ns |
| LUT | 4709 | 5038 | +329 |
| Logic LUT | 4021 | 4350 | +329 |
| FF | 2177 | 2203 | +26 |
| Critical path start | `FSM_onehot_st_q_reg[6]` | `uop_p2_q_reg[lane_ctrl][op][1]` | 控制源换名 |
| Critical path end | `lane_popcnt_q_reg[0][4]` | `lane_popcnt_q_reg[1][4]` | capture endpoint 未改变 |

需要注意：`ec561b73` 报告使用 Vivado 2022.2，`a010fdf9` 报告使用 Vivado 2024.2，因此资源和 timing 变化不能全部绝对归因于 RTL。不过，在现有实验条件下，encoded 方案没有产生 timing 收益，且关键路径仍是 P2 control 到 popcount capture。它不应继续作为新 timing baseline。

本次必须改为 predecoded bit control。允许在 P1 控制装载端对已有 `uop.op_type` 做一次预解码，但 P2 local control register 到 compute/capture 之间不得再有 encoded op 比较器。

## 3. 新方案总目标

新方案采用：

```text
P1 control predecode
  -> lane0_p2_ctrl_q -> lane0 compute -> lane0 local capture_q
  -> lane1_p2_ctrl_q -> lane1 compute -> lane1 local capture_q
  -> lane2_p2_ctrl_q -> lane2 compute -> lane2 local capture_q
  -> lane3_p2_ctrl_q -> lane3 compute -> lane3 local capture_q
```

核心目标：

- 使用 FPGA 友好的 one-hot / direct bit control；
- 每 lane 一份独立 P2 local control register；
- P2 关键路径上不使用 `lane_op` enum 或 `capture_kind` enum；
- 每个 local control bit 只驱动本 lane compute 和 capture；
- 尽可能把 `lane_result_q/lane_popcnt_q/lane_clip_q` 放入 per-lane slice；
- 保持 `ec561b73` 已验证的 split payload 宽度；
- 不增加 pipeline stage；
- 不增加 instruction cycles；
- 不改变 P3 GLOBAL 的消费语义；
- 不改变 VRF、fast path、response 或测试预期。

本次目标不是减少 RTL 文本中的信号数量，而是减少：

- 共享控制 fanout；
- encoded compare；
- TOP 到 lane payload capture 的长路径；
- 重复或派生控制；
- route-dominated critical path。

如果 one-hot 方案使用更多 FF 或更多控制 bit，但 LUT 更少、fanout 更低、critical path 更短，这是可以接受的 FPGA timing 权衡。

## 4. 可删除的冗余控制信号

### 4.1 最终建议删除

| baseline 信号/逻辑 | 最终处理 | 替代方式 |
|---|---|---|
| `uop.use_xor` | 删除 | P1/P2 边界预解码为 per-lane `do_xor_only` 或 `do_popcount_diff` |
| `uop.use_popcount` | 删除 | per-lane `do_popcount_diff` |
| `uop.use_counter` | 删除 | per-lane `do_counter` |
| `uop.use_clip` | 删除 | per-lane `do_clip` |
| `uop.use_shift` | 删除 | per-lane `do_shift` |
| `uop_lane_bool_valid` | 删除 | local `do_xor_only \| do_popcount_diff` |
| `lane_cnt_valid` | 删除 | local `do_counter` |
| `lane_shift_valid` | 删除 | local `do_shift` |
| `lane_clip_valid` | 删除 | local `do_clip` |
| TOP P2 capture priority if/else | 删除 | local registered `capture_vec/pop/clip` bit |

### 4.2 第一阶段暂时保留

为隔离 timing 变量，阶段 1A 可暂时保留 `use_*`，只把它们作为 P1/P2 边界 one-hot control register 的装载源。此时：

- `use_*` 不再直接驱动 P2 compute/capture；
- `use_*` 到 local ctrl_q 的 fanout只应约为 4；
- P2 critical path 从 local ctrl_q 开始；
- OOC 先验证寄存器复制本身是否有效。

阶段 1C 再删除 `use_*`，改为在 local ctrl_q 装载端根据 `uop_p1_q.op_type` 预解码。比较器只位于 local ctrl_q 之前，不位于 local ctrl_q 到 capture_q 的关键路径。

### 4.3 建议保留

| 信号/结构 | 原因 |
|---|---|
| `uop.valid` | pipeline 流动控制，不能用 lane control 替代 |
| `uop.op_type` | P1 地址行为、P3 GLOBAL 语义和 loop 仍需要 |
| `uop.chunk_idx/subgroup_idx/class_idx` | P3 loop 和地址生成需要 |
| `lane_result_q/lane_popcnt_q/lane_clip_q` 的 split 宽度 | `ec561b73` 已证明有效 |
| `hperm_word_off_q/hperm_lane_base_q` | HPERM source word selection 仍在 TOP |
| P3 对三个 split payload 的直接消费 | 不重新合并宽 mux |

`hperm_nibble_q`、`uop.perm_nibble` 和 lane shift 参数是否进一步合并，应在阶段 1C 单独判断，不能和第一刀 timing 实验混在一起。

## 5. 新 one-hot 控制信号草案

推荐最终类型：

```systemverilog
typedef struct packed {
  logic       do_xor_only;
  logic       do_popcount_diff;
  logic       do_counter;
  logic       do_clip;
  logic       do_shift;

  logic       capture_vec;
  logic       capture_pop;
  logic       capture_clip;

  logic [1:0] subgroup;
  logic [3:0] threshold;
  logic [3:0] perm_nibble;
} hdec_p2_lane_ctrl_t;
```

不使用：

- `hdec_lane_op_e`；
- `hdec_lane_capture_kind_e`；
- `lane_ctrl.op == ...`；
- `lane_ctrl.capture_kind == ...`。

`do_xor_only` 与 `do_popcount_diff` 分开，目的是让五种 operation family 满足 `$onehot0`。HSIM/HMATCH 只置 `do_popcount_diff`，local bool valid 由一个本地 OR 生成：

```systemverilog
bool_valid = ctrl_q.do_xor_only | ctrl_q.do_popcount_diff;
```

capture bits 独立注册并满足：

```systemverilog
$onehot0({
  ctrl_q.capture_vec,
  ctrl_q.capture_pop,
  ctrl_q.capture_clip
});
```

建议不在最终关键路径上增加独立 `valid` bit。`do_*` 和 `capture_*` 在非 P2 周期清零，本身就是有效脉冲。额外 `valid && capture_pop` 会增加一层逻辑，并形成新的共享控制候选。

如果实现阶段为了调试保留 `valid`：

- 只能用于 assertion 或状态检查；
- 不应串入 payload capture D/CE 关键路径；
- OOC 后若无必要应删除。

操作映射：

| UOP | do control | capture control |
|---|---|---|
| `UOP_HBIND_CHUNK` | `do_xor_only=1` | `capture_vec=1` |
| `UOP_HSIM_CHUNK` | `do_popcount_diff=1` | `capture_pop=1` |
| `UOP_HMATCH_CHUNK` | `do_popcount_diff=1` | `capture_pop=1` |
| `UOP_HCNTADD_SUBGROUP` | `do_counter=1` | `capture_vec=1` |
| `UOP_HCNTCLIP_READ` | `do_clip=1` | `capture_clip=1` |
| `UOP_HPERM_CHUNK` | `do_shift=1` | `capture_vec=1` |

vector result 的 local selection 使用 one-hot bit mux，不使用 encoded case：

```text
do_xor_only -> bool_result
do_counter  -> counter_result
do_shift    -> shift_result
```

该 mux 每 lane 独立，popcount 和 clip capture 不经过 vector mux。

## 6. per-lane ctrl_q 设计方案

### 6.1 方案 A：shared `p2_ctrl_q`

```text
shared p2_ctrl_q
  -> lane0
  -> lane1
  -> lane2
  -> lane3
  -> TOP capture
```

| 项目 | 评估 |
|---|---|
| FF | 最少 |
| LUT | 无 encoded compare 时可较低 |
| fanout | shared bit 仍驱动 4 lane 及 capture |
| route | 仍可能跨越整个 P2 区域 |
| critical path | 可能只是把 FSM/use_* 换成 shared one-hot bit |
| 是否满足每 lane local ctrl | 否 |

shared one-hot 比 encoded op 更好，但没有解决“一个控制源驱动四个 lane”的核心问题，不推荐作为最终结构。

### 6.2 方案 B：4 份 per-lane `p2_lane_ctrl_q`

```systemverilog
hdec_p2_lane_ctrl_t p2_lane_ctrl_q[LANE_NUM];
```

```text
p2_lane_ctrl_q[0] -> lane0 only
p2_lane_ctrl_q[1] -> lane1 only
p2_lane_ctrl_q[2] -> lane2 only
p2_lane_ctrl_q[3] -> lane3 only
```

| 项目 | 评估 |
|---|---|
| FF | 增加，但 FPGA FF 成本可接受 |
| LUT | P2 不需要 op comparator；预期持平或下降 |
| fanout | 每个 Q bit 只驱动本 lane |
| route | 控制起点可放到 lane 附近 |
| critical path | 从 local FF 到 local compute/capture |
| 是否满足每 lane local ctrl | 是 |

推荐方案 B。

关键实现要求：

1. ctrl_q 在进入 `S_UOP_P2_LANE` 前一拍装载。
2. `S_UOP_P2_LANE` 使用已注册 one-hot bit，不现场 decode。
3. 离开 P2 后 ctrl_q 清零，避免重复 capture。
4. HCNTADD/HCNTCLIP 从 P3 直接回 P2 时，必须在同一 P3->P2 边界重新装载 local ctrl 和新 subgroup。
5. 不增加新的 P2 等待状态。

### 6.3 等价寄存器合并风险

四份 ctrl_q 的 D 值在多数周期相同，Vivado 可能执行 equivalent register removal，把四份逻辑等价寄存器重新合并成一个高扇出寄存器。模块层级本身不能保证物理复制。

每次 OOC 必须检查：

- synthesized netlist 中每个 control bit 是否确实有 4 个 FDCE/FDRE；
- 每个 local ctrl Q 的 fanout 是否只覆盖一个 lane；
- high fanout report 中是否重新出现 shared ctrl；
- critical path startpoint 是否来自目标 lane 的 local ctrl_q。

默认先不加大范围 `DONT_TOUCH/KEEP_HIERARCHY`，因为这些属性可能阻止有益优化并增加 LUT。如果 Vivado 合并了 local ctrl_q，再只对目标 ctrl_q register 使用窄范围 `KEEP` 或等效属性，并重新比较 OOC。不能假设“写了数组”就已经完成物理复制。

## 7. per-lane payload capture slice 设计方案

### 7.1 方案 A：ctrl per-lane，capture 留在 TOP

```text
local ctrl_q[lid] -> lane compute
                  -> TOP lane_popcnt_q[lid]
```

优点：

- 改动小；
- 可以单独验证 ctrl replication 对 fanout 的影响；
- 不改变 payload register 数量和 P3 接口。

风险：

- capture always_ff 仍属于 TOP；
- 综合 flatten 后 local ctrl 到 TOP capture 的 route 可能仍然较长；
- `control -> lane_popcnt_q` endpoint 很可能仍是 worst path；
- 只能作为阶段 1A 的测量点，不建议作为最终结构。

### 7.2 方案 B：per-lane ctrl + per-lane payload capture slice

建议新增：

```text
core/hdec/rtl/hdec_p2_lane_slice.sv
```

每个 slice 包含：

- `p2_lane_ctrl_q`；
- 一个 `hdec_lane_4x64` instance；
- 本 lane 的 `lane_result_q[63:0]`；
- 本 lane 的 `lane_popcnt_q[6:0]`；
- 本 lane 的 `lane_clip_q[15:0]`；
- local one-hot vector result selection；
- local capture enable。

TOP 只接收四个 slice 的已注册输出：

```text
lane_vec64_q[lid]
lane_pop7_q[lid]
lane_clip16_q[lid]
```

P3 保持原语义：

- HBIND/HCNTADD/HPERM 读取 vec64；
- HSIM/HMATCH 读取 pop7；
- HCNTCLIP 读取 clip16。

capture 在 P2->P3 原有边界完成，因此：

- 不增加 pipeline stage；
- 不增加 cycles；
- payload register 数量理论上不变，只改变层级归属；
- control Q 和 capture D/CE 更接近同一 lane。

方案 B 更可能真正改善：

```text
control -> lane_popcnt_q
```

原因是 startpoint、popcount combinational cone 和 endpoint 都在同一 slice 内。推荐它作为最终目标。

不建议默认对整个 slice 使用 `KEEP_HIERARCHY` 或 `DONT_TOUCH`。先让 Vivado正常优化，再根据物理寄存器复制和 critical path 报告决定是否只保护 local ctrl register。

## 8. 预期资源和 timing 影响

完整 control struct 不含 `valid` 时为：

```text
5 do bits + 3 capture bits + 2 subgroup + 4 threshold + 4 perm = 18 bits/lane
```

四 lane 理论 local control storage：

```text
18 x 4 = 72 FF
```

实际净增加会低于或接近该值，取决于：

- 阶段 1C 删除 `use_*` 后综合能移除多少 uop control FF；
- `perm_nibble` 和其它参数是否仍在 uop/global register 中重复保存；
- Vivado 是否保留四份参数寄存器；
- 未使用字段是否被综合删除。

粗略目标：

| Metric | 预期 |
|---|---|
| FF | 比 `ec561b73` 增加约 30-80，允许以 FF 换 route |
| LUT | 应持平或下降；不能接受再次出现约 +329 LUT 的 encoded decode 开销 |
| LUTRAM | 不变 688 |
| BRAM/DSP | 保持 0 |
| shared control fanout | 明显下降，每 local control Q 只驱动一个 lane |
| route delay ratio | 目标低于 baseline 约 79.9% |
| WNS @150MHz | 目标优于 -0.312 ns |
| WNS @200MHz | 目标优于 -1.979 ns |
| Estimated Fmax | 目标高于约 143.3 MHz |

目标 critical path：

- 不再从 `FSM_onehot_st_q_reg[6]` 开始；
- 不再从 encoded `lane_ctrl.op` 开始；
- 不应跨越 shared four-lane control network；
- 若 endpoint 仍是 `lane_popcnt_q[lid]`，startpoint 应是同一 lane 的 local ctrl_q 或 local data cone，且 route delay/fanout必须下降；
- 更理想的是 worst path 移出 P2 control-to-capture cone。

## 9. 分阶段实现计划

推荐保留 1A/1B/1C 三个 OOC checkpoint，但每阶段必须是独立可回退实验，不能一次混合完成。

### 阶段 1A：per-lane one-hot ctrl_q 最小实验

目标：只验证 local register replication 是否降低共享 P2 control fanout。

计划修改范围：

- `core/hdec/rtl/hdec_pkg.sv`：增加 one-hot control type，不增加 enum；
- `core/hdec/rtl/hdec_top.sv`：增加 4 份 ctrl_q，在 P1/P2 和 P3/P2 边界装载；
- 暂不新增 payload slice；
- 暂不移动 payload registers；
- 暂时保留 `use_*` 作为 ctrl_q 装载源；
- P2 compute/capture 改为读取 `p2_lane_ctrl_q[lid]`；
- 不增加 stage/cycle。

第一刀建议只注册 5 个 `do_*` 和 3 个 `capture_*` bit，共约 32 FF。`subgroup/threshold/perm_nibble` 暂时保留现有路径，避免第一次 OOC 同时引入参数复制。

验收：

- 20/20 PASS；
- synthesized netlist 确实保留四份 local ctrl FF；
- local ctrl fanout 不跨四 lane；
- WNS/Fmax 至少不劣于 `ec561b73`；
- 若 local registers 被合并，先解决复制真实性再判断方案。

Go/no-go：

- 若 timing 改善或持平且 fanout 明显下降，进入 1B；
- 若 timing 明显恶化，先检查寄存器是否被合并、capture 是否仍被 shared FSM gating，不直接继续堆叠重构。

### 阶段 1B：per-lane P2 result slice

目标：把 local control、compute 和 split payload capture 放在同一结构边界。

计划修改范围：

- 新增 `core/hdec/rtl/hdec_p2_lane_slice.sv`；
- slice 内实例化 `hdec_lane_4x64`；
- slice 内保存 per-lane ctrl_q；
- slice 内保存 vec64/pop7/clip16 capture registers；
- `core/hdec/rtl/hdec_top.sv` 删除 TOP 对三个 payload register 的 sequential ownership；
- TOP P3 继续消费四组 slice registered output；
- `core/Flist.cva6` 加入新文件。

本阶段再评估是否把 subgroup/threshold/perm_nibble 复制进入每 lane ctrl_q。建议：

- popcount 路径不需要的参数不应进入 popcount capture cone；
- 参数只驱动对应 local compute block；
- 参数复制是否保留，以 fanout、FF 和 WNS 实测决定。

验收：

- 不新增 pipeline stage/cycle；
- P3 GLOBAL diff 只允许 payload source 层级变化，不改变行为；
- worst path 不再是 shared TOP control 到 TOP `lane_popcnt_q`；
- LUT 不出现 encoded 方案的显著增长。

### 阶段 1C：删除 use_* 和旧 TOP P2 控制

目标：在 timing 结构已经有效后做最终 cleanup。

计划：

- 从 `hdec_uop_t` 删除 5 个 `use_*`；
- 在 P1/P2 ctrl load 边界根据现有 `uop_p1_q.op_type` 预解码 one-hot bits；
- P3 直接回 P2 的 HCNTADD/HCNTCLIP 分支直接装载已知 one-hot bit 和新 subgroup；
- 删除旧 TOP `uop_lane_bool_valid/lane_cnt_valid/lane_shift_valid/lane_clip_valid`；
- 删除旧 TOP capture priority if/else；
- 不引入 `lane_op` 或 `capture_kind` enum；
- 不把三个 split payload 重新合并。

预解码 comparator 位于 local ctrl_q 之前。必须通过 timing report 确认新 worst path没有转移为：

```text
uop_p1_q.op_type -> p2_lane_ctrl_q
```

如果该路径成为瓶颈，可把 one-hot template 更早生成，但仍不能把 encoded op 带入 P2 local critical path。

### 阶段顺序判断

用户建议的 1A -> 1B -> 1C 顺序合理，原因是它能分离三个变量：

1. register replication；
2. capture locality；
3. control cleanup/predecode source。

不建议第一步直接同时完成 1A+1B+1C，否则 OOC 变好或变坏时无法判断是 register replication、slice hierarchy、use_* 删除还是参数复制造成。

## 10. 验证计划

### 10.1 功能验证

每阶段必须执行：

```text
make verilate NUM_JOBS=16
HDEC current 20/20 regression
git diff --check
```

必须确认：

- 不修改 `verif/hdec/*.S` 测试语义；
- benchmark cycle count 不增加；
- HBIND/HSIM/HMATCH/HCNTADD/HCNTCLIP/HPERM 结果不变；
- VADDR/VWR64/VRD64、HCLR/HCNTCLR 不变；
- P3 GLOBAL、VRF writeback、response 不变。

### 10.2 Assertion

仿真阶段建议检查：

```text
$onehot0({do_xor_only, do_popcount_diff, do_counter, do_clip, do_shift})
$onehot0({capture_vec, capture_pop, capture_clip})
```

并检查 operation/capture 配对：

- XOR/COUNTER/SHIFT 只能配 `capture_vec`；
- POPCOUNT_DIFF 只能配 `capture_pop`；
- CLIP 只能配 `capture_clip`；
- 非 P2 周期 local control 全零。

### 10.3 Vivado OOC

每阶段执行：

- Top: `hdec_top`
- Part: `xc7z020clg400-2`
- Mode: `synth_design -mode out_of_context`
- Clock sweep: 100 / 125 / 150 / 175 / 200 MHz

必须收集：

- WNS/TNS/failing endpoints；
- Fmax；
- LUT/Logic LUT/LUTRAM/FF/BRAM/DSP/CARRY；
- power；
- critical path startpoint/endpoint；
- route delay ratio；
- high fanout nets；
- control sets；
- local ctrl register 是否被合并；
- 每个 local ctrl Q 的实际 fanout。

### 10.4 公平对比

已有数据跨 Vivado 2022.2 和 2024.2，存在工具版本混杂。正式决策应在同一 Vivado 版本、同一脚本、同一机器设置下重新综合：

1. `ec561b73`；
2. `a010fdf9`；
3. 新 one-hot 阶段 1A；
4. 新 one-hot 阶段 1B；
5. 新 one-hot 阶段 1C。

三版本核心对比：

| 版本 | 控制结构 | capture 位置 | 已知结果/目标 |
|---|---|---|---|
| `ec561b73` | TOP FSM + `use_*` | TOP split registers | 当前有效 baseline，~143.3 MHz |
| `a010fdf9` | shared encoded `lane_ctrl.op/capture_kind` | TOP split registers | ~142.2 MHz，LUT +329，不作新 baseline |
| 新 one-hot 方案 | predecoded per-lane ctrl_q | 最终下沉到 per-lane slice | 目标降低 fanout 和 route delay |

## 11. 推荐结论

1. 建议从 `ec561b73` 对应的 `e0925738` 分支头开始新实验，当前计划分支选择正确。
2. 建议抛弃 `a010fdf9` 作为 timing baseline；它只保留为失败对照实验。
3. 第一刀应做 per-lane one-hot ctrl_q，不应做 shared one-hot ctrl_q。
4. 第一刀先只复制 8 个 operation/capture bit，保留 payload capture 在 TOP，形成最小 OOC checkpoint。
5. 只复制 control 不足以保证最终改善；如果 1A 证明 local FF 未被合并且 fanout下降，应继续把 payload capture 下沉到 `hdec_p2_lane_slice.sv`。
6. 最终方案建议同时拥有 per-lane ctrl register 和 per-lane split payload capture register。
7. 不应为了控制信号数量好看而重新编码；one-hot 增加少量 FF 是可接受的。
8. 在用户审查并批准本计划前，不执行任何 RTL 修改。
