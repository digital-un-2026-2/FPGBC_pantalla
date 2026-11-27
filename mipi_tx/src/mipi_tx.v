// Cableado del transmisor lógico: sin estado ni registros propios.
module mipi_tx #(
    parameter integer LP_DIV = 1,
    parameter integer T_LPX = 1,
    parameter integer T_PREP = 1,
    parameter integer T_ZERO = 1,
    parameter integer T_TRAIL = 1,
    parameter integer C_LINE = 1091,
    parameter integer T_CLK_START = 0,
    parameter FRAME_MODE = 1'b0
) (
    input CLK_BYTE,
    input RST_BYTE,  // Síncrono activo en 1: cubrir un ↑ y el ↓ siguiente.

    input INIT_REQ,
    input [7:0] INIT_BYTE,
    input INIT_LAST,
    output INIT_READY,
    output INIT_NEXT,
    output INIT_DONE_TX,

    input VID_REQ,
    input VID_LINE_RDY,
    input [15:0] VID_WORD,
    output VID_RD,

    input READY,
    input LOCK,
    output HS_REQ,
    output CLK_REQ,
    output [2:0] LP_P,
    output [2:0] LP_N,
    output [7:0] HS_BYTE0,
    output [7:0] HS_BYTE1
);
  wire LP_START, LP_DONE, PK_START, PK_DONE, SOT_EN;
  wire [1:0] LP_D0, SEL_OUT, LP_FORCE;
  wire [15:0] WORD;
  wire [1:0] BURST_KIND;

  link_fsm #(
      .T_LPX(T_LPX), .T_PREP(T_PREP), .T_ZERO(T_ZERO), .T_TRAIL(T_TRAIL),
      .C_LINE(C_LINE), .T_CLK_START(T_CLK_START), .FRAME_MODE(FRAME_MODE)
  ) link (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE),
      .INIT_REQ(INIT_REQ), .INIT_READY(INIT_READY), .INIT_DONE_TX(INIT_DONE_TX),
      .VID_REQ(VID_REQ), .VID_LINE_RDY(VID_LINE_RDY),
      .READY(READY), .LOCK(LOCK), .HS_REQ(HS_REQ), .CLK_REQ(CLK_REQ),
      .LP_START(LP_START), .LP_DONE(LP_DONE), .PK_START(PK_START), .PK_DONE(PK_DONE),
      .SEL_OUT(SEL_OUT), .LP_FORCE(LP_FORCE), .SOT_EN(SOT_EN), .BURST_KIND(BURST_KIND)
  );

  lp_tx #(.LP_DIV(LP_DIV)) lp (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE),
      .INIT_BYTE(INIT_BYTE), .INIT_LAST(INIT_LAST), .INIT_NEXT(INIT_NEXT),
      .LP_START(LP_START), .LP_DONE(LP_DONE), .LP_D0(LP_D0)
  );

  hs_packer #(.FRAME_MODE(FRAME_MODE)) packer (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE),
      .VID_WORD(VID_WORD), .VID_RD(VID_RD),
      .PK_START(PK_START), .PK_DONE(PK_DONE), .WORD(WORD), .BURST_KIND(BURST_KIND)
  );

  phy_if phy (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE),
      .SEL_OUT(SEL_OUT), .LP_FORCE(LP_FORCE), .SOT_EN(SOT_EN),
      .LP_D0(LP_D0), .WORD(WORD),
      .LP_P(LP_P), .LP_N(LP_N), .HS_BYTE0(HS_BYTE0), .HS_BYTE1(HS_BYTE1)
  );
endmodule
