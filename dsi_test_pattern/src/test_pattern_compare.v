`timescale 1ns / 1ps

module test_pattern_compare #(parameter BITS = 8, parameter GREATER_EQUAL = 0) (
    input [BITS-1:0] a, input [BITS-1:0] b, output z
);
  assign z = GREATER_EQUAL ? (a >= b) : (a == b);
endmodule
