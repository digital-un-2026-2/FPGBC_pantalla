`timescale 1ns/1ps
// Candidate rPLL wiring, not a characterized PLL/clock-tree profile.
// Values must come from device-specific characterization before PROFILE_OK=1.
// Defaults only express nominal S320 ratios; PHASE=0000 is not centered CLK.
module gowin_tx_pll #(
    parameter IDIV=0, FBDIV=3, ODIV=4, SDIV=4,
    parameter PHASE="0000", parameter DEVICE="GW2AR-18"
) (input ref_clk, rst, output byte_clk, fclk_d, fclk_c, lock_raw);
  rPLL #(.FCLKIN("40.0"),.IDIV_SEL(IDIV),.FBDIV_SEL(FBDIV),.ODIV_SEL(ODIV),
      .DYN_IDIV_SEL("false"),.DYN_FBDIV_SEL("false"),.DYN_ODIV_SEL("false"),
      .DYN_DA_EN("false"),.PSDA_SEL(PHASE),.DUTYDA_SEL("1000"),
      .CLKFB_SEL("internal"),.DYN_SDIV_SEL(SDIV),.CLKOUTD_SRC("CLKOUT"),
      .DEVICE(DEVICE)) pll0 (
      .CLKIN(ref_clk),.RESET(rst),.RESET_P(1'b0),.CLKFB(1'b0),
      .FBDSEL(6'b0),.IDSEL(6'b0),.ODSEL(6'b0),.DUTYDA(4'b0),.PSDA(4'b0),.FDLY(4'b0),
      .CLKOUT(fclk_d),.CLKOUTP(fclk_c),.CLKOUTD(byte_clk),.CLKOUTD3(),.LOCK(lock_raw));
endmodule
