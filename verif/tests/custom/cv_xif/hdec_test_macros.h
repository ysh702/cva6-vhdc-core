// =============================================================================
// hdec_test_macros.h — HDEC custom instruction inline assembly macros
// =============================================================================
// Uses .insn r pseudo-instruction (standard RISC-V assembler) to emit
// R-type custom-0 instructions.  The assembler encodes:
//   funct7[31:25] | rs2[24:20] | rs1[19:15] | funct3[14:12] | rd[11:7] | opcode[6:0]
//
// HDEC opcode: 0x0B (custom-0)
//
// Register encoding in operand_a (rs1 value at runtime):
//   bit 21:15  = binarize threshold
//   bit 13:10  = vd  (VRF destination register index, 0-15)
//   bit  8:5   = vs1 (VRF source register 1 index, 0-15)
//   bit  3:0   = vs2 (VRF source register 2 index, 0-15)
//
// Register encoding in operand_b (rs2 value at runtime):
//   For INGEST: bit 3:0 = VRF register number (0-15)
// =============================================================================

// funct7 values
#define F7_DEFAULT      0
#define F7_BUNDLE_ACCUM 1

// funct3 values
#define F3_BIND      0
#define F3_BUNDLE    1
#define F3_MATCH     2
#define F3_INGEST    3
#define F3_BINARIZE  4
#define F3_PERMUTE   5
#define F3_ECC_START 6
#define F3_ECC_FETCH 7

// ── Macros using .insn r ────────────────────────────────────────────────────
// .insn r opcode, funct3, funct7, rd, rs1, rs2

// BIND: VRF[vd] = VRF[vs1] XOR VRF[vs2]
#define HDEC_BIND(rd,rs1)            .insn r 0x0B, F3_BIND,      F7_DEFAULT,      rd, rs1, zero

// BUNDLE: accumulate XOR into cnt_array
#define HDEC_BUNDLE(rd,rs1)          .insn r 0x0B, F3_BUNDLE,    F7_DEFAULT,      rd, rs1, zero

// MATCH: return popcnt of VRF[vs1] XOR VRF[vs2]
#define HDEC_MATCH(rd,rs1)           .insn r 0x0B, F3_MATCH,     F7_DEFAULT,      rd, rs1, zero

// INGEST: write data from rs1 to VRF[rs2[3:0]]  (needs both rs1 and rs2)
#define HDEC_INGEST(rd,rs1,rs2)      .insn r 0x0B, F3_INGEST,    F7_DEFAULT,      rd, rs1, rs2

// BINARIZE: threshold VRF[vs1], write to VRF[vd] (threshold in rs1[21:15])
#define HDEC_BINARIZE(rd,rs1)        .insn r 0x0B, F3_BINARIZE,  F7_DEFAULT,      rd, rs1, zero

// PERMUTE: circular left shift VRF[vs1] by 1 bit
#define HDEC_PERMUTE(rd,rs1)         .insn r 0x0B, F3_PERMUTE,   F7_DEFAULT,      rd, rs1, zero

// ECC_START: start ECC GF(2^256) multiply, private key in rs1
#define HDEC_ECC_START(rd,rs1)       .insn r 0x0B, F3_ECC_START, F7_DEFAULT,      rd, rs1, zero

// ECC_FETCH: read ECC result (no source operands)
#define HDEC_ECC_FETCH(rd)           .insn r 0x0B, F3_ECC_FETCH, F7_DEFAULT,      rd, zero, zero

// CLEAR_CNT: clear bundle accumulator (funct7=1, funct3=1)
#define HDEC_CLEAR_CNT(rd)           .insn r 0x0B, F3_BUNDLE,    F7_BUNDLE_ACCUM, rd, zero, zero

// BUNDLE_ACCUM: accumulate with vs2 forced to 0 (funct7=1, funct3=4)
#define HDEC_BUNDLE_ACCUM(rd,rs1)    .insn r 0x0B, F3_BINARIZE,  F7_BUNDLE_ACCUM, rd, rs1, zero

// ── Helper macros for VRF address encoding ───────────────────────────────────
#define VRF_ADDR(vd,vs1,vs2)  (((vd) << 10) | ((vs1) << 5) | (vs2))
