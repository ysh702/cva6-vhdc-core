# V37 popcount + 规约 XOR 并行尝试记录

日期：2026-06-15

分支：`hdec-ecc-pointmul-v37`

基线：V35，`4193f204 hdec: select V35 5M point-add optimization`

工具：
- 仿真：`scripts/hdec/xsim_hdec_ecc_pmul_profile_v27.tcl`
- 综合：`scripts/hdec/run_ooc_200.ps1`
- Vivado：2024.2
- 器件：`xc7z020clg400-2`
- OOC 约束：5.000 ns

## 目标

这一轮验证用户提出的想法：不要只让 ECC 专属规约 XOR 计算斜线，而是让“popcount 的最低位”和规约 XOR 一起服务 ECC 多项式乘法。

在二元域里，一个 diagonal 的结果就是一串 AND 部分积的奇偶性：

```text
diagonal bit = popcount(partial_products) 的最低位
             = partial_products 的规约 XOR
```

所以如果 popcount 结果本来已经存在，取最低位几乎不要面积；但如果为了这个最低位重新生成完整 popcount 计数树，综合器会付出明显 LUT 代价。

## 选中的 RTL 版本

选中版本是 `popxor24_lsb`：

```text
保留 V35 的 32-bit leaf 和 27-leaf Karatsuba
原来每拍计算 16 条 32-bit diagonal parity
新增一组 4x64 partial vector
每拍额外得到 8 条 32-bit parity
合计每拍 24 条 diagonal parity
一个 32x32 leaf 从 4 拍降到 3 拍
```

这个版本没有使用完整 `$countones` 结果，而是直接保留 popcount 最低位等价的奇偶校验硬件：

```text
低 32 位规约 XOR -> 一个 parity
高 32 位规约 XOR -> 一个 parity
4 个 lane 合计 -> 8 个 parity
```

## 结果对比

| 方案 | 仿真 | PMUL 周期 | 比 V35 少 | Logic LUT | 比 V35 多 | FF | 比 V35 多 | WNS(ns) | Fmax(MHz) | 判断 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| V35 基线 | PASS | 341624 | 0 | 5921 | 0 | 1802 | 0 | 0.243 | 210.217 | baseline |
| popxor24，完整 `$countones` 后取最低位 | PASS | 309143 | 32481 | 6252 | 331 | 1806 | 4 | 0.243 | 210.217 | 拒绝，完整 popcount 树面积太贵 |
| popxor24_lsb，只实现最低位/奇偶性 | PASS | 309143 | 32481 | 6174 | 253 | 1815 | 13 | 0.045 | 201.816 | 本轮选中 |
| popxor24_slot036，0/3/6 编码降 base mux | PASS | 309143 | 32481 | 6442 | 521 | 1833 | 31 | 0.204 | 208.507 | 拒绝，编码反而扩大控制逻辑 |

确认版报告：
- 仿真：`reports/hdec/v37_popxor24_lsb_confirm_2026_06_15/xsim_ecc_pmul_profile_v27/xsim.log`
- OOC：`reports/hdec/v37_popxor24_lsb_confirm_2026_06_15/ooc_popxor24_lsb_confirm`

确认版关键 profile：

| 项目 | 周期 |
|---|---:|
| `PMUL_PROFILE_WALL_CYCLES` | 309143 |
| `PMUL_PROFILE_ST_ECC_DIAG_CYCLES` | 129924 |
| `PMUL_PROFILE_ST_ECC_LEAF_FOLD_CYCLES` | 129924 |
| `PMUL_PROFILE_GF_MUL_STARTS` | 1203 |
| `PMUL_PROFILE_GF_MUL_STARTS_ADD` | 1165 |

## 对两个关键问题的回答

### 每个 lane 每拍 64 个 AND 够不够？

如果一个 64-bit lane 只承载两个 32-bit diagonal partial，那么够：

```text
低 32 位 -> 1 条 diagonal partial
高 32 位 -> 1 条 diagonal partial
```

4 个 lane 一组 4x64 partial vector，每拍可以给出 8 条 32-bit diagonal parity。

但如果想让“ECC 原有规约 XOR”和“popcount 最低位”同时计算不同 diagonal，就需要额外 partial 生成。当前选中版本就是新增一组 4x64 partial vector，让原来的 16 条 parity 变成 24 条 parity。

### 取 popcount 最低位要不要额外面积？

分两种情况：

```text
如果完整 popcount 已经被 HDC 正在计算，取最低位几乎只是连线。
如果为了 ECC 单独生成完整 popcount，再只取最低位，面积很不划算。
```

这轮数据正好验证了这一点：完整 `$countones` 版本比 V35 多 331 个 Logic LUT；改成 LSB-only parity 后降到多 253 个 Logic LUT，但仍然不是很轻，因为真正增加面积的还有第三组 4x64 partial 生成、24-bit leaf 打包和控制路径。

## 判断

`popxor24_lsb` 可以作为“popcount + 规约 XOR 并行服务 ECC”的 RTL 证据保留：功能通过、周期减少 32481、200MHz OOC 通过。

但它不是目前面积/周期比最优的实用版本。它和前面的 Plan2 斜线尾部旁路周期相同，都是 309143 周期；Plan2 的 Logic LUT 约为 6051，只比 V35 多 130，而本轮选中版本是 6174，比 V35 多 253。

所以本轮结论是：

```text
popcount 最低位这个数学想法是对的；
但在当前 RTL 里，直接新增 partial 并行度来喂 popcount/parity，面积收益比还不如先前的调度型优化。
```

后续如果继续沿这个方向走，应该优先考虑真正复用已有 HDC popcount 的空闲输入路径，而不是复制一份只服务 ECC 的 partial 生成逻辑。
