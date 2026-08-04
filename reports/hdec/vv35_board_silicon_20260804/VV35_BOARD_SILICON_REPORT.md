# VV35 ZYNQ 板级验证报告（2026-08-04）

## 结论

VV35 的 standalone `hdec_top` 板级端点已在连接的 ZYNQ-7020 上完成真实硅片功能与周期验证。最终实现、下载和 VIO 采集均使用 Vivado 2024.2。5 轮连续重复、每轮 3 个场景，共 15/15 个场景通过脚本的逐字段 fail-fast 检查。

该结论资格化的是板上功能、结果和周期；它不是 CVA6 软件集成结果，也不是开发板电源轨的物理功耗测量。当前设计没有把 `metric_active` 引到经确认的无负载测试点，板上也没有可读的电流测量通道，因此不能从本轮 VIO 运行声明物理功率或能量。

`physical_rail_power=NOT_MEASURED`；`physical_rail_energy=NOT_MEASURED`。

## 冻结对象

- 分支：`VV35`
- 被测核心 RTL 基线提交：`498e957761d562030b67c68cb13e60bcdfd4da0c`；运行时与 `origin/VV35` 一致
- RTL：VV35 默认参数的 standalone `hdec_top`；核心 RTL 未修改
- 器件：`xc7z020clg400-2`
- 工具：Vivado v2024.2，Build 5239630
- 硬件目标：`localhost:3121/xilinx_tcf/Digilent/C3054C71ABCD`
- 工作负载：1 次 K-233 PMUL + 1632 次四类别 HMATCH
- 生成预装载文件 SHA-256：`81a1da931fb70e439b66a198d72df5300a165d672fbd2a1cc65fef3616ec421e`

## 最终布局布线

| 指标 | 结果 |
|---|---:|
| 目标时钟 | 200 MHz / 5.000 ns |
| WNS / TNS | +0.064 ns / 0.000 ns |
| WHS / THS | +0.031 ns / 0.000 ns |
| Setup/Hold failing endpoints | 0 / 0 |
| Unconstrained internal endpoints | 0 |
| Fully routed nets | 10691 / 10691 |
| Routing errors | 0 |
| 全板 Slice LUT / FF | 7302 / 5435 |
| HDEC 层级 Slice LUT / FF | 4738 / 1513 |
| HDEC 层级 BRAM / DSP | 4 / 0 |

bitstream 写出前 DRC 为 0 Error，但不能表述为零告警：报告包含 27 个 Warning，其中 20 个为 HDEC BRAM 地址/控制寄存器异步复位相关的 `REQP-1839`，另有 standalone PL 未实例化 PS7 的 `ZPS7-1` 和 debug-hub/布局告警。Methodology 报告还有 8 个 Warning（4 个 debug-hub LUT 异步复位、4 个 BRAM 输出寄存器未并入）。这些没有阻止时序收敛、完整路由或 bitstream 生成，但应保留在证据边界中。

## 实板结果

每个场景都强制检查：请求模式与实际模式、sequence 单调递增、snapshot valid、pass/fail、idle/busy/metric、phase、预装载数、错误计数/代码、固定周期窗、HMATCH 完成数、自然 HMATCH 完成周期、最终 HMATCH 值和 ECC 状态字。

| 场景 | 固定窗口周期 | 200 MHz 时间 | 自然 HMATCH 完成周期 | HMATCH 数 | 预装载 | 错误 | 结果 |
|---|---:|---:|---:|---:|---:|---:|---|
| INTERLEAVED | 200144 | 1.000720 ms | 200114 | 1632 | 112 | 0 | 5/5 PASS |
| SERIAL | 337853 | 1.689265 ms | 337853 | 1632 | 112 | 0 | 5/5 PASS |
| CLOCKED_IDLE | 2000000 | 10.000000 ms | 0 | 0 | 112 | 0 | 5/5 PASS |

两个活动场景均得到最后 HMATCH `0x1f9` 和最终状态 `0x48`。交织相对串行减少 137709 周期，即 40.760%；等效加速比为 1.68805 倍。

最终读取的 SysMon 值为 43.7 °C、VCCINT 0.993 V、VCCAUX 1.778 V、VCCBRAM 0.993 V。SysMon 没有提供电流，因此这些电压/温度值不能转换为板级功率。

## 功耗与能量口径

已有的 VV35 FPGA 功耗主证据仍是同一工作负载的布局布线后门级 SAIF 活动回标，不是本轮 VIO 的物理板卡测量：

| 指标 | SERIAL | INTERLEAVED | 变化 |
|---|---:|---:|---:|
| 平均总功率 | 0.235 W | 0.285 W | +21.277% |
| 平均动态功率 | 0.130 W | 0.180 W | +38.462% |
| 总能量 | 0.396977 mJ | 0.285205 mJ | -28.156% |
| 动态能量 | 0.219604 mJ | 0.180130 mJ | -17.975% |

该 SAIF 直接标注 4139/7284 个设计网络（56.82%，Vivado 四舍五入为 57%），confidence 为 High；未直接标注的网络仍由概率传播。因此正确表述是“平均功率升高，但任务时间缩短更多，估算总能量和动态能量下降”。

最终板级工程产生的 `power_vectorless_reference_only.rpt` 没有 SAIF，内部活动覆盖低于 25%，且复位活动有准确性警告，只能作为工程参考，不能写入测量结果。

若要补齐物理板级功率/能量，必须先把 `metric_active` 引到经原理图确认的无负载测试点，并用能分轨采样电流的仪器采集 SERIAL、INTERLEAVED 和 CLOCKED_IDLE 的相同轨道、相同环境、配对重复波形；禁止用 LED 标记，因为 LED 电流会污染窗口能量。

## 证据与哈希

- bitstream SHA-256：`c06dce529c37c28108b36b727170688a98db22f27c53f37a25e40567d3051232`
- LTX SHA-256：`ff85d80e5707fa02af3b59f0b179b8634dc348a74375f00bb179a0b0ca368752`
- routed DCP SHA-256：`c82cdf9c916f7546a047722e58fe6d3bed056e27c973c7ff728981647bea534f`
- 5 轮 CSV SHA-256：`06b282b32adbf13efe1d7168f16475ae212ca1ff84fd8cea2061dfb6eb1de975`
- 5 轮硬件日志 SHA-256：`87aaf61ca83c58eef228a5efd73f7b57af320d535e2bb71d6c37e93a5e31c7ea`
- timing report SHA-256：`d543a1c34ad0100861d2e91b92bc547a10e768d9cac1f1cb8591c40435780b83`

5 轮逐场景结果的仓库副本为 `board_results_5trials_validated.csv`；它与上述原始 CSV 逐字段一致，提交时仅规范化为 LF 行尾。原始 bitstream、LTX、DCP 和完整 Vivado 报告未纳入 Git，它们仍位于 `H:/CVA6-HDEC/build/vv35_zynq7020_board_final_20260804`。活动回标功耗报告位于 `reports/hdec/vv35_eval_gate_saif_full_sdf_20260803`。
