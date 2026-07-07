# VV15 low-area cycle recovery plan

Date: 2026-07-08

Branch/worktree: `VV15`, `E:/HDEC/cva6-vhdc-core/tmp/hdec_vv15_finite_template_worktree`

## 0. 结论先行

VV15 下一步不应该沿着“加倍 diagonal group / 加第二套 folding / 加第二个 accumulator”的方向走。端侧小面积 ECC 文献里的主线非常一致：真正可持续的低面积提速来自资源约束下的调度、流水、旁路、固定数据变换和避免空转，而不是简单复制算术单元。

映射到我们当前 RTL，最值得做的是：

1. 把 `S_ECC_LEAF_FOLD` 从显式 drain 变成下一次 diagonal capture 期间的固定模板折叠。
2. 把 `S_ECC_WRITE_PAIR` / `S_ECC_WRITE_DRAIN` 里的等待和 VRF 读写间隙压掉，用 pending-write bypass 和同一 XOR0 packet 继续复用。
3. 在 point-add / point-double 调度层做 resource-constrained DFG compaction，把 XOR-only add、load、fold、writeback 尽量放到 bit-matrix 或 leaf-fold 的影子周期里。

这三步都坚持同一个底线：不新增独立 ECC 乘法器、不新增第二套大 folding 网络、不破坏 HDC/ECC 统一 bit-matrix 数据结构和 XOR0 accumulator 故事。

## 1. 文献读到的关键模式

### 1.1 Khan and Benaissa, TCAS-II 2015

Paper: `Throughput/Area-efficient ECC Processor Using Montgomery Point Multiplication on FPGA`

URL: https://eprints.whiterose.ac.uk/id/eprint/92952/9/WRRO_92952.pdf

这篇是当前最贴近我们的低面积/高吞吐路线之一。它的贡献不是简单加很多乘法器，而是：

- segmented-pipelined digit-serial multiplier；
- combined point-add / point-double algorithm；
- compact distributed-RAM memory unit；
- careful scheduling，减少 arithmetic logic block idle cycle；
- 在实现层做 timing constraint 和 logic-level modification。

它的启发是：低面积 ECC 的关键不是“每一层都最大并行”，而是让少量算术资源被连续喂满。对 VV15 来说，对应的不是 double diagonal lane，而是让 leaf-fold、writeback、next-load 与已有 bit-matrix product 交错。

### 1.2 Southampton hardware ECC survey

Paper: `A Survey of Hardware Implementations of Elliptic Curve Cryptographic Systems`

URL: https://eprints.soton.ac.uk/398632/1/Final.pdf

这篇 survey 把二进制域 coprocessor 的取舍讲得很清楚：

- ECC performance 由底层 finite-field arithmetic 决定；
- ECPM 是比较 ECC 实现的核心指标；
- Khan/Benaissa 的低面积高吞吐来自 optimized memory unit、pipelined digit-serial multiplier、careful scheduling and avoiding idle cycles；
- Karatsuba/bit-parallel pipeline 可以带来约 2x 速度，但资源可能涨到约 5x。

对 VV15 的警告是：如果我们为了减少 capture 周期去复制 diagonal AND/parity 面，很容易走到 survey 里“速度更快但资源暴涨”的路线。这与 `<4700 Logic LUT` 和 HDC/ECC 复用故事相冲突。

### 1.3 Zode and Deshmukh, JPDC 2022

Paper: `Optimization of elliptic curve scalar multiplication using constraint based scheduling`

URL: https://www.sciencedirect.com/science/article/abs/pii/S0743731522001216

这篇的关键词是 constraint-based scheduling：

- 修改 point addition / point doubling 的 DFG；
- 对 field multiplication 施加资源约束；
- 通过重新排序 critical path 与 multiplier utilization，优化 area-delay product；
- 报告 area reduction 41.21%，delay reduction 2.4%，ADP 改善。

它对 VV15 很重要，因为它说明“周期下降”不一定来自增加乘法器，也可以来自约束单一重资源后的 DFG 重排。我们现在的重资源不是传统 multiplier，而是共享 bit-matrix + XOR0 + VRF 读写时序，所以要做的是 HDC/ECC 共享资源约束下的 micro-scheduler。

### 1.4 Sutter, Deschamps and Imana, TIE 2013

