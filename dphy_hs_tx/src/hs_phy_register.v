`timescale 1ns/1ps
module hs_phy_register #(parameter WIDTH=1, parameter RESET_DATA=1) (
    input clk, rst, en, input [WIDTH-1:0] d, output reg [WIDTH-1:0] q
);
  always @(posedge clk) begin
    if (RESET_DATA && rst) q <= {WIDTH{1'b0}};
    else if (!rst && en) q <= d;
  end
endmodule
