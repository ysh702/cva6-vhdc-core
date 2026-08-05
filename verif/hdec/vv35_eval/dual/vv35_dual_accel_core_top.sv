// Independent HDC+ECC accelerator for VV35 PPA evaluation.
//
// The HDC and ECC engines are deliberately instantiated as independent
// hdec_top instances.  Consequently, each engine retains its own VRF and
// compute datapath.  Only the narrow command/response interface is shared.
module vv35_dual_accel_core_top import hdec_pkg::*; #(
    parameter bit ECC_STATUS_CYCLE_COUNT = 1'b0,
    parameter bit ECC_DEBUG_FIELD_OPS    = 1'b0,
    parameter bit ECC_PMUL_RESIDUE_SEEDING = 1'b1,
    parameter bit ECC_PMUL_AFFINE_FACTORING = 1'b1,
    parameter bit ECC_INV_SQUARE_REDIRECT = 1'b1,
    parameter bit ECC_PMUL_DBL_FROBENIUS = 1'b1,
    parameter bit ECC_PMUL_ADD_Z_FORWARD = 1'b1
) (
    input  logic        clk_i,
    input  logic        rst_ni,
    input  logic        valid_i,
    output logic        ready_o,
    input  hdec_op_t    operator_i,
    input  logic [63:0] operand_a_i,
    input  logic [63:0] operand_b_i,
    output logic        valid_o,
    output logic [63:0] result_o
);

    typedef enum logic [1:0] {
        ROUTE_HDC  = 2'd0,
        ROUTE_ECC  = 2'd1,
        ROUTE_BOTH = 2'd2
    } route_e;

    logic hdc_ready;
    logic hdc_valid;
    logic [63:0] hdc_result;
    logic ecc_ready;
    logic ecc_valid;
    logic [63:0] ecc_result;

    logic hdc_req_valid;
    logic ecc_req_valid;
    logic accept;
    route_e input_route;

    logic busy_q;
    route_e active_route_q;
    route_e last_compute_owner_q;
    logic wait_hdc_q;
    logic wait_ecc_q;
    logic [63:0] hdc_result_q;
    logic [63:0] ecc_result_q;

    function automatic logic is_hdc_compute(input hdec_op_t op,
                                             input logic [63:0] operand_a);
        case (op)
            HDEC_HCLR,
            HDEC_HCNTCLR,
            HDEC_HCNTADD,
            HDEC_HBIND,
            HDEC_HSIM,
            HDEC_HCNTCLIP,
            HDEC_HMATCH: is_hdc_compute = 1'b1;
            HDEC_HPERM:  is_hdc_compute = !operand_a[18];
            default:     is_hdc_compute = 1'b0;
        endcase
    endfunction

    function automatic logic is_ecc_compute(input hdec_op_t op,
                                             input logic [63:0] operand_a);
        case (op)
            HDEC_ECC_MUL,
            HDEC_ECC_STATUS,
            HDEC_ECC_ADD,
            HDEC_ECC_ALIGN,
            HDEC_ECC_REDUCE: is_ecc_compute = 1'b1;
            HDEC_HPERM:      is_ecc_compute = operand_a[18];
            default:         is_ecc_compute = 1'b0;
        endcase
    endfunction

    always_comb begin
        // Address and writes are mirrored so both private VRFs observe the
        // same host-visible initialization stream.  Reads select the VRF of
        // the most recently issued compute command; reset defaults to HDC.
        if ((operator_i == HDEC_VADDR) || (operator_i == HDEC_VWR64)) begin
            input_route = ROUTE_BOTH;
        end else if (operator_i == HDEC_VRD64) begin
            input_route = last_compute_owner_q;
        end else if (is_ecc_compute(operator_i, operand_a_i)) begin
            input_route = ROUTE_ECC;
        end else begin
            input_route = ROUTE_HDC;
        end
    end

    always_comb begin
        case (input_route)
            ROUTE_HDC:  ready_o = !busy_q && hdc_ready;
            ROUTE_ECC:  ready_o = !busy_q && ecc_ready;
            ROUTE_BOTH: ready_o = !busy_q && hdc_ready && ecc_ready;
            default:    ready_o = 1'b0;
        endcase
    end

    assign accept        = valid_i && ready_o;
    assign hdc_req_valid = accept && ((input_route == ROUTE_HDC) ||
                                      (input_route == ROUTE_BOTH));
    assign ecc_req_valid = accept && ((input_route == ROUTE_ECC) ||
                                      (input_route == ROUTE_BOTH));

    always_comb begin
        valid_o  = busy_q
                   && (!wait_hdc_q || hdc_valid)
                   && (!wait_ecc_q || ecc_valid);
        unique case (active_route_q)
            ROUTE_HDC:
                result_o = hdc_valid ? hdc_result : hdc_result_q;
            ROUTE_ECC:
                result_o = ecc_valid ? ecc_result : ecc_result_q;
            ROUTE_BOTH:
                result_o = (hdc_valid ? hdc_result : hdc_result_q) |
                           (ecc_valid ? ecc_result : ecc_result_q);
            default:
                result_o = '0;
        endcase
    end

