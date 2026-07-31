package hdec_vv31_check_pkg;
    import hdec_pkg::*;
    import hdec_vv31_vectors_pkg::*;

    function automatic bit vv31_known64(input logic [63:0] value);
        vv31_known64 = !$isunknown(value);
    endfunction

    function automatic bit vv31_known256(input logic [255:0] value);
        vv31_known256 = !$isunknown(value);
    endfunction

    function automatic bit vv31_known1024(input logic [1023:0] value);
        vv31_known1024 = !$isunknown(value);
    endfunction

    function automatic bit vv31_legal_random_k(input logic [255:0] scalar);
        vv31_legal_random_k =
            (scalar != 0)
            && (scalar < VV31_K233_N)
            && (scalar[255:233] == 0)
            && (scalar != 256'd3);
    endfunction

    function automatic int unsigned vv31_hamming_weight256(
        input logic [255:0] value
    );
        int unsigned count;
        begin
            count = 0;
            for (int bit_index = 0; bit_index < 256; bit_index++)
                count += value[bit_index];
            vv31_hamming_weight256 = count;
        end
    endfunction

endpackage
