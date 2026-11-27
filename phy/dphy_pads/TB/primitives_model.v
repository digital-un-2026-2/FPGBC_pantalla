`timescale 1ps / 1ps

module TBUF (input I, OEN, output O);
  assign O = OEN ? 1'bz : I;
endmodule

module TLVDS_TBUF (input I, OEN, output O, OB);
  assign O  = OEN ? 1'bz : I;
  assign OB = OEN ? 1'bz : ~I;
endmodule

module IOBUF (input I, OEN, output O, inout IO);
  assign IO = OEN ? 1'bz : I;
  assign O = IO;
endmodule
