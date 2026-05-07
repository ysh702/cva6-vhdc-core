# HDEC 协处理器完整架构文档

## 目录
1. [系统层次总览](#1-系统层次总览)
2. [CV-X-IF 协议层](#2-cv-x-if-协议层)
3. [HDEC 顶层控制](#3-hdec-顶层控制)
4. [Lane 流水线硬件设计](#4-lane-流水线硬件设计)
5. [HDC 指令数据流](#5-hdc-指令数据流)
6. [ECC 指令数据流](#6-ecc-指令数据流)
7. [信号完整清单](#7-信号完整清单)

---

## 1. 系统层次总览

```
┌─────────────────────────────────────────────────────────┐
│ CVA6 CPU Core                                           │
│   decoder.sv  →  illegal instr  →  CV-X-IF path         │
│   issue_stage →  cvxif_req_o    →  issue_valid + id     │
│   commit      ←  cvxif_resp_i   ←  result_valid + id    │
└──────────────────────┬──────────────────────────────────┘
                       │ cvxif_req / cvxif_resp (struct)
┌──────────────────────┴──────────────────────────────────┐
│ hdec_xif_coprocessor.sv  (CV-X-IF 包装层)               │
│   - 指令匹配 (mask/match 表)                             │
│   - Issue→Register 两拍握手                              │
│   - trans_id 保存 & Result 通道输出                      │
│   - hdec_start 单周期脉冲生成                            │
│   - result_valid 电平信号保持                            │
└──────────────────────┬──────────────────────────────────┘
                       │ valid_i, operator_i, rs1, rs2
┌──────────────────────┴──────────────────────────────────┐
│ hdec_top.sv  (HDC+ECC 融合协处理器)                      │
│   - VRF: 4 BRAM banks × 64×64-bit = 2KB                │
│   - Main FSM: IDLE → EXECUTE → FINISH                   │
│   - ECC FSM: ACTIVE → WAIT1 → WAIT2 → SHIFT (→DONE)    │
│   - Lane 仲裁: HDC 优先, ECC 填空隙                     │
└──────────────────────┬──────────────────────────────────┘
                       │ 4× lanes_in, lane_valid_in, owner
┌──────────────────────┴──────────────────────────────────┐
│ hdec_lane.sv ×4  (64-bit Lane 流水线)                   │
│   Stage 1: XOR + L1→L2→L3 (组合逻辑)                    │
│   mid-pipe: 寄存器 (切断时序路径)                        │
│   Stage 2: L4→L5→L6 (组合逻辑)                          │
│   Owner 追踪: s1 → mid → s2 (与数据同步流水)             │
└─────────────────────────────────────────────────────────┘
```

---

## 2. CV-X-IF 协议层

### 2.1 接口信号 (hdec_xif_coprocessor.sv)

CV-X-IF 使用单一 struct 端口 `cvxif_req_i` / `cvxif_resp_o`，内部包含 4 个通道：

| 通道 | 方向 | 结构体字段 | 作用 |
|---|---|---|---|
| Compressed | 主→协 | `compressed_valid` + `compressed_req` | 压缩指令解压 (未使用，始终 reject) |
| Issue | 主→协 | `issue_valid` + `issue_req` | 发送 32-bit 指令 + hartid + id |
| Register | 主→协 | `register_valid` + `register` | 发送操作数 (rs[]) + rs_valid 标志 |
| Commit | 主→协 | `commit_valid` + `commit` | 通知提交/杀死 (未使用，自动通过) |
| Result | 协→主 | `result_valid` + `result` | 返回计算结果 + id + rd + we |

### 2.2 指令匹配 (10 条自定义指令)

所有指令共享 opcode `7'b0001011` (custom-0)。通过 funct7 + funct3 区分：

| 指令 | funct7 | funct3 | register_read | 说明 |
|---|---|---|---|---|
| HDEC_BIND | 0000000 | 000 | 01 (rs1 only) | VRF XOR |
| HDEC_BUNDLE | 0000000 | 001 | 01 (rs1 only) | 累加+binary化 |
| HDEC_MATCH | 0000000 | 010 | 01 (rs1 only) | popcnt |
| HDEC_INGEST | 0000000 | 011 | 11 (rs1+rs2) | 写VRF |
| HDEC_BINARIZE | 0000000 | 100 | 01 (rs1 only) | 阈值二值化 |
| HDEC_PERMUTE | 0000000 | 101 | 01 (rs1 only) | 循环移位 |
| HDEC_ECC_START | 0000000 | 110 | 01 (rs1 only) | 启动ECC |
| HDEC_ECC_FETCH | 0000000 | 111 | 00 (无操作数) | 取ECC结果 |
| HDEC_CLEAR_CNT | 0000001 | 001 | 00 (无操作数) | 清零累加器 |
| HDEC_BUNDLE_ACCUM | 0000001 | 100 | 01 (rs1 only) | 累加(vs2=0) |

### 2.3 两拍握手时序

```
周期  | CPU (Issue)           | CPU (Register)        | hdec_xif_coprocessor
──────┼───────────────────────┼───────────────────────┼──────────────────────────
  N   | issue_valid=1         | register_valid=1      | ① 指令匹配 (mask & instr)
      | issue_req={instr,     | register={hartid,     |    → hdec_matched=1
      |   hartid, id}         |   id, rs[], rs_valid} |    → hdec_resp (accept,
      |                       |                       |      writeback, reg_read)
      |                       |                       | ② 检查 rs_valid 标志
      |                       |                       |    → rs1_ready, rs2_ready
      |                       |                       | ③ 检查 hdec_ready (VRF就绪)
      |                       |                       | ④ issue_ready = 全部条件∧
      |                       |                       |    → issue_accepted 上升沿
      |                       |                       |    → hdec_start 单周期脉冲
──────┼───────────────────────┼───────────────────────┼──────────────────────────
 N+1  | (issue 握手完成)      |                       | ⑤ saved_id/hartid/rd/op 锁存
      |                       |                       | ⑥ hdec_top.valid_i=1
      |                       |                       |    → 状态机启动
      |                       |                       | ⑦ transaction_active=1
──────┼───────────────────────┼───────────────────────┼──────────────────────────
 ...  |                       |                       | hdec_top 内部计算...
──────┼───────────────────────┼───────────────────────┼──────────────────────────
 N+k  |                       |                       | ⑧ hdec_top.valid_o=1
      |                       |                       |    → hdec_valid_out=1
      |                       |                       |    → result_valid=1 (保持)
      |                       |                       | ⑨ result={saved_hartid,
      |                       |                       |      saved_id, data,
      |                       |                       |      saved_rd, we=1}
──────┼───────────────────────┼───────────────────────┼──────────────────────────
      | CPU scoreboard 解锁   |                       | ⑩ issue_valid↓ → result↓
```

### 2.4 关键设计决策

**hdec_start 脉冲化**：`issue_valid` 是电平信号 (CPU 保持到握手完成)。直接连到 hdec_top 会反复触发状态机。通过上升沿检测 `issue_accepted && !issue_accepted_q` 生成单周期脉冲。

**result_valid 电平化**：示例协处理器使用电平 result_valid (保持到 opcode 变化)。脉冲信号会被 writeback 阶段的单周期忙碌窗口丢失。使用 `!issue_valid || hdec_start` 清除，`hdec_valid_out && transaction_active` 设置。

**i_ecc_mode 动态赋值**：`lane_owner_in == OWNER_ECC || (!hdc_active && ecc_state_q != ECC_IDLE)`。ECC 注入 S1 时强开进位抑制，HDC 无 ECC 时正常进位。

---

## 3. HDEC 顶层控制

### 3.1 VRF 存储架构

```
16 个逻辑寄存器 × 1024-bit = 2KB
跨 4 个 BRAM Bank 交织存储:

Bank 0 (64×64-bit):  reg0_chunk0, reg0_chunk4,  reg0_chunk8,  reg0_chunk12,
                      reg1_chunk0, ...
Bank 1 (64×64-bit):  reg0_chunk1, reg0_chunk5,  reg0_chunk9,  reg0_chunk13, ...
Bank 2 (64×64-bit):  reg0_chunk2, reg0_chunk6,  reg0_chunk10, reg0_chunk14, ...
Bank 3 (64×64-bit):  reg0_chunk3, reg0_chunk7,  reg0_chunk11, reg0_chunk15, ...

寻址: addr[5:0] = {reg_id[3:0], sub_chunk[1:0]}
      每次 send 读 4 个 Bank × 64-bit = 256-bit
      4 次 send 覆盖完整 1024-bit 寄存器
```

### 3.2 主状态机 (HDC)

```
         ┌──────────────────────┐
         │       ST_IDLE        │  ready_o = vrf_ready
         │  (等待 HDEC 指令)    │  (ECC_FETCH pending 时 = 0)
         └────┬────────────┬────┘
              │ FAST 指令   │ MULTI-CYCLE 指令
    ┌─────────┘             └─────────┐
    ▼ (INGEST/ECC_START/              ▼ (BIND/BUNDLE/MATCH/
    │  CLEAR_CNT)                     │  PERMUTE/BINARIZE/
    │  result 下一拍返回              │  BUNDLE_ACCUM)
    │  state → ST_IDLE                │  state → ST_EXECUTE
    ▼                                 ▼
 (完成)                    ┌──────────────────────┐
                           │     ST_EXECUTE        │  send 4次 (BRAM读)
                           │  send_cnt 0→1→2→3    │  recv 4次 (Lane收结果)
                           │  ECC 填空隙注入 S1   │
                           └──────────┬───────────┘
                                      │ recv_cnt == 4
                                      ▼
                           ┌──────────────────────┐
                           │     ST_FINISH         │  valid_o=1, result_o 输出
                           │  (1 周期后回 IDLE)    │
                           └──────────────────────┘
```

**RAW 冒险防护**：`pipe_wr_pending` 追踪 VRF 写回未完成。`raw_hazard()` 检查 vs1/vs2/vd 是否与未完成写冲突。冲突时 `ready_o = 0`。

### 3.3 ECC 状态机

```
         ┌──────────────────────────────────────┐
         │              ECC_IDLE                 │ 等待 ECC_START
         │  (ECC_START + valid_i → ACTIVE)      │
         └──────────────────┬───────────────────┘
                            ▼
         ┌──────────────────────────────────────┐
         │             ECC_ACTIVE                │ 抢占 S1 (如果空闲)
         │  k0=1: 注入 ecc_A/ecc_Acc → WAIT1   │
         │  k0=0: 跳过 Lane → SHIFT             │
         └──────┬──────────────────┬────────────┘
                │ k0=1             │ k0=0
                ▼                  │
         ┌──────────┐              │
         │ ECC_WAIT1│ 数据在mid-pipe│
         │ → WAIT2  │              │
         └────┬─────┘              │
              ▼                    │
         ┌──────────┐              │
         │ ECC_WAIT2│ S2处理中      │
         │ 等OWNER_ECC输出         │
         │ → SHIFT  │              │
         └────┬─────┘              │
              └────────────────────┘
                       ▼
         ┌──────────────────────────────────────┐
         │             ECC_SHIFT                 │
         │  ecc_k_q >>= 1                        │
         │  ecc_A_q ← 移位 + POLY_MASK (if MSB) │
         │  loop_cnt++ → ACTIVE (or DONE at 255)│
         └──────────────────┬───────────────────┘
                            │ loop=255
                            ▼
         ┌──────────────────────────────────────┐
         │             ECC_DONE  (sticky)        │
         │  保持直到 ECC_FETCH 取走结果          │
         │  ECC_FETCH → result 返回 → IDLE      │
         └──────────────────────────────────────┘
```

**ECC 参数**：
- GF(2^256) 不可约多项式: `0x425` (低 11 位)
- 私钥: rs1 传入，256 次迭代
- 每迭代 ~4 周期 (k0=1) 或 ~1 周期 (k0=0)

### 3.4 Lane 仲裁逻辑 (细粒度交织)

```
每个时钟周期:
  if (state_q == ST_EXECUTE && vrf_read_launched)
      → lane_valid_in=1, owner=OWNER_HDC    // HDC send (最高优先级)

  if (!lane_valid_in && ecc_state_q == ECC_ACTIVE && ecc_k_q[0]==1)
      → lane_valid_in=1, owner=OWNER_ECC    // ECC 填空隙 (S1 空闲时)
```

**时序示例** (HDC 4次 send + ECC 交织):
```
周期:  S1 占用     S2 占用     输出
  0:   HDC(send0)  idle        -
  1:   HDC(send1)  HDC(send0)  -
  2:   HDC(send2)  HDC(send1)  HDC(send0)→recv0
  3:   HDC(send3)  HDC(send2)  HDC(send1)→recv1
  4:   ECC          HDC(send3)  HDC(send2)→recv2
  5:   idle         ECC         HDC(send3)→recv3
  6:   idle         idle        ECC→ecc_Acc_q 捕获
```

---

## 4. Lane 流水线硬件设计

### 4.1 全加器 (ecc_full_adder.sv)

```
输入: a, b, cin, ecc_mode
输出: sum, cout

half_sum   = a ^ b
half_carry = a & b
sum        = half_sum ^ cin
cout       = ecc_mode ? 0 : (half_carry | (half_sum & cin))
                                    ↑
                          ecc_mode=0: 正常进位 (HDC popcnt)
                          ecc_mode=1: 进位切断 (ECC GF(2) XOR)
```

**关键创新**：进位切断在**每一个 1-bit 加法器**内部实现，而非在树顶端用 MUX 选择。ecc_mode 随数据流并行传播，零额外延迟。

### 4.2 多态加法器 (poly_adder — 在 hdec_lane.sv 内)

```systemverilog
poly_adder #(WIDTH=N):
  输入: i_ecc_mode, a[N-1:0], b[N-1:0]
  输出: sum[N:0]
  内部: N 个 ecc_full_adder 级联
        ecc_mode 统一传入每一级
```

### 4.3 64级二叉树 (hdec_lane.sv)

```
                        Stage 1 (组合逻辑)                     │  Stage 2 (组合逻辑)
                                                               │
  s1_xor_result[63:0]                                         │
    = rs1 ^ rs2  (1 周期延迟: s1_xor_result 是寄存器)          │
         │                                                     │
    ┌────┴─────┬───────── ... ────────┐                        │
    L1: 32× poly_adder #(1)           │  (64→32, 2-bit sum)    │
    └────┬─────┴───────── ... ────────┘                        │
    ┌────┴─────┬───────── ... ────────┐                        │
    L2: 16× poly_adder #(2)           │  (32→16, 3-bit sum)    │
    └────┬─────┴───────── ... ────────┘                        │
    ┌────┴─────┬───────── ... ────────┐                        │
    L3:  8× poly_adder #(3)           │  (16→8,  4-bit sum)    │
    └────┬─────┴───────── ... ────────┘                        │
         │                                                     │
    ─ ─ ─│─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─│─ ─ ─
         │               mid-pipe 寄存器                       │
    ┌────┴─────┬───────── ... ────────┐                        │
    lvl3_out_mid[7:0] (4-bit ×8)      │                        │
    mid_ecc_mode_q (1-bit 控制信号)    │                        │
    ─ ─ ─│─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─│─ ─ ─
         │                                                     │
    ┌────┴─────┬───────── ... ────────┐                        │
    L4:  4× poly_adder #(4)           │  (8→4,   5-bit sum)    │
    └────┬─────┴───────── ... ────────┘                        │
    ┌────┴─────┬───────── ... ────────┐                        │
    L5:  2× poly_adder #(5)           │  (4→2,   6-bit sum)    │
    └────┬─────┴───────── ... ────────┘                        │
    ┌────┴─────┬───────── ... ────────┐                        │
    L6:  1× poly_adder #(6)           │  (2→1,   7-bit sum)    │
    └─────────────────────────────────┘                        │
         │                                                     │
    tree_final_out[6:0]                                        │
         │                                                     │
    ─ ─ ─│─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─│─ ─ ─
         │               S2 输出寄存器                          │
    s2_popcnt_val[6:0], s2_lane_data[63:0]                     │
    o_owner (s1→mid→s2 追踪)                                   │
```

**资源统计**：63 个 poly_adder，每 poly_adder 级联 N 个 ecc_full_adder (1 到 6)。总计约 200 个 ecc_full_adder 实例，<2000 逻辑门。

### 4.4 Owner 追踪流水线

```
i_owner ──→ [s1_owner_q] ──→ [mid_owner_q] ──→ [s2_owner_q] ──→ o_owner
              ↑S1寄存器        ↑mid-pipe寄存器    ↑S2寄存器        ↑组合输出

与数据同步:
  周期 N:   i_owner=ECC → s1_owner_q=ECC (数据进入 S1)
  周期 N+1: mid_owner_q=ECC (数据进入 mid-pipe)
  周期 N+2: s2_owner_q=ECC (数据进入 S2) → o_owner=ECC → 输出
```

### 4.5 BUNDLE 累加器

```systemverilog
cnt_array[63:0] (7-bit 每元素)
    = 前值 + {6'd0, s1_xor_result[i]}     // 每个 1-bit XOR 结果累加

binarized_result[i] = (cnt_array[i] > i_threshold) ? 1 : 0

// BUNDLE (HDEC_BUNDLE): 累加 XOR 结果 + 输出二值化
// BINARIZE (HDEC_BINARIZE): 只用二值化, 不清除
// CLEAR_CNT: 清空 cnt_array
// BUNDLE_ACCUM: 累加时 vs2 强制为 0
```

### 4.6 输出路由

```systemverilog
// 数据输出 (根据 owner 选择):
o_lane_data = (s1_op_mode == HDEC_BIND)  ? s1_xor_result       // XOR 结果
            : (s1_op_mode == HDEC_BUNDLE) ? updated_binarized   // 二值化结果
            : 64'b0;

// ECC 输出:
o_ecc_data = (s2_owner_q == OWNER_ECC) ? s2_lane_data           // 完整 64-bit XOR
            : {57'b0, s2_popcnt_val};                           // popcnt 结果

// popcnt 输出:
o_popcnt_val = s2_popcnt_val;  // 7-bit hamming weight
```

---

## 5. HDC 指令数据流

### 5.1 INGEST (写 VRF)

```
CPU → rs1=64-bit数据, rs2[3:0]=VRF寄存器号
  │
  ▼
ST_IDLE: valid_i=1, operator=INGEST
  → result_valid_n=1 (快路径, 下拍返回)
  → wr_pending=1, wr_bank=ing_cnt[1:0], wr_addr={reg_id, sub_chunk}
  → vrf_b{0-3}[wr_addr] <= operand_a_i
  → ing_cnt++ (自动循环 0→1→2→3→0..., 子块自动递增)
```

### 5.2 BIND (XOR)

```
CPU → rs1 = {threshold[21:15], vd[13:10], vs1[8:5], vs2[3:0]}
  │
  ▼
ST_IDLE → ST_EXECUTE:
  saved_vd=vd, saved_vs1=vs1, saved_vs2=vs2

  send 4 次:
    vrf_ra_addr[i] = {saved_vs1, send_cnt}
    vrf_rb_addr[i] = {saved_vs2, send_cnt}
    lanes_in_1[i] = vrf_ra_pipe[i]  (VRF[vs1] 数据)
    lanes_in_2[i] = vrf_rb_pipe[i]  (VRF[vs2] 数据)

  Lane 计算:
    s1_xor_result = rs1 ^ rs2   (64-bit XOR)
    s2_lane_data  = s1_xor_result

  recv 4 次 (Lane 输出 → VRF 写回):
    vrf_b{i}[{saved_vd, recv_cnt}] <= lanes_out_data[i]  (VRF[vd])

ST_FINISH: valid_o=1, result_o=0 (数据在 VRF 里)
```

### 5.3 PERMUTE (循环左移 1 位)

```
BIND 类似, 但 lanes_in_1 路由不同:
  lanes_in_1[0] = {vrf_ra_pipe[0][62:0], vrf_ra_pipe[1][63]}   // Bank0 左移, 借 Bank1 MSB
  lanes_in_1[1] = {vrf_ra_pipe[1][62:0], vrf_ra_pipe[2][63]}
  lanes_in_1[2] = {vrf_ra_pipe[2][62:0], vrf_ra_pipe[3][63]}
  lanes_in_1[3] = {vrf_ra_pipe[3][62:0], vrf_rb_pipe[0][63]}   // Bank3 从 Port B 预读借位
  (vs2 不使用, vs1 自身旋转)
```

### 5.4 MATCH (Hamming 距离)

```
BIND 类似, 但结果不同:
  Lane 计算 XOR + popcnt (加法树正常进位)
  total_popcnt = Σ lanes_out_popcnt[i]  (4 次 send 累加)
ST_FINISH: result_o = {52'b0, total_popcnt}  (12-bit popcnt)
```

### 5.5 BUNDLE / BINARIZE / BUNDLE_ACCUM / CLEAR_CNT

```
BUNDLE: 每次 XOR 后 cnt_array += s1_xor_result[0:63] (每 bit 独立累加)
        输出 = threshold(cnt_array) 二值化结果
BINARIZE: 只输出二值化, 不累加新数据 (threshold 来自 rs1)
BUNDLE_ACCUM: vs2 强制为 0 (只累加 vs1)
CLEAR_CNT: 清空 cnt_array, 1 周期返回
```

---

## 6. ECC 指令数据流

### 6.1 ECC_START

```
CPU → rs1 = 64-bit 私钥
  │
  ▼
ST_IDLE: valid_i=1, operator=ECC_START
  → ecc_k_q   = {192'b0, operand_a_i}    (256-bit 密钥)
  → ecc_A_q   = 256'hFFFF_FFFF            (初始化)
  → ecc_Acc_q = 256'b0                    (累加器清零)
  → ecc_state = ECC_ACTIVE
  → result_valid_n=1 (快路径, ECC 在后台运行)
```

### 6.2 ECC 迭代 (后台)

```
while loop_cnt < 256:
  ECC_ACTIVE:
    if ecc_k_q[0] == 1:
      抢占 S1 (如果空闲) → lanes_in_[0-3] = ecc_A_q[255:0], ecc_Acc_q[255:0]
      → WAIT1 → WAIT2
      
      Lane 在 ECC 模式下处理:
        i_ecc_mode=1 → 加法树进位全切断 → 纯 XOR
        o_ecc_data = s2_lane_data (64-bit XOR)
      
      WAIT2 末: ecc_Acc_q[255:0] <= {lanes_out_ecc[3..0]}
    
    if ecc_k_q[0] == 0:
      → SHIFT (跳过 Lane, 不需要计算)
  
  ECC_SHIFT:
    ecc_k_q >>= 1
    ecc_A_q = (ecc_A_q[255] == 1) ? (ecc_A_q << 1) ^ POLY_MASK
                                  : (ecc_A_q << 1)
    loop_cnt++

ECC_DONE: 保持 sticky (不自动回 IDLE)
```

### 6.3 ECC_FETCH

```
CPU → (无操作数, register_read=00)
  │
  ▼
ST_IDLE: valid_i=1, operator=ECC_FETCH
  if ecc_state == ECC_DONE:
    result_valid_n=1, result_data_n=ecc_Acc_q[63:0]
    ecc_state → ECC_IDLE (取走结果后释放)
  else:
    ecc_fetch_pending_n=1 (等待 ECC 完成)
    ready_o=0 (阻塞新指令)
    当 ECC_DONE 时: result_valid_n=1, pending 清除
```

---

## 7. 信号完整清单

### 7.1 CV-X-IF 包装层 (hdec_xif_coprocessor)

| 信号 | 位宽 | 方向 | 说明 |
|---|---|---|---|
| cvxif_req_i | struct | 输入 | CV-X-IF 请求 (Issue+Register+Commit) |
| cvxif_resp_o | struct | 输出 | CV-X-IF 响应 (Issue+Compressed+Result) |
| issue_valid | 1 | 内部 | Issue 通道有效 |
| issue_req.instr | 32 | 内部 | 待匹配的指令 |
| issue_req.id | X_ID_WIDTH | 内部 | 事务 ID |
| issue_ready | 1 | 内部 | 协处理器就绪 (门控) |
| hdec_matched | 1 | 内部 | 指令匹配成功 |
| hdec_resp.accept | 1 | 内部 | 接受指令 |
| hdec_resp.writeback | 1 | 内部 | 写回使能 |
| hdec_resp.register_read | 2 | 内部 | 需要的寄存器 (rs1, rs2) |
| hdec_start | 1 | 内部 | 上升沿脉冲, 触发 hdec_top |
| hdec_operator | 4 | 内部 | 当前操作码 |
| hdec_ready | 1 | 输入 | hdec_top 就绪 |
| hdec_valid_out | 1 | 输入 | hdec_top 结果有效 |
| hdec_result | 64 | 输入 | hdec_top 计算结果 |
| result_valid | 1 | 输出 | 结果有效 (电平) |
| result.id | X_ID_WIDTH | 输出 | 事务 ID (与 issue 相同) |
| result.data | 64 | 输出 | 结果数据 |
| result.rd | 5 | 输出 | 目标寄存器 |
| result.we | 1 | 输出 | 写回使能 |
| saved_id/hartid/rd/op | - | 内部 | 事务期间锁存的 ID 信息 |
| transaction_active | 1 | 内部 | 事务进行中 |

### 7.2 HDEC 顶层 (hdec_top)

| 信号 | 位宽 | 说明 |
|---|---|---|
| valid_i | 1 | 指令启动 (单周期脉冲) |
| ecc_valid_i | 1 | ECC 启动标志 |
| operator_i | 4 | hdec_op 操作码 |
| operand_a_i | 64 | rs1 数据 |
| operand_b_i | 64 | rs2 数据 |
| ready_o | 1 | 可接受新指令 |
| valid_o | 1 | 结果有效 |
| result_o | 64 | 结果数据 |
| vrf_b{0-3} | 64×64 | 4 个 BRAM Bank |
| vrf_ra/rb_addr[0:3] | 6×4 | Port A/B 读地址 |
| vrf_ra/rb_pipe[0:3] | 64×4 | Port A/B 读数据 |
| vrf_read_launched | 1 | 上一拍发起了读 |
| wr_pending/bank/addr/data | - | 写转发 |
| state_q | 2 | 主状态 (IDLE/EXECUTE/FINISH) |
| send_cnt_q | 3 | 发送计数 (0-3) |
| recv_cnt_q | 3 | 接收计数 (0-3) |
| total_popcnt_q | 12 | MATCH 累加 popcnt |
| saved_vd/vs1/vs2_q | 4×3 | 锁存的 VRF 寄存器号 |
| saved_op_q | 4 | 锁存的操作码 |
| latched_operator | 4 | Lane 当前操作码 |
| latched_threshold | 7 | BINARIZE 阈值 |
| lane_valid_in | 1 | Lane 输入有效 |
| lane_owner_in | 2 | Lane 输入 owner |
| lanes_in_1/2[0:3] | 64×4 | Lane 输入数据 |
| lanes_out_valid[0:3] | 4 | Lane 输出有效 |
| lanes_out_data[0:3] | 64×4 | Lane 输出数据 |
| lanes_out_popcnt[0:3] | 7×4 | Lane 输出 popcnt |
| lanes_out_ecc[0:3] | 64×4 | Lane 输出 ECC |
| lane_o_owner[0:3] | 2×4 | Lane 输出 owner |
| ecc_state_q | 3 | ECC 状态 |
| ecc_loop_cnt_q | 9 | ECC 迭代计数 (0-255) |
| ecc_k_q | 256 | ECC 多项式参数 k |
| ecc_A_q | 256 | ECC 多项式参数 A |
| ecc_Acc_q | 256 | ECC 累加器 |
| ecc_fetch_pending_q | 1 | ECC_FETCH 等待中 |
| pipe_wr_pending | 1 | VRF 写回未完成 |
| pipe_vd_q | 4 | 未完成的写目标 |

### 7.3 Lane 流水线 (hdec_lane)

| 信号 | 位宽 | 说明 |
|---|---|---|
| i_valid | 1 | 输入有效 |
| i_op_mode | 4 | 操作模式 |
| i_ecc_mode | 1 | ECC 进位抑制 |
| i_cnt_clear | 1 | 累加器清零 |
| i_owner | 2 | 输入 owner 标签 |
| i_rs1/rs2_data | 64 | 输入操作数 |
| o_valid | 1 | 输出有效 |
| o_owner | 2 | 输出 owner 标签 |
| o_lane_data | 64 | 输出数据 |
| o_popcnt_val | 7 | 输出 popcnt |
| o_ecc_data | 64 | 输出 ECC |
| s1_xor_result | 64 | S1 XOR 结果 (寄存器) |
| s1_op_mode | 4 | S1 锁存操作码 |
| s1_valid | 1 | S1 有效 |
| s1_owner_q | 2 | S1 owner 标签 |
| s1_xor_result | 64 | S1 XOR 输出 (寄存器) |
| cnt_array[63:0] | 7×64 | BUNDLE 累加器 |
| updated_binarized | 64 | 二值化结果 (组合) |
| lvl1_out[31:0] | 2×32 | 树 L1 输出 |
| lvl2_out[15:0] | 3×16 | 树 L2 输出 |
| lvl3_out[7:0] | 4×8 | 树 L3 输出 |
| lvl3_out_mid[7:0] | 4×8 | mid-pipe 寄存器 |
| mid_ecc_mode_q | 1 | mid-pipe ecc_mode |
| mid_valid | 1 | mid-pipe 有效 |
| mid_owner_q | 2 | mid-pipe owner |
| lvl4_out[3:0] | 5×4 | 树 L4 输出 |
| lvl5_out[1:0] | 6×2 | 树 L5 输出 |
| tree_final_out | 7 | 树最终输出 (组合) |
| s2_popcnt_val | 7 | S2 popcnt (寄存器) |
| s2_lane_data | 64 | S2 数据 (寄存器) |
| s2_valid | 1 | S2 有效 |
| s2_owner_q | 2 | S2 owner 标签 |
