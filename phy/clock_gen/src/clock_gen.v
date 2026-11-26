// Relojes internos del PHY para GW2AR-LV18EQ144PC8/I7.
// RESET reinicia la PLL, no es RST_BYTE. No se conmuta ni se inhibe un reloj
// por LOCK o por peticiones de enlace. La fase de HS_CLK no se genera aquí.
module clock_gen (
    input  CLK_REF,
    input  RESET,
    output CLK_BYTE,
    output CLK_HS,
    output LOCK_RAW
);
  rPLL #(
      .DEVICE("GW2AR-18"),
      .FCLKIN("40"),
      .DYN_IDIV_SEL("false"),
      .IDIV_SEL(1),             // 40 / 2 = 20 MHz en PFD.
      .DYN_FBDIV_SEL("false"),
      .FBDIV_SEL(10),           // 20 × 11 = 220 MHz en CLKOUT.
      .DYN_ODIV_SEL("false"),
      .ODIV_SEL(4),             // 220 × 4 = 880 MHz en VCO.
      .CLKFB_SEL("internal"),
      .DYN_DA_EN("false"),
      .CLKOUT_BYPASS("false"),
      .CLKOUTD_BYPASS("false"),
      .CLKOUTD_SRC("CLKOUT"),
      .DYN_SDIV_SEL(4)          // 220 / 4 = 55 MHz en CLKOUTD.
  ) pll (
      .CLKIN(CLK_REF),
      .RESET(RESET),
      .RESET_P(1'b0),
      .CLKFB(1'b0),
      .IDSEL(6'b0),
      .FBDSEL(6'b0),
      .ODSEL(6'b0),
      .PSDA(4'b0),
      .DUTYDA(4'b0),
      .FDLY(4'b0),
      .CLKOUT(CLK_HS),
      .CLKOUTD(CLK_BYTE),
      .CLKOUTP(),
      .CLKOUTD3(),
      .LOCK(LOCK_RAW)
  );
endmodule
