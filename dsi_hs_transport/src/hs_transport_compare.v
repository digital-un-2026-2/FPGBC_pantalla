`timescale 1ns / 1ps
module hs_transport_compare #(parameter BITS = 8, parameter NOT_EQUAL = 0) (
    input [BITS-1:0] a, input [BITS-1:0] b, output z
);
  assign z = NOT_EQUAL ? (a != b) : (a == b);
endmodule