Paper: `Efficient Elliptic Curve Point Multiplication Using Digit-Serial Binary Field Operations`

URL: https://www.academia.edu/4183009/Efficient_Elliptic_Curve_Point_Multiplication_Using_Digit_Serial_Binary_Field_Operations

这篇从 digit-serial computation 的粒度探索提速点：

- 在 GF multiplication 和 division datapath 上探索不同 digit-serial levels；
- 寻找 optimal digit size；
- 也提到 out-of-order execution、data forwarding、deep pipeline、instruction-level parallelism 这类处理器式技术在 ECC datapath 中的使用。

对 VV15 的启发是：我们不一定要把 group 并行度翻倍，而是可以找适合 HDEC RTL 的“有效 digit”：例如 `sub-boundary lookahead` 已经证明小调度能降周期且不增面积；下一步应寻找 `leaf-fold word`、`write-pair lane`、`pending packet` 这种更适合本设计的调度粒度。

### 1.5 Power/area efficient ECC for resource-constrained devices, Electronics 2023

Paper: `Power/Area-Efficient ECC Processor Implementation for Resource-Constrained Devices`

URL: https://www.mdpi.com/2079-9292/12/19/4110

这篇用 Bivariate Polynomial Basis + modified Radix-n Interleaved Multiplication 做低面积/低功耗，同时强调：

- LD-Montgomery point multiplication algorithm 被调整以改善 scheduling；
- finite-field operations are built in parallel with the finite-field multiplier；
- area 通过 resource reuse 降低；
- clock gating / asynchronous counter 面向功耗。

对 VV15 的映射是：不要在 bit-matrix 旁边再造 ECC folding 大单元，而应把 folding/write/load 放进 shared path 的空隙。`folding in parallel with product` 必须是轻模板，而不是 VV14-1 那种宽动态 mux。

### 1.6 RFID tag ECC processor, PMC 2014

Paper: `Design of an Elliptic Curve Cryptography Processor for RFID Tag Chips`

URL: https://pmc.ncbi.nlm.nih.gov/articles/PMC4239904/

这篇端侧设计的价值在于它关注了寄存器和控制复杂度：

- 新 inversion algorithm 用更少寄存器；
- coordinate swapping 方法降低 controller complexity，并缩短 iterative calculation；
- circular shift register 降低 register-file area；
- clock gating 和 asynchronous counter 降功耗。

对 VV15 的启发是：我们的 `WRITE_PAIR` 和 VRF 读写调度也可能是“控制/寄存器组织”的周期源，不应该只盯乘法主体。低面积下，旁路和寄存器复用往往比再加运算单元更值得。

### 1.7 Area-sensitive GF(2^233) Booth multiplier designs, 2023/2024

Papers:

- `Area-Efficient Realization of Binary Elliptic Curve Point Multiplication Processor for Cryptographic Applications`
  URL: https://www.mdpi.com/2076-3417/13/12/7018
- `FPGA Implementation of Elliptic-Curve Point Multiplication Over GF(2^233) Using Booth Polynomial Multiplier for Area-Sensitive Applications`
  URL: https://pureadmin.qub.ac.uk/ws/portalfiles/portal/628046952/FPGA_Implementation_of_Elliptic-Curve_Point_Multiplication_Over_GF2233_Using_Booth_Polynomial_Multiplier_for_Area-Sensitive_Applications.pdf

这类工作通常使用 iterative bit-serial / Booth polynomial multiplier，并且复用一个 adder、multiplier、square block，把 inversion 建在已有 multiplier/square 上。它们面积低，但周期成本较高。

对 VV15 的启发是“复用单元”和“pipeline register placement”，不是照搬 bit-serial Booth。我们的 bit-matrix 本身就是共享低面积底座，下一步要让线性 folding 和写回也成为这个底座上的固定 schedule，而不是另起 ECC 独立单元。

### 1.8 Kumar constrained-device dissertation

Work: `Elliptic Curve Cryptography for Constrained Devices`

URL: https://informatik.rub.de/wp-content/uploads/2021/11/kumar_diss.pdf

这篇从 constrained devices 角度给出几条非常有用的设计思想：

