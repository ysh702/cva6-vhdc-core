// RETIRED VV33 PROBE
//
// The former phase-lifetime contract observed the rejected vv33_fg_* wide
// sidecar.  Those signals are intentionally absent from the accepted design.
// Keep this compile-safe marker so stale source lists produce an explicit
// retirement result instead of a hierarchy-resolution error.  The maintained
// end-to-end replacement is tb_vv33_fixed_workload.sv.
module tb_vv33_phase_lifetime_contract;
    initial begin
        $display(
            "[VV33:phase_lifetime_contract] RETIRED replacement=tb_vv33_fixed_workload"
        );
        $finish;
    end
endmodule
