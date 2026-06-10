// =============================================================================
// hdec_pkg.sv — HDEC Phase 1 Constants, Types, Opcodes, Instruction Table
// =============================================================================
// HDEC-LiteV-4L64-HV1024: 4 lanes × 64-bit, 1024-bit HDC vectors
// ECC V1 adds raw GF(2) 256x256 diagonal multiplication and shared GF(2) ops.
// =============================================================================

package hdec_pkg;

    // ── Architecture Constants ──────────────────────────────────────────────
    localparam int VRF_ENTRIES  = 64;
    localparam int VRF_WIDTH    = 256;
    localparam int LANE_NUM     = 4;
    localparam int LANE_WIDTH   = 64;
    localparam int HDC_BITS     = 1024;
    localparam int HDC_CHUNKS   = 4;       // VRF entries per HDC hypervector

    // ── Derived Widths ──────────────────────────────────────────────────────
    localparam int VRF_IDX_W = $clog2(VRF_ENTRIES);   // 6
    localparam int VRF_BNK_W = $clog2(LANE_NUM);       // 2

    // ── Owner Tags ──────────────────────────────────────────────────────────
    localparam logic [1:0] OWNER_NONE = 2'd0;
    localparam logic [1:0] OWNER_HDC  = 2'd1;
    localparam logic [1:0] OWNER_ECC  = 2'd2;   // reserved for future ECC

    // ── Controller Status Codes ─────────────────────────────────────────────
    localparam logic [1:0] STATUS_OK              = 2'd0;
    localparam logic [1:0] STATUS_NOT_IMPLEMENTED = 2'd1;
    localparam logic [1:0] STATUS_ERROR           = 2'd2;

    // ── Opcode Enum ─────────────────────────────────────────────────────────
    typedef enum logic [3:0] {
        HDEC_VWR64     = 4'd0,
        HDEC_VRD64     = 4'd1,
        HDEC_HCLR      = 4'd2,
        HDEC_HCNTCLR   = 4'd3,    // was HDEC_BCLR
        HDEC_HCNTADD   = 4'd4,    // was HDEC_BADD
        HDEC_HBIND     = 4'd5,
        HDEC_HPERM     = 4'd6,
        HDEC_HSIM      = 4'd7,
        HDEC_HCNTCLIP  = 4'd8,    // was HDEC_CLIP
        HDEC_HMATCH    = 4'd9,    // was HDEC_HSEARCH
        HDEC_VADDR     = 4'd10,
        HDEC_ECC_MUL   = 4'd11,   // ECC V1 raw GF(2) 256x256 diagonal multiply
        HDEC_ECC_STATUS= 4'd12,   // ECC V1 status/debug read
        HDEC_ECC_ADD   = 4'd13,   // ECC V1 GF(2) add/sub via shared XOR lane
        HDEC_ECC_ALIGN = 4'd14    // ECC V1 256-bit field row align via shared HPERM lane
    } hdec_op_t;

    // ── UOP Pipeline Types ─────────────────────────────────────────────────
    typedef enum logic [2:0] {
        UOP_IDLE             = 3'd0,
        UOP_HBIND_CHUNK      = 3'd1,
        UOP_HSIM_CHUNK       = 3'd2,
        UOP_HMATCH_CHUNK     = 3'd3,
        UOP_HCNTADD_SUBGROUP = 3'd4,
        UOP_HCNTCLIP_READ    = 3'd5,
        UOP_HPERM_CHUNK      = 3'd6
    } hdec_uop_type_e;

    typedef struct packed {
        // ── Control ──
        logic                   valid;
        hdec_uop_type_e         op_type;

        // ── VRF Addressing ──
        logic [VRF_IDX_W-1:0]   src0_addr;
        logic [VRF_IDX_W-1:0]   src1_addr;
        logic [VRF_IDX_W-1:0]   dst_addr;

        // ── Iteration ──
        logic [1:0]             chunk_idx;
        logic [1:0]             subgroup_idx;

        // ── Class / Search ──
        logic [2:0]             class_idx;

        // ── Compute Parameters ──
        logic [3:0]             perm_nibble;

        // ── Compute Enables ──
        logic                   use_counter;
        logic                   use_clip;
        logic                   use_shift;

        // ── Op Type Tags ──
        logic                   is_last_class;
    } hdec_uop_t;

    // ── RISC-V Custom-0 Opcode ──────────────────────────────────────────────
    localparam logic [6:0] OPCODE_HDEC = 7'b0001011;   // 0x0B

    // ── funct7 Values ───────────────────────────────────────────────────────
    localparam logic [6:0] F7_PHASE1_BASE   = 7'b000_0010;  // vwr64..hsim
    localparam logic [6:0] F7_PHASE1_EXT    = 7'b000_0011;  // clip, hsearch

    // ── funct3 Values ───────────────────────────────────────────────────────
    localparam logic [2:0] F3_VWR64    = 3'b000;
    localparam logic [2:0] F3_VRD64    = 3'b001;
    localparam logic [2:0] F3_HCLR     = 3'b010;
    localparam logic [2:0] F3_HCNTCLR  = 3'b011;
    localparam logic [2:0] F3_HCNTADD  = 3'b100;
    localparam logic [2:0] F3_HBIND    = 3'b101;
    localparam logic [2:0] F3_HPERM    = 3'b110;
    localparam logic [2:0] F3_HSIM     = 3'b111;
    localparam logic [2:0] F3_HCNTCLIP = 3'b000;   // funct7=000_0011
    localparam logic [2:0] F3_HMATCH   = 3'b001;   // funct7=000_0011
    localparam logic [2:0] F3_VADDR    = 3'b010;   // funct7=000_0011
    localparam logic [2:0] F3_ECC_MUL  = 3'b011;   // funct7=000_0011
    localparam logic [2:0] F3_ECC_STATUS = 3'b100; // funct7=000_0011
    localparam logic [2:0] F3_ECC_ADD  = 3'b101;   // funct7=000_0011
    localparam logic [2:0] F3_ECC_ALIGN = 3'b110;  // funct7=000_0011

    // ── CV-X-IF Issue Response Struct ───────────────────────────────────────
    typedef struct packed {
        logic        accept;
        logic [0:0]  writeback;
        logic [1:0]  register_read;   // 00=none, 01=rs1, 10=rs2, 11=both
    } hdec_issue_resp_t;

    // ── Instruction Table Entry ─────────────────────────────────────────────
    typedef struct packed {
        logic [31:0]        mask;
        logic [31:0]        instr;
        hdec_issue_resp_t   resp;
        hdec_op_t           opcode;
    } hdec_instr_entry_t;

    // ── Number of Instructions in Table ─────────────────────────────────────
    localparam int HDEC_NB_INSTR = 15;

    // ── Instruction Table Generator ─────────────────────────────────────────
    function automatic hdec_instr_entry_t [HDEC_NB_INSTR-1:0] get_hdec_instr_table();
        logic [31:0] mask = 32'hFE00_707F;  // opcode+funct3+funct7 are key bits
        logic [31:0] base = {16'h0, 2'b00, OPCODE_HDEC};
        hdec_instr_entry_t [HDEC_NB_INSTR-1:0] tbl;

        // 0: hdec_vwr64  (funct7=000_0010, funct3=000, rs1+rs2)
        tbl[0].mask   = mask;
        tbl[0].instr  = base | (F7_PHASE1_BASE << 25) | (F3_VWR64 << 12);
        tbl[0].resp   = '{accept:1'b1, writeback:1'b1, register_read:2'b11};
        tbl[0].opcode = HDEC_VWR64;

        // 1: hdec_vrd64  (funct7=000_0010, funct3=001, rs1 only)
        tbl[1].mask   = mask;
        tbl[1].instr  = base | (F7_PHASE1_BASE << 25) | (F3_VRD64 << 12);
        tbl[1].resp   = '{accept:1'b1, writeback:1'b1, register_read:2'b01};
        tbl[1].opcode = HDEC_VRD64;

        // 2: hdec_hclr     (funct7=000_0010, funct3=010, no reg read)
        tbl[2].mask   = mask;
        tbl[2].instr  = base | (F7_PHASE1_BASE << 25) | (F3_HCLR << 12);
        tbl[2].resp   = '{accept:1'b1, writeback:1'b1, register_read:2'b00};
        tbl[2].opcode = HDEC_HCLR;

        // 3: hdec_hcntclr  (funct7=000_0010, funct3=011, no reg read)
        tbl[3].mask   = mask;
        tbl[3].instr  = base | (F7_PHASE1_BASE << 25) | (F3_HCNTCLR << 12);
        tbl[3].resp   = '{accept:1'b1, writeback:1'b1, register_read:2'b00};
        tbl[3].opcode = HDEC_HCNTCLR;

        // 4: hdec_hcntadd  (funct7=000_0010, funct3=100, rs1)
        tbl[4].mask   = mask;
        tbl[4].instr  = base | (F7_PHASE1_BASE << 25) | (F3_HCNTADD << 12);
        tbl[4].resp   = '{accept:1'b1, writeback:1'b1, register_read:2'b01};
        tbl[4].opcode = HDEC_HCNTADD;

        // 5: hdec_hbind  (funct7=000_0010, funct3=101, rs1)
        tbl[5].mask   = mask;
        tbl[5].instr  = base | (F7_PHASE1_BASE << 25) | (F3_HBIND << 12);
        tbl[5].resp   = '{accept:1'b1, writeback:1'b1, register_read:2'b01};
        tbl[5].opcode = HDEC_HBIND;

        // 6: hdec_hperm  (funct7=000_0010, funct3=110, rs1)
        tbl[6].mask   = mask;
        tbl[6].instr  = base | (F7_PHASE1_BASE << 25) | (F3_HPERM << 12);
        tbl[6].resp   = '{accept:1'b1, writeback:1'b1, register_read:2'b01};
        tbl[6].opcode = HDEC_HPERM;

        // 7: hdec_hsim   (funct7=000_0010, funct3=111, rs1)
        tbl[7].mask   = mask;
        tbl[7].instr  = base | (F7_PHASE1_BASE << 25) | (F3_HSIM << 12);
        tbl[7].resp   = '{accept:1'b1, writeback:1'b1, register_read:2'b01};
        tbl[7].opcode = HDEC_HSIM;

        // 8: hdec_hcntclip (funct7=000_0011, funct3=000, rs1)
        tbl[8].mask   = mask;
        tbl[8].instr  = base | (F7_PHASE1_EXT << 25) | (F3_HCNTCLIP << 12);
        tbl[8].resp   = '{accept:1'b1, writeback:1'b1, register_read:2'b01};
        tbl[8].opcode = HDEC_HCNTCLIP;

        // 9: hdec_hmatch   (funct7=000_0011, funct3=001, rs1)
        tbl[9].mask   = mask;
        tbl[9].instr  = base | (F7_PHASE1_EXT << 25) | (F3_HMATCH << 12);
        tbl[9].resp   = '{accept:1'b1, writeback:1'b1, register_read:2'b01};
        tbl[9].opcode = HDEC_HMATCH;

        // 10: hdec_vaddr  (funct7=000_0011, funct3=010, rs1)
        tbl[10].mask   = mask;
        tbl[10].instr  = base | (F7_PHASE1_EXT << 25) | (F3_VADDR << 12);
        tbl[10].resp   = '{accept:1'b1, writeback:1'b1, register_read:2'b01};
        tbl[10].opcode = HDEC_VADDR;

        // 11: hdec_ecc_mul (funct7=000_0011, funct3=011, rs1)
        tbl[11].mask   = mask;
        tbl[11].instr  = base | (F7_PHASE1_EXT << 25) | (F3_ECC_MUL << 12);
        tbl[11].resp   = '{accept:1'b1, writeback:1'b1, register_read:2'b01};
        tbl[11].opcode = HDEC_ECC_MUL;

        // 12: hdec_ecc_status (funct7=000_0011, funct3=100, no reg read)
        tbl[12].mask   = mask;
        tbl[12].instr  = base | (F7_PHASE1_EXT << 25) | (F3_ECC_STATUS << 12);
        tbl[12].resp   = '{accept:1'b1, writeback:1'b1, register_read:2'b00};
        tbl[12].opcode = HDEC_ECC_STATUS;

        // 13: hdec_ecc_add (funct7=000_0011, funct3=101, rs1)
        tbl[13].mask   = mask;
        tbl[13].instr  = base | (F7_PHASE1_EXT << 25) | (F3_ECC_ADD << 12);
        tbl[13].resp   = '{accept:1'b1, writeback:1'b1, register_read:2'b01};
        tbl[13].opcode = HDEC_ECC_ADD;

        // 14: hdec_ecc_align (funct7=000_0011, funct3=110, rs1)
        tbl[14].mask   = mask;
        tbl[14].instr  = base | (F7_PHASE1_EXT << 25) | (F3_ECC_ALIGN << 12);
        tbl[14].resp   = '{accept:1'b1, writeback:1'b1, register_read:2'b01};
        tbl[14].opcode = HDEC_ECC_ALIGN;

        return tbl;
    endfunction

endpackage
