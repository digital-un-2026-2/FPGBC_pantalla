`timescale 1ns/1ps
// Candidate IOLOGIC binding. MAP_BITS selects the source bit for D0..D7.
// Default identity is a model convention, NOT a characterized Gowin profile.
module gowin_tx_ser8 #(
    parameter [23:0] MAP_BITS=24'hfac688, parameter HWL="false"
) (input [7:0] d, input pclk, fclk, rst, output q);
  wire [7:0] mapped;
  genvar b;
  generate for (b=0;b<8;b=b+1) begin: bit_map
    assign mapped[b] = d[MAP_BITS[3*b +: 3]];
  end endgenerate
  OSER8 #(.GSREN("false"),.LSREN("true"),.HWL(HWL),.TXCLK_POL(1'b0)) ser (
      .D0(mapped[0]),.D1(mapped[1]),.D2(mapped[2]),.D3(mapped[3]),
      .D4(mapped[4]),.D5(mapped[5]),.D6(mapped[6]),.D7(mapped[7]),
      .TX0(1'b0),.TX1(1'b0),.TX2(1'b0),.TX3(1'b0),
      .PCLK(pclk),.FCLK(fclk),.RESET(rst),.Q0(q),.Q1());
endmodule
