# V159 HDC Self-Learning Vivado Result

## Goal

把 V48 的 top-k self-learning HDC 算法接进当前 RTL 验证流，同时保持当前最好 HDEC 面积点：

- HDC 算法：固定 top-k 类别原型，查询向量和类别原型做 AND-overlap，分数为 `popcount(query & proto[class])`。
- 自学习策略：软件维护每类 score/top-k 状态，错分时更新真类并抑制预测类。
- 硬件职责：VRF 存 query/prototype，HSIM 执行 AND-overlap popcount，VWR64 写回软件选出的新 prototype。
- 面积目标：新增自学习能力不引入综合 RTL 面积；当前 RTL 只保留 try7 的 `group_dist` 9-bit 窄化。

## Implementation

新增或纳入文件：

- `scripts/hdec/algo/hdc_overlap_eval.py`
  - V48 Python 原型本体，包含数据集加载、随机投影编码、top-k prototype 和 self-learning 参考实现。
- `scripts/hdec/algo/gen_hdc_selflearn_fixture.py`
  - 复用 `hdc_overlap_eval.py` 的数据集、随机投影、top-k prototype 和 self-learning 规则。
  - 生成 `meta.txt`、`initial_proto.mem`、`samples.mem`、`final_proto.mem`、`summary.json`。
  - prediction tie-break 按 V48 Python 原型的 `argpartition + argsort` 行为生成，保证 Vivado xsim 对齐旧准确率记录。
- `verif/hdec/tb_hdec_hdc_selflearn_v1.sv`
  - 用 Vivado testbench 扮演软件调度器。
  - 初始 prototype 写入 VRF；每个 sample 写 query 到 VRF slot 0。
  - 对每个 class 调一次 HSIM，拿 RTL 的 `popcount(query & prototype)` 分数。
  - 预测、top-k 更新和是否写回由 fixture/软件策略决定。
  - 最后读回 VRF prototype，与 Python 生成的 `final_proto.mem` 逐 word 比较。
- `scripts/hdec/xsim_hdec_hdc_selflearn_v1.tcl`
  - 编译 HDEC RTL 和 self-learning testbench。
  - 通过 plusarg 传入 fixture 目录。

保留设计选择：

- 不把 top-k 选择器放进 RTL，因为 1024-bit 固定 K 选择需要排序/选择网络或多轮扫描控制器，会明显增加 LUT/FF。
- 不修改 HMATCH tie-break。V48 self-learning 需要软件级 tie/update 策略，因此用 HSIM 逐类分数更准确，也不增加面积。
- 不修改 ECC PMUL、reduce、VRF ISA 或 HDC/ECC 主数据通路。

## Verified Results

Vivado xsim:

| Test | Result |
| --- | --- |
| UCI-HAR `L_diffmax_topk256_self_mistake`, seed 7 | PASS, 2598/2947, accuracy 0.8815744825, updates 349 |
| WISDM `K_own_topk256_self_mistake`, seed 1 | PASS, 1078/1643, accuracy 0.6561168594, updates 565 |
| `xsim_hdec_hdc_full_flow_v20` | PASS |
| `xsim_hdec_ecc_reduce_v1` | PASS |
| `xsim_hdec_ecc_pmul_profile_v27` | PASS, `PMUL_PROFILE_WALL_CYCLES=190151` |

OOC synthesis, Vivado 2024.2, `xc7z020clg400-2`, 5 ns:

| Metric | V159 current |
| --- | ---: |
| Slice LUT / Total LUT | 5195 |
| Logic LUT | 5067 |
| LUTRAM | 128 |
| FF | 1877 |
| BRAM | 4 |
| DSP | 0 |
| CARRY4 | 12 |
| WNS | 0.247 ns |
| Fmax estimate | 210.393 MHz |
| Worst endpoint | `lane_result_q_reg[0][14]/D` |

Compared with the previous accepted try7 area point, total LUT, logic LUT, FF,
Fmax, and PMUL wall cycles are unchanged. The self-learning flow is therefore
functionally integrated without adding synthesized area.

## ClaudeCode Ubuntu Handoff

Recommended next Ubuntu 22.04 validation:

1. Keep the same fixture semantics.
   - Use `scripts/hdec/algo/gen_hdc_selflearn_fixture.py`.
   - First reproduce the two checked fixtures above.
2. Build a RISC-V/C intrinsic wrapper around the same hardware primitive sequence.
   - `VWR64` writes query/prototype words.
   - `HSIM` is called once per class to get exact overlap score.
   - C software owns prediction tie-break, top-k self-learning, and final prototype writeback.
3. CVA6/Verilator checks should compare against the fixture, not just pass/fail.
   - Accuracy must match `summary.json`.
   - Update count must match `summary.json`.
   - Final prototype memory must match `final_proto.mem`.
4. ECC regression invariants to keep:
   - PMUL wall cycles stay at `190151`.
   - Existing ECC reduce and PMUL profile tests pass.
   - No ISA-visible HDC/ECC opcode change.

If GCC/Verilator results disagree with Vivado xsim, first check software tie-break
and bit packing order before changing RTL.
