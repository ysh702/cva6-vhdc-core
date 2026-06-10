# HDEC ECC KPD32 V10 增量面积与时序报告

## 评估口径

本报告先采用“增量面积”来估算 ECC 面积：

```text
ECC LUT  = 当前 HDC+ECC 总 LUT  - V9 HDC-only 总 LUT
ECC FF   = 当前 HDC+ECC 总 FF   - V9 HDC-only 总 FF
ECC 占比 = ECC 增量 / 当前 HDC+ECC 总量
```

基准 HDC-only OOC 记录：

| Baseline | LUT | Logic LUT | LUTRAM | FF | Fmax MHz | WNS ns |
|---|---:|---:|---:|---:|---:|---:|
| V9 HDC-only | 3687 | 3343 | 344 | 1863 | 207.684 | 0.185 |

说明：ECC 已经复用 VRF 和 popcount slice，所以不能只把 Vivado hierarchy 里的 `(hdec_top)` 当作 ECC 面积。增量法更适合回答“加入 ECC 后多出来多少 LUT/FF，以及占总设计多少比例”。

## 主表

| Version | Total LUT | Logic LUT | LUTRAM | FF | ECC incr LUT | ECC LUT % | ECC incr Logic LUT | ECC Logic % | ECC incr FF | ECC FF % | Fmax MHz | WNS ns | ECC_MUL cycles |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| V8 HDC+ECC final | 5172 | 4572 | 600 | 2011 | 1485 | 28.71% | 1229 | 26.88% | 148 | 7.36% | 202.470 | 0.061 | 394 |
| V10 round11 product-pair | 5068 | 4596 | 472 | 2017 | 1381 | 27.25% | 1253 | 27.26% | 154 | 7.64% | 202.470 | 0.061 | 394 |
| V10 round14 path-counter | 5108 | 4636 | 472 | 2025 | 1421 | 27.82% | 1293 | 27.89% | 162 | 8.00% | 202.470 | 0.061 | 390 |
| V10 round15 path-only formula | 5120 | 4648 | 472 | 2013 | 1433 | 27.99% | 1305 | 28.08% | 150 | 7.45% | 202.470 | 0.061 | 390 |
| V10 round16 path-only table | 5030 | 4558 | 472 | 2015 | 1343 | 26.70% | 1215 | 26.66% | 152 | 7.54% | 202.470 | 0.061 | 390 |

## 当前结论

当前最佳候选是 `round16_path_only_mask_table`。

相对 V8 final：

| Metric | V8 final | round16 | Change |
|---|---:|---:|---:|
| Total LUT | 5172 | 5030 | -142 |
| Logic LUT | 4572 | 4558 | -14 |
| LUTRAM | 600 | 472 | -128 |
| FF | 2011 | 2015 | +4 |
| ECC incr LUT | 1485 | 1343 | -142 |
| ECC LUT ratio | 28.71% | 26.70% | -2.01 pp |
| ECC incr Logic LUT | 1229 | 1215 | -14 |
| ECC FF ratio | 7.36% | 7.54% | +0.18 pp |
| Fmax MHz | 202.470 | 202.470 | same |
| ECC_MUL cycles | 394 | 390 | -4 |

## 设计变化摘要

- ECC product bank 从 2 组 `4x64` 改为 1 组 `4x128`，LUTRAM 从 V8 的 600 降到 472。
- ECC result 写回从 8 拍单 bank 写回，改为 4 拍 pair bank 写回，ECC_MUL 周期从 394 降到 390。
- Karatsuba 叶子选择从 `leaf_id -> path` 双控制，改为只保留 `leaf_path`，减少重复控制状态。
- `ecc_k_q` 和 `ecc_leaf_id_q` 已移除，控制语义更接近一个可复用的小型路径计数器。
- OOC 关键路径仍是 P2 popcount capture，当前 Fmax 仍为 202.470 MHz，未跌破 200 MHz 底线。

## 注意

round16 的 MUXF7 数量较高，但总 LUT 和 ECC 增量 LUT 目前最好。后续若继续优化，应优先观察：

- ECC 增量 LUT 是否继续下降；
- ECC 增量 FF 是否不要继续上涨；
- 总 Fmax 是否保持 200 MHz 以上；
- P2 popcount capture 是否仍是唯一主墙；
- VRF 和 pop slice 的层级面积是否只是“把 ECC 成本转移到共享硬件”，而不是实际复用增强。
