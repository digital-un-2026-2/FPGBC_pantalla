`timescale 1ns / 1ps
// Sigma0/Sigma1 suman uno; Sigma2 resta uno. Aritmetica modular BITS.
module hs_transport_add #(parameter BITS = 8, parameter SUBTRACT = 0) (
    input [BITS-1:0] data_in, output [BITS-1:0] data_out
);
  assign data_out = SUBTRACT ? data_in - 1'b1 : data_in + 1'b1;
endmodule
