// ============================================================================
// tb_coralnpu.sv — drives CoreMiniAxi exactly like the real host does:
// write the program over AXI, set the start PC, release reset, poll status.
// Dumps every internal signal so you can 抓线 in the waveform viewer.
//
//   +PROG=sim/prog.hex   file of "ADDR DATA" hex lines (from sim/elf2hex.py)
//   +ENTRY=00000000      entry point
//   +TIMEOUT=200000      max core clock cycles before giving up
// ============================================================================
`timescale 1ns/1ps

module tb_coralnpu;
  localparam CLK_NS = 16;                 // 62.5 MHz, same as the FX600 build

  logic clk = 0, rstn = 0;
  always #(CLK_NS/2) clk = ~clk;

  // ---- AXI slave side (we are the master) ----
  logic         awvalid, awready; logic [31:0] awaddr; logic [7:0] awlen;
  logic [2:0]   awsize; logic [1:0] awburst;
  logic         wvalid, wready, wlast; logic [127:0] wdata; logic [15:0] wstrb;
  logic         bvalid, bready; logic [1:0] bresp;
  logic         arvalid, arready; logic [31:0] araddr; logic [7:0] arlen;
  logic [2:0]   arsize; logic [1:0] arburst;
  logic         rvalid, rready, rlast; logic [127:0] rdata; logic [1:0] rresp;

  // ---- core master side: accept and DECERR everything ----
  logic m_awvalid, m_wvalid, m_wlast, m_bready, m_arvalid, m_rready;
  logic [5:0] m_awid, m_arid; logic [7:0] m_arlen;

  logic halted, fault, wfi;

  CoreMiniAxi u_core (
    .io_aclk(clk), .io_aresetn(rstn),
    .io_axi_slave_write_addr_ready(awready), .io_axi_slave_write_addr_valid(awvalid),
    .io_axi_slave_write_addr_bits_addr(awaddr), .io_axi_slave_write_addr_bits_prot(3'b0),
    .io_axi_slave_write_addr_bits_id(6'b0), .io_axi_slave_write_addr_bits_len(awlen),
    .io_axi_slave_write_addr_bits_size(awsize), .io_axi_slave_write_addr_bits_burst(awburst),
    .io_axi_slave_write_addr_bits_lock(1'b0), .io_axi_slave_write_addr_bits_cache(4'b0),
    .io_axi_slave_write_data_ready(wready), .io_axi_slave_write_data_valid(wvalid),
    .io_axi_slave_write_data_bits_data(wdata), .io_axi_slave_write_data_bits_last(wlast),
    .io_axi_slave_write_data_bits_strb(wstrb),
    .io_axi_slave_write_resp_ready(bready), .io_axi_slave_write_resp_valid(bvalid),
    .io_axi_slave_write_resp_bits_id(), .io_axi_slave_write_resp_bits_resp(bresp),
    .io_axi_slave_read_addr_ready(arready), .io_axi_slave_read_addr_valid(arvalid),
    .io_axi_slave_read_addr_bits_addr(araddr), .io_axi_slave_read_addr_bits_prot(3'b0),
    .io_axi_slave_read_addr_bits_id(6'b0), .io_axi_slave_read_addr_bits_len(arlen),
    .io_axi_slave_read_addr_bits_size(arsize), .io_axi_slave_read_addr_bits_burst(arburst),
    .io_axi_slave_read_addr_bits_lock(1'b0), .io_axi_slave_read_addr_bits_cache(4'b0),
    .io_axi_slave_read_data_ready(rready), .io_axi_slave_read_data_valid(rvalid),
    .io_axi_slave_read_data_bits_data(rdata), .io_axi_slave_read_data_bits_id(),
    .io_axi_slave_read_data_bits_resp(rresp), .io_axi_slave_read_data_bits_last(rlast),
    // master port: always ready, DECERR responses
    .io_axi_master_write_addr_ready(1'b1), .io_axi_master_write_addr_valid(m_awvalid),
    .io_axi_master_write_addr_bits_addr(), .io_axi_master_write_addr_bits_prot(),
    .io_axi_master_write_addr_bits_id(m_awid), .io_axi_master_write_addr_bits_len(),
    .io_axi_master_write_addr_bits_size(), .io_axi_master_write_addr_bits_burst(),
    .io_axi_master_write_addr_bits_lock(), .io_axi_master_write_addr_bits_cache(),
    .io_axi_master_write_data_ready(1'b1), .io_axi_master_write_data_valid(m_wvalid),
    .io_axi_master_write_data_bits_data(), .io_axi_master_write_data_bits_last(m_wlast),
    .io_axi_master_write_data_bits_strb(),
    .io_axi_master_write_resp_ready(m_bready), .io_axi_master_write_resp_valid(1'b0),
    .io_axi_master_write_resp_bits_id(6'b0), .io_axi_master_write_resp_bits_resp(2'b11),
    .io_axi_master_read_addr_ready(1'b1), .io_axi_master_read_addr_valid(m_arvalid),
    .io_axi_master_read_addr_bits_addr(), .io_axi_master_read_addr_bits_prot(),
    .io_axi_master_read_addr_bits_id(m_arid), .io_axi_master_read_addr_bits_len(m_arlen),
    .io_axi_master_read_addr_bits_size(), .io_axi_master_read_addr_bits_burst(),
    .io_axi_master_read_addr_bits_lock(), .io_axi_master_read_addr_bits_cache(),
    .io_axi_master_read_data_ready(m_rready), .io_axi_master_read_data_valid(1'b0),
    .io_axi_master_read_data_bits_data(128'b0), .io_axi_master_read_data_bits_id(6'b0),
    .io_axi_master_read_data_bits_resp(2'b11), .io_axi_master_read_data_bits_last(1'b1),
    .io_halted(halted), .io_fault(fault), .io_wfi(wfi),
    .io_irq(1'b0), .io_timer_irq(1'b0), .io_software_irq(1'b0),
    .io_boot_addr(32'h0), .io_te(1'b0),
    .io_dm_req_ready(), .io_dm_req_valid(1'b0), .io_dm_req_bits_address(32'b0),
    .io_dm_req_bits_data(32'b0), .io_dm_req_bits_op(2'b0),
    .io_dm_rsp_ready(1'b1), .io_dm_rsp_valid(), .io_dm_rsp_bits_data(), .io_dm_rsp_bits_op()
  );

  // ---- one 32-bit write, byte-strobed into the right lane of the 128-bit bus ----
  task automatic axi_w32(input [31:0] addr, input [31:0] data);
    int unsigned lane = addr[3:2];
    begin
      @(posedge clk);
      awaddr <= addr; awlen <= 8'd0; awsize <= 3'd2; awburst <= 2'b01; awvalid <= 1'b1;
      wdata  <= {4{data}}; wstrb <= 16'hF << (4*lane); wlast <= 1'b1; wvalid <= 1'b1;
      bready <= 1'b1;
      fork
        begin wait (awvalid && awready); @(posedge clk); awvalid <= 1'b0; end
        begin wait (wvalid  && wready ); @(posedge clk); wvalid  <= 1'b0; end
      join
      wait (bvalid); @(posedge clk); bready <= 1'b0;
    end
  endtask

  task automatic axi_r32(input [31:0] addr, output [31:0] data);
    int unsigned lane = addr[3:2];
    begin
      @(posedge clk);
      araddr <= addr; arlen <= 8'd0; arsize <= 3'd2; arburst <= 2'b01; arvalid <= 1'b1;
      rready <= 1'b1;
      wait (arvalid && arready); @(posedge clk); arvalid <= 1'b0;
      wait (rvalid); data = rdata[32*lane +: 32]; @(posedge clk); rready <= 1'b0;
    end
  endtask

  string   progfile;
  int unsigned entry, timeout_cycles, cyc = 0;
  int fd, code, nwords = 0;
  logic [31:0] a, d, status;

  always @(posedge clk) cyc <= cyc + 1;

  initial begin
    awvalid=0; wvalid=0; bready=0; arvalid=0; rready=0; wlast=0; wstrb=0;
    if (!$value$plusargs("PROG=%s", progfile))  progfile = "sim/prog.hex";
    if (!$value$plusargs("ENTRY=%h", entry))    entry = 32'h0;
    if (!$value$plusargs("TIMEOUT=%d", timeout_cycles)) timeout_cycles = 200000;

    $dumpfile("sim/waves.vcd");
    $dumpvars(0, tb_coralnpu);        // everything, all hierarchy — 抓线

    repeat (20) @(posedge clk);
    rstn <= 1'b1;                      // release the core's own reset input
    repeat (20) @(posedge clk);

    // hold core in reset via CSR, sanity-check the bus
    axi_w32(32'h00030000, 32'h1);
    axi_w32(32'h00030004, 32'hDEADBEEF);
    axi_r32(32'h00030004, d);
    $display("[TB] bus check: wrote DEADBEEF, read %08x %s", d, (d==32'hDEADBEEF) ? "(OK)" : "(MISMATCH)");
    if (d !== 32'hDEADBEEF) begin $display("[TB] FAIL: bus"); $finish; end

    fd = $fopen(progfile, "r");
    if (fd == 0) begin $display("[TB] cannot open %s", progfile); $finish; end
    while (!$feof(fd)) begin
      code = $fscanf(fd, "%h %h\n", a, d);
      if (code == 2) begin axi_w32(a, d); nwords++; end
    end
    $fclose(fd);
    $display("[TB] loaded %0d words from %s", nwords, progfile);

    axi_w32(32'h00030004, entry);
    axi_w32(32'h00030000, 32'h1);
    axi_w32(32'h00030000, 32'h0);
    $display("[TB] core released at PC %08x (cycle %0d)", entry, cyc);

    forever begin
      axi_r32(32'h00030008, status);
      if (status[0]) begin
        $display("[TB] HALTED at cycle %0d, status=%02x (%s)", cyc, status,
                 status[1] ? "FAULT" : "clean");
        $finish;
      end
      if (cyc > timeout_cycles) begin
        $display("[TB] TIMEOUT after %0d cycles (status=%02x)", cyc, status);
        $finish;
      end
      repeat (50) @(posedge clk);
    end
  end
endmodule
