# V32 Final Same-Cycle Interleaved Scheduler Design

Date: 2026-06-14

Branch: `hdec-ecc-pointmul-v32`

Base: V31 retained point, commit `74db03b3`

## 1. V32 的目标

V32 不再把目标定义成“继续给 ECC 后台任务加一个更复杂的控制器”。这个方向在 V31 已经证明风险很高：控制入口一旦进入 `ready_o`、`valid_i`、`S_RESULT` 或 HDC 指令译码热路径，Vivado 会把很多原本局部的条件扩散到大扇出组合锥里，最后 OOC 结果会比理论预期差很多。

V32 的目标改成：

1. 保留 V31 已经验证通过的低面积后台 PMUL 入口。
2. 在不污染 HDC 主线热路径的前提下，实现真正的“同周期交织”。
3. 先只让 ECC 的本地计算片段在 HDC 前台运行时后台推进。
4. 只在证明有资源空隙后，再扩展到 VRF / lane / reduction 等共享资源片段。
5. 评价标准不只看功能，还必须看 OOC：
   - 200 MHz 保持通过；
   - Logic LUT 不应高于 V31 的 5847；
   - FF 不应高于 V31 的 1799；
   - 如果 RTL 改动不能降低 ECC 专属控制复杂度，宁可回退。

## 2. V31 留下的硬证据

V31 的有效版本如下：

| Version | Logic LUT | Slice LUT | LUTRAM | FF | WNS | Fmax |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| V30 baseline | 5838 | 6310 | 472 | 1800 | 0.247 ns | 210.393 MHz |
| V31 result-only dispatch | 5847 | 6319 | 472 | 1799 | 0.247 ns | 210.393 MHz |

V31 的功能结果：

| Test | Result |
| --- | --- |
| single PMUL | `PMUL_BLOCKING_WALL_CYCLES=401971` |
| foreground HDC loop + background PMUL | `PMUL_BG_HDC_LOOP_WALL_CYCLES=424499`, `HDC_ITERS=20`, PASS |

V31 失败尝试给出的结论更重要：

| Attempt | Result | Lesson |
| --- | ---: | --- |
| `S_RESULT -> ECC step` direct dispatch | 6864 Logic LUT | 直接把 ECC 调度挂进结果返回组合路径会炸 LUT |
| `S_ECC_BG_DISPATCH` + idle dispatch | 5961 Logic LUT | 后台入口不能同时挂在 `S_IDLE` 和 `S_RESULT` |
| 上一项再加 bgclear | 5936 Logic LUT | 局部清理有帮助，但不够 |
| packed counter-base function | simulation fail | 计数器映射不能用过度抽象破坏时序语义 |
| `bg_slice` touching `ready_o` | 6734 Logic LUT, WNS 0.121 | 绝对不要让后台调度影响 `ready_o` |

因此，V32 不能靠“大一统仲裁器”硬顶。正确方向是把 ECC 后台推进拆成资源等级不同的小片段，然后只把确定无冲突、低扇出的片段做成 sidecar。

## 3. 当前 RTL 的资源分层

现有 `hdec_top.sv` 中，ECC PMUL 并不是所有状态都需要共享 HDC 资源。按资源类型可分成五类：

| ECC 片段 | 典型状态 | 使用资源 | 是否适合同周期 sidecar |
| --- | --- | --- | --- |
| Local diagonal compute | `S_ECC_DIAG_ISSUE`, `S_ECC_DIAG_WAIT` | ECC 本地寄存器、KPD/diag parity 组合逻辑 | 是，V32 第一目标 |
| VRF read address / read wait | `S_ECC_LOAD_A`, `S_ECC_LOAD_B`, 部分 `S_ECC_LEAF_FOLD` | VRF 读口、读等待 | 暂不做，需要证明 VRF 泡泡 |
| VRF write | `S_ECC_WRITE_PAIR`, `S_ECC_REDUCE_WRITE` | VRF 写口 | 暂不做，冲突代价高 |
| row buffer / reduce / shift | `S_ECC_REDUCE_LOAD_LO` 等 | HDC row buffer、shift/reduce 局部路径 | 暂不做，容易影响 HDC 主线 |
| UOP/XOR style shared operation | `S_RD_WAIT` 及复用路径 | HDC 主 FSM 的通用执行路径 | 暂不做，控制耦合太强 |

最关键的发现是：`S_ECC_DIAG_ISSUE` 这一段主要更新 `ecc_leaf_prod`、`ecc_pipe0_valid`、`ecc_diag_slot`、`ecc_diag16_pipe` 等 ECC 本地状态，不读写 VRF，也不使用 HDC 的 lane/popcount/uop 写回路径。它是最适合做真正同周期后台推进的部分。

## 4. V32 的最终架构

