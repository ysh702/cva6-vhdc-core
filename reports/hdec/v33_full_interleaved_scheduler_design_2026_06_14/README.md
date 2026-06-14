# V33 Full Same-Cycle Interleaved Scheduler Gap Analysis

Date: 2026-06-14

Branch: `hdec-ecc-pointmul-v33`

Base: V32-B accepted point, commit `a1addc1c`

## 1. V33 的目标定义

V33 的目标不是继续扩大 V32-B 的 local sidecar，而是完成用户定义的完整同周期流水线交织：

```text
HDC 作为前台主线持续运行；
ECC 作为后台 job 运行；
ECC 当前步骤需要某个共享资源时：
  如果 HDC 当前周期不用该资源，ECC 就推进；
  如果 HDC 当前周期正在用该资源，ECC 就等待；
ECC 当前步骤只用本地资源时：
  ECC 可以和 HDC 同周期推进。
```

这个定义比 V32-B 更强。V32-B 只完成了最后一类：ECC local diagonal compute 可以和 HDC 同周期推进。V33 要覆盖剩余共享资源类。

## 2. V32-B 已经完成了什么

V32-B 的保留结果：

| Version | Logic LUT | Slice LUT | LUTRAM | FF | WNS | Fmax |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| V30 baseline | 5838 | 6310 | 472 | 1800 | 0.247 ns | 210.393 MHz |
| V31 result-only dispatch | 5847 | 6319 | 472 | 1799 | 0.247 ns | 210.393 MHz |
| V32-B accepted | 5829 | 6301 | 472 | 1795 | 0.243 ns | 210.217 MHz |

V32-B 功能结果：

| Case | Result |
| --- | --- |
| single blocking PMUL | PASS, `PMUL_BLOCKING_WALL_CYCLES=401971` |
| background PMUL + foreground HDC loop | PASS, `PMUL_BG_HDC_LOOP_WALL_CYCLES=754622`, `HDC_ITERS=449` |

这说明三件事：

1. 单独 ECC PMUL 没有变慢。
2. HDC 前台可以大量推进。
3. ECC 的 local diagonal 阶段已经能在 HDC 前台运行时后台推进。

这一步已经给论文故事提供了第一块硬证据：ECC 不是只在 HDC 停下时运行，而是确实有一部分计算在 HDC 运行期间被隐藏。

## 3. 距离完整同周期调度还差多少

按照资源类型看，V33 还差四大类。

| Resource class | V32-B 状态 | V33 需要完成 |
| --- | --- | --- |
| ECC local diagonal | 已完成 same-cycle sidecar | 保持，不要破坏面积 |
| VRF read | 仍由主 FSM/coarse dispatch 独占推进 | HDC 不读 VRF 的周期允许 ECC 偷读 |
| VRF write | 仍由主 FSM/coarse dispatch 独占推进 | HDC 不写 VRF 的周期允许 ECC 写回 |
| HDC UOP/lane path | ECC add/xor 类操作仍走主 UOP 流水 | HDC 不占 lane/uop 时允许 ECC issue chunk |
| hspread/reduction/rowbuf | 仍走主 FSM | 只在确认无 rowbuf/shift/reduce 冲突后开放 |

如果用完成度估计：

- 调度故事的基础设施：约 50% 完成。
- 真正同周期执行能力：约 25% 完成。
- 完整资源级 opportunistic interleaving：约 30% 完成。
- 面积控制基础：已经完成，因为 V32-B 低于 V31。

所以 V33 不是“再补一个小状态”就能完成，而是要把 ECC 后台 job 从单纯 local sidecar 扩展成资源感知 micro-scheduler。

## 4. V33 不能走的路

V31/V32 的失败经验非常明确，V33 不能采用这些做法：

1. 不能做宽 resource mask 总线。
2. 不能把 ECC 调度条件挂进 `ready_o`。
3. 不能让 `S_RESULT` 直接组合跳大量 ECC 状态。
4. 不能复制第二套完整 ECC FSM。
5. 不能新增大规模 VRF read/write mux。
6. 不能靠“看起来更简单”的 flag encoding 替代 OOC 结果。

