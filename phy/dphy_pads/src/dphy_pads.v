module dphy_pads (
    input [2:0] LP_P, LP_N,
    input HS_D0, HS_D1, HS_CLK,
    input [1:0] LP_DAT_MODE, LP_CLK_MODE,
    input HS_EN, CLK_EN, ISO,
    output LP_D0_P, LP_D0_N, LP_D1_P, LP_D1_N, LP_CLK_P, LP_CLK_N,
    output HS_D0_P, HS_D0_N, HS_D1_P, HS_D1_N, HS_CLK_P, HS_CLK_N
);
  localparam [1:0] LP_DRIVE = 2'b01, LP_BIAS = 2'b10;

  wire drive_dat = LP_DAT_MODE == LP_DRIVE;
  wire drive_clk = LP_CLK_MODE == LP_DRIVE;
  wire bias_dat = LP_DAT_MODE == LP_BIAS;
  wire bias_clk = LP_CLK_MODE == LP_BIAS;

  // An HS request without bias cannot enable the differential driver.
  // A simultaneous request for an LP symbol and HS isolates that group.
  wire oen_lp_dat = ISO || !(bias_dat || (drive_dat && !HS_EN));
  wire oen_lp_clk = ISO || !(bias_clk || (drive_clk && !CLK_EN));
  wire oen_hs_dat = ISO || !HS_EN || !bias_dat;
  wire oen_hs_clk = ISO || !CLK_EN || !bias_clk;

  TBUF lp_d0_p (.I(drive_dat && LP_P[0]), .OEN(oen_lp_dat), .O(LP_D0_P));
  TBUF lp_d0_n (.I(drive_dat && LP_N[0]), .OEN(oen_lp_dat), .O(LP_D0_N));
  TBUF lp_d1_p (.I(drive_dat && LP_P[1]), .OEN(oen_lp_dat), .O(LP_D1_P));
  TBUF lp_d1_n (.I(drive_dat && LP_N[1]), .OEN(oen_lp_dat), .O(LP_D1_N));
  TBUF lp_clk_p (.I(drive_clk && LP_P[2]), .OEN(oen_lp_clk), .O(LP_CLK_P));
  TBUF lp_clk_n (.I(drive_clk && LP_N[2]), .OEN(oen_lp_clk), .O(LP_CLK_N));

  TLVDS_TBUF hs_d0 (.I(HS_D0), .OEN(oen_hs_dat), .O(HS_D0_P), .OB(HS_D0_N));
  TLVDS_TBUF hs_d1 (.I(HS_D1), .OEN(oen_hs_dat), .O(HS_D1_P), .OB(HS_D1_N));
  TLVDS_TBUF hs_clk (.I(HS_CLK), .OEN(oen_hs_clk), .O(HS_CLK_P), .OB(HS_CLK_N));
endmodule
