# HDEC ECC Diagonal Multiply V1 综合报告

日期：2026-06-09
分支：`hdec-ecc-diagonal-mul-v1`
基础版本：`07bd8cbd hdec: split P2 popcount with P3 accumulation`
Vivado：2024.2
器件：`xc7z020clg400-2`
Top：`hdec_top`

## 1. V1 完成范围

本版完成 ECC V1 原型：256-bit 二元域原始多项式乘法。

计算语义是：

```text
P[k] = XOR over all i+j=k of A[i] & B[j]
```

也就是用户提出的“斜线加法”：同一条斜线上的所有部分积做无进位加法，等价于求奇偶。

本版暂不包含：

- 模约减。
- Montgomery LD。
- ITA 求逆。
- 点乘。
- 数字签名完整协议 FSM。

## 2. 自定义指令接口

新增两个 HDEC Custom-0 指令：

| 指令 | funct7 | funct3 | 含义 |
|---|---:|---:|---|
| `HDEC_ECC_MUL` | `0000011` | `011` | 启动 256x256 原始 GF(2) 斜线乘法 |
| `HDEC_ECC_STATUS` | `0000011` | `100` | ECC 状态/调试读取 |

`HDEC_ECC_MUL` 的 `rs1` 编码：

```text
rs1[17:12] = dst VRF entry
rs1[11:6]  = A source VRF entry
rs1[5:0]   = B source VRF entry
```

512-bit 原始乘积写回：

```text
dst     = product[255:0]
dst + 1 = product[511:256]
```

`dst=63` 会返回错误，因为 `dst+1` 超出 64-entry VRF。

## 3. 数据通路设计

V1 采用算子旁边的影子寄存器：

| 寄存器 | 位宽 | 作用 |
|---|---:|---|
| `ecc_a_q` | 256 | 保存 A |
| `ecc_b_q` | 256 | 保存 B |
| `ecc_b_window_q` | 256 | 保存当前斜线对应的 B 移位窗口 |
| `ecc_word_q` | 64 | 暂存当前 64-bit 输出字 |
| `ecc_k_q` | 9 | 当前斜线编号 0..510 |

最终保留的是 shift-window 结构：

```text
k=0:    window[0] = B[0]
k+1:    window_next[255:1] = window[254:0]
        window_next[0]     = B[k+1] or 0
```

每一拍斜线输入：

```text
partial_vec[lane] = A_shadow[lane] & B_window[lane]
```

然后复用已有 `hdec_p2_pop_slice`：

```text
src_a_i = partial_vec
src_b_i = 0
```

ECC 输出 bit 是 8 个 32-bit popcount partial 的最低位异或。

## 4. 功能验证

Python 参考模型：

- `scripts/hdec/ecc_diag_mul_ref.py`

Vivado xsim testbench：

- `verif/hdec/tb_hdec_ecc_diag_mul_v1.sv`

覆盖内容：

- 256-bit dense mixed vector。
- 高位边界 vector，覆盖 product bit 510。
- 通过 VRF `dst` 和 `dst+1` 读回完整 512-bit raw product。

结果：

```text
[HDEC_ECC_DIAG_MUL_V1] PASS
```

保存日志：

- `xsim_ecc_diag_mul_v1.log`

## 5. OOC PPA 结果

对比基线是当前 P2/HMATCH 优化后版本 `trial12_p2_partial_p3accum_200`。

200MHz 是主要 PPA 对比口径：

| Version | Period | WNS ns | Est. Fmax MHz | LUT | Logic LUT | LUTRAM | FF | BRAM | DSP | CARRY4 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline trial12 | 5.000 ns | -0.051 | 197.981 | 4505 | 3817 | 688 | 2080 | 0 | 0 | 16 |
| ECC V1 final uop3 | 5.000 ns | -0.166 | 193.573 | 5211 | 4523 | 688 | 2952 | 0 | 0 | 16 |

175MHz 约束下：

| Version | Period | WNS ns | Est. Fmax MHz | LUT | Logic LUT | LUTRAM | FF | BRAM | DSP | CARRY4 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| ECC V1 final uop3 | 5.714 ns | +0.534 | 193.050 | 5033 | 4345 | 688 | 2952 | 0 | 0 | 16 |

