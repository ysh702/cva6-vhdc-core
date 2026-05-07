# Cycle-Stealing 交织验证报告

**测试**: `hdec_steal_test.S` — ECC_START → BIND (多周期) → 20 NOP → ECC_FETCH  
**仿真结果**: `SUCCESS (tohost = 0) after 35840 cycles`

---

## 关键时序：t=2861 ~ t=2872

```
t      HDC      ECC       S1_own   S2_own[0]  send  recv  ecc_loop  事件
───────────────────────────────────────────────────────────────────────────────
2861   EXEC     ECC_SH    NONE     ECC         0     0     0        HDC 刚进 EXEC，ECC 上轮结束
2862   EXEC     ECC_ACT   HDC      ECC         0     0     1        HDC send0，ECC 等 S1
2863   EXEC     ECC_ACT   HDC      ECC         1     0     1        HDC send1
2864   EXEC     ECC_ACT   HDC      ECC         2     0     1        HDC send2
2865   EXEC     ECC_ACT   HDC      HDC         3     0     1        HDC send3，S2 开始出 HDC
2866   EXEC     ECC_ACT   HDC      HDC         4     1     1        send 完，recv 开始
2867   EXEC     ECC_ACT   ECC      HDC         5     2     1        ★ STEAL: ECC 注入 S1
2868   EXEC     ECC_W1    NONE     HDC         5     3     1        ECC 进 mid-pipe
2869   FIN      ECC_W2    NONE     HDC         5     4     1        HDC 收完 4 个 recv
2870   IDLE     ECC_W2    NONE     ECC         5     4     1        ECC 进 S2
2871   IDLE     ECC_SH    NONE     ECC         5     4     1        ECC 捕获结果
2872   IDLE     ECC_ACT   ECC      ECC         5     4     2        ECC 下一轮注入
```

**S1_own 翻转点**: t=2867。在 HDC 仍处于 EXEC（recv=2/4，尚未完成），S1 空闲的第一拍，ECC 立即抢占。

---

## 三阶段分解

### 阶段 A：ECC 先跑（t=2857 ~ t=2861）

BIND 指令到来前，ECC_START 已启动 ECC 状态机。ECC 完成 loop=0 的第一次注入：

```
t=2857  ECC_ACT → S1_own=ECC (ECC 第一次注入 S1)
t=2858  ECC_W1  (数据进 mid-pipe)
t=2859  ECC_W2  (数据进 S2)
t=2860  ECC_W2  (等 S2 输出)
t=2861  ECC_SH  → loop=0→1 (捕获结果，进入下一轮)
```

### 阶段 B：HDC 霸占 S1（t=2862 ~ t=2866）

BIND 进入 ST_EXECUTE。4 拍 send 连续占用 S1：

```
t=2862  send0→S1 (S1_own=HDC)  ECC: ACTIVE 等待
t=2863  send1→S1               ECC: ACTIVE 等待
t=2864  send2→S1               ECC: ACTIVE 等待
t=2865  send3→S1               ECC: ACTIVE 等待
t=2866  vrf_read_launched=0    ECC: ACTIVE 等待 (1 周期残留延迟)
```

ECC 在 ACTIVE 停留 5 个周期，被 HDC 的连续 send 阻挡。

### 阶段 C：Cycle Steal（t=2867）

```diff
- t=2866  S1_own=HDC  recv=1/4  ECC 阻塞
+ t=2867  S1_own=ECC  recv=2/4  ECC 注入！← 零气泡抢占
```

ECC 在 HDC recv 阶段成功窃取 S1。此后 HDC 收尾（recv 3→4→FINISH），ECC 数据独立流经 mid-pipe→S2。

---

## 数据完整性验证

**S2_own[0] 时间线**：

```
t=2860→2864: S2_own=ECC  (ECC loop=0 的旧数据在 S2 末端)
t=2865→2869: S2_own=HDC  (BIND send2→send3 的 popcnt 结果)
t=2870→2871: S2_own=ECC  (ECC loop=1 的新数据在 S2 末端)
```

- ECC→HDC→ECC 切换发生在 `mid_ecc_mode_q` 和数据一起从 mid-pipe 进 S2 时，每次切换都正确
- HDC 的 4 个 recv 全部收到（recv_cnt 从 0→4），无丢失
- ECC 的 ecc_loop 从 0 递增到 1，中间经过的 SHIFT 状态正确捕获 lane 输出

---

## 关键设计验证结论

| 验证项 | 状态 | 证据 |
|---|---|---|
| ECC 在 HDC recv 阶段抢占 S1 | ✅ | t=2867: HDC=EXEC, recv=2, S1_own=ECC |
| HDC 数据不被 ECC 注入覆盖 | ✅ | S2_own 在 2865→2869 保持 HDC |
| ECC 数据不被 HDC 注入覆盖 | ✅ | ecc_loop 正常递增，ecc_Acc_q 正确捕获 |
| mid_ecc_mode_q 随数据正确绑定 | ✅ | ECC 的 S2 输出在 ECC 模式，HDC 在 HDC 模式 |
| owner 标签路由正确 | ✅ | 无 owner 错位导致的 recv 丢失或 ECC 误捕获 |

---

## 仿真环境

- 工具: Verilator 5.x
- 配置: `cv64a6_imafdc_sv39` (CvxifEn=1)
- 测试: `hdec_steal_test.S` (ECC_START → BIND → 20 NOP → ECC_FETCH)
- 结果: `SUCCESS (tohost = 0) after 35840 cycles`
