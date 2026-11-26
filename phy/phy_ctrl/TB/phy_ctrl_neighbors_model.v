`timescale 1ns / 1ps

// Solo banco: un slot por ↓, sin DDR. Los pares HS de datos muestran un bit
// representativo por carril; la palabra latcheada representa el slot completo.
module phy_ctrl_neighbors_model (
    input CLK_BYTE,
    input CLK_CARRIER,
    input [2:0] LP_P,
    input [2:0] LP_N,
    input [7:0] HS_BYTE0,
    input [7:0] HS_BYTE1,
    input LP_EN,
    input HS_EN,
    input CLK_EN,
    input CLK_ARM,
    input ISO,
    input [1:0] SER_MODE,

    output reg [1:0] SERIAL_SLOT,
    output reg [15:0] SERIAL_WORD,
    output [2:0] PAD_P,
    output [2:0] PAD_N
);
  localparam [1:0] OFF = 2'b00, WORD = 2'b10, TRAIL = 2'b11;
  reg CLK_PREPARED;

  // Cambiar SER_MODE en ↑ no conmuta ni el patrón ni la palabra del slot en
  // curso. ISO sí puede abortarlo sin esperar al reloj.
  always @(negedge CLK_BYTE or posedge ISO) begin
    if (ISO) begin
      SERIAL_SLOT <= OFF;
      SERIAL_WORD <= 16'h0000;
      CLK_PREPARED <= 1'b0;
    end else begin
      SERIAL_SLOT <= SER_MODE;
      if (SER_MODE == WORD) SERIAL_WORD <= {HS_BYTE1, HS_BYTE0};
      CLK_PREPARED <= CLK_ARM;
    end
  end

  wire [1:0] HS_BITS = (SERIAL_SLOT == WORD) ? {SERIAL_WORD[8], SERIAL_WORD[0]} :
                       (SERIAL_SLOT == TRAIL) ? 2'b11 : 2'b00;
  wire DRIVE_LP = LP_EN && !ISO;
  wire DRIVE_HS = HS_EN && !ISO;
  wire DRIVE_CLK = CLK_PREPARED && CLK_EN && !ISO;

  // Resolución ideal de drivers: no se modelan resistencias, fase D-PHY ni pads Gowin.
  assign PAD_P = DRIVE_LP ? LP_P : 3'bzzz;
  assign PAD_N = DRIVE_LP ? LP_N : 3'bzzz;
  assign PAD_P[1:0] = DRIVE_HS ? HS_BITS : 2'bzz;
  assign PAD_N[1:0] = DRIVE_HS ? ~HS_BITS : 2'bzz;
  assign PAD_P[2] = DRIVE_CLK ? CLK_CARRIER : 1'bz;
  assign PAD_N[2] = DRIVE_CLK ? !CLK_CARRIER : 1'bz;
endmodule