- 低端处理器上少量硬件扩展可显著加速 multiplication，同时降低 code-size/data-RAM；
- binary-field digit-serial multiplier 的 digit-size 选择非常关键；
- DAM/NAM accumulator 结构比传统 LSD multiplier 更快；
- 某些 field arithmetic 可以转成 bitwise rotation / wiring 这类低成本操作；
- 极小面积 ECC 也能通过 addition chain、fast squarer、temporary variable 优化获得可用性能。

对 VV15 的启发是：在 GF(2) 里，“移位、重连线、固定 XOR 模板”比“动态通用函数”更像端侧低面积设计。我们应把 VV14-1 的 direct dynamic folding 转成 fixed template folding。

## 2. VV15 当前周期占比

当前可接受 checkpoint：

- `PMUL_PROFILE_WALL_CYCLES = 339100`
- `Logic LUT = 4655`
- `FF = 1422`
- `Fmax = 207.297 MHz`
- `BRAM = 4`
- `DSP = 0`

按 state profile 拆开：

| Region | Cycles | Wall-cycle share | 判断 |
|---|---:|---:|---|
| `S_ECC_LEAF_FOLD` | 256608 | 75.67% | 第一优先级。它既大，又是 GF(2) linear transform，最适合用固定模板和调度重叠消除。 |
| `S_ECC_WRITE_PAIR` | 42768 | 12.61% | 第二优先级。不是核心乘法，适合用 pending-write bypass / write-load overlap 压缩。 |
| `S_ECC_DIAG` | 11880 | 3.50% | 不是现在最值得用面积攻击的点。复制 diagonal lane 代价大、收益小。 |
| `S_ECC_UOP` | 4242 | 1.25% | 可在 DFG compaction 中顺手压，但不是第一阶段。 |
| `S_ECC_LOAD` | 3564 | 1.05% | 可与 write/fold shadow overlap。 |
| `S_ECC_REDUCE` | 2821 | 0.83% | 保持正确性即可，不优先。 |
| `S_ECC_WRITE_DRAIN` | 1188 | 0.35% | 小，但可随 write-pair bypass 一起消掉。 |

按 PMUL phase 拆开：

| Phase | Cycles | Share | 判断 |
|---|---:|---:|---|
| `PMUL_FIELD` | 321308 | 94.75% | 真正大头。优化必须围绕 field op 的内部 schedule，而不是 scalar 顶层花样。 |
| `PMUL_ADD` | 5656 | 1.67% | 可调度压缩，但不能寄希望单独优化它带来质变。 |
| `PMUL_COPY` | 705 | 0.21% | 小。 |
| `INV_MUL + INV_SQR` | 3629 | 1.07% | inversion 不是当前瓶颈，不应优先重写 inversion。 |

关键判断：

不是“谁最大就直接优化谁”，而是要看能不能低面积优化。`S_ECC_LEAF_FOLD` 同时满足“大”和“可低面积重叠”：它是线性 folding，不需要新增 AND 面；它可以被固定模板化；它可以在下一 leaf/sub 的 diagonal capture 影子里通过 XOR0 完成。相比之下，`S_ECC_DIAG` 虽然是 product 本体，但占比仅 3.50%，用复制硬件去打它会破坏面积和故事。

## 3. 已经排除的路线

### 3.1 直接加 diagonal parallelism

不建议。原因：

- 当前 `S_ECC_DIAG` 占比只有 3.50%；
- 加 group-pair / diagonal-pair 很容易复制 bit-matrix AND/parity 或扩大 mux；
- 文献中 bit-parallel / Karatsuba pipeline 往往以明显资源增长换速度；
- 与 HDC/ECC 共享统一底座的叙事不匹配。

保留一个很窄的例外：如果后续能把 group-pair 作为同一 parity row 的固定小模板展开，而不是复制 AND 面，则可以作为第四阶段探索。

### 3.2 继续 VV14-1 direct dynamic group folding

不建议原样继续。VV14-1 证明了 group-level folding 可行，但它的问题也明确：

- dynamic path/sub/group mux 太宽；
- area 增量偏大；
- capture 主体没有显著压缩；
- 看起来像 bit-matrix 主路径旁边多了一块 ECC folding 逻辑。

下一步只能继承“group/leaf contribution 可直接进入 XOR0”的思想，不能继承宽动态函数形态。

