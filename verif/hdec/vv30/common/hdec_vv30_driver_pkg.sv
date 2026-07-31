package hdec_vv30_driver_pkg;
    import hdec_pkg::*;

    function automatic logic [63:0] vv30_hperm_operand(
        input logic [3:0] dst_slot,
        input logic [3:0] src_slot,
        input logic [9:0] rotate
    );
        begin
            vv30_hperm_operand = '0;
            vv30_hperm_operand[3:0]  = dst_slot;
            vv30_hperm_operand[7:4]  = src_slot;
            vv30_hperm_operand[17:8] = rotate;
        end
    endfunction

    function automatic logic [63:0] vv30_vaddr_operand(
        input logic [1:0] bank,
        input logic [5:0] row
    );
        vv30_vaddr_operand = {56'd0, bank, row};
    endfunction

endpackage