V32-B 已经证明：RTL 直觉经常输给 Vivado 映射。V33 每一步都必须以 OOC 数据决定保留或回退。

## 5. V33 推荐架构

V33 采用“三层调度”，而不是一个大仲裁器。

### Layer 0: V32-B local sidecar

继续保留：

- `ecc_diag_bg_state_q/n`
- `ecc_diag_issue_fire`
- `ecc_diag_flush_fire`
- `S_ECC_BG_DISPATCH` 统一启动 sidecar

这层不碰共享资源，是 V33 的面积锚点。

### Layer 1: Tiny Resource Class Predicates

新增极少数资源占用判断，宽度控制在 3 到 4 个 1-bit 信号：

| Signal | Meaning |
| --- | --- |
| `hdc_vrf_r_busy` | 当前 HDC 前台状态占用 VRF read |
| `hdc_vrf_w_busy` | 当前 HDC 前台状态占用 VRF write |
| `hdc_uop_busy` | 当前 HDC 前台状态占用 UOP/lane pipeline |
| `hdc_rowbuf_busy` | 当前 HDC 前台状态占用 rowbuf/shift/reduce 临时路径 |

这些信号必须只由 `st_q` 和已经存在的 pipeline valid bit 推导，不允许接入 `ready_o` 或 HDC 指令译码热路径。

### Layer 2: ECC Background Micro-Issue

ECC 后台不新增完整 FSM，只新增一个小型 micro-issue 入口：

| ECC micro class | Example states | Required resource |
| --- | --- | --- |
| `ECC_BG_LOCAL` | diagonal sidecar | none |
| `ECC_BG_VRF_R` | load A/B, leaf prefetch, scalar read, copy read | VRF read |
| `ECC_BG_VRF_W` | write pair, reduce write, const write, copy write | VRF write |
| `ECC_BG_UOP` | PMUL add/xor chunks through `S_UOP_*` | UOP/lane |
| `ECC_BG_ROWBUF` | hspread/reduce load and temporary rowbuf use | rowbuf/shift/reduce |

V33 的关键不是把所有 ECC 状态复制一遍，而是让 `S_ECC_BG_DISPATCH` 根据当前 ECC phase 产生一个 micro class，然后只在对应 HDC resource free 时推进一步。

## 6. 最小新增信号建议

V33 第一版建议新增这些信号，避免面积失控：

| Signal | Width | Reason |
| --- | ---: | --- |
| `ecc_bg_wait_res_q/n` | 3 | 记录后台 ECC 正在等哪类资源 |
| `ecc_bg_resume_q/n` | 3-4 | 记录资源拿到后恢复到哪个小入口 |
| `hdc_vrf_r_busy` | 1 | VRF read 冲突判断 |
| `hdc_vrf_w_busy` | 1 | VRF write 冲突判断 |
| `hdc_uop_busy` | 1 | UOP/lane 冲突判断 |
| `hdc_rowbuf_busy` | 1 | rowbuf/reduce 冲突判断 |

暂时不要新增：

- 第二套 `vrf_req` 结构体；
- 256-bit ECC write shadow buffer；
- per-state full resource mask ROM；
- profile counters；
- debug status output。

如果必须选择，优先新增窄状态，不新增宽数据 mux。

## 7. V33 实施顺序

### V33-A: 精确测量基准

先新增一个 V33 专用 testbench，测同一套 `run_hdc_foreground_flow()` 的 standalone 周期。

原因：V32-B 已经证明 raw wall time 本身不能说明好坏，必须按用户定义比较：

```text
standalone PMUL cycles + N * standalone HDC full-flow cycles
vs.
interleaved PMUL+HDC wall cycles for the same N HDC iterations
```

V33-A 不改 RTL，只把基准测准。

### V33-B: VRF read bubble stealing

优先做 VRF read，因为它比 VRF write 风险小：

- ECC load A/B 需要 VRF read；
- leaf fold 里部分 cycle 需要预取下一个 leaf；
- scalar read 也需要 VRF read；
- 如果 HDC 当前状态不读 VRF，ECC 可以发一个 read address。

目标：不新增第二个 VRF port，只在 HDC 不用 read port 时使用现有 port。

成功标准：

