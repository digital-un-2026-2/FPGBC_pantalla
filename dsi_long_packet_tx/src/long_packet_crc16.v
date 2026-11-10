`timescale 1ns / 1ps

// CRC DSI: x^16 + x^12 + x^5 + 1; bits del byte LSB primero.
// Inicialización FFFF, sin XOR final. Red combinacional de un byte.
module long_packet_crc16 (
    input [15:0] crc_in,
    input [7:0] byte_in,
    output reg [15:0] crc_out
);
  integer bit_index;
  always @(*) begin
    crc_out = crc_in;
    for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
      if (crc_out[0] ^ byte_in[bit_index])
        crc_out = (crc_out >> 1) ^ 16'h8408;
      else
        crc_out = crc_out >> 1;
    end
  end
endmodule