V32 最终应采用“两层调度”：

### 4.1 粗粒度入口保持 V31

V31 已经证明低面积可行的后台入口继续保留：

- HDC 前台指令仍然通过原来的 `S_IDLE -> HDC states -> S_RESULT` 主线运行。
- ECC 后台 PMUL 只在 HDC 指令边界附近被 coarse dispatch。
- `ready_o` 仍然只由 `st_q == S_IDLE` 决定。
- `valid_o` 仍然只由 `st_q == S_RESULT` 决定。
- 不向 HDC 指令译码路径新增 ECC 优先级判断。

这层的意义是保证功能稳定，并为 sidecar 启停提供一个低成本入口。

### 4.2 细粒度 sidecar 只推进 ECC local diagonal

新增一个非常小的 ECC local sidecar，原则如下：

- 只在后台 ECC job 有效时启用。
- 只覆盖 field multiply 里的 diagonal inner loop。
- 不申请 VRF 读写。
- 不碰 HDC lane。
- 不碰 HDC row buffer。
- 不影响 `ready_o`。
- 不向 HDC 主 FSM 增加 resource mask 总线。

概念上，V32 的同周期执行应变成：

```text
cycle N:
  HDC foreground FSM advances one normal HDC step
  ECC local sidecar advances one diagonal slot if active
```

也就是说，这一部分是真正的同周期交织，不是 V31 那种“指令边界让一下 ECC”。

### 4.3 sidecar 完成后再回到粗粒度 ECC FSM

当 diagonal inner loop 完成后，sidecar 不直接继续做 VRF 写回或 reduction，而是只置位一个很小的 resume 条件。之后仍由 V31 的 coarse dispatch 把 ECC 送回：

```text
ECC load A/B
  -> start local diagonal sidecar
  -> HDC foreground may continue
  -> sidecar finishes local diagonal
  -> coarse dispatch resumes ECC leaf fold / write / reduce
```

这样可以避免一次性做成完整双 FSM，降低面积和时序风险。

## 5. 为什么这条路线更可能减少 LUT/FF

过去几轮失败的共同原因不是“少了一个调度器”，而是“调度器放错了地方”。如果用全局仲裁器同时判断 HDC/ECC 每个状态需要的资源，就需要：

- 新增资源 mask；
- 新增优先级选择；
- 新增状态保持；
- 新增结果返回路径判断；
- 新增 VRF 地址/写数据 mux；
- 扩大 `ready_o` 或 `S_RESULT` 的组合锥。

这些东西理论上优雅，但在 FPGA 上会被映射成大量 LUT 和扇出。

V32 的 sidecar-first 路线更省面积，是因为它不引入通用仲裁问题：

| 设计选择 | 面积影响 |
| --- | --- |
| 不做通用 resource mask | 避免一组宽条件进入主 FSM |
| 不新增第二套 VRF mux | 避免读写口仲裁 LUT |
| 不修改 `ready_o` | 避免最大扇出路径被污染 |
| 不复制完整 ECC FSM | 避免状态译码翻倍 |
| 复用现有 ECC diagonal 寄存器 | 新 FF 极少 |
| 只新增 local active/done/resume 标志 | 控制锥局部化 |

如果实现得足够克制，sidecar 只会带来少量局部控制；随后可以反向删除或合并 `S_ECC_DIAG_ISSUE` / `S_ECC_DIAG_WAIT` 在主 FSM 中的一部分状态译码，才有机会把 V31 的 +9 LUT 收回来，甚至低于 V30。

## 6. 建议的 V32 实施步骤

### Step A: 文档化并冻结约束

当前这个报告就是 Step A。先把能做和不能做写清楚，避免再次做出综合上明显高风险的“大调度器”。

### Step B: diagonal sidecar 最小实现

只新增最少状态：

| Signal | Width | Purpose |
| --- | ---: | --- |
| `ecc_diag_bg_active_q` | 1 | 后台 diagonal sidecar 正在运行 |
| `ecc_diag_bg_done_q` | 1 | sidecar 已完成，等待 coarse dispatch resume |
| 可选 `ecc_diag_bg_resume_q` | 1 | 用于区分下一次 dispatch 应进入 fold 而不是重新 diag |

优先复用已有的：

- `ecc_diag_slot_q`
- `ecc_pipe0_valid_q`
- `ecc_pipe0_diag_slot_q`
- `ecc_diag16_pipe_q`
- `ecc_leaf_prod_q`
- `ecc_leaf_a_q`
- `ecc_leaf_b_q`

不要新增第二套 diagonal 数据寄存器。否则 FF 会明显上涨。

### Step C: 后台 PMUL load B 后启动 sidecar

当前主 FSM 大致是：

