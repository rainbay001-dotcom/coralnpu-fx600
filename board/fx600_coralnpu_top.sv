// ============================================================================
// fx600_coralnpu_top: Google Coral NPU on the Huawei FX600 (Xilinx VU9P).
//
//   Host PCIe (Gen3 x16) --> XDMA IP (AXI-Lite master, BAR0)
//        --> AXI-Lite clock converter (250 MHz XDMA axi_aclk -> core clock)
//        --> axil_to_core_axi4 bridge (32b lite -> single-beat 128b AXI4)
//        --> CORE (CoreMiniAxi or RvvCoreMiniAxi) axi_slave port
//   CORE axi_master --> axi4_decerr_responder (returns DECERR, never hangs)
//
// Core clock: derived by MMCM from the FX600 100 MHz LVDS system clock
// (pin_sys_clk_p/n, AY23/BA23). Default 100 MHz / 8 * CORE_CLK_MULT... see
// the MMCM parameters below (defaults give 62.5 MHz for the scalar core;
// override CORE_CLKOUT_DIVIDE for the RVV build, e.g. 32.0 -> 25 MHz).
//
// BAR0 map seen by the host (XDMA AXI-Lite window):
//   0x0000_0000 .. core address space 1:1 (ITCM 0x0, DTCM 0x10000, CSR 0x30000)
//   The XDMA AXI-Lite master presents 32-bit addresses; we pass them straight
//   through, so host offset == core address. Keep BAR0 >= 1 MiB.
//
// Board pins/timing come from Huawei's fx600.xdc (board/fx600_huawei_ref.xdc,
// Apache-2.0) trimmed to what this design uses (board/fx600_coralnpu.xdc).
// ============================================================================

