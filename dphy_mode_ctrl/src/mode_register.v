`timescale 1ns / 1ps

module mode_register #(
    parameter BITS = 1,
    parameter [BITS-1:0] RESET_VALUE = {BITS{1'b0}}
) (
    input clk, input rst, input ld,
    input [BITS-1:0] data_in,
    output reg [BITS-1:0] data_out
);
  always @(negedge clk) begin
    if (rst) data_out <= RESET_VALUE;
    else if (ld) data_out <= data_in;
  end
endmodule
