`timescale 1ns / 1ps

module scheduler_register #(parameter integer BITS = 1) (
    input clk, input rst, input ld,
    input [BITS-1:0] d, output reg [BITS-1:0] q
);
  always @(posedge clk) begin
    if (rst) q <= {BITS{1'b0}};
    else if (ld) q <= d;
  end
endmodule
