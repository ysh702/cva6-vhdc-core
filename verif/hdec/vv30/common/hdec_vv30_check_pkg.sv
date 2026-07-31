package hdec_vv30_check_pkg;

    function automatic bit vv30_known64(input logic [63:0] value);
        vv30_known64 = !$isunknown(value);
    endfunction

    function automatic bit vv30_known233(input logic [232:0] value);
        vv30_known233 = !$isunknown(value);
    endfunction

    function automatic int unsigned vv30_hamming_weight256(
        input logic [255:0] value
    );
        int unsigned count;
        begin
            count = 0;
            for (int bit_idx = 0; bit_idx < 256; bit_idx++)
                count += value[bit_idx];
            vv30_hamming_weight256 = count;
        end
    endfunction

endpackage