相对 baseline，200MHz 口径增量：

| Metric | Delta |
|---|---:|
| LUT | +706 |
| Logic LUT | +706 |
| LUTRAM | 0 |
| FF | +872 |
| BRAM | 0 |
| DSP | 0 |
| CARRY4 | 0 |

FF 增量主要来自影子寄存器：

```text
A shadow       256 FF
B shadow       256 FF
B window       256 FF
current word    64 FF
counter/control small remainder
```

## 6. VRF 路径小优化结论

本次保留一个低风险优化：

```text
hdec_uop_type_e: 4 bit -> 3 bit
```

原因是内部 uop 类型只有 0..6，第四位永远不需要。原来最差路径从无意义的 `op_type[3]` 出发，打到 VRF LUTRAM 端口。

试验结果：

| Trial | WNS ns | Est. Fmax MHz | LUT | FF | 结论 |
|---|---:|---:|---:|---:|---|
| streamword before uop3 | -0.219 | 191.608 | 5254 | 2956 | 不作为最终版 |
| final uop3 | -0.166 | 193.573 | 5211 | 2952 | 保留 |
| prefetch next subgroup | -0.188 | 192.753 | 5219 | 2950 | 不保留 |
| VRF write-data default | -0.200 | 192.308 | 5240 | 2952 | 不保留 |

保留版收益：

```text
WNS:  -0.219 ns -> -0.166 ns
Fmax: 191.608 MHz -> 193.573 MHz
LUT:  5254 -> 5211
FF:   2956 -> 2952
```

## 7. 当前关键路径

200MHz top path：

```text
uop_p3_q_reg[op_type][0]
  -> VRF LUTRAM port i_vrf/vrf_b0.../DP/I
```

延迟：

```text
data delay  4.816 ns
logic delay 1.085 ns
route delay 3.731 ns
route ratio 0.775
logic level 5
```

小白解释：

现在最慢的不是 ECC 斜线 popcount 本身，而是“P3 阶段的控制信号一路跑到 VRF 的 LUTRAM 读/写端口”。这条路径 77.5% 是布线延迟，说明它更像布线和扇出问题，不是某个大算术器太慢。

## 8. 是否继续优化 VRF 路径

可以继续优化，但需要更深层的端口时序改造，不建议继续靠零散小 mux 语义去碰运气。

已经尝试并放弃的两个办法：

- 提前发 HCNTADD/HCNTCLIP 下一 subgroup 读地址：会把源头换成 FSM 状态位，时序变差。
- 把 P3 写数据默认设成 `lane_result_q`：会把源头换成 `op_q[1]`，时序也变差。

后续真正有效的方向更可能是：

- 把 VRF 读地址/写地址/写使能做成更局部的已注册端口控制。
- 把 HCNTADD/HCNTCLIP 的“同拍写当前结果 + 读下一项”拆开，代价是这两类指令增加少量周期。
- 或者为高频路径设计小型旁路/暂存寄存器，减少直接打到 LUTRAM 端口的控制扇出。

## 9. V1 结论

ECC V1 已达到当前阶段目标：

- CVA6/HDEC 自定义 ECC 指令入口已加入。
- 256-bit 原始 GF(2) 斜线乘法功能通过 Vivado xsim。
- 复用了现有 popcount/parity 算子。
- 结果可以通过 VRF 读回。
- LUTRAM 不增加。
- BRAM/DSP 不增加。
- 保留 `uop3` 小优化后，PPA 比原 streamword 版本更好。

当前不足：

- 还没有严格过 200MHz OOC。
- 当前估算 Fmax 约 193.6MHz。
- 最后一堵墙仍是 VRF/control 到 LUTRAM 端口的 route-dominated path。

建议保留本 RTL 作为 ECC diagonal multiply V1 基线。下一步可以在此基础上继续做模约减和 ECC 上层 FSM；如果必须先过 200MHz，再专门开一个 VRF 端口时序优化分支。