`ifdef VV35_DUAL_INDEPENDENT_IPS
    (* keep_hierarchy = "yes", dont_touch = "yes" *)
    vv35_hdc_ip_top u_hdc (
        .clk_i,
        .rst_ni,
        .valid_i(hdc_req_valid),
        .ready_o(hdc_ready),
        .operator_i,
        .operand_a_i,
        .operand_b_i,
        .valid_o(hdc_valid),
        .result_o(hdc_result)
    );
`else
    (* keep_hierarchy = "yes" *)
    hdec_top #(
        .ECC_STATUS_CYCLE_COUNT(ECC_STATUS_CYCLE_COUNT),
        .ECC_DEBUG_FIELD_OPS(ECC_DEBUG_FIELD_OPS),
        .ECC_PMUL_RESIDUE_SEEDING(ECC_PMUL_RESIDUE_SEEDING),
        .ECC_PMUL_AFFINE_FACTORING(ECC_PMUL_AFFINE_FACTORING),
        .ECC_INV_SQUARE_REDIRECT(ECC_INV_SQUARE_REDIRECT),
        .ECC_PMUL_DBL_FROBENIUS(ECC_PMUL_DBL_FROBENIUS),
        .ECC_PMUL_ADD_Z_FORWARD(ECC_PMUL_ADD_Z_FORWARD),
        .VV31_SCHED_ENABLE(1'b0),
        .VV33_FINE_INTERLEAVE(1'b0),
        .VV33_PAIRED_HMATCH(1'b0),
        .ENABLE_HDC_OPS(1'b1),
        .ENABLE_ECC_OPS(1'b0)
    ) u_hdc (
        .clk_i,
        .rst_ni,
        .valid_i(hdc_req_valid),
        .ready_o(hdc_ready),
        .operator_i,
        .operand_a_i,
        .operand_b_i,
        .valid_o(hdc_valid),
        .result_o(hdc_result)
    );
`endif

`ifdef VV35_DUAL_INDEPENDENT_IPS
    (* keep_hierarchy = "yes", dont_touch = "yes" *)
    vv35_ecc_ip_top u_ecc (
        .clk_i,
        .rst_ni,
        .valid_i(ecc_req_valid),
        .ready_o(ecc_ready),
        .operator_i,
        .operand_a_i,
        .operand_b_i,
        .valid_o(ecc_valid),
        .result_o(ecc_result)
    );
`else
    (* keep_hierarchy = "yes" *)
    hdec_top #(
        .ECC_STATUS_CYCLE_COUNT(ECC_STATUS_CYCLE_COUNT),
        .ECC_DEBUG_FIELD_OPS(ECC_DEBUG_FIELD_OPS),
        .ECC_PMUL_RESIDUE_SEEDING(ECC_PMUL_RESIDUE_SEEDING),
        .ECC_PMUL_AFFINE_FACTORING(ECC_PMUL_AFFINE_FACTORING),
        .ECC_INV_SQUARE_REDIRECT(ECC_INV_SQUARE_REDIRECT),
        .ECC_PMUL_DBL_FROBENIUS(ECC_PMUL_DBL_FROBENIUS),
        .ECC_PMUL_ADD_Z_FORWARD(ECC_PMUL_ADD_Z_FORWARD),
        .VV31_SCHED_ENABLE(1'b1),
        .VV33_FINE_INTERLEAVE(1'b0),
        .VV33_PAIRED_HMATCH(1'b0),
        .ENABLE_HDC_OPS(1'b0),
        .ENABLE_ECC_OPS(1'b1)
    ) u_ecc (
        .clk_i,
        .rst_ni,
        .valid_i(ecc_req_valid),
        .ready_o(ecc_ready),
        .operator_i,
        .operand_a_i,
        .operand_b_i,
        .valid_o(ecc_valid),
        .result_o(ecc_result)
    );
`endif

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            busy_q               <= 1'b0;
            active_route_q       <= ROUTE_HDC;
            last_compute_owner_q <= ROUTE_HDC;
            wait_hdc_q           <= 1'b0;
            wait_ecc_q           <= 1'b0;
            hdc_result_q         <= '0;
            ecc_result_q         <= '0;
        end else begin
            if (accept) begin
                busy_q         <= 1'b1;
                active_route_q <= input_route;
                wait_hdc_q     <= (input_route == ROUTE_HDC) ||
                                  (input_route == ROUTE_BOTH);
                wait_ecc_q     <= (input_route == ROUTE_ECC) ||
                                  (input_route == ROUTE_BOTH);

                if (is_hdc_compute(operator_i, operand_a_i))
                    last_compute_owner_q <= ROUTE_HDC;
                else if (is_ecc_compute(operator_i, operand_a_i))
                    last_compute_owner_q <= ROUTE_ECC;
            end

            if (busy_q) begin
                if (hdc_valid) begin
                    hdc_result_q <= hdc_result;
                    wait_hdc_q   <= 1'b0;
                end
                if (ecc_valid) begin
                    ecc_result_q <= ecc_result;
                    wait_ecc_q   <= 1'b0;
                end

                if ((!wait_hdc_q || hdc_valid) &&
                    (!wait_ecc_q || ecc_valid)) begin
                    busy_q <= 1'b0;
                end
            end
        end
    end

`ifndef SYNTHESIS
    // Mirrored management operations are expected to return the same status.
    always_ff @(posedge clk_i) begin
        if (rst_ni && busy_q && (active_route_q == ROUTE_BOTH) &&
            hdc_valid && ecc_valid) begin
            assert (hdc_result == ecc_result)
                else $error("VV35 dual baseline: mirrored response mismatch");
        end
    end
`endif

endmodule