### 3.3 NAF/window/precompute/标量算法大改

暂不建议。原因：

- 会引入额外存储、预计算点、非均匀调度或 side-channel 叙事问题；
- 我们当前主题是 HDC/ECC 共享底座，不是单独做最快 ECC accelerator；
- 当前 profile 显示 field-op 内部 drain 才是主要问题。

### 3.4 专门重写 inversion

不优先。当前 `INV_MUL + INV_SQR` 约 1.07%，不是值得第一阶段投入的点。

## 4. 下一步 RTL 计划

### Phase A: fixed-template leaf-fold shadowing

目标：

把 `S_ECC_LEAF_FOLD` 的显式 drain 大幅压缩，但不引入 VV14-1 的宽动态 folding packet。

基本思想：

当前 leaf product 完成后，不再停下来专门 fold 4 个 fold words，而是在下一 leaf/sub 的 diagonal capture 周期里，把前一 leaf 的 fold word 作为一个 fixed-template token 喂给 XOR0。模板只由有限合法 path/sub/fold_word 决定，不在组合逻辑里动态计算通用 reduce packet。

RTL 形态：

1. 保留 VV14/VV15 的 `leaf_product_q` 表示，先不做同组 parity 的 same-cycle folding。
2. 新增一个非常小的 `fold_token_q`：
   - `valid`
   - `leaf_path_id`
   - `fold_word_idx`
   - `leaf_product_word`
3. 生成固定模板函数，例如：
   - `ecc_kpd64_fold_template_packet(path_id, fold_word_idx, word64)`
   - 内部使用有限 `case` / constant wiring / XOR mask；
   - 不输入动态 `path_mask`；
   - 不扫描 128-bit leaf delta；
   - 不引入新的 accumulator。
4. 调度上：
   - 当前 leaf capture 结束后，只登记 `fold_token_q`；
   - 下一 leaf 的 `S_ECC_DIAG_CAPTURE` 期间，如果 XOR0 port 空闲，就发射一个 fold template packet；
   - fold token 与 diagonal product 使用同一个 XOR0 accumulation path；
   - leaf 边界只保留必要的 hazard clear，不保留完整 fold drain。
5. 如果下一 leaf 不存在，最后一个 leaf 才进入短 drain，把剩余 tokens flush 完。

为什么这不是面积换周期：

- folding 是 GF(2) 线性映射，模板是常量 wiring + 小 XOR；
- 不复制 bit-matrix AND/parity；
- 不复制 XOR0；
- 不做 VV14-1 那种 `path/sub/group/parity` 全动态 mux；
- 用调度消掉空转，而不是加第二条运算通路。

预期收益：

- 之前 hidden-fold 探针已经说明 `~291k` 级别周期存在可能，但面积/Fmax 失败；
- fixed-template 目标是保留它的周期收益，去掉其动态逻辑面积；
- 第一版接受目标：`PMUL <= 305k`，`Logic LUT < 4700`，`Fmax >= 200 MHz`；
- 理想目标：`PMUL 290k-300k`，`Logic LUT <= 4665`。

拒绝条件：

- `Logic LUT >= 4700`；
- `Fmax < 200 MHz`；
- 模板函数退化成大 mux；
- 需要第二套 accumulator 或第二个 matrix datapath。

### Phase B: write-pair / write-drain overlap and bypass

目标：

压缩 `S_ECC_WRITE_PAIR = 42768` 和 `S_ECC_WRITE_DRAIN = 1188`，但不增加 VRF 端口。

基本思想：

低面积文献常用 memory scheduling、register reuse、data forwarding 来减少等待。VV15 的结果已经在 `hdc_src0_q` / reduced packet 中，很多 write-pair 周期本质是把结果搬回 VRF，然后下一个操作又读回来。可以增加很小的 pending-write bypass，而不是增加 register-file port。

RTL 形态：

1. 增加 `ecc_pending_write_q`：
   - `valid`
   - `addr`
   - `packet`
   - `lane_mask`
2. 当下一条 ECC load 命中 pending write address：
   - 直接从 pending packet forward；
   - 同时允许物理 writeback 在后台完成；
   - 不增加 VRF write/read port。