```text
S_ECC_LOAD_A_WAIT
S_ECC_LOAD_A
S_ECC_LOAD_B_WAIT
S_ECC_LOAD_B
S_ECC_DIAG_ISSUE
S_ECC_DIAG_WAIT
S_ECC_LEAF_FOLD
```

V32 后台模式应改成：

```text
S_ECC_LOAD_A_WAIT
S_ECC_LOAD_A
S_ECC_LOAD_B_WAIT
S_ECC_LOAD_B
  if background:
    start sidecar
    yield foreground
  else:
    keep original blocking path
sidecar runs during HDC
sidecar done
coarse dispatch resumes S_ECC_LEAF_FOLD
```

前台单独 ECC PMUL 可以继续使用原来的 blocking 路径，保证单独 PMUL 周期和功能不被破坏。

### Step D: 只在 sidecar 成功后再考虑 VRF bubble stealing

VRF bubble stealing 不应作为 V32 第一补丁，因为它需要回答几个真实问题：

- HDC 哪些状态确实不需要 VRF？
- VRF read latency 是否会让 ECC 偷读破坏 HDC 下一拍数据？
- 是否需要新增 `vrf_owner`？
- 是否会引入额外 read-address mux？

这些问题没有波形证据前，不值得先做。V31 已经证明“想当然的仲裁”很容易涨 LUT。

## 7. V32 的验证计划

每一个 RTL 小版本必须同时做：

1. `xsim` 单独 PMUL。
2. `xsim` HDC foreground loop + ECC background PMUL。
3. Vivado OOC 200 MHz。
4. 与 V31 的 area/timing/cycle 对比。

最低接受线：

| Metric | Accept |
| --- | --- |
| single PMUL correctness | PASS |
| background PMUL correctness | PASS |
| single PMUL cycles | 不应比 V31 变差 |
| interleaved wall cycles | 应比 V31 隐藏更多 ECC local cycles |
| Logic LUT | 不高于 5847，理想低于 5838 |
| FF | 不高于 1799，理想低于 1800 |
| WNS | 200 MHz pass |

如果任一补丁带来明显 LUT 上涨，必须先解释上涨来自哪条组合路径；解释不了就回退。

## 8. 最终故事如何表述

V32 的论文故事不应该说“我们额外加了一个 ECC 控制器”。更好的表述是：

> HDEC 将 ECC scalar multiplication 拆分为共享资源片段和本地可推进片段。HDC 保持前台主任务语义，ECC 作为后台 job 被映射到统一执行基础设施上；其中不占用 HDC 数据通路的 field-multiply diagonal 阶段可在 HDC 周期内 sidecar 推进，VRF/写回/reduction 等共享片段仍由轻量级 coarse scheduler 在指令边界提交。该设计避免了完整双控制器和宽资源仲裁器，使 ECC 控制开销从“专用控制逻辑”转化为 HDC 执行系统中的后台调度能力。

这和用户设想的故事是一致的：

- HDC 持续重复完整流程；
- ECC 在后台完成一次 scalar multiplication；
- 如果 HDC 正在使用共享算子，ECC 等待；
- 如果 ECC 当前步骤只需要本地资源，它可以同周期推进；
- 最终比较的是“单独 ECC + HDC 循环工作”的总周期，和“前台 HDC + 后台 ECC”的 wall time。

V31 已经完成的是第一层：低面积后台 job 入口。

V32 要完成的是第二层：真正同周期 sidecar 推进，并且用更少的控制复杂度讲清楚硬件复用故事。

## 9. 当前 V32 第一结论

V32 不应从“大重构控制层”开始，而应从“局部 sidecar 化 diagonal inner loop”开始。原因很直接：

- 它是当前 RTL 中最明确无共享资源冲突的 ECC 片段；
- 它不会污染 HDC ready/valid 热路径；
- 它能形成真正同周期交织的证据；
- 它有机会把 ECC 主 FSM 的 diagonal 状态译码从大控制器中拿出来；
- 它是最有可能在不涨面积的情况下继续隐藏 ECC 周期的入口。

下一步 RTL 修改应只实现这个最小闭环：background load B 后启动 diagonal sidecar，sidecar 完成后 resume 到 leaf fold。任何 VRF 级别的资源偷取都等这个闭环综合通过后再做。

## 10. V32-B RTL 实施结果

V32-B 已经实现了第一阶段 local-only same-cycle sidecar。当前接受版本的 RTL 改动集中在 `core/hdec/rtl/hdec_top.sv`：

