// Adaptador lógico: captura en negedge lo presentado antes del flanco.
// En el negedge que acepta PK_START en el packer, el mux ya selecciona W0.
// La selección de modo físico y la habilitación de drivers no pasan por aquí.
module phy_if (
    input CLK_BYTE,
    input RST_BYTE,  // Síncrono activo en 1.
    input [1:0] SEL_OUT,
    input [1:0] LP_FORCE,
    input SOT_EN,
    input [1:0] LP_D0,
    input [15:0] WORD,

    output [2:0] LP_P,
    output [2:0] LP_N,
    output [7:0] HS_BYTE0,
    output [7:0] HS_BYTE1
);
  wire LP_USE_D0;
  wire [1:0] FORCED_PN;
  wire [1:0] HS_SEL;
  wire [2:0] LP_P_D, LP_N_D;
  wire [7:0] BYTE0_D, BYTE1_D;

  phy_if_out_sel out_sel (
      .SEL_OUT(SEL_OUT), .LP_FORCE(LP_FORCE), .SOT_EN(SOT_EN),
      .LP_USE_D0(LP_USE_D0), .FORCED_PN(FORCED_PN), .HS_SEL(HS_SEL)
  );

  phy_if_lp_mux lp_mux (
      .LP_D0(LP_D0), .LP_USE_D0(LP_USE_D0), .FORCED_PN(FORCED_PN),
      .LP_P_D(LP_P_D), .LP_N_D(LP_N_D)
  );

  phy_if_hs_mux hs_mux (
      .WORD(WORD), .HS_SEL(HS_SEL),
      .BYTE0_D(BYTE0_D), .BYTE1_D(BYTE1_D)
  );

  reg_0 #(.BITS(6), .RESET_VALUE(6'b111111)) lp_out_reg (
      .clk(CLK_BYTE), .rst(RST_BYTE), .ld(1'b1),
      .reg_in({LP_P_D, LP_N_D}), .reg_out({LP_P, LP_N})
  );

  reg_0 #(.BITS(16), .RESET_VALUE(16'h0000)) hs_out_reg (
      .clk(CLK_BYTE), .rst(RST_BYTE), .ld(1'b1),
      .reg_in({BYTE1_D, BYTE0_D}), .reg_out({HS_BYTE1, HS_BYTE0})
  );
endmodule
