# HDEC TCAS-I Framing

## One-Sentence Argument

HDEC shows that binary HDC training/inference and binary-field ECC arithmetic can be organized as a unified GF(2) bit-matrix computation, enabling a shared packet-based execution structure that supports edge learning and security with less duplicated hardware than separate accelerators.

## Paper Identity

Frame HDEC as a shared/fusion accelerator with an algorithm-hardware co-design layer.

- The HDC subsystem supports the target binary HDC training, self-learning/update, and inference flow.
- Its paper role is to provide the learning-side bit-matrix substrate, not to challenge every standalone HDC processor.
- The ECC subsystem supports complete GF(2^233) field arithmetic and scalar point multiplication.
- The central contribution is the unified data representation and shared execution structure across HDC and ECC.

Do not narrate that the engineering began from HDCU or from a particular RTL version. Present the final research logic.

## Main Story Line

1. Edge nodes need local learning/inference and public-key security under one resource budget.
2. Separate HDC and ECC accelerators duplicate state, bit-level operators, accumulation/reduction, and writeback boundaries.
3. Binary HDC and binary-field ECC differ in task semantics but share a GF(2) bit-matrix computational form.
4. HDEC defines a unified GF(2) bit-matrix data structure and packet flow.
5. HDC primitives and ECC polynomial arithmetic enter a shared state, bit-product/reduction, GF(2) accumulation, and writeback substrate.
6. Karatsuba-diagonal multiplication and diagonal-level on-the-fly modular reduction keep ECC PMUL inside this substrate rather than adding an independent wide product/reduction path.
7. Measurements demonstrate functionality, private/shared area, timing, PMUL cycles, and savings relative to complete separate accelerators.

## Canonical Terminology

| Concept | Chinese working term | English term |
|---|---|---|
| HDC | 超维计算 | hyperdimensional computing (HDC) |
| ECC | 椭圆曲线密码 | elliptic curve cryptography (ECC) |
| binary field | 二元域 | binary field |
| GF(2) | 二元有限域 GF(2) | GF(2) |
| unified representation | 统一 GF(2) 位矩阵数据结构 | unified GF(2) bit-matrix data representation |
| shared substrate | 共享 GF(2) 位矩阵执行结构 | shared GF(2) bit-matrix execution structure |
| 4x64 packet | 四路六十四位数据包 | four-lane 64-bit packet |
| row representation | 位矩阵行级表示 | row-level bit-matrix representation |
| bit product and reduction | 位积生成与归约 | bit-product generation and reduction |
| XOR accumulation | GF(2) 异或累加 | GF(2) XOR accumulation |
| polynomial modular multiplication | 多项式模乘 | polynomial modular multiplication |
| diagonal folding | 斜线级边算边模 | diagonal-level on-the-fly modular reduction |

Expand HDC and ECC at first use. Hardware-standard abbreviations such as FPGA, LUT, FF, BRAM, and DSP do not require expansion for the target circuit readership unless the journal template demands it.

## Preferred Contribution Order

1. **Unified data representation:** formulate binary HDC and binary-field ECC as GF(2) bit-matrix packet flows.
2. **Shared execution structure:** share vector/packet state, bit-product/reduction, GF(2) accumulation, and writeback while supporting both complete target workflows.
3. **ECC mapping and reduction:** map GF(2^233) polynomial modular multiplication into the common substrate and integrate diagonal-level on-the-fly modular reduction.
4. **Implementation evidence:** validate HDC, ECC, resource sharing, private area, timing, PMUL cycles, constant-time behavior, and separate-accelerator savings.

The fixed sparse overlapping prototype method is a supporting HDC-side transformation. Do not place it before the unified representation unless the final paper is explicitly repositioned as an HDC algorithm paper.

## What to Claim When Supported

- HDEC implements a compact binary HDC training/inference substrate for the target model.
- Binary-field ECC polynomial arithmetic uses the unified GF(2) bit-matrix representation.
- HDC and ECC share packet state, bit-product/reduction, GF(2) accumulation, and writeback resources.
- ECC modular multiplication is integrated into the shared dataflow rather than implemented as a fully independent multiplier datapath.
- Diagonal-level on-the-fly modular reduction avoids waiting for a complete wide product before all reduction work begins.
- Full HDEC uses fewer resources than complete separate HDC and ECC accelerators under equivalent interface assumptions.

## What Not to Claim

- HDEC replaces every general-purpose or application-specific HDC accelerator.
- Every bit of HDEC hardware is shared.
- ECC-private area equals full HDEC minus a smaller HDC-only synthesis without hierarchy analysis.
- The design is faster because scalar zero or special values are skipped.
- A common wrapper or terminology alone proves hardware reuse.
- FPGA LUT and ASIC gate-area results are directly interchangeable.

## Introduction Boundary

The Introduction should name the unified data representation, shared execution structure, polynomial modular multiplication, and diagonal-level reduction. Move these details later:

- four-lane packet widths and register semantics;
- leaf/sub/group terminology;
- row-tile implementation;
- FSM states and cycle-level issue/capture behavior;
- exact fold templates and writeback muxes.

## Required Evidence Map

| Claim | Required evidence |
|---|---|
| Complete HDC support | supported operations, train/update/infer workflow, accuracy/function tests |
| Complete ECC support | field-operation and PMUL golden checks, curve/field definition |
| Shared data representation | mapping equations/figure and common packet/state flow |
| Shared hardware | architecture hierarchy, shared-resource buckets, private-area accounting |
| Diagonal-level reduction | algorithm/dataflow figure, correctness, cycle/area ablation |
| Constant time | representative scalar traces and fixed operation counts |
| Area saving | full HDEC versus complete separate accelerators under matched scope |
