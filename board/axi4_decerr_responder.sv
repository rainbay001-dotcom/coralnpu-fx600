// ============================================================================
// Terminates CoreMiniAxi's AXI4 master port. Accepts every transaction and
// returns DECERR, so a stray core access outside the TCMs errors instead of
// hanging the core (a ready-low tie-off would deadlock the LSU).
// ============================================================================

module axi4_decerr_responder (
  input  logic         aclk,
  input  logic         aresetn,

  output logic         s_awready,
  input  logic         s_awvalid,
  input  logic [5:0]   s_awid,
  output logic         s_wready,
  input  logic         s_wvalid,
  input  logic         s_wlast,
  input  logic         s_bready,
  output logic         s_bvalid,
  output logic [5:0]   s_bid,
  output logic [1:0]   s_bresp,

  output logic         s_arready,
  input  logic         s_arvalid,
  input  logic [5:0]   s_arid,
  input  logic [7:0]   s_arlen,
  input  logic         s_rready,
  output logic         s_rvalid,
  output logic [5:0]   s_rid,
  output logic [1:0]   s_rresp,
  output logic [127:0] s_rdata,
  output logic         s_rlast
);

  localparam logic [1:0] DECERR = 2'b11;

  // Write side: sink AW, sink W beats through last, then one DECERR B.
  typedef enum logic [1:0] {W_IDLE, W_DATA, W_RESP} wstate_e;
  wstate_e    wstate_q;
  logic [5:0] bid_q;

  assign s_awready = (wstate_q == W_IDLE);
  assign s_wready  = (wstate_q == W_DATA);
  assign s_bvalid  = (wstate_q == W_RESP);
  assign s_bid     = bid_q;
  assign s_bresp   = DECERR;

  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      wstate_q <= W_IDLE;
      bid_q    <= '0;
    end else begin
      unique case (wstate_q)
        W_IDLE: if (s_awvalid) begin
          bid_q    <= s_awid;
          wstate_q <= W_DATA;
        end
        W_DATA: if (s_wvalid && s_wlast) wstate_q <= W_RESP;
        W_RESP: if (s_bready)            wstate_q <= W_IDLE;
        default: wstate_q <= W_IDLE;
      endcase
    end
  end

  // Read side: accept AR, stream arlen+1 DECERR beats.
  typedef enum logic {R_IDLE, R_DATA} rstate_e;
  rstate_e    rstate_q;
  logic [5:0] rid_q;
  logic [7:0] rcnt_q;

  assign s_arready = (rstate_q == R_IDLE);
  assign s_rvalid  = (rstate_q == R_DATA);
  assign s_rid     = rid_q;
  assign s_rresp   = DECERR;
  assign s_rdata   = '0;
  assign s_rlast   = (rcnt_q == 8'd0);

  always_ff @(posedge aclk) begin
    if (!aresetn) begin
      rstate_q <= R_IDLE;
      rid_q    <= '0;
      rcnt_q   <= '0;
    end else begin
      unique case (rstate_q)
        R_IDLE: if (s_arvalid) begin
          rid_q    <= s_arid;
          rcnt_q   <= s_arlen;
          rstate_q <= R_DATA;
        end
        R_DATA: if (s_rready) begin
          if (rcnt_q == 8'd0) rstate_q <= R_IDLE;
          else                rcnt_q   <= rcnt_q - 8'd1;
        end
        default: rstate_q <= R_IDLE;
      endcase
    end
  end

endmodule
