`timescale 1ns/1ps
module hs_phy_sub #(parameter WIDTH=12) (
    input [WIDTH-1:0] value, output [WIDTH-1:0] result
);
  assign result = value - {{(WIDTH-1){1'b0}},1'b1};
endmodule
