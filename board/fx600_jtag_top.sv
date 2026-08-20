// ============================================================================
// fx600_jtag_top: Coral NPU on the Huawei FX600, JTAG-only bring-up variant.
// No PCIe. Control comes in over the same JTAG cable used for programming:
//
//   Vivado hw_server --JTAG--> jtag_axi IP (AXI4 master, 32-bit, bursts)
//        --> axi_dwidth_converter (32 -> 128)
//        --> CORE (CoreMiniAxi / RvvCoreMiniAxi) axi_slave
//   CORE axi_master --> axi4_decerr_responder
//
// Clocking: 100 MHz board LVDS clock -> MMCM -> clk_core (62.5 MHz scalar /
// 25 MHz rvv). Everything, including the JTAG-AXI master, runs on clk_core;
// the JTAG side of jtag_axi is internally asynchronous, so no CDC IP needed.
//
// Status: fpga_act LED blinks while the core runs, solid when halted.
// ============================================================================

`timescale 1ns / 1ps

module fx600_jtag_top #(
  parameter real CORE_CLKOUT_DIVIDE = 16.0   // 1000 MHz VCO / 16 = 62.5 MHz
) (
  input  wire pin_sys_clk_p,
  input  wire pin_sys_clk_n,
  input  wire pin_reset_n,
  output wire fpga_act
);

  // ---- clock + reset -------------------------------------------------------
  wire sys_clk_100;
  IBUFDS ibuf_sysclk (.I(pin_sys_clk_p), .IB(pin_sys_clk_n), .O(sys_clk_100));

  (* ASYNC_REG = "TRUE" *) reg [2:0] rst_sync_q = 3'b000;
  always @(posedge sys_clk_100 or negedge pin_reset_n)
    if (!pin_reset_n) rst_sync_q <= 3'b000;
    else              rst_sync_q <= {rst_sync_q[1:0], 1'b1};
  wire sys_rst_n = rst_sync_q[2];

  wire clk_fb, clk_fb_buf, clk_core_unbuf, clk_core, mmcm_locked;
  MMCME4_ADV #(
    .BANDWIDTH("OPTIMIZED"), .CLKFBOUT_MULT_F(10.000), .CLKIN1_PERIOD(10.000),
    .CLKOUT0_DIVIDE_F(CORE_CLKOUT_DIVIDE), .DIVCLK_DIVIDE(1), .COMPENSATION("AUTO")
  ) u_mmcm_core (
    .CLKIN1(sys_clk_100), .CLKIN2(1'b0), .CLKINSEL(1'b1),
    .CLKFBIN(clk_fb_buf), .CLKFBOUT(clk_fb), .CLKFBOUTB(),
    .CLKOUT0(clk_core_unbuf), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(),
    .CLKOUT2(), .CLKOUT2B(), .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
    .LOCKED(mmcm_locked), .RST(~sys_rst_n), .PWRDWN(1'b0),
    .DADDR(7'b0), .DCLK(1'b0), .DEN(1'b0), .DI(16'b0), .DWE(1'b0), .DO(), .DRDY(),
    .PSCLK(1'b0), .PSEN(1'b0), .PSINCDEC(1'b0), .PSDONE(), .CDDCREQ(1'b0), .CDDCDONE()
  );
  BUFG bufg_fb   (.I(clk_fb),         .O(clk_fb_buf));
  BUFG bufg_core (.I(clk_core_unbuf), .O(clk_core));

  (* ASYNC_REG = "TRUE" *) reg [2:0] core_rst_q = 3'b000;
  always @(posedge clk_core or negedge mmcm_locked)
    if (!mmcm_locked) core_rst_q <= 3'b000;
    else              core_rst_q <= {core_rst_q[1:0], 1'b1};
  wire core_aresetn = core_rst_q[2];

  // ---- JTAG -> AXI4 (32-bit, bursts) --------------------------------------
  wire [31:0] j_awaddr; wire [7:0] j_awlen; wire [2:0] j_awsize; wire [1:0] j_awburst;
  wire [2:0]  j_awprot; wire [3:0] j_awcache; wire j_awlock; wire j_awvalid, j_awready;
  wire [31:0] j_wdata;  wire [3:0] j_wstrb; wire j_wlast, j_wvalid, j_wready;
  wire [1:0]  j_bresp;  wire j_bvalid, j_bready;
  wire [31:0] j_araddr; wire [7:0] j_arlen; wire [2:0] j_arsize; wire [1:0] j_arburst;
  wire [2:0]  j_arprot; wire [3:0] j_arcache; wire j_arlock; wire j_arvalid, j_arready;
  wire [31:0] j_rdata;  wire [1:0] j_rresp; wire j_rlast, j_rvalid, j_rready;

  jtag_axi_0 u_jtag_axi (
    .aclk(clk_core), .aresetn(core_aresetn),
    .m_axi_awaddr(j_awaddr), .m_axi_awlen(j_awlen), .m_axi_awsize(j_awsize),
    .m_axi_awburst(j_awburst), .m_axi_awlock(j_awlock), .m_axi_awcache(j_awcache),
    .m_axi_awprot(j_awprot), .m_axi_awqos(), .m_axi_awvalid(j_awvalid), .m_axi_awready(j_awready),
    .m_axi_wdata(j_wdata), .m_axi_wstrb(j_wstrb), .m_axi_wlast(j_wlast),
    .m_axi_wvalid(j_wvalid), .m_axi_wready(j_wready),
    .m_axi_bresp(j_bresp), .m_axi_bvalid(j_bvalid), .m_axi_bready(j_bready),
    .m_axi_araddr(j_araddr), .m_axi_arlen(j_arlen), .m_axi_arsize(j_arsize),
    .m_axi_arburst(j_arburst), .m_axi_arlock(j_arlock), .m_axi_arcache(j_arcache),
    .m_axi_arprot(j_arprot), .m_axi_arqos(), .m_axi_arvalid(j_arvalid), .m_axi_arready(j_arready),
    .m_axi_rdata(j_rdata), .m_axi_rresp(j_rresp), .m_axi_rlast(j_rlast),
    .m_axi_rvalid(j_rvalid), .m_axi_rready(j_rready)
  );

  // ---- 32 -> 128 width conversion (same clock, sync) -----------------------
  wire [31:0]  s_awaddr; wire [7:0] s_awlen; wire [2:0] s_awsize; wire [1:0] s_awburst;
  wire [2:0]   s_awprot; wire [3:0] s_awcache; wire s_awlock; wire s_awvalid, s_awready;
  wire [127:0] s_wdata;  wire [15:0] s_wstrb; wire s_wlast, s_wvalid, s_wready;
  wire [1:0]   s_bresp;  wire s_bvalid, s_bready;
  wire [31:0]  s_araddr; wire [7:0] s_arlen; wire [2:0] s_arsize; wire [1:0] s_arburst;
  wire [2:0]   s_arprot; wire [3:0] s_arcache; wire s_arlock; wire s_arvalid, s_arready;
  wire [127:0] s_rdata;  wire [1:0] s_rresp; wire s_rlast, s_rvalid, s_rready;

  axi_dwidth_0 u_dwidth (
    .s_axi_aclk(clk_core), .s_axi_aresetn(core_aresetn),
    .s_axi_awaddr(j_awaddr), .s_axi_awlen(j_awlen), .s_axi_awsize(j_awsize),
    .s_axi_awburst(j_awburst), .s_axi_awlock(j_awlock), .s_axi_awcache(j_awcache),
    .s_axi_awprot(j_awprot), .s_axi_awregion(4'b0), .s_axi_awqos(4'b0),
    .s_axi_awvalid(j_awvalid), .s_axi_awready(j_awready),
    .s_axi_wdata(j_wdata), .s_axi_wstrb(j_wstrb), .s_axi_wlast(j_wlast),
    .s_axi_wvalid(j_wvalid), .s_axi_wready(j_wready),
    .s_axi_bresp(j_bresp), .s_axi_bvalid(j_bvalid), .s_axi_bready(j_bready),
    .s_axi_araddr(j_araddr), .s_axi_arlen(j_arlen), .s_axi_arsize(j_arsize),
    .s_axi_arburst(j_arburst), .s_axi_arlock(j_arlock), .s_axi_arcache(j_arcache),
    .s_axi_arprot(j_arprot), .s_axi_arregion(4'b0), .s_axi_arqos(4'b0),
    .s_axi_arvalid(j_arvalid), .s_axi_arready(j_arready),
    .s_axi_rdata(j_rdata), .s_axi_rresp(j_rresp), .s_axi_rlast(j_rlast),
    .s_axi_rvalid(j_rvalid), .s_axi_rready(j_rready),

    .m_axi_awaddr(s_awaddr), .m_axi_awlen(s_awlen), .m_axi_awsize(s_awsize),
    .m_axi_awburst(s_awburst), .m_axi_awlock(s_awlock), .m_axi_awcache(s_awcache),
    .m_axi_awprot(s_awprot), .m_axi_awregion(), .m_axi_awqos(),
    .m_axi_awvalid(s_awvalid), .m_axi_awready(s_awready),
    .m_axi_wdata(s_wdata), .m_axi_wstrb(s_wstrb), .m_axi_wlast(s_wlast),
    .m_axi_wvalid(s_wvalid), .m_axi_wready(s_wready),
    .m_axi_bresp(s_bresp), .m_axi_bvalid(s_bvalid), .m_axi_bready(s_bready),
    .m_axi_araddr(s_araddr), .m_axi_arlen(s_arlen), .m_axi_arsize(s_arsize),
    .m_axi_arburst(s_arburst), .m_axi_arlock(s_arlock), .m_axi_arcache(s_arcache),
    .m_axi_arprot(s_arprot), .m_axi_arregion(), .m_axi_arqos(),
    .m_axi_arvalid(s_arvalid), .m_axi_arready(s_arready),
    .m_axi_rdata(s_rdata), .m_axi_rresp(s_rresp), .m_axi_rlast(s_rlast),
    .m_axi_rvalid(s_rvalid), .m_axi_rready(s_rready)
  );

  // ---- core master termination ---------------------------------------------
  wire         m_awready, m_awvalid; wire [5:0] m_awid;
  wire         m_wready, m_wvalid, m_wlast;
  wire         m_bready, m_bvalid; wire [5:0] m_bid; wire [1:0] m_bresp;
  wire         m_arready, m_arvalid; wire [5:0] m_arid; wire [7:0] m_arlen;
  wire         m_rready, m_rvalid; wire [127:0] m_rdata; wire [5:0] m_rid; wire [1:0] m_rresp; wire m_rlast;

  axi4_decerr_responder u_term (
    .aclk(clk_core), .aresetn(core_aresetn),
    .s_awready(m_awready), .s_awvalid(m_awvalid), .s_awid(m_awid),
    .s_wready(m_wready), .s_wvalid(m_wvalid), .s_wlast(m_wlast),
    .s_bready(m_bready), .s_bvalid(m_bvalid), .s_bid(m_bid), .s_bresp(m_bresp),
    .s_arready(m_arready), .s_arvalid(m_arvalid), .s_arid(m_arid), .s_arlen(m_arlen),
    .s_rready(m_rready), .s_rvalid(m_rvalid), .s_rid(m_rid), .s_rresp(m_rresp),
    .s_rdata(m_rdata), .s_rlast(m_rlast)
  );

  // ---- the core -------------------------------------------------------------
`ifndef CORE_MODULE
`define CORE_MODULE CoreMiniAxi
`endif
  wire core_halted, core_fault, core_wfi;

  `CORE_MODULE u_core (
    .io_aclk(clk_core), .io_aresetn(core_aresetn),

    .io_axi_slave_write_addr_ready(s_awready), .io_axi_slave_write_addr_valid(s_awvalid),
    .io_axi_slave_write_addr_bits_addr(s_awaddr), .io_axi_slave_write_addr_bits_prot(s_awprot),
    .io_axi_slave_write_addr_bits_id(6'b0), .io_axi_slave_write_addr_bits_len(s_awlen),
    .io_axi_slave_write_addr_bits_size(s_awsize), .io_axi_slave_write_addr_bits_burst(s_awburst),
    .io_axi_slave_write_addr_bits_lock(s_awlock), .io_axi_slave_write_addr_bits_cache(s_awcache),
    .io_axi_slave_write_data_ready(s_wready), .io_axi_slave_write_data_valid(s_wvalid),
    .io_axi_slave_write_data_bits_data(s_wdata), .io_axi_slave_write_data_bits_last(s_wlast),
    .io_axi_slave_write_data_bits_strb(s_wstrb),
    .io_axi_slave_write_resp_ready(s_bready), .io_axi_slave_write_resp_valid(s_bvalid),
    .io_axi_slave_write_resp_bits_id(), .io_axi_slave_write_resp_bits_resp(s_bresp),
    .io_axi_slave_read_addr_ready(s_arready), .io_axi_slave_read_addr_valid(s_arvalid),
    .io_axi_slave_read_addr_bits_addr(s_araddr), .io_axi_slave_read_addr_bits_prot(s_arprot),
    .io_axi_slave_read_addr_bits_id(6'b0), .io_axi_slave_read_addr_bits_len(s_arlen),
    .io_axi_slave_read_addr_bits_size(s_arsize), .io_axi_slave_read_addr_bits_burst(s_arburst),
    .io_axi_slave_read_addr_bits_lock(s_arlock), .io_axi_slave_read_addr_bits_cache(s_arcache),
    .io_axi_slave_read_data_ready(s_rready), .io_axi_slave_read_data_valid(s_rvalid),
    .io_axi_slave_read_data_bits_data(s_rdata), .io_axi_slave_read_data_bits_id(),
    .io_axi_slave_read_data_bits_resp(s_rresp), .io_axi_slave_read_data_bits_last(s_rlast),

    .io_axi_master_write_addr_ready(m_awready), .io_axi_master_write_addr_valid(m_awvalid),
    .io_axi_master_write_addr_bits_addr(), .io_axi_master_write_addr_bits_prot(),
    .io_axi_master_write_addr_bits_id(m_awid), .io_axi_master_write_addr_bits_len(),
    .io_axi_master_write_addr_bits_size(), .io_axi_master_write_addr_bits_burst(),
    .io_axi_master_write_addr_bits_lock(), .io_axi_master_write_addr_bits_cache(),
    .io_axi_master_write_data_ready(m_wready), .io_axi_master_write_data_valid(m_wvalid),
    .io_axi_master_write_data_bits_data(), .io_axi_master_write_data_bits_last(m_wlast),
    .io_axi_master_write_data_bits_strb(),
    .io_axi_master_write_resp_ready(m_bready), .io_axi_master_write_resp_valid(m_bvalid),
    .io_axi_master_write_resp_bits_id(m_bid), .io_axi_master_write_resp_bits_resp(m_bresp),
    .io_axi_master_read_addr_ready(m_arready), .io_axi_master_read_addr_valid(m_arvalid),
    .io_axi_master_read_addr_bits_addr(), .io_axi_master_read_addr_bits_prot(),
    .io_axi_master_read_addr_bits_id(m_arid), .io_axi_master_read_addr_bits_len(m_arlen),
    .io_axi_master_read_addr_bits_size(), .io_axi_master_read_addr_bits_burst(),
    .io_axi_master_read_addr_bits_lock(), .io_axi_master_read_addr_bits_cache(),
    .io_axi_master_read_data_ready(m_rready), .io_axi_master_read_data_valid(m_rvalid),
    .io_axi_master_read_data_bits_data(m_rdata), .io_axi_master_read_data_bits_id(m_rid),
    .io_axi_master_read_data_bits_resp(m_rresp), .io_axi_master_read_data_bits_last(m_rlast),

    .io_halted(core_halted), .io_fault(core_fault), .io_wfi(core_wfi),
    .io_irq(1'b0), .io_timer_irq(1'b0), .io_software_irq(1'b0),
    .io_boot_addr(32'h0), .io_te(1'b0),
    .io_dm_req_ready(), .io_dm_req_valid(1'b0), .io_dm_req_bits_address(32'b0),
    .io_dm_req_bits_data(32'b0), .io_dm_req_bits_op(2'b0),
    .io_dm_rsp_ready(1'b1), .io_dm_rsp_valid(), .io_dm_rsp_bits_data(), .io_dm_rsp_bits_op()
  );

  reg [24:0] hb = 25'd0;
  always @(posedge clk_core) hb <= hb + 25'd1;
  assign fpga_act = core_halted | hb[24];

endmodule
