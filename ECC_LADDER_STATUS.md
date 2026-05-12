# ECC Ladder 架构升级 — 当前状态与问题总结

**日期**: 2026-05-08  
**目标**: 在 hdec_top.sv 中实现完整的 GF(2^256) Montgomery Ladder + ITA 点乘卸载  
**当前阶段**: GF_MUL 子状态机死锁排查

---

## 1. 已完成的工作

### 1.1 架构基础设施 ✅

| 组件 | 状态 | 说明 |
|---|---|---|
| `gf_sqr_256()` | ✅ 通过 | 单周期组合逻辑平方器（~1000 XOR 门, ~2.5 kGE） |
| `ladder_k_q` | ✅ 通过 | 256-bit 私钥保护寄存器（唯一新增 D-FF） |
| `ecc_top_q` (ECC_IDLE→INIT→LADDER→ITA→DONE) | ✅ 编译 | 顶层梯子状态机 |
| `ecc_uPC_q` / `ladder_sub_q` | ✅ 编译 | 微码程序计数器 + 子步计数器 |
| `ECC_SLOT0`/`ECC_SLOT1` (VRF slot 14-15) | ✅ 编译 | L2 SRAM 存储映射 |
| VRF 读写标志 (`ecc_vrf_wr`, `ecc_wr_data`) | ✅ 编译 | Load-Store 机制 |
| Two-Always Block 方法 | ✅ 通过 | 组合 `_d` 与时序 `_q` 严格分离 |
| GF_LOAD 状态 | ✅ 加入 | 插入 GF_IDLE→GF_LOAD→GF_ACTIVE 的 1 拍操作数稳定延迟 |

### 1.2 INIT 阶段 ✅

ECC_START 指令触发 INIT → 7 个 uPC 步骤将 xG/X1/Z1/X2/Z2 写入 VRF slot 14-15。此阶段通过探针验证正确执行：

```
t=2846: ecc_top=1 (ECC_INIT)
t=2853: ecc_top=2 (ECC_LADDER), step=2, sub=0
```

### 1.3 现有测试保持通过 ✅

| 测试 | 结果 |
|---|---|
| `hdec_full_test.S` (HDC + ECC) | SUCCESS |
| `hdec_steal_test.S` (Cycle Stealing) | SUCCESS |
| `bench.c` (5-mode benchmark) | SUCCESS |

---

## 2. 当前阻塞问题

### 2.1 核心死锁：GF_MUL 不响应 gfmul_trigger 🔴

**探针日志**（t=2855 开始）：

```
t=2855: ecc_top=2(LADDER) sub=2 gf=0(GF_IDLE) trig=1
t=2856: ecc_top=2 sub=2 gf=0 trig=1  ← sub 卡在 2
t=2857: ecc_top=2 sub=2 gf=0 trig=1
...（永远重复）
```

- Ladder 控制器已发出 `gfmul_trigger = 1`
- GF 状态机保持在 `gf_state_q = GF_IDLE`，未跳转到 `GF_LOAD`
- Ladder 在 sub=2 永远等待 `gf_state_q == GF_DONE`
- 主从状态机死锁

### 2.2 根本原因分析

在 `always_comb` 块中的执行顺序：

```
always_comb begin
    默认值: gfmul_trigger = 0;
    
    case(state_q) ... endcase        // HDC 主状态机
    
    case(gf_state_q) ... endcase     // GF 子状态机 ← 在此处读 gfmul_trigger
    //   GF_IDLE: if (gfmul_trigger) gf_state_n = GF_LOAD;  ← 读到的是 0！
    
    case(ecc_top_q) ... endcase      // Ladder 控制器 ← 在此处设 gfmul_trigger=1
    //   4'd2: gfmul_trigger = 1;    ← 设置太晚了！
end
```

**Ladder 控制器在 GF 状态机之后执行**。`gfmul_trigger` 由 ladder 设为 1，但 GF 状态机已经用旧值 0 完成了评估。Verilator 的 `always_comb` 未因 `gfmul_trigger` 的内部变化触发重新评估。

### 2.3 次要问题

| 问题 | 位置 | 严重度 |
|---|---|---|
| 重复的 `case (ecc_top_q)` 块 | 第 375 行和第 485 行 | 🔴 旧块覆盖新块的 `ecc_top_n` |
| `gf_k_q<=gf_A_q` / `gf_Acc_q<='0` | 第 475-481 行 | 🟡 `<=` 在 `always_comb` 中不生效 |
| `$display` 探针输出不可见 | 探针块 | 🟡 输出缓冲问题 |

---

## 3. 待执行的修复

### 3.1 交换执行顺序（高优先级）

将 Ladder 控制器移到 GF 状态机**之前**：

```
always_comb begin
    case(state_q) ... endcase
    case(ecc_top_q) ... endcase   ← 先执行，设 gfmul_trigger=1
    case(gf_state_q) ... endcase  ← 后执行，读到 gfmul_trigger=1 ✓
end
```

### 3.2 删除重复的 case 块

移除第 485 行旧版 ladder 控制器。

### 3.3 修复 always_comb 中的非阻塞赋值

将 `gf_k_q<=gf_A_q` → `gf_k_d=gf_A_q`，`gf_Acc_q<='0` → `gf_Acc_d='0`。

### 3.4 验证

- `rm -rf work-ver && make verilate` — 编译通过
- `timeout 30 ./Variane_testharness hdec_full_test.elf` — 期望 GF 进入 ACTIVE，梯子完成

---

## 4. 架构实现进度

```
完整点乘 R = k×G:
  ┌─ INIT ──────────────── ✅ 完成
  ├─ Ladder (255步) ────── 🔴 死锁在第一个 GF_MUL
  │  ├─ Point Double ──── 🔴 未验证
  │  └─ Point Add ─────── 🔴 未验证
  ├─ ITA (求逆) ────────── ⬜ 占位（跳到 DONE）
  └─ ECC_DONE → FETCH ──── ⬜ 框架就位
```
