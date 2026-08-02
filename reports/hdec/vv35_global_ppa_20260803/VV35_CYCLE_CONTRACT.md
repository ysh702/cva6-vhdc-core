# VV35 周期及功能合同

## 1. 冻结周期

VV35 不改变任务调度、状态推进或外部请求响应时序。最终候选与 VV35-0 使用相同随机向量及测试合同，得到：

| 对象 | VV35-0 | VV35 候选 | 变化 |
|---|---:|---:|---:|
| K-233 PMUL | 146908 | 146908 | 0 |
| GF(2) 域乘 | 179 | 179 | 0 |
| GF(2) 乘加 | 179 | 179 | 0 |
| 合法 HPERM | 58 | 58 | 0 |
| 四类普通 HMATCH | 117 | 117 | 0 |
| HDC episode | 3162 | 3162 | 0 |
| HMATCH 交织 wall | 200144 | 200144 | 0 |
| HMATCH 交织 PMUL service | 147364 | 147364 | 0 |

四个新生成的合法 K-233 标量的汉明重量分别为 103、116、104、116，PMUL 均为 146908 cycles。GF 乘加的 4096 组随机输入全部通过，域乘与乘加均为 179 cycles，临时写回为 0。

## 2. HMATCH 交织合同

最终候选保持 VV33 的固定工作量及事件计数：

| 指标 | 结果 |
|---|---:|
| 交织期间完成 HMATCH | 1632 |
| 串行固定工作量 | 337853 cycles |
| 交织 wall | 200144 cycles |
| 节省周期 | 137709 cycles |
| 周期下降 | 40.76% |
| 加速比 | 1.688x |
| 理想差距收敛 | 93.73% |
| 接受/响应 | 1177/1177 |
| 位矩阵/POPCOUNT 事件 | 18832/18832 |
| 数据/控制重叠 | 21811/14560 |
| 资源配对事件 | 47080 |
| 所有共享资源冲突 | 0 |

两种交织开关配置均可编译。smoke 对照中串行与交织固定工作量均通过，交织配置产生 8 次平方读取重叠、8 次平方写回重叠，矩阵、XOR0、payload 及 VRF 读写冲突均为 0。

## 3. 最终验证证据

- 四 K 及 VV30 stage3：`tmp/hdec_logs/vv35/final_stage3_20260803/run_manifest.json`
- HMATCH 精确合同：`tmp/hdec_logs/vv35/final_hmatch_exact_20260803/run_manifest.json`
- 交织开关 smoke：`tmp/hdec_logs/vv35/final_vv33_on_off_20260803/run_manifest.json`
- VV31 现存合同：`tmp/hdec_logs/vv35/final_vv31_stage_existing/run_manifest.json`
- ECC ADD：`tmp/hdec_logs/vv35/final_ecc_add/xsim_ecc_add_v1/xsim.log`
- ECC REDUCE：`tmp/hdec_logs/vv35/final_ecc_reduce/xsim_ecc_reduce_v1/xsim.log`
- ECC INV：`tmp/hdec_logs/vv35/final_ecc_inv/xsim_ecc_inv_v17/xsim.log`

VV30 stage3 清单的总体字段为 `FAIL`，原因不是功能失败。`hperm_contract` 的固定 PASS 文本包含正则字符，Runner 未进行转义，因而把 Vivado 的 “Pass Through NonSizing Optimizer” 误计为第二个 PASS。该问题在旧 VV31 基线中同样存在。HPERM 本身完成全部 1024 种旋转编码、256 组槽对并输出唯一功能 PASS。

VV31 stage 仅有五个现存测试源，五项均通过。另有四个登记测试源缺失，因此该层只记为 `NO_DECISION`，不表述为完整 VV31 stage 通过。