- Logic LUT 不高于 V32-B 的 5829 太多，最好仍低于 V31 的 5847。
- 单独 PMUL 仍为 401971 cycles。
- background wall 不应出现无意义等待。

### V33-C: VRF write bubble stealing

VRF write 比 read 更危险，因为写数据宽、bank enable 宽，容易新增 mux。

可先只开放小范围：

- ECC const write；
- ECC copy write；
- ECC reduce write；
- ECC write pair。

如果宽写 mux 导致 LUT 上涨，V33-C 必须回退，不能为了“完整”牺牲面积故事。

### V33-D: UOP/lane opportunistic issue

ECC PMUL 中点加/点倍会使用 `UOP_HBIND_CHUNK` 这类 lane/uop 路径。V33-D 的目标是：

- HDC 不在 `S_UOP_*` pipeline 时，ECC 可以 issue 一个 UOP chunk；
- HDC 正在 UOP pipeline 中时，ECC 等待；
- 不复制 lane pipeline 寄存器。

这一步是完整故事里最重要但也最危险的一步。它可能比 VRF stealing 更容易涨 LUT，因为涉及 `uop_p0/p1/p2/p3` 多级寄存器。

### V33-E: rowbuf / hspread / reduction opportunistic issue

最后做 rowbuf/reduction，因为它和 HDC 的 `hdc_src0_q`、`lane_result_q`、hspread path 耦合更强。

建议先只做保守版本：

- 当 HDC 完全不在 rowbuf/shift/reduce 相关状态时，ECC 才推进；
- 不与 HDC 同时改 `hdc_src0_q`；
- 不新增第二套 row buffer。

如果这一步面积明显上涨，可以把它留作 coarse dispatch，并在论文中说明 rowbuf/reduction 是共享资源冲突区，V33 完整调度重点覆盖 local/VRF/UOP 三类主要空隙。

## 8. 完整功能的验收标准

V33 如果要宣称“全部功能完成”，至少要满足：

| Check | Requirement |
| --- | --- |
| Standalone ECC | PMUL cycles 不高于 V32-B，功能 PASS |
| Standalone HDC | full-flow PASS，周期基准固定 |
| Interleaved HDC+ECC | HDC foreground loop PASS，ECC result PASS |
| Resource rule | HDC 用某资源时 ECC 不推进对应 micro class |
| Local sidecar | diagonal local 仍可同周期推进 |
| Area | Logic LUT 尽量保持低于 V31；若超过必须解释收益 |
| Timing | 200 MHz PASS |

V33 不能只看 interleaved wall time。真正该报告的是：

```text
N = ECC 完成前 HDC 完成的 full-flow 次数
standalone_total = PMUL_blocking + N * HDC_full_flow
interleaved_total = measured_wall
saved_cycles = standalone_total - interleaved_total
```

这才和用户定义的故事一致。

## 9. 当前判断

V33 要完成全部功能是可行的，但不能一口气写一个大仲裁器。最佳路线是：

1. 先固定比较口径和 standalone HDC full-flow 周期。
2. 保留 V32-B local sidecar 和低面积结果。
3. 先做 VRF read stealing。
4. 再做 VRF write stealing。
5. 再做 UOP/lane stealing。
6. 最后评估 rowbuf/reduction 是否值得同周期化。

如果 V33 全部成功，最终故事可以升级成：

> HDEC does not merely reuse hardware spatially. It converts ECC scalar multiplication into a background job composed of local, VRF, UOP, and row-buffer micro-classes. HDC remains the foreground pipeline, while ECC opportunistically advances each micro-class only when the corresponding HDC resource is idle. This provides both area sharing and same-cycle temporal interleaving.

中文讲法就是：

> 我们不是简单把 ECC 塞进 HDC 旁边，而是把 ECC 点乘拆成资源类型明确的后台微任务。HDC 是前台流水线，ECC 根据当前微任务所需资源，在 HDC 没占用对应资源的周期推进；如果 HDC 占用，ECC 等待。V32-B 已经完成本地计算类微任务，V33 要把 VRF、UOP/lane、rowbuf/reduction 这几类共享资源也接入这个规则。

这是完整同周期流水线交织调度的清晰版本。
