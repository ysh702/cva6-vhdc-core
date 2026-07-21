# VV25 R31正式回归摘要

来源：`reports/hdec/vv25_r31_final_regression_20260719`中的当前正式日志。下表只记录经核对的成功标记和关键数据；原始仿真日志不提交。

| 测试 | 结果 | 关键证据 |
|---|---|---|
| `xsim_vv25_native_xor1` | PASS | legacy=2048 cycles；ECC diag=2048 cycles；224原生节点；14复用节点 |
| `xsim_ecc_diag_mul_v1` | PASS | 16×16/32×32斜线乘法路径 |
| `xsim_ecc_mul_cycle_count_r31_final` | PASS | `ECC_MUL_CYCLES=184` |
| `xsim_ecc_diag_reduce_map_v1` | PASS | 4096个归约映射向量 |
| `xsim_ecc_reduce_v1` | PASS | ECC模约减 |
| `xsim_ecc_inv_v17` | PASS | ECC求逆 |
| `xsim_ecc_add_v1` | PASS | ECC加法 |
| `xsim_ecc_align_v1` | PASS | ECC对齐 |
| `xsim_ecc_pmul_v18` | PASS | 完整PMUL功能 |
| `xsim_ecc_pmul_profile_v27` | PASS | `PMUL_PROFILE_WALL_CYCLES=166840` |
| `xsim_ecc_pmul_bg_idle_v27` | PASS | `PMUL_BG_IDLE_WALL_CYCLES=166841` |
| `xsim_ecc_pmul_bg_v27` | PASS | 后台PMUL |
| `xsim_ecc_pmul_bg_hdc_loop_v31` | PASS | PMUL/HDC交织wall=167938；HDC等价cycles=1095 |
| `xsim_hdc_full_flow_v20` | PASS | HDC完整流程 |
| `xsim_hdc_selflearn_v1` | PASS | correct=26/32；updates=6 |
| `xsim_hmatch_compare_split` | PASS | 全部compare-split情形 |
| `xsim_hperm_bit_align` | PASS | HPERM位对齐 |
| `xsim_shift_align_bit` | PASS | 共享移位对齐 |
| `xsim_cvxif_smoke_vv24` | PASS | CV-X-IF smoke |

此外，三套Python算法模型均通过8位穷举65536对和至少100000组随机32位测试；`vv25_reuse_structure_check.py`通过8/8结构检查。
