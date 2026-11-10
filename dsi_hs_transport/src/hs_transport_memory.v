`timescale 1ns / 1ps
module hs_transport_memory #(
    parameter integer WORDS = 2048,
    parameter integer ADDR_BITS = (WORDS > 1) ? $clog2(WORDS) : 1
) (
    input clk, input write_en, input read_en,
    input [ADDR_BITS-1:0] write_address, input [ADDR_BITS-1:0] read_address,
    input [17:0] data_in, output reg [17:0] q
);
  reg [17:0] memory [0:WORDS-1];
  // Q es el registro de lectura: no hay una segunda etapa de salida.
  // Sin reset en RAM/Q; la UC y los contadores invalidan el paquete.
  always @(posedge clk) begin
    if (write_en) memory[write_address] <= data_in;
    if (read_en) q <= memory[read_address];
  end
endmodule
