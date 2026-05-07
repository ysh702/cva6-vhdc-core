// =============================================================================
// hdec_xif_pkg.sv — HDEC coprocessor type definitions for CV-X-IF integration
// =============================================================================
// Defines the hdec_op enum (replaces fu_op for HDEC-specific operations),
// TRANS_ID_BITS localparam, and the instruction match table used by the
// CV-X-IF instruction decoder.
// =============================================================================

package hdec_xif_pkg;

    // --- HDEC Operation Codes ---
    typedef enum logic [3:0] {
        HDEC_BIND         = 4'd0,
        HDEC_BUNDLE       = 4'd1,
        HDEC_MATCH        = 4'd2,
        HDEC_INGEST       = 4'd3,
        HDEC_BINARIZE     = 4'd4,
        HDEC_PERMUTE      = 4'd5,
        HDEC_ECC_START    = 4'd6,
        HDEC_ECC_FETCH    = 4'd7,
        HDEC_BUNDLE_ACCUM = 4'd8,
        HDEC_CLEAR_CNT    = 4'd9
    } hdec_op;

    // --- Transaction ID width (matches CVA6 TRANS_ID_BITS) ---
    localparam int unsigned HDEC_TRANS_ID_BITS = 4;

    // --- Lane pipeline owner tags ---
    localparam logic [1:0] OWNER_NONE = 2'd0;
    localparam logic [1:0] OWNER_HDC  = 2'd1;
    localparam logic [1:0] OWNER_ECC  = 2'd2;

    // --- RISC-V Instruction Encoding ---
    // Custom-0 opcode: 7'b0001011
    localparam logic [6:0] OPCODE_HDEC = 7'b0001011;

    // funct7 field
    localparam logic [6:0] F7_HDEC_DEFAULT      = 7'b000_0000;
    localparam logic [6:0] F7_HDEC_BUNDLE_ACCUM = 7'b000_0001;

    // funct3 fields
    localparam logic [2:0] F3_HDEC_BIND      = 3'b000;
    localparam logic [2:0] F3_HDEC_BUNDLE    = 3'b001;
    localparam logic [2:0] F3_HDEC_MATCH     = 3'b010;
    localparam logic [2:0] F3_HDEC_INGEST    = 3'b011;
    localparam logic [2:0] F3_HDEC_BINARIZE  = 3'b100;
    localparam logic [2:0] F3_HDEC_PERMUTE   = 3'b101;
    localparam logic [2:0] F3_HDEC_ECC_START = 3'b110;
    localparam logic [2:0] F3_HDEC_ECC_FETCH = 3'b111;

    // --- XIF Instruction Decoder Types ---
    // copro_issue_resp_t for HDEC (all instructions accept, write back)
    typedef struct packed {
        logic        accept;
        logic [0:0]  writeback;      // WRITEREGFLAGS_T: single-write
        logic [1:0]  register_read;  // READREGFLAGS_T: rs1, rs2
    } hdec_issue_resp_t;

    // opcode_t for HDEC internal pipeline
    typedef hdec_op opcode_t;

    // --- Instruction Table Entry ---
    typedef struct packed {
        logic [31:0] mask;
        logic [31:0] instr;
        hdec_issue_resp_t resp;
        opcode_t opcode;
    } hdec_instr_entry_t;

    // =========================================================================
    // Instruction Match Table
    // =========================================================================
    localparam int unsigned HDEC_NB_INSTR = 10;

    function automatic hdec_instr_entry_t [HDEC_NB_INSTR-1:0] get_hdec_instr_table();
        hdec_instr_entry_t [HDEC_NB_INSTR-1:0] tbl;

        // Common mask: match opcode[6:0]=0001011, funct3[14:12], funct7[31:25]
        //   mask bits: 31:25 (funct7), 14:12 (funct3), 6:0 (opcode)
        //   ignore bits: 24:15 (rs2, rs1), 11:7 (rd)
        logic [31:0] base_mask = 32'hFE00_707F;
        logic [31:0] base_op   = {16'h0000, 2'b00, OPCODE_HDEC};

        // 0: BIND     — funct7=0, funct3=000
        tbl[0].mask  = base_mask;
        tbl[0].instr = base_op | (F7_HDEC_DEFAULT << 25) | (F3_HDEC_BIND << 12);
        tbl[0].resp  = '{accept: 1'b1, writeback: 1'b1, register_read: 2'b01};
        tbl[0].opcode = HDEC_BIND;

        // 1: BUNDLE   — funct7=0, funct3=001
        tbl[1].mask  = base_mask;
        tbl[1].instr = base_op | (F7_HDEC_DEFAULT << 25) | (F3_HDEC_BUNDLE << 12);
        tbl[1].resp  = '{accept: 1'b1, writeback: 1'b1, register_read: 2'b01};
        tbl[1].opcode = HDEC_BUNDLE;

        // 2: MATCH    — funct7=0, funct3=010
        tbl[2].mask  = base_mask;
        tbl[2].instr = base_op | (F7_HDEC_DEFAULT << 25) | (F3_HDEC_MATCH << 12);
        tbl[2].resp  = '{accept: 1'b1, writeback: 1'b1, register_read: 2'b01};
        tbl[2].opcode = HDEC_MATCH;

        // 3: INGEST   — funct7=0, funct3=011
        tbl[3].mask  = base_mask;
        tbl[3].instr = base_op | (F7_HDEC_DEFAULT << 25) | (F3_HDEC_INGEST << 12);
        tbl[3].resp  = '{accept: 1'b1, writeback: 1'b1, register_read: 2'b11};
        tbl[3].opcode = HDEC_INGEST;

        // 4: BINARIZE — funct7=0, funct3=100
        tbl[4].mask  = base_mask;
        tbl[4].instr = base_op | (F7_HDEC_DEFAULT << 25) | (F3_HDEC_BINARIZE << 12);
        tbl[4].resp  = '{accept: 1'b1, writeback: 1'b1, register_read: 2'b01};
        tbl[4].opcode = HDEC_BINARIZE;

        // 5: PERMUTE  — funct7=0, funct3=101
        tbl[5].mask  = base_mask;
        tbl[5].instr = base_op | (F7_HDEC_DEFAULT << 25) | (F3_HDEC_PERMUTE << 12);
        tbl[5].resp  = '{accept: 1'b1, writeback: 1'b1, register_read: 2'b01};
        tbl[5].opcode = HDEC_PERMUTE;

        // 6: ECC_START — funct7=0, funct3=110
        tbl[6].mask  = base_mask;
        tbl[6].instr = base_op | (F7_HDEC_DEFAULT << 25) | (F3_HDEC_ECC_START << 12);
        tbl[6].resp  = '{accept: 1'b1, writeback: 1'b1, register_read: 2'b01};
        tbl[6].opcode = HDEC_ECC_START;

        // 7: ECC_FETCH — funct7=0, funct3=111
        tbl[7].mask  = base_mask;
        tbl[7].instr = base_op | (F7_HDEC_DEFAULT << 25) | (F3_HDEC_ECC_FETCH << 12);
        tbl[7].resp  = '{accept: 1'b1, writeback: 1'b1, register_read: 2'b00};
        tbl[7].opcode = HDEC_ECC_FETCH;

        // 8: CLEAR_CNT — funct7=1, funct3=001
        tbl[8].mask  = base_mask;
        tbl[8].instr = base_op | (F7_HDEC_BUNDLE_ACCUM << 25) | (F3_HDEC_BUNDLE << 12);
        tbl[8].resp  = '{accept: 1'b1, writeback: 1'b1, register_read: 2'b00};
        tbl[8].opcode = HDEC_CLEAR_CNT;

        // 9: BUNDLE_ACCUM — funct7=1, funct3=100
        tbl[9].mask  = base_mask;
        tbl[9].instr = base_op | (F7_HDEC_BUNDLE_ACCUM << 25) | (F3_HDEC_BINARIZE << 12);
        tbl[9].resp  = '{accept: 1'b1, writeback: 1'b1, register_read: 2'b01};
        tbl[9].opcode = HDEC_BUNDLE_ACCUM;

        return tbl;
    endfunction

endpackage