3. 对 write-drain：
   - 如果 drain 只是保证上一次 write 可见，则由 bypass valid 替代一部分等待；
   - 只有跨 HDC/ECC mode 或外部可观察边界才强制 drain。
4. 对 write-pair：
   - 尽量把 pair write 的第二半与下一次 `S_ECC_LOAD` 或 fold-token issue 交错；
   - 复用现有 4x64 packet，不新增宽 bus。

为什么值得：

- `WRITE_PAIR + WRITE_DRAIN` 占 12.96%，仅次于 leaf-fold；
- 它不是 GF product 本体，调度和旁路更可能低面积见效；
- 和 RFID/端侧文献里“coordinate swapping / register file / controller complexity”优化思路一致。

第一版接受目标：

- `PMUL` 再降 `8k-20k` cycles；
- `Logic LUT` 增量不超过 `+20`，最好下降；
- `Fmax >= 200 MHz`。

拒绝条件：

- 增加第二个 VRF 端口；
- forwarding 需要宽动态选择网络，导致 LUT 接近或超过 4700；
- 破坏 HDC full-flow regression。

### Phase C: point-op DFG compaction under shared resource constraints

目标：

在不改 Montgomery ladder 安全/规整结构的前提下，把 point-add/double 内部的 field op 调度压紧。

当前 profile：

- `SUB_ADD = 321773`
- `SUB_DBL = 10016`
- `SUB_AFFINE = 7293`

这里的 `SUB_ADD` 大，不等于“改 point addition 公式”一定最好。更稳妥的是先做 DFG compaction：

1. 抽取 ECC uop trace：
   - operation type；
   - source/destination VRF addr；
   - field op type；
   - 是否只做 XOR add/copy；
   - 是否依赖上一 field multiply result。
2. 标记可移动节点：
   - XOR-only field add；
   - copy；
   - load prefetch；
   - fold token issue；
   - writeback finalization。
3. 对共享资源建约束：
   - bit-matrix product slot；
   - XOR0 accumulator slot；
   - VRF physical write slot；
   - pending-write bypass hazard。
4. 做局部 reorder：
   - 不跨越 secret-dependent branch；
   - 不改变 scalar loop regularity；
   - 只在固定 ladder schedule 内移动无依赖的小操作。

第一版接受目标：

- 在 Phase A/B 后再降 `5k-15k` cycles；
- `Logic LUT < 4700`；
- 控制逻辑变化保持小而可解释。

拒绝条件：

- 需要新的大 scoreboard；
- 需要多端口 VRF；
- 引入 variable-time scalar behavior；
- 让 HDC/ECC 复用故事变成 ECC-only scheduler。

### Phase D: optional group-pair only after A/B/C

只有在 A/B/C 完成后仍需要进一步压周期，才考虑 group-pair。

前提必须很窄：

- 不复制 bit-matrix AND 面；
- 不复制 parity tree；
- 只利用已经捕获/即将捕获的 fixed template；
- group-pair 的收益必须来自 fewer control bubbles 或 shared XOR subexpression，而不是双倍硬件。

如果做不到这些，就不做。

## 5. 实验顺序

### Step 0: checkpoint current VV15

当前 VV15 是一个可接受 checkpoint：

- cycle 从 VV14 的约 `360484` 降到 `339100`；
- area 保持在 `4655 Logic LUT`；
- `Fmax = 207.297 MHz`；
- reduce/add/HDC regressions 已通过。

在进入 Phase A RTL 编辑前，应先保留当前状态，避免后续探索污染可接受基线。

### Step 1: derive template coverage

先不改 FSM，先生成/人工枚举模板覆盖表：

| Dimension | Bound |
|---|---:|
| legal KPD64 leaf path | 9 |
| fold word | 4 |
| output packet lanes | 4x64 |
| reduction polynomial | fixed GF(2^233), `x^233 = x^74 + 1` |

产物不是 ROM 大表，而是 RTL-friendly constant wiring/case template。

检查点：

- 模板对所有合法 path 的输出必须 bit-exact 等价于当前 `ecc_kpd64_leaf_reduce_packet`；
- 若模板综合后 LUT 变大，说明写法仍是 dynamic mux，要重写。

### Step 2: add fold-token shadow issue

先只 shadow 一个 fold word，验证：

