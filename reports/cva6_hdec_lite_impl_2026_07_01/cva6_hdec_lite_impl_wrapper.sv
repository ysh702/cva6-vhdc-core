module cva6_hdec_lite_impl_wrapper (
  input  logic        clk_pad_i,
  input  logic        rst_ni,
  output logic [15:0] keep_o
);

  logic clk_core;

  BUFG i_clk_bufg (
    .I(clk_pad_i),
    .O(clk_core)
  );

  localparam config_pkg::cva6_cfg_t CVA6Cfg =
      build_config_pkg::build_config(cva6_config_pkg::cva6_cfg);
  localparam type rvfi_probes_instr_t = `RVFI_PROBES_INSTR_T(CVA6Cfg);
  localparam type rvfi_probes_csr_t = `RVFI_PROBES_CSR_T(CVA6Cfg);
  localparam type rvfi_probes_t = struct packed {
    logic csr;
    logic instr;
  };

  ariane_axi::req_t  noc_req;
  ariane_axi::resp_t noc_resp;

  assign noc_resp = '0;

  ariane #(
    .CVA6Cfg              (CVA6Cfg),
    .rvfi_probes_instr_t  (rvfi_probes_instr_t),
    .rvfi_probes_csr_t    (rvfi_probes_csr_t),
    .rvfi_probes_t        (rvfi_probes_t)
  ) i_ariane (
    .clk_i         (clk_core),
    .rst_ni        (rst_ni),
    .boot_addr_i   (CVA6Cfg.VLEN'(64'h0000_0000_8000_0000)),
    .hart_id_i     ('0),
    .irq_i         ('0),
    .ipi_i         (1'b0),
    .time_irq_i    (1'b0),
    .debug_req_i   (1'b0),
    .rvfi_probes_o (),
    .noc_req_o     (noc_req),
    .noc_resp_i    (noc_resp)
  );

  assign keep_o = {
    ^noc_req.aw.addr[63:32],
    ^noc_req.aw.addr[31:0],
    ^noc_req.ar.addr[63:32],
    ^noc_req.ar.addr[31:0],
    ^noc_req.w.data[63:32],
    ^noc_req.w.data[31:0],
    noc_req.aw_valid,
    noc_req.ar_valid,
    noc_req.w_valid,
    noc_req.b_ready,
    noc_req.r_ready,
    ^noc_req.aw.id,
    ^noc_req.ar.id,
    ^noc_req.w.strb,
    ^noc_req.aw.len,
    ^noc_req.ar.len
  };

endmodule

