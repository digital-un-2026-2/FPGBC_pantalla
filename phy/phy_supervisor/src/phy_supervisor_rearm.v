module phy_supervisor_rearm (
    input CLK_BYTE, CUT_REQ,
    output reg RST_BYTE = 1'b1
);
  (* async_reg = "true" *) reg [1:0] PERMIT = 2'b00;
  reg UP_SEEN = 1'b0, PAIR_SEEN = 1'b0;
  wire CUT_LOCAL = !PERMIT[1];

  always @(posedge CLK_BYTE or posedge CUT_REQ) begin
    if (CUT_REQ) PERMIT <= 2'b00;
    else PERMIT <= {PERMIT[0], 1'b1};
  end

  always @(posedge CLK_BYTE or posedge CUT_LOCAL) begin
    if (CUT_LOCAL) begin
      UP_SEEN <= 1'b0;
      RST_BYTE <= 1'b1;
    end else begin
      UP_SEEN <= 1'b1;
      RST_BYTE <= !PAIR_SEEN;
    end
  end

  always @(negedge CLK_BYTE or posedge CUT_LOCAL) begin
    if (CUT_LOCAL) PAIR_SEEN <= 1'b0;
    else PAIR_SEEN <= UP_SEEN;
  end
endmodule
