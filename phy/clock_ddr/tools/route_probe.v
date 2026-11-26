// Sonda de P&R: los buffers son sumideros, no drivers del PHY.
module route_probe #(parameter DELAY = 1'b0) (
    input CLK_REF, RESET_N,
    output D0_P, D0_N, D1_P, D1_N, CLK_P, CLK_N
);
  wire CLK_BYTE, CLK_HS, LOCK_RAW, HS_D0, HS_D1, HS_CLK;
  wire RST_BYTE = !RESET_N;
  wire ISO = RST_BYTE || !LOCK_RAW;
  reg [17:0] stimulus;

  clock_gen clocks (CLK_REF, 1'b0, CLK_BYTE, CLK_HS, LOCK_RAW);
  clock_ddr #(.USE_IODELAY(DELAY), .STATIC_DELAY_TAPS(32)) forwarded (
      .CLK_HS(CLK_HS), .ISO(ISO), .CLK_TOGGLE(1'b1), .HS_CLK(HS_CLK)
  );

  always @(negedge CLK_BYTE) begin
    if (RST_BYTE) stimulus <= 0;
    else          stimulus <= stimulus + 1'b1;
  end

  hs_serializer d0 (CLK_BYTE, CLK_HS, RST_BYTE, ISO, stimulus[9:8], stimulus[7:0], HS_D0);
  hs_serializer d1 (CLK_BYTE, CLK_HS, RST_BYTE, ISO, stimulus[9:8], stimulus[17:10], HS_D1);
  TLVDS_OBUF sink_d0 (.I(HS_D0), .O(D0_P), .OB(D0_N));
  TLVDS_OBUF sink_d1 (.I(HS_D1), .O(D1_P), .OB(D1_N));
  TLVDS_TBUF sink_clk (.I(HS_CLK), .OEN(ISO), .O(CLK_P), .OB(CLK_N));
endmodule