- function correctness；
- XOR0 accumulation ordering；
- no hazard with diagonal capture；
- last-leaf flush 正确。

再扩展到 4 fold words。

### Step 3: run focused regressions

每次 probe 最少跑：

- ECC reduce regression；
- ECC add regression；
- ECC PMUL profile；
- HDC full-flow regression；
- OOC timing/utilization。

通过标准：

```text
PMUL PASS
HDC full-flow PASS
Logic LUT < 4700
Fmax >= 200 MHz
BRAM = 4
DSP = 0
```

### Step 4: only then enter writeback bypass

不要同时改 fold shadow 和 write bypass。Phase A 先独立过门槛，再动 Phase B。

## 6. 预期里程碑

| Milestone | PMUL cycles target | Logic LUT target | 说明 |
|---|---:|---:|---|
| Current accepted VV15 | 339100 | 4655 | sub-level registered lookahead，已可接受。 |
| A1: one-word fold shadow | 325k-333k | <4700 | 验证模板和顺序。 |
| A2: full fixed-template fold shadow | 290k-305k | <4700 | 主收益点。 |
| B: pending-write bypass | 275k-295k | <4700 | 压 write-pair / drain。 |
| C: DFG compaction | 265k-285k | <4700 | 小幅继续压缩。 |

这些目标是探针目标，不是承诺值。任何一步如果面积超过门槛，就回退并保留上一 checkpoint。

## 7. 论文故事如何变强

如果 Phase A/B 成功，VV15 的故事会比 VV14-1 更完整：

```text
HDC/ECC share a unified bit-matrix substrate
-> ECC multiplication uses shared diagonal bit-matrix AND/parity
-> modular reduction is represented as fixed GF(2) folding templates
-> folding/writeback are scheduled under resource constraints
-> XOR0 remains the single shared GF(2) accumulator
-> latency is reduced without duplicating ECC arithmetic units
```

这比“加一个 ECC 加速器”更像 TCAS-I 可讲的架构贡献：不是用面积换周期，而是证明 ECC 的 polynomial multiply/reduction/writeback 都可以被约束在 HDC 的 bit-matrix 计算底座里，并通过固定模板和调度减少空转。

## 8. 下一步最具体的 RTL 起手式

第一刀只做 Phase A 的 A1：

1. 找到当前 `ecc_kpd64_leaf_reduce_packet` 的调用点和 leaf-fold FSM。
2. 写一个只覆盖 `fold_word_idx = 0` 的 fixed-template packet function。
3. 加 `fold_token_q`，在 leaf capture 完成后登记 token。
4. 在下一次 safe slot issue token 到 XOR0。
5. 最后一 leaf 用原有 leaf-fold flush 兜底。
6. 跑 reduce/add/PMUL/HDC/OOC。

如果 A1 的 LUT 没有低于当前 hidden-fold rejected versions，则立刻停，不扩展 A2。原因是模板写法没真正消掉动态 mux。

## 9. Anti-patterns

不要做：

- 不要复制 diagonal AND/parity lane；
- 不要新增第二个 reduced accumulator；
- 不要把 path/sub/group/parity 全塞进一个通用 dynamic folding function；
- 不要为了 PMUL 几千周期去牺牲 HDC full-flow 或 Fmax；
- 不要把 `<4700 Logic LUT` 当成软约束；
- 不要把当前 RTL 说成最终 diagonal-group fully fused pipeline，除非同组 product/fold 真正低面积融合。

可以做：

- 用固定模板代替动态函数；
- 用 forwarding 代替多端口存储；
- 用 schedule overlap 代替硬件复制；
- 用小探针真实综合数字决定去留；
- 保持 XOR0 和 bit-matrix 复用主线。

## 10. 希望补全文精读的论文清单

下面这些论文我目前只能稳定看到摘要、题录、引用段或二手综述，不能完整检查它们的 DFG、调度表、控制 FSM 和资源表。如果后续要继续把 VV15 做深，最希望优先补这些全文。

### Priority 0