`timescale 1ns / 1ps

module fx600_coralnpu_top #(
  parameter real   CORE_CLKOUT_DIVIDE = 16.0,   // MMCM: 100MHz*10/CORE_CLKOUT_DIVIDE  (16 -> 62.5 MHz)
  parameter        CORE_IS_RVV        = 0       // documentation only; core module is selected by build script define
) (
  // FX600 system clock (100 MHz LVDS) and board reset (active low, LVCMOS12)
  input  wire         pin_sys_clk_p,
  input  wire         pin_sys_clk_n,
  input  wire         pin_reset_n,

  // PCIe Gen3 x16 endpoint
  input  wire         pin_pcie_ref_clk_p,
  input  wire         pin_pcie_ref_clk_n,
  input  wire [15:0]  pin_pcie_rxp_in,
  input  wire [15:0]  pin_pcie_rxn_in,
  output wire [15:0]  pin_pcie_txp_out,
  output wire [15:0]  pin_pcie_txn_out,

  // Board activity LED (optional; drives core-halted status). Leave unconnected
  // in the XDC if the pin is unknown.
  output wire         fpga_act
);

  // ---------------------------------------------------------------------------
  // Clocks / resets
  // ---------------------------------------------------------------------------
  wire sys_clk_100;          // buffered 100 MHz board clock
  wire sys_rst_n_sync;       // board reset, synchronized to sys_clk_100
  wire pcie_refclk, pcie_refclk_gt;
  wire xdma_axi_aclk;        // 250 MHz from XDMA (user clock)
  wire xdma_axi_aresetn;
  wire clk_core;             // core clock (MMCM from sys_clk_100)
  wire core_aresetn;         // core reset, released after MMCM lock + PCIe link

  IBUFDS ibuf_sysclk (.I(pin_sys_clk_p), .IB(pin_sys_clk_n), .O(sys_clk_100));

  // Board reset synchronizer (async assert, sync deassert)
  (* ASYNC_REG = "TRUE" *) reg [2:0] sys_rst_sync_q = 3'b000;
  always @(posedge sys_clk_100 or negedge pin_reset_n) begin
    if (!pin_reset_n) sys_rst_sync_q <= 3'b000;
    else              sys_rst_sync_q <= {sys_rst_sync_q[1:0], 1'b1};
  end
  assign sys_rst_n_sync = sys_rst_sync_q[2];

  // PCIe reference clock buffer (100 MHz)
  IBUFDS_GTE4 #(.REFCLK_HROW_CK_SEL(2'b00)) ibuf_pcie_refclk (
    .I(pin_pcie_ref_clk_p), .IB(pin_pcie_ref_clk_n), .CEB(1'b0),
    .O(pcie_refclk_gt), .ODIV2(pcie_refclk)
  );

  // Core clock MMCM: 100 MHz in, VCO = 100*10 = 1000 MHz, CLKOUT0 = 1000/CORE_CLKOUT_DIVIDE
  wire clk_fb, clk_fb_buf, clk_core_unbuf, mmcm_locked;
  MMCME4_ADV #(
    .BANDWIDTH        ("OPTIMIZED"),
    .CLKFBOUT_MULT_F  (10.000),
    .CLKIN1_PERIOD    (10.000),
    .CLKOUT0_DIVIDE_F (CORE_CLKOUT_DIVIDE),
    .DIVCLK_DIVIDE    (1),
    .COMPENSATION     ("AUTO")
  ) u_mmcm_core (
    .CLKIN1(sys_clk_100), .CLKIN2(1'b0), .CLKINSEL(1'b1),
    .CLKFBIN(clk_fb_buf), .CLKFBOUT(clk_fb), .CLKFBOUTB(),
    .CLKOUT0(clk_core_unbuf), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
    .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
    .LOCKED(mmcm_locked), .RST(~sys_rst_n_sync), .PWRDWN(1'b0),
    .DADDR(7'b0), .DCLK(1'b0), .DEN(1'b0), .DI(16'b0), .DWE(1'b0), .DO(), .DRDY(),
    .PSCLK(1'b0), .PSEN(1'b0), .PSINCDEC(1'b0), .PSDONE(),
    .CDDCREQ(1'b0), .CDDCDONE()
  );
  BUFG bufg_fb   (.I(clk_fb),         .O(clk_fb_buf));
  BUFG bufg_core (.I(clk_core_unbuf), .O(clk_core));

  // Core reset: released only when MMCM locked AND XDMA reports link up/out of reset
  (* ASYNC_REG = "TRUE" *) reg [2:0] core_rst_sync_q = 3'b000;
  wire core_rst_src_n = mmcm_locked & xdma_axi_aresetn;
  always @(posedge clk_core or negedge core_rst_src_n) begin
    if (!core_rst_src_n) core_rst_sync_q <= 3'b000;
    else                 core_rst_sync_q <= {core_rst_sync_q[1:0], 1'b1};
  end
  assign core_aresetn = core_rst_sync_q[2];

  // ---------------------------------------------------------------------------
  // XDMA endpoint (AXI-Lite master only; DMA channels unused)
  //   Generate with build/gen_ip.tcl. Expected instance name: xdma_0.
  //   Config: PCIe Gen3 x16, AXI-Lite Master enabled (BAR0, >= 1 MB), no DMA
  //   channels needed for control (we still generate 1 H2C/1 C2H to keep the IP happy;
  //   they are left idle).
  // ---------------------------------------------------------------------------
  wire [31:0] axil_awaddr;  wire [2:0] axil_awprot; wire axil_awvalid, axil_awready;
  wire [31:0] axil_wdata;   wire [3:0] axil_wstrb;  wire axil_wvalid,  axil_wready;
  wire [1:0]  axil_bresp;   wire axil_bvalid, axil_bready;
  wire [31:0] axil_araddr;  wire [2:0] axil_arprot; wire axil_arvalid, axil_arready;
  wire [31:0] axil_rdata;   wire [1:0] axil_rresp;  wire axil_rvalid,  axil_rready;

  wire user_lnk_up;

  xdma_0 u_xdma (
    .sys_clk        (pcie_refclk),
    .sys_clk_gt     (pcie_refclk_gt),
    .sys_rst_n      (sys_rst_n_sync),      // board reset as PCIe perst proxy (see note in RUNME)
    .user_lnk_up    (user_lnk_up),

    .pci_exp_txp    (pin_pcie_txp_out),
    .pci_exp_txn    (pin_pcie_txn_out),
    .pci_exp_rxp    (pin_pcie_rxp_in),
    .pci_exp_rxn    (pin_pcie_rxn_in),

    .axi_aclk       (xdma_axi_aclk),
    .axi_aresetn    (xdma_axi_aresetn),
    .usr_irq_req    (1'b0),
    .usr_irq_ack    (),

    // AXI-Lite master (BAR0)
    .m_axil_awaddr  (axil_awaddr),
    .m_axil_awprot  (axil_awprot),
    .m_axil_awvalid (axil_awvalid),
    .m_axil_awready (axil_awready),
    .m_axil_wdata   (axil_wdata),
    .m_axil_wstrb   (axil_wstrb),
    .m_axil_wvalid  (axil_wvalid),
    .m_axil_wready  (axil_wready),
    .m_axil_bvalid  (axil_bvalid),
    .m_axil_bresp   (axil_bresp),
    .m_axil_bready  (axil_bready),
    .m_axil_araddr  (axil_araddr),
    .m_axil_arprot  (axil_arprot),
    .m_axil_arvalid (axil_arvalid),
    .m_axil_arready (axil_arready),
    .m_axil_rdata   (axil_rdata),
    .m_axil_rresp   (axil_rresp),
    .m_axil_rvalid  (axil_rvalid),
    .m_axil_rready  (axil_rready),

    // Unused DMA AXI-MM master: tie ready/valid off so the IP is quiescent.
    .m_axi_awready  (1'b1), .m_axi_wready (1'b1), .m_axi_bid (4'b0), .m_axi_bresp (2'b0), .m_axi_bvalid (1'b0),
    .m_axi_arready  (1'b1), .m_axi_rid (4'b0), .m_axi_rdata (64'b0), .m_axi_rresp (2'b0), .m_axi_rlast (1'b0), .m_axi_rvalid (1'b0),
    .m_axi_awid (), .m_axi_awaddr (), .m_axi_awlen (), .m_axi_awsize (), .m_axi_awburst (), .m_axi_awprot (),
    .m_axi_awvalid (), .m_axi_awlock (), .m_axi_awcache (), .m_axi_wdata (), .m_axi_wstrb (), .m_axi_wlast (),
    .m_axi_wvalid (), .m_axi_bready (), .m_axi_arid (), .m_axi_araddr (), .m_axi_arlen (), .m_axi_arsize (),
    .m_axi_arburst (), .m_axi_arprot (), .m_axi_arvalid (), .m_axi_arlock (), .m_axi_arcache (), .m_axi_rready ()
  );

  // ---------------------------------------------------------------------------
  // AXI-Lite clock crossing: XDMA 250 MHz -> core clock (Xilinx AXI Clock Converter,
  // AXI4LITE, 32/32, ACLK_ASYNC=1). Generated by build/gen_ip.tcl as axil_cdc_0.
  // ---------------------------------------------------------------------------
  wire [31:0] c_awaddr; wire c_awvalid, c_awready;
  wire [31:0] c_wdata;  wire [3:0] c_wstrb; wire c_wvalid, c_wready;
  wire [1:0]  c_bresp;  wire c_bvalid, c_bready;
  wire [31:0] c_araddr; wire c_arvalid, c_arready;
  wire [31:0] c_rdata;  wire [1:0] c_rresp; wire c_rvalid, c_rready;

  axil_cdc_0 u_axil_cdc (
    .s_axi_aclk(xdma_axi_aclk), .s_axi_aresetn(xdma_axi_aresetn),
    .s_axi_awaddr(axil_awaddr), .s_axi_awprot(axil_awprot), .s_axi_awvalid(axil_awvalid), .s_axi_awready(axil_awready),
    .s_axi_wdata(axil_wdata),   .s_axi_wstrb(axil_wstrb),   .s_axi_wvalid(axil_wvalid),   .s_axi_wready(axil_wready),
    .s_axi_bresp(axil_bresp),   .s_axi_bvalid(axil_bvalid), .s_axi_bready(axil_bready),
    .s_axi_araddr(axil_araddr), .s_axi_arprot(axil_arprot), .s_axi_arvalid(axil_arvalid), .s_axi_arready(axil_arready),
    .s_axi_rdata(axil_rdata),   .s_axi_rresp(axil_rresp),   .s_axi_rvalid(axil_rvalid),   .s_axi_rready(axil_rready),

    .m_axi_aclk(clk_core), .m_axi_aresetn(core_aresetn),
    .m_axi_awaddr(c_awaddr), .m_axi_awprot(), .m_axi_awvalid(c_awvalid), .m_axi_awready(c_awready),
    .m_axi_wdata(c_wdata),   .m_axi_wstrb(c_wstrb), .m_axi_wvalid(c_wvalid), .m_axi_wready(c_wready),
    .m_axi_bresp(c_bresp),   .m_axi_bvalid(c_bvalid), .m_axi_bready(c_bready),
    .m_axi_araddr(c_araddr), .m_axi_arprot(), .m_axi_arvalid(c_arvalid), .m_axi_arready(c_arready),
    .m_axi_rdata(c_rdata),   .m_axi_rresp(c_rresp), .m_axi_rvalid(c_rvalid), .m_axi_rready(c_rready)
  );

  // ---------------------------------------------------------------------------
  // AXI-Lite -> core AXI4 bridge
  // ---------------------------------------------------------------------------
  wire         s_awready, s_awvalid; wire [31:0] s_awaddr; wire [2:0] s_awprot; wire [5:0] s_awid;
  wire [7:0]   s_awlen; wire [2:0] s_awsize; wire [1:0] s_awburst; wire s_awlock; wire [3:0] s_awcache;
  wire         s_wready, s_wvalid; wire [127:0] s_wdata; wire s_wlast; wire [15:0] s_wstrb;
  wire         s_bready, s_bvalid; wire [5:0] s_bid; wire [1:0] s_bresp;
  wire         s_arready, s_arvalid; wire [31:0] s_araddr; wire [2:0] s_arprot; wire [5:0] s_arid;
  wire [7:0]   s_arlen; wire [2:0] s_arsize; wire [1:0] s_arburst; wire s_arlock; wire [3:0] s_arcache;
  wire         s_rready, s_rvalid; wire [127:0] s_rdata; wire [5:0] s_rid; wire [1:0] s_rresp; wire s_rlast;

  axil_to_core_axi4 u_bridge (
    .aclk(clk_core), .aresetn(core_aresetn),
    .s_axil_awaddr(c_awaddr), .s_axil_awvalid(c_awvalid), .s_axil_awready(c_awready),
    .s_axil_wdata(c_wdata), .s_axil_wstrb(c_wstrb), .s_axil_wvalid(c_wvalid), .s_axil_wready(c_wready),
    .s_axil_bresp(c_bresp), .s_axil_bvalid(c_bvalid), .s_axil_bready(c_bready),
    .s_axil_araddr(c_araddr), .s_axil_arvalid(c_arvalid), .s_axil_arready(c_arready),
    .s_axil_rdata(c_rdata), .s_axil_rresp(c_rresp), .s_axil_rvalid(c_rvalid), .s_axil_rready(c_rready),
    .m_awready(s_awready), .m_awvalid(s_awvalid), .m_awaddr(s_awaddr), .m_awprot(s_awprot), .m_awid(s_awid),
    .m_awlen(s_awlen), .m_awsize(s_awsize), .m_awburst(s_awburst), .m_awlock(s_awlock), .m_awcache(s_awcache),
    .m_wready(s_wready), .m_wvalid(s_wvalid), .m_wdata(s_wdata), .m_wlast(s_wlast), .m_wstrb(s_wstrb),
    .m_bready(s_bready), .m_bvalid(s_bvalid), .m_bid(s_bid), .m_bresp(s_bresp),
    .m_arready(s_arready), .m_arvalid(s_arvalid), .m_araddr(s_araddr), .m_arprot(s_arprot), .m_arid(s_arid),
    .m_arlen(s_arlen), .m_arsize(s_arsize), .m_arburst(s_arburst), .m_arlock(s_arlock), .m_arcache(s_arcache),
    .m_rready(s_rready), .m_rvalid(s_rvalid), .m_rdata(s_rdata), .m_rid(s_rid), .m_rresp(s_rresp), .m_rlast(s_rlast)
  );

  // ---------------------------------------------------------------------------
  // Core AXI master termination (DECERR responder)
  // ---------------------------------------------------------------------------
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
    .s_rready(m_rready), .s_rvalid(m_rvalid), .s_rid(m_rid), .s_rresp(m_rresp), .s_rdata(m_rdata), .s_rlast(m_rlast)
  );

  // ---------------------------------------------------------------------------
  // The NPU core. CORE_MODULE is a build-time define: CoreMiniAxi (default) or
  // RvvCoreMiniAxi. Both share the same port list.
  // ---------------------------------------------------------------------------
`ifndef CORE_MODULE
`define CORE_MODULE CoreMiniAxi
`endif

  wire core_halted, core_fault, core_wfi;

  `CORE_MODULE u_core (
    .io_aclk(clk_core), .io_aresetn(core_aresetn),

    .io_axi_slave_write_addr_ready(s_awready), .io_axi_slave_write_addr_valid(s_awvalid),
    .io_axi_slave_write_addr_bits_addr(s_awaddr), .io_axi_slave_write_addr_bits_prot(s_awprot),
    .io_axi_slave_write_addr_bits_id(s_awid), .io_axi_slave_write_addr_bits_len(s_awlen),
    .io_axi_slave_write_addr_bits_size(s_awsize), .io_axi_slave_write_addr_bits_burst(s_awburst),
    .io_axi_slave_write_addr_bits_lock(s_awlock), .io_axi_slave_write_addr_bits_cache(s_awcache),
    .io_axi_slave_write_data_ready(s_wready), .io_axi_slave_write_data_valid(s_wvalid),
    .io_axi_slave_write_data_bits_data(s_wdata), .io_axi_slave_write_data_bits_last(s_wlast),
    .io_axi_slave_write_data_bits_strb(s_wstrb),
    .io_axi_slave_write_resp_ready(s_bready), .io_axi_slave_write_resp_valid(s_bvalid),
    .io_axi_slave_write_resp_bits_id(s_bid), .io_axi_slave_write_resp_bits_resp(s_bresp),
    .io_axi_slave_read_addr_ready(s_arready), .io_axi_slave_read_addr_valid(s_arvalid),
    .io_axi_slave_read_addr_bits_addr(s_araddr), .io_axi_slave_read_addr_bits_prot(s_arprot),
    .io_axi_slave_read_addr_bits_id(s_arid), .io_axi_slave_read_addr_bits_len(s_arlen),
    .io_axi_slave_read_addr_bits_size(s_arsize), .io_axi_slave_read_addr_bits_burst(s_arburst),
    .io_axi_slave_read_addr_bits_lock(s_arlock), .io_axi_slave_read_addr_bits_cache(s_arcache),
    .io_axi_slave_read_data_ready(s_rready), .io_axi_slave_read_data_valid(s_rvalid),
    .io_axi_slave_read_data_bits_data(s_rdata), .io_axi_slave_read_data_bits_id(s_rid),
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
    .io_dm_req_ready(), .io_dm_req_valid(1'b0), .io_dm_req_bits_address(32'b0), .io_dm_req_bits_data(32'b0),
    .io_dm_req_bits_op(2'b0),
    .io_dm_rsp_ready(1'b1), .io_dm_rsp_valid(), .io_dm_rsp_bits_data(), .io_dm_rsp_bits_op()
  );

  // Heartbeat / status LED: slow blink while running, solid when halted, off if no PCIe link.
  reg [24:0] hb = 25'd0;
  always @(posedge clk_core) hb <= hb + 25'd1;
  assign fpga_act = user_lnk_up & (core_halted | hb[24]);

endmodule
