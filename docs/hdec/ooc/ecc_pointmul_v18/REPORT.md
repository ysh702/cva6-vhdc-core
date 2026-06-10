# HDEC ECC Pointmul V18 Report

## 范围

分支: `hdec-ecc-pointmul-v18`

基线: `hdec-ecc-pointmul-v17` / `c342239e`

Vivado: 2024.2

器件: `xc7z020clg400-2`

Top: `hdec_top`

目标: OOC 200 MHz, 5.000 ns。

V18 在 V17 的 ITA 求逆基础上，实现了功能完整的 `sect233k1 / NIST K-233` 标量点乘入口:

```text
Q = kP
```

曲线和域:

- field: `GF(2^233)`
- reduction polynomial: `f(x)=x^233+x^74+1`
- curve: `sect233k1 / K-233`
- equation: `y^2 + xy = x^3 + 1`
- `a=0`, `b=1`

K-233 参数来自 SEC 2 v2.0: https://www.secg.org/sec2-v2.pdf

## 指令入口

`HDEC_ECC_STATUS` 继续作为 ECC macro-job 入口。

```text
[31]    GF_INV start
[30]    PMUL start
[17:12] PMUL out_x row
[11:6]  PMUL point_x row
[5:0]   PMUL scalar row
```

PMUL 约定:

- `point_y` 在 `point_x+1`
- 输出 `Q.x` 写到 `out_x`
- 输出 `Q.y` 写到 `out_x+1`
- V18 内部固定使用 `VRF[32:63]` 作为 LD projective 坐标和 scratch workspace
- 因此 PMUL 第一版要求用户输入/输出 row 在 `VRF[0:31]`

## RTL 修改

- 新增 `ECC_JOB_PMUL` macro-job。
- 新增 K-233 Montgomery ladder / Lopez-Dahab projective 调度:
  - `R0`/`R1` ladder point;
  - 每个 scalar bit 顺序执行 point add 与 point double;
  - 使用 projective 坐标避免每 bit 求逆;
  - 最后复用 V17 `GF_INV` 做 affine recovery。
- 继续复用已有 datapath:
  - `GF_ADD` 复用 HBIND/XOR lane;
  - `GF_MUL` 复用 KPD32 diagonal multiply + reduce;
  - `GF_SQR` 复用 HSPREAD + reduce;
  - `GF_INV` 复用 V17 ITA macro-job;
  - 没有新增 DSP、BRAM、第二套 ECC multiplier 或第二套 popcount engine。
- 新增 PMUL testbench:
  - `verif/hdec/tb_hdec_ecc_pmul_v18.sv`
  - `scripts/hdec/xsim_hdec_ecc_pmul_v18.tcl`
- 更新 `HDEC_ECC_STATUS` package 注释，记录 PMUL operand encoding。

## 功能验证

Vivado xsim:

| Test | Result | Notes |
|---|---|---|
| `tb_hdec_ecc_pmul_v18` | PASS | K-233 base point `G`, scalar `k=3`, checks affine `3G.x/3G.y` |
| `tb_hdec_ecc_inv_v17` | PASS | `GF_INV_CYCLES=6066` |
| `tb_hdec_ecc_reduce_v1` | PASS | REDUCE / GF_MUL / GF_SQR regression |

PMUL sample:

```text
PMUL_CYCLES=18414
```

说明: 该周期数是 `k=3` 样例的 RTL 仿真周期。当前 V18 对 leading-zero/infinity 情况有旁路，因此不是最终 constant-time 性能数字。后续如果用于安全实现，需要做 constant-time 调度加固。

## OOC PPA

| Version | Main change | WNS (ns) | Est. Fmax (MHz) | LUT | Logic LUT | LUTRAM | FF | BRAM | DSP | CARRY4 | Worst endpoint |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| V17 final | ITA `GF_INV` macro-job | 0.255 | 210.748 | 6105 | 5633 | 472 | 2104 | 0 | 0 | 20 | `ecc_inv_step_q_reg[0]/CE` |
| V18 final | K-233 PMUL macro-job | 0.219 | 209.161 | 6714 | 6242 | 472 | 2158 | 0 | 0 | 20 | `ecc_dst_q_reg[0]/CE` |

Delta from V17:

- LUT: +609
- Logic LUT: +609
- LUTRAM: unchanged
- FF: +54
- BRAM/DSP: unchanged at 0
- Estimated Fmax: -1.587 MHz, still above 200 MHz

## Timing Notes

Top paths remain control CE paths, not ECC arithmetic datapaths.

| Rank | Simple class | Data delay (ns) | Logic (ns) | Route (ns) | Route ratio | Endpoint |
|---:|---|---:|---:|---:|---:|---|
| 1-6 | ECC destination/control CE | 4.570 | 1.190 | 3.380 | 0.740 | `ecc_dst_q_reg[*]/CE` |
| 7-10 | GF_INV step control CE | 4.562 | 1.190 | 3.372 | 0.739 | `ecc_inv_step_q_reg[*]/CE` |
| 11+ | HSPREAD / control CE | 4.526 | 1.190 | 3.336 | 0.737 | `hperm_dst_base_q_reg[*]/CE` |

V18 仍然过 200 MHz。新增 PMUL 后，最差路径仍是 top-level 控制到 CE 的布线路径；KPD32、reduce、HSPREAD 和 popcount 算术本身没有成为新的 timing wall。

## 结论

V18 已经把 V17 还缺的 Montgomery LD 标量点乘控制接起来了。现在 `HDEC_ECC_STATUS[30]` 不再返回 `STATUS_NOT_IMPLEMENTED`，而是能启动 K-233 的 `Q=kP`，并输出 affine `(x,y)`。

这版可以作为“完整 ECC 标量点乘功能版”保留。

需要注意的边界:

- V18 是 K-233 固定曲线版本，不是 B-233 通用曲线版本。
- V18 是功能正确优先的 PMUL 第一版，还不是数字签名完整系统。
- V18 还没有做 constant-time 加固；leading-zero/infinity 旁路会让周期依赖标量形态。
- 内部工作区固定占用 `VRF[32:63]`，后续若要和 HDC bundle/counter 真正并发，需要再做资源仲裁或地址重命名。

下一步建议:

1. 如果论文叙事先要“完整标量点乘”，保留 V18。
2. 下一版优先做 PMUL 控制面积优化，把当前大 case 调度压成更规则的 micro-op descriptor。
3. 如需安全实现，再做 constant-time ladder scheduling，避免 leading-zero/infinity 旁路泄露周期信息。
4. 再评估是否将 K-233 的 Frobenius/tau 特性纳入优化，但不要破坏当前 HDC/ECC 共享 datapath 主线。
