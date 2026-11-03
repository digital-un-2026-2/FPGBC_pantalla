`timescale 1ns / 1ps

// Modelos funcionales ideales de las primitivas Gowin usadas por el DUT.
// SOLO simulacion: no incluir este archivo en las fuentes de sintesis.
// No representan umbrales, resistencias, retardos, pulls ni D-PHY.
module IOBUF (
    output O,
    inout IO,
    input I,
    input OEN
);
  assign IO = OEN ? 1'bz : I;
  assign O = IO;
endmodule

module TBUF (
    output O,
    input I,
    input OEN
);
  assign O = OEN ? 1'bz : I;
endmodule