1. Z. U. A. Khan and M. Benaissa, `High-Speed and Low-Latency ECC Processor Implementation Over GF(2^m) on FPGA`, IEEE Transactions on Very Large Scale Integration Systems, vol. 25, no. 1, pp. 165-176, 2017. DOI: `10.1109/TVLSI.2016.2574620`.

   为什么要看：这是 TCAS-II 2015 throughput/area-efficient 版本之后的扩展版，重点可能包括 single-multiplier / multi-multiplier 结构、modified Lopez-Dahab Montgomery PM、avoid data dependency、cycle reduction。我们最想学的是它怎么在资源约束下重排 PA/PD 和 multiplier utilization。

2. M. Zeghid, H. Y. Ahmed, A. Chehri, and A. Sghaier, `Speed/Area-Efficient ECC Processor Implementation Over GF(2^m) on FPGA via Novel Algorithm-Architecture Co-Design`, IEEE Transactions on Very Large Scale Integration Systems, vol. 31, no. 8, pp. 1192-1203, 2023. DOI: `10.1109/TVLSI.2023.3268999`.

   为什么要看：题目本身就是 algorithm-architecture co-design，并且是 speed/area dual objective。它可能会给出 field multiplier、PM algorithm 和控制器如何联合压 ADP 的完整设计过程。对我们判断 Phase C 的 DFG compaction 很关键。

3. L. Li and S. Li, `High-Performance Pipelined Architecture of Elliptic Curve Scalar Multiplication over GF(2^m)`, IEEE Transactions on Very Large Scale Integration Systems, vol. 24, no. 4, pp. 1223-1232, 2016. DOI: `10.1109/TVLSI.2015.2453360`.

   为什么要看：它偏速度优先，bit-parallel Karatsuba MAC 面积较大，不是我们要照搬的路线。但它的 pipeline stage placement、modified Montgomery ladder sharing 和 scheduling 对我们很有反面/对照价值：哪些提速靠面积换，哪些提速靠调度。

4. S. Harb and M. Jarrah, `FPGA Implementation of the ECC Over GF(2^m) for Small Embedded Applications`, ACM Transactions on Embedded Computing Systems, vol. 18, no. 2, Article 17, 2019. DOI: `10.1145/3310354`.

   为什么要看：这篇是 small embedded applications，摘要里提到 Lopez-Dahab projective arithmetic、ROM-based state machine、compact core。它可能对我们 Phase B 的 controller/register/bypass 设计更有价值，而不是只看 multiplier。

5. B. Rashidi, S. M. Sayedi, and R. Rezaeian Farashahi, `High-speed hardware architecture of scalar multiplication for binary elliptic curve cryptosystems`, Microelectronics Journal, vol. 52, pp. 49-65, 2016. DOI: `10.1016/j.mejo.2016.03.006`.

   为什么要看：这篇标题直接是 binary curve scalar multiplication hardware architecture。我们想看它的 critical path 重排、PA/PD 并行度、GNB/PB arithmetic 取舍，以及它到底哪些并行是低面积的，哪些是面积换周期。

### Priority 1

6. M. Imran, M. Rashid, A. R. Jafri, and M. Kashif, `Throughput/area optimized pipelined architecture for elliptic curve crypto processor`, IET Computers & Digital Techniques, vol. 13, no. 5, pp. 361-368, 2019. DOI: `10.1049/iet-cdt.2018.5056`.

   为什么要看：题目和我们的目标很接近，可能有 pipeline/control 细节，可作为 VV15 fixed-template shadow scheduling 的旁证。

7. P. K. G. Nadikuda and L. Boppana, `An area-time efficient point-multiplication architecture for ECC over GF(2^m) using polynomial basis`, Microprocessors and Microsystems, vol. 91, Article 104525, 2022. DOI: `10.1016/j.micpro.2022.104525`.

   为什么要看：polynomial basis 和我们 GF(2^233) polynomial multiply/reduction 更贴近，重点看它怎么做 area-time 而不是 pure throughput。

8. R. Salarifard, S. Bayat-Sarmadi, and H. Mosanaei-Boorani, `A Low-Latency and Low-Complexity Point-Multiplication in ECC`, IEEE Transactions on Circuits and Systems I: Regular Papers, vol. 65, no. 9, pp. 2869-2877, 2018. DOI: `10.1109/TCSI.2018.2801118`.

   为什么要看：低延迟 + 低复杂度的组合值得参考，尤其要判断它是否通过算法重排获得低复杂度，还是用了不适合我们共享 HDC/ECC 故事的专用硬件。

