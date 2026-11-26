// Modelos funcionales de prueba, NO modelos eléctricos ni bibliotecas Gowin.
`timescale 1ns/1ps
`ifndef FPGBC_WHITE
module TBUF(input I, input OEN, output O);
  assign O = OEN ? 1'bz : I;
endmodule

module IOBUF(input I, input OEN, output O, inout IO);
  assign IO = OEN ? 1'bz : I;
  assign O = IO;
endmodule
`endif

module IBUF(input I, output O);
  assign O = I;
endmodule

module OBUF(input I, output O);
  assign O = I;
endmodule
