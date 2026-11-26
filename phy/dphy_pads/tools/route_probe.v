// Sonda offline. El estímulo cambia los OE y símbolos independientemente
// para que ningún pin o ruta se elimine por propagación de constantes.
module route_probe #(parameter DELAY = 1'b0) (
    input CLK_REF, RESET_N,
    output LP_D0_P, LP_D0_N, LP_D1_P, LP_D1_N, LP_CLK_P, LP_CLK_N,
    output HS_D0_P, HS_D0_N, HS_D1_P, HS_D1_N, HS_CLK_P, HS_CLK_N
);
  wire CLK_BYTE, CLK_HS, LOCK_RAW, HS_D0, HS_D1, HS_CLK;
  wire RST_BYTE = !RESET_N;
  wire ISO = RST_BYTE || !LOCK_RAW;
  reg [29:0] stimulus;

  clock_gen clocks (CLK_REF, 1'b0, CLK_BYTE, CLK_HS, LOCK_RAW);
  clock_ddr #(.USE_IODELAY(DELAY), .STATIC_DELAY_TAPS(32)) forwarded (
      .CLK_HS(CLK_HS), .ISO(ISO), .HS_CLK(HS_CLK)
  );
  always @(negedge CLK_BYTE) begin
    if (RST_BYTE) stimulus <= 0;
    else          stimulus <= stimulus + 1'b1;
  end
  hs_serializer d0 (CLK_BYTE, CLK_HS, RST_BYTE, ISO, stimulus[9:8], stimulus[7:0], HS_D0);
  hs_serializer d1 (CLK_BYTE, CLK_HS, RST_BYTE, ISO, stimulus[9:8], stimulus[17:10], HS_D1);

  dphy_pads pads (
      .LP_P(stimulus[20:18]), .LP_N(stimulus[23:21]),
      .HS_D0(HS_D0), .HS_D1(HS_D1), .HS_CLK(HS_CLK),
      .LP_DAT_MODE(stimulus[25:24]), .LP_CLK_MODE(stimulus[27:26]),
      .HS_EN(stimulus[28]), .CLK_EN(stimulus[29]), .ISO(ISO),
      .LP_D0_P(LP_D0_P), .LP_D0_N(LP_D0_N), .LP_D1_P(LP_D1_P), .LP_D1_N(LP_D1_N),
      .LP_CLK_P(LP_CLK_P), .LP_CLK_N(LP_CLK_N),
      .HS_D0_P(HS_D0_P), .HS_D0_N(HS_D0_N), .HS_D1_P(HS_D1_P), .HS_D1_N(HS_D1_N),
      .HS_CLK_P(HS_CLK_P), .HS_CLK_N(HS_CLK_N)
  );
endmodule
