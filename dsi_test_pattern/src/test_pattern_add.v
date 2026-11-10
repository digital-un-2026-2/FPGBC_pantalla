`timescale 1ns / 1ps

module test_pattern_add #(parameter BITS = 8) (
    input [BITS-1:0] data_in, output [BITS-1:0] data_out
);
  assign data_out = data_in + 1'b1;
endmodule
