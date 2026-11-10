`timescale 1ns / 1ps
// M0: entrada 0 = INDEX+1; entrada 1 = cero.
module hs_transport_mux #(parameter BITS = 8) (
    input [BITS-1:0] in0, input [BITS-1:0] in1,
    input sel, output [BITS-1:0] data_out
);
  assign data_out = sel ? in1 : in0;
endmodule
