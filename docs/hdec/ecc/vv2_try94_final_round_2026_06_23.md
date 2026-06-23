# VV2 try94 最后一轮优化记录

日期：2026-06-23  
分支：`hdec-vv2-area-ecc-control`  
最终保留版本：`try102 / 79f782e9`

## 最终选择

最终仍保留 `try102 / 79f782e9`，因为它是目前总面积最好的版本：

| 版本 | Total LUT | Logic LUT | LUTRAM | FF | Fmax | PMUL cycles | 结论 |
|---|---:|---:|---:|---:|---:|---:|---|
| try102 | 5127 | 4999 | 128 | 1833 | 210.393MHz | 190151 | 保留 |

`try102` 的改动是去掉 `ecc_product_pair_hold_we`，让 product pair hold 每拍自然装载 scratch 读口数据。这个改动没有改变算法和周期，但减少了一点控制选择逻辑。

## 为什么继续看 try94

FF name-probe 显示 `ecc_product` 正好有 128 个 FF，这基本就是 `ecc_product_pair_hold_q[127:0]`。所以 try94 的方向很有吸引力：如果能删掉这 128 个 ECC-only FF，同时不明显增加 LUT，就可以显著降低 ECC 专属 FF。

但是 product scratch 是 `4 x 128` 的 LUTRAM，只有一个组合读口。ECC 写回 VRF 时每次要同时写 4 个 64-bit bank，也就是同一拍需要 pair0 和 pair1，下一组需要 pair2 和 pair3。因此如果不保留一个 128-bit pair hold，就必须：

- 复制 scratch 读口，代价是 LUTRAM/LUT 增加；
- 或借用已有 128-bit/64-bit 寄存器暂存，代价是这些寄存器输入 MUX 变大。

这就是 try94 系列“省 FF 但涨 LUT”的根本原因。

## 最后一轮尝试

| 版本 | 思路 | PMUL | Total LUT | Logic LUT | FF | Fmax | 结论 |
|---|---|---:|---:|---:|---:|---:|---|
| try108 | 128-bit hold 改成 64-bit hold，低 64 位借用 `ecc_leaf_prod_q` | 190151 | 5194 | 5066 | 1774 | 210.393MHz | 拒绝 |
| try109 | 完全删除 hold，顺序局部捕获到 `ecc_leaf128_prod_q` | 190151 | 5232 | 5104 | 1701 | 210.393MHz | 拒绝 |
| try110 | 复现组合式 try94，偶数 pair 写入 `ecc_leaf128_prod_n` | 190151 | 5165 | 5037 | 1705 | 210.393MHz | 拒绝 |

## 结论

try94/try110 确实能节省约 128 个 ECC-only FF，但新增的 128-bit 写回暂存 MUX 会把 Logic LUT 从 try102 的 4999 增加到 5037，代价仍偏大。try108 只省一半 FF 反而涨更多 LUT，说明 64-bit 拆分没有让 Vivado 得到更好的映射。try109 更差，说明把捕获写进顺序块不会自动减少组合选择，反而让状态条件进入更大的寄存器输入锥。

因此本轮不把 try94 系列合入 VV2。当前最稳的 VV2 仍是 `try102 / 79f782e9`：总面积最低、时序稳定、PMUL 周期不变。后续如果还想吃掉这 128 FF，理论上需要改变 product scratch 的读写组织方式，而不是继续把 pair hold 挪到已有宽寄存器里。

## 保留文件

失败补丁已保留在：

- `reports/hdec/vv2_area_ecc_control_2026_06_23/try108_product_hold64_leafprod_rejected.patch`
- `reports/hdec/vv2_area_ecc_control_2026_06_23/try109_product_hold_leaf128_seqcap_rejected.patch`
- `reports/hdec/vv2_area_ecc_control_2026_06_23/try110_product_hold_leaf128_comb_rejected.patch`

相关 OOC / xsim 报告目录保留在 `reports/hdec/vv2_area_ecc_control_2026_06_23/`。
