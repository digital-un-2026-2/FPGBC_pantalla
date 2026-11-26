`timescale 1ps / 1ps

module TBUF (input I, OEN, output O);
  assign O = OEN ? 1'bz : I;
endmodule

module TLVDS_TBUF (input I, OEN, output O, OB);
  assign O  = OEN ? 1'bz : I;
  assign OB = OEN ? 1'bz : ~I;
endmodule
