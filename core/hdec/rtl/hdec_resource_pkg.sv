// =============================================================================
// hdec_resource_pkg.sv — HDEC Resource Definitions
// =============================================================================
// Defines VRF address space layout, bank mapping, HDC vector slot allocation,
// bundle accumulator slot allocation, and ECC reserved slot allocation.
// RTL does NOT hardcode HV0=VRF[0:3] — it only references base index + offset.
// The mapping convention is documented in docs/hdec/data_mapping.md.
// =============================================================================

package hdec_resource_pkg;
    import hdec_pkg::*;

    // ── VRF Layout Constants ────────────────────────────────────────────────
    //     VRF[ 0: 3] : HDC vector slot 0 (1024-bit = 4 × 256-bit entries)
    //     VRF[ 4: 7] : HDC vector slot 1
    //     VRF[ 8:11] : HDC vector slot 2
    //     VRF[12:15] : HDC vector slot 3
    //     VRF[16:31] : Reserved HDC vector slots 4-7
    //     VRF[32:47] : Bundle accumulator (16 entries × 256-bit each for 4-bit counters)
    //     VRF[48:55] : Reserved (HDC scratch / future expansion)
    //     VRF[56:63] : ECC reserved slots (8 × 256-bit for X1/Z1/X2/Z2/scratch)
    // ────────────────────────────────────────────────────────────────────────

    // HDC vector: 4 contiguous VRF entries = 1024-bit hypervector
    localparam int HDC_VEC_ENTRIES = HDC_CHUNKS;        // 4
    localparam int HDC_VEC_COUNT   = VRF_ENTRIES / 8;   // 8 vectors max

    // Bundle accumulator: 16 contiguous VRF entries = 1024 × 4-bit counters
    localparam int BUNDLE_ENTRIES  = 16;
    localparam int BUNDLE_BASE     = VRF_ENTRIES / 2;   // VRF[32]

    // ECC reserved: 8 entries at top of VRF
    localparam int ECC_ENTRIES     = 8;
    localparam int ECC_BASE        = VRF_ENTRIES - ECC_ENTRIES;  // VRF[56]

    // ── hclr Parameters ─────────────────────────────────────────────────────
    // hclr clears one HDC vector slot: base index + 4 entries
    localparam int HCLR_CLEAR_ENTRIES = HDC_VEC_ENTRIES;        // 4

    // ── bclr Parameters ─────────────────────────────────────────────────────
    // bclr clears one bundle accumulator slot: base index + 16 entries
    localparam int BCLR_CLEAR_ENTRIES = BUNDLE_ENTRIES;         // 16

    // ── Bank Mapping ───────────────────────────────────────────────────────
    // Each Lane[0:3] corresponds to one VRF bank:
    //   Lane 0 ↔ bank 0 (bits  63:0   of each 256-bit VRF entry)
    //   Lane 1 ↔ bank 1 (bits 127:64)
    //   Lane 2 ↔ bank 2 (bits 191:128)
    //   Lane 3 ↔ bank 3 (bits 255:192)
    function automatic logic [VRF_BNK_W-1:0] lane_to_bank(int lane_id);
        return VRF_BNK_W'(lane_id);
    endfunction

    // ── VRF Address Encoding ───────────────────────────────────────────────
    // vwr64/vrd64: bank = operand[7:6], entry index = operand[5:0]
    function automatic logic [VRF_IDX_W-1:0] get_vrf_entry(logic [63:0] operand);
        return operand[VRF_IDX_W-1:0];
    endfunction

    function automatic logic [VRF_BNK_W-1:0] get_vrf_bank(logic [63:0] operand);
        return operand[7:6];
    endfunction

endpackage
