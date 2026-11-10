`timescale 1ns / 1ps

module lane_register #(
    parameter BITS = 8
) (
    input clk, input rst,
    input [BITS-1:0] reg_in, input ld,
    output reg [BITS-1:0] reg_out
);
  always @(posedge clk) begin
    if (rst) reg_out <= {BITS{1'b0}};
    else if (ld) reg_out <= reg_in;
  end
endmodule
