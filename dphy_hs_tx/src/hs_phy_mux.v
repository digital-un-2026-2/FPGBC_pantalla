`timescale 1ns/1ps
module hs_phy_mux #(parameter WIDTH=16, INPUTS=2, SEL_WIDTH=1) (
    input [WIDTH*INPUTS-1:0] values, input [SEL_WIDTH-1:0] sel,
    output reg [WIDTH-1:0] value
);
  always @(*) begin
    value = {WIDTH{1'b0}};
    if (sel < INPUTS) value = values[sel*WIDTH +: WIDTH];
  end
endmodule
