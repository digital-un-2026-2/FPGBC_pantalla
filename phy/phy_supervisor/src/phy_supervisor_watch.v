module phy_supervisor_watch (
    input CLK_WD, RST_WD, CLK_WATCH, RST_SUP,
    output reg OK,
    output ACKED
);
  wire RST_WATCH;
  reg REQ, SENT;
  reg [6:0] AGE;
  (* async_reg = "true" *) reg [1:0] REQ_SYNC, ACK_SYNC;

  phy_supervisor_reset_sync reset_watch (
      .CLK(CLK_WATCH), .RESET_IN(RST_SUP), .RESET_OUT(RST_WATCH)
  );

  always @(negedge CLK_WATCH or posedge RST_WATCH) begin
    if (RST_WATCH) REQ_SYNC <= 2'b00;
    else REQ_SYNC <= {REQ_SYNC[0], REQ};
  end

  always @(negedge CLK_WD or posedge RST_WD) begin
    if (RST_WD) ACK_SYNC <= 2'b00;
    else ACK_SYNC <= {ACK_SYNC[0], REQ_SYNC[1]};
  end

  assign ACKED = SENT && (REQ == ACK_SYNC[1]);

  always @(negedge CLK_WD or posedge RST_WD) begin
    if (RST_WD) begin
      REQ <= 1'b0;
      SENT <= 1'b0;
      AGE <= 7'd0;
      OK <= 1'b0;
    end else if (!SENT || ACKED) begin
      REQ <= !REQ;
      SENT <= 1'b1;
      AGE <= 7'd0;
      OK <= SENT;
    end else if (AGE < 7'd64) begin
      AGE <= AGE + 1'b1;
      if (AGE == 7'd63) OK <= 1'b0;
    end
    // Even after timeout, keep the same request outstanding until ACK.
  end
endmodule
