module hs_packer_crc16 (
    input CLK_BYTE,
    input RST_BYTE,
    input CRC_CLR,
    input CRC_EN,
    input [15:0] VID_WORD,

    output reg [15:0] CRC_WORD
);
  localparam [15:0] POLY = 16'h8408;

  function [15:0] crc_byte(input [15:0] crc, input [7:0] dato);
    reg [15:0] resto;
    integer i;
    begin
      resto = crc ^ {8'h00, dato};
      for (i = 0; i < 8; i = i + 1)
        resto = (resto >> 1) ^ ({16{resto[0]}} & POLY);
      crc_byte = resto;
    end
  endfunction

  // Dos pasos combinacionales, D0 y luego D1; un solo registro sin XOR final.
  always @(negedge CLK_BYTE) begin
    if (RST_BYTE || CRC_CLR) begin
      CRC_WORD <= 16'hffff;
    end else if (CRC_EN) begin
      CRC_WORD <= crc_byte(crc_byte(CRC_WORD, VID_WORD[7:0]), VID_WORD[15:8]);
    end
  end
endmodule
