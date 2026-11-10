`timescale 1ns/1ps
module hs_phy_zero #(parameter WIDTH=12) (
    input [WIDTH-1:0] value, output is_zero
);
  assign is_zero = (value == {WIDTH{1'b0}});
endmodule
