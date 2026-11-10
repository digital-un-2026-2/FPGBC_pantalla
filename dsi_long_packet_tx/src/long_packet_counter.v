`timescale 1ns / 1ps

module long_packet_counter #(
    parameter BITS = 2
) (
    input clk,
    input rst,
    input inc,

    output reg [BITS-1:0] count_out
);

  always @(posedge clk) begin
    if (rst) begin
      count_out <= {BITS{1'b0}};
    end else if (inc) begin
      count_out <= count_out + 1'b1;
    end
  end

endmodule
