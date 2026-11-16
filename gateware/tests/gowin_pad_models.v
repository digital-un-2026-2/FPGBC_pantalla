// Modelos funcionales de prueba, NO modelos eléctricos ni bibliotecas Gowin.
`timescale 1ns/1ps
module TBUF(input I, input OEN, output O);
  assign O = OEN ? 1'bz : I;
endmodule

module TLVDS_TBUF(input I, input OEN, output O, output OB);
  assign O = OEN ? 1'bz : I;
  assign OB = OEN ? 1'bz : ~I;
endmodule

module IBUF(input I, output O);
  assign O = I;
endmodule