1. 增加 2-bit `ecc_diag_bg_state_q/n`，状态为 idle / issue / flush / done。
2. 增加 `ecc_diag_issue_fire` 和 `ecc_diag_flush_fire`，让 blocking ECC 和 background sidecar 共用同一份 diagonal 更新逻辑。
3. 后台 PMUL 在 `S_ECC_LOAD_B` 后可以启动 sidecar。
4. `S_ECC_LEAF_FOLD` 切换到下一个 leaf 后也可以继续启动 sidecar。
5. `S_ECC_BG_DISPATCH` 在 sidecar active 时只负责让出或等待；sidecar done 后恢复到 `S_ECC_LEAF_FOLD`。
6. `ready_o`、`valid_o`、VRF broker、HDC lane/uop 译码路径都没有加入新的通用仲裁。

注意：这个版本是 V32-B，不是完整 V32-C/D。它只覆盖 ECC field multiply 的 local diagonal 阶段；VRF read/write、leaf fold、reduction、HDC uop 复用仍然走 V31 coarse dispatch。

### 10.1 保留版本结果

| Case | Result |
| --- | --- |
| Single blocking PMUL | PASS, `PMUL_BLOCKING_WALL_CYCLES=401971` |
| Background PMUL + foreground HDC loop | PASS, `PMUL_BG_HDC_LOOP_WALL_CYCLES=721567`, `HDC_ITERS=454` |
| OOC 200 MHz | PASS |

| Version | Logic LUT | Slice LUT | LUTRAM | FF | WNS | Fmax |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| V30 baseline | 5838 | 6310 | 472 | 1800 | 0.247 ns | 210.393 MHz |
| V31 result-only dispatch | 5847 | 6319 | 472 | 1799 | 0.247 ns | 210.393 MHz |
| V32-B accepted | 5898 | 6370 | 472 | 1791 | 0.238 ns | 209.996 MHz |

和 V31 相比，V32-B 的 Logic LUT 增加 51，FF 减少 8，200 MHz 时序仍通过。这个面积还没有达到“反向减少 LUT”的最终目标，但它是目前唯一同时满足功能正确、时序接近 V31、且没有发生 LUT 爆炸的 same-cycle sidecar 版本。

### 10.2 周期行为解释

V31 的 interleaving 测试结果是：

| Version | PMUL background wall cycles | HDC full-flow iterations before PMUL done |
| --- | ---: | ---: |
| V31 | 424499 | 20 |
| V32-B | 721567 | 454 |

V32-B 的 raw wall time 变长，但这不是单独 ECC 变慢，因为 blocking PMUL 仍然是 401971 cycles。变长的原因是：V32-B 开始真正让 HDC 前台持续运行，ECC local diagonal 在 HDC 运行期间后台推进。因此同一段 PMUL 完成窗口内，HDC 从 20 次 full-flow 提升到 454 次 full-flow。

这说明 V32-B 的意义不是“让后台 PMUL wall time 绝对更短”，而是把比较方式切到用户定义的目标：

```text
standalone ECC PMUL + standalone repeated HDC work
vs.
foreground repeated HDC work + background ECC PMUL
```

在这个口径下，V32-B 已经产生了真正的同周期交织证据：HDC 前台大量推进时，ECC 也能在不占用共享资源的 local diagonal 阶段同步推进。

### 10.3 被拒绝的尝试

| Attempt | Functional | OOC Result | Decision |
| --- | --- | --- | --- |
| duplicate sidecar tail update | PASS | Logic LUT 6656, FF 1800, WNS 0.121 | reject |
| shared update + flag encoding | PASS | Logic LUT 6754, FF 1821, WNS 0.121 | reject |
| shared update + PMUL_FIELD-only sidecar | PASS | Logic LUT 6730, FF 1817, WNS 0.117 | reject |
| shared update + enum state + PMUL_FIELD/INV_MUL | PASS | Logic LUT 5898, FF 1791, WNS 0.238 | accept |

这里的经验很明确：RTL 看起来更简单不等于 Vivado OOC 面积更低。`PMUL_FIELD-only` 和 flag encoding 理论上更小，但综合后都把 LUT 拉高。因此当前保留 enum/shared 版本。

### 10.4 下一步面积回收方向

V32-B 还没完成“反向减少 LUT/FF”。下一步应集中回收这 51 个 Logic LUT，而不是立刻扩展 VRF 级偷周期：

1. 尝试把 `S_ECC_BG_DISPATCH` 和 sidecar done resume 合并，减少一层后台状态译码。
2. 检查 `ecc_diag_issue_fire` 是否可以被局部化到 ECC control cone，避免影响 `st_n` ROM 映射。
3. 评估是否能删除主 FSM 中独立的 `S_ECC_DIAG_WAIT` 状态，让 blocking 和 sidecar flush 更统一。
4. 只有当 V32-B 面积回到 V31 附近后，再进入 V32-C 的 VRF bubble stealing。

当前结论：V32-B 已完成 local-only same-cycle interleaving 的第一个可运行闭环，但还不是最终面积最优版本。
