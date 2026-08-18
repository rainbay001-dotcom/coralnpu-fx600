// ============================================================================
// AXI4-Lite (32-bit) -> CoreMiniAxi AXI4 (128-bit data, 6-bit ID) bridge.
// Single outstanding transaction; every AXI-Lite access becomes one 4-byte
// single-beat AXI4 burst on the core port, steered to the right 32-bit lane
// of the 128-bit data bus.
// ============================================================================

module axil_to_core_axi4 (
  input  logic         aclk,
  input  logic         aresetn,

  // AXI4-Lite slave (from OCL clock converter, core clock domain)
  input  logic [31:0]  s_axil_awaddr,
  input  logic         s_axil_awvalid,
  output logic         s_axil_awready,
  input  logic [31:0]  s_axil_wdata,
  input  logic [3:0]   s_axil_wstrb,
  input  logic         s_axil_wvalid,
  output logic         s_axil_wready,
  output logic [1:0]   s_axil_bresp,
  output logic         s_axil_bvalid,
  input  logic         s_axil_bready,
  input  logic [31:0]  s_axil_araddr,
  input  logic         s_axil_arvalid,
  output logic         s_axil_arready,
  output logic [31:0]  s_axil_rdata,
  output logic [1:0]   s_axil_rresp,
  output logic         s_axil_rvalid,
  input  logic         s_axil_rready,

  // CoreMiniAxi AXI4 slave port (this module is the master)
  input  logic         m_awready,
  output logic         m_awvalid,
  output logic [31:0]  m_awaddr,
  output logic [2:0]   m_awprot,
  output logic [5:0]   m_awid,
  output logic [7:0]   m_awlen,
  output logic [2:0]   m_awsize,
  output logic [1:0]   m_awburst,
  output logic         m_awlock,
  output logic [3:0]   m_awcache,
  input  logic         m_wready,
  output logic         m_wvalid,
  output logic [127:0] m_wdata,
  output logic         m_wlast,
  output logic [15:0]  m_wstrb,
  output logic         m_bready,
  input  logic         m_bvalid,
  input  logic [5:0]   m_bid,
  input  logic [1:0]   m_bresp,
  input  logic         m_arready,
  output logic         m_arvalid,
  output logic [31:0]  m_araddr,
  output logic [2:0]   m_arprot,
  output logic [5:0]   m_arid,
  output logic [7:0]   m_arlen,
  output logic [2:0]   m_arsize,
  output logic [1:0]   m_arburst,
  output logic         m_arlock,
  output logic [3:0]   m_arcache,
  output logic         m_rready,
  input  logic         m_rvalid,
  input  logic [127:0] m_rdata,
  input  logic [5:0]   m_rid,
  input  logic [1:0]   m_rresp,
  input  logic         m_rlast
);

  typedef enum logic [2:0] {
    ST_IDLE,
    ST_WR_CMD,
    ST_WR_RESP,
    ST_WR_LITE_B,
    ST_RD_CMD,
    ST_RD_DATA,
    ST_RD_LITE_R
  } state_e;

  state_e      state_q;
  logic [31:0] addr_q;
  logic [31:0] wdata_q;
  logic [3:0]  wstrb_q;
  logic [1:0]  lane_q;
  logic        aw_got_q, w_got_q;
  logic        aw_sent_q, w_sent_q;
  logic [1:0]  resp_q;
  logic [31:0] rdata_q;

  // Constant AXI4 attributes: 4-byte single-beat INCR, id 0
  assign m_awprot  = 3'b000;
  assign m_awid    = 6'd0;
  assign m_awlen   = 8'd0;
  assign m_awsize  = 3'b010;
  assign m_awburst = 2'b01;
  assign m_awlock  = 1'b0;
  assign m_awcache = 4'b0000;
  assign m_arprot  = 3'b000;
  assign m_arid    = 6'd0;
  assign m_arlen   = 8'd0;
  assign m_arsize  = 3'b010;
  assign m_arburst = 2'b01;
  assign m_arlock  = 1'b0;
  assign m_arcache = 4'b0000;

  assign m_awaddr = addr_q;
  assign m_araddr = addr_q;
  assign m_wdata  = {4{wdata_q}};
  assign m_wstrb  = 16'(wstrb_q) << (4 * lane_q);
  assign m_wlast  = 1'b1;

  assign m_awvalid = (state_q == ST_WR_CMD) && !aw_sent_q;
  assign m_wvalid  = (state_q == ST_WR_CMD) && !w_sent_q;
  assign m_bready  = (state_q == ST_WR_RESP);
  assign m_arvalid = (state_q == ST_RD_CMD);
  assign m_rready  = (state_q == ST_RD_DATA);

  // AXI-Lite handshakes
  assign s_axil_awready = (state_q == ST_IDLE) && !aw_got_q;
  assign s_axil_wready  = (state_q == ST_IDLE) && !w_got_q;
  assign s_axil_arready = (state_q == ST_IDLE) && !aw_got_q && !w_got_q && !s_axil_awvalid;
  assign s_axil_bresp   = resp_q;
  assign s_axil_bvalid  = (state_q == ST_WR_LITE_B);
  assign s_axil_rdata   = rdata_q;
  assign s_axil_rresp   = resp_q;
  assign s_axil_rvalid  = (state_q == ST_RD_LITE_R);

  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      state_q   <= ST_IDLE;
      aw_got_q  <= 1'b0;
      w_got_q   <= 1'b0;
      aw_sent_q <= 1'b0;
      w_sent_q  <= 1'b0;
      addr_q    <= '0;
      wdata_q   <= '0;
      wstrb_q   <= '0;
      lane_q    <= '0;
      resp_q    <= '0;
      rdata_q   <= '0;
    end else begin
      unique case (state_q)
        ST_IDLE: begin
          if (s_axil_awvalid && s_axil_awready) begin
            addr_q   <= s_axil_awaddr;
            lane_q   <= s_axil_awaddr[3:2];
            aw_got_q <= 1'b1;
          end
          if (s_axil_wvalid && s_axil_wready) begin
            wdata_q <= s_axil_wdata;
            wstrb_q <= s_axil_wstrb;
            w_got_q <= 1'b1;
          end
          if ((aw_got_q || (s_axil_awvalid && s_axil_awready)) &&
              (w_got_q  || (s_axil_wvalid  && s_axil_wready))) begin
            state_q   <= ST_WR_CMD;
            aw_sent_q <= 1'b0;
            w_sent_q  <= 1'b0;
          end else if (s_axil_arvalid && s_axil_arready) begin
            addr_q  <= s_axil_araddr;
            lane_q  <= s_axil_araddr[3:2];
            state_q <= ST_RD_CMD;
          end
        end

        ST_WR_CMD: begin
          if (m_awvalid && m_awready) aw_sent_q <= 1'b1;
          if (m_wvalid  && m_wready)  w_sent_q  <= 1'b1;
          if ((aw_sent_q || (m_awvalid && m_awready)) &&
              (w_sent_q  || (m_wvalid  && m_wready))) begin
            state_q <= ST_WR_RESP;
          end
        end

        ST_WR_RESP: begin
          if (m_bvalid) begin
            resp_q  <= m_bresp;
            state_q <= ST_WR_LITE_B;
          end
        end

        ST_WR_LITE_B: begin
          if (s_axil_bready) begin
            aw_got_q <= 1'b0;
            w_got_q  <= 1'b0;
            state_q  <= ST_IDLE;
          end
        end

        ST_RD_CMD: begin
          if (m_arready) state_q <= ST_RD_DATA;
        end

        ST_RD_DATA: begin
          if (m_rvalid) begin
            rdata_q <= m_rdata[32 * lane_q +: 32];
            resp_q  <= m_rresp;
            state_q <= ST_RD_LITE_R;
          end
        end

        ST_RD_LITE_R: begin
          if (s_axil_rready) state_q <= ST_IDLE;
        end

        default: state_q <= ST_IDLE;
      endcase
    end
  end

endmodule
