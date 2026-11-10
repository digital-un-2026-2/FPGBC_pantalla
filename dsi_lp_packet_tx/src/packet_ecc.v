`timescale 1ns / 1ps

module packet_ecc (
    input [23:0] header,
    output [7:0] ecc
);

  // header = {Data 1, Data 0, Data ID}; header[0] es D0 de DSI.
  // Misma matriz que dsi_header_ecc en scripts/test_lpdt_hw.py.
  // Referencia de contraste: sun6i_dsi_ecc_array del driver Linux sun6i_mipi_dsi.
  assign ecc[0] = header[0] ^ header[1] ^ header[2] ^ header[4] ^ header[5]
                ^ header[7] ^ header[10] ^ header[11] ^ header[13] ^ header[16]
                ^ header[20] ^ header[21] ^ header[22] ^ header[23];
  assign ecc[1] = header[0] ^ header[1] ^ header[3] ^ header[4] ^ header[6]
                ^ header[8] ^ header[10] ^ header[12] ^ header[14] ^ header[17]
                ^ header[20] ^ header[21] ^ header[22] ^ header[23];
  assign ecc[2] = header[0] ^ header[2] ^ header[3] ^ header[5] ^ header[6]
                ^ header[9] ^ header[11] ^ header[12] ^ header[15] ^ header[18]
                ^ header[20] ^ header[21] ^ header[22];
  assign ecc[3] = header[1] ^ header[2] ^ header[3] ^ header[7] ^ header[8]
                ^ header[9] ^ header[13] ^ header[14] ^ header[15] ^ header[19]
                ^ header[20] ^ header[21] ^ header[23];
  assign ecc[4] = header[4] ^ header[5] ^ header[6] ^ header[7] ^ header[8]
                ^ header[9] ^ header[16] ^ header[17] ^ header[18] ^ header[19]
                ^ header[20] ^ header[22] ^ header[23];
  assign ecc[5] = header[10] ^ header[11] ^ header[12] ^ header[13] ^ header[14]
                ^ header[15] ^ header[16] ^ header[17] ^ header[18] ^ header[19]
                ^ header[21] ^ header[22] ^ header[23];
  assign ecc[7:6] = 2'b00;

endmodule
