# 第四章 C 的方法假设与实现判据

## 上位问题

第四章 C 不再寻找一个与融合映射并列的局部算子，而是回答：

> B 节产生的斜线系数能否持续停留在共享 GF(2) 后端中，直接形成任务可见的
> 模结果及复合域表达式，而不在每个域乘边界物化中间结果。

## 方法

设第 \(j\) 个域乘的第 \(k\) 组斜线系数为 \(d_{j,k}\)，融合映射为
\(\Phi_{j,k}\)，共享 XOR0 维护 233 位余数状态：

\[
S_{j,k+1}=S_{j,k}\oplus\Phi_{j,k}(d_{j,k}).
\]

状态支持三种入口：

1. \(S_{0,0}=0\)，形成普通域乘。
2. \(S_{0,0}=D\)，形成 \(D\oplus AB\bmod f(x)\)。
3. \(S_{j+1,0}=S_{j,K}\)，使多个乘积的模贡献跨乘积边界连续归并。

最终可表达：

\[
S_{\mathrm{out}}
=D\oplus\bigoplus_j A_jB_j \bmod f(x).
\]

由此形成一条连续机制链：

```text
31-bit diagonal coefficient
        ↓
factorized modular-contribution map
        ↓
shared XOR0 residue state
        ↓
zero seed / VRF seed / retained state
        ↓
single final VRF write
```

## RTL 落点

第一步实现可初始化状态。普通乘法清零，乘加从 VRF 附加项开始。PMUL 首先
融合 ADD step6/7：

\[
X_{\mathrm{out}}=T_6\oplus x_PT_5.
\]

第二步试验跨乘积状态延续。ADD step5 形成 \(T_6=T_0T_1\) 后不写 VRF，
保留 XOR0 状态，再连续归并 step6 的 \(x_PT_5\) 模贡献，最终仅写
\(X_{\mathrm{out}}\)。

## 可证伪判据

- 独立黄金模型与全部随机 GF_MAC、PMUL 逐位一致。
- 合法随机 K 的周期与 K 值及 Hamming weight 无关。
- M1 中临时乘积行写次数为零。
- 状态延续变体中 T6 临时写次数为零。
- 不新增第二套 233 位累加状态，不扩大为三输入 XOR 关键路径。
- Fmax 不低于 200 MHz，WNS 非负。
- 面积相对前一累计阶段尽量不增加，轻微增加时必须有明确周期及写回事务收益。

## Claim 边界

有限域 MAC 及 \(A\cdot B+C\) 的代数不是本文提出。已有 ECC 架构已经将域加
并入乘法约减。HDEC 可以主张的局部结构差异是：

> 斜线系数产生的模贡献直接更新 HDC 与 ECC 共用的 4×64 XOR0 余数状态，
> 该状态可由附加项初始化，也可跨域乘边界延续，从而减少中间域结果在共享
> VRF 中的物化。

相关先例：L. Li and S. Li, “High-Performance Pipelined Architecture of
Elliptic Curve Scalar Multiplication Over GF(2m),” IEEE TVLSI, 2016,
doi:10.1109/TVLSI.2015.2453360。

该机制是表示驱动跨域融合的实现延伸，不作为新的有限域算法，也不与 HDEC
总体结构贡献并列。
