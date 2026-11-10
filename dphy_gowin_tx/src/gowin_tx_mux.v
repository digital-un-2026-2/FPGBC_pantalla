`timescale 1ns/1ps
module gowin_tx_mux #(parameter WIDTH=1) (
    input [WIDTH-1:0] d0, d1, input sel, output [WIDTH-1:0] q
);
  assign q = sel ? d1 : d0;
endmodule
