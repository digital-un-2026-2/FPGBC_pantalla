`timescale 1ns/1ps
// Test-only S320/S480 contract model. NOT a vendor timing/PLL/OSER8 model.
// It deliberately supplies J+1 PCLK loads and centered CLK bit boundaries.
`ifndef GOWIN_MODEL_J
`define GOWIN_MODEL_J 0
`endif
module rPLL #(
    parameter FCLKIN="40.0", IDIV_SEL=0, FBDIV_SEL=3, ODIV_SEL=4,
    DYN_IDIV_SEL="false", DYN_FBDIV_SEL="false", DYN_ODIV_SEL="false",
    DYN_DA_EN="false", PSDA_SEL="0000", DUTYDA_SEL="1000",
    CLKFB_SEL="internal", DYN_SDIV_SEL=4, CLKOUTD_SRC="CLKOUT", DEVICE="GW2AR-18"
) (
    input CLKIN, RESET, RESET_P, CLKFB, input [5:0] FBDSEL, IDSEL, ODSEL,
    input [3:0] DUTYDA, PSDA, FDLY,
    output CLKOUT, CLKOUTP, CLKOUTD, CLKOUTD3, LOCK
);
  reg fast=1, shifted=0;
  reg locked=1, halted=0;
  localparam real HALF=FBDIV_SEL==5 ? 2.083333333 : 3.125;
  reg divided=0;
  reg [1:0] divider=0;
  always #(HALF) fast=~fast;
  always @(fast) shifted <= #(HALF/2) fast;
  always @(posedge fast) begin
    divider<=divider+1;
    if(divider==1 || divider==3) divided<=!divided;
  end
  assign CLKOUT=halted ? 1'b0 : fast;
  assign CLKOUTP=halted ? 1'b0 : shifted;
  assign CLKOUTD=halted ? 1'b0 : FBDIV_SEL==5 ? divided : CLKIN;
  assign CLKOUTD3=1'b0;
  assign LOCK=locked && !RESET;
endmodule

module OSER8 #(parameter GSREN="false", LSREN="true", HWL="false", TXCLK_POL=0) (
    input D0,D1,D2,D3,D4,D5,D6,D7,TX0,TX1,TX2,TX3,PCLK,FCLK,RESET,
    output reg Q0, output Q1
);
  localparam J=`GOWIN_MODEL_J;
  reg [7:0] stages[0:J];
  integer i, bit_index=0;
  // Samples the pre-edge value, including the real R_FRAME ahead of OSER8.
  always @(posedge PCLK or posedge RESET) begin
    if (RESET) begin
      for (i=0;i<=J;i=i+1) stages[i]<=0;
      bit_index=0;
    end else begin
      stages[0]<={D7,D6,D5,D4,D3,D2,D1,D0};
      for (i=1;i<=J;i=i+1) stages[i]<=stages[i-1];
      bit_index=0;
    end
  end
  always @(posedge FCLK or negedge FCLK or posedge RESET) begin
    if (RESET) Q0=0;
    else begin
      #0.001;
      if (RESET) Q0=0;
      else begin Q0=stages[J][bit_index]; bit_index=(bit_index+1)%8; end
    end
  end
  assign Q1=1'b0;
endmodule
module TBUF(input I,OEN,output O);
  assign O=OEN ? 1'bz : I;
endmodule
module TLVDS_TBUF(input I,OEN,output O,OB);
  assign O=OEN ? 1'bz : I;
  assign OB=OEN ? 1'bz : ~I;
endmodule
