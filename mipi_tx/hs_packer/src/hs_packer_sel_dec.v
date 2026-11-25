module hs_packer_sel_dec #(
    parameter [10:0] CNT_DONE = 11'd1083
) (
    input [10:0] CNT,
    input PK_START,

    output reg [1:0] SEL_WORD,
    output CNT_EN,
    output VID_RD,
    output CRC_CLR,
    output PK_DONE
);
  localparam [10:0] CNT_PIX = 11'd2;
  localparam [10:0] CNT_CRC = CNT_DONE - 11'd1;

  // VID_RD habilita también el CRC: ambos consumen la misma palabra en negedge.
  assign CRC_CLR = PK_START && (CNT == 11'd0);
  assign CNT_EN = CRC_CLR || ((CNT != 11'd0) && (CNT <= CNT_DONE));
  assign VID_RD = (CNT >= CNT_PIX) && (CNT < CNT_CRC);
  assign PK_DONE = (CNT == CNT_DONE);

  always @(*) begin
    if (CNT < CNT_PIX) SEL_WORD = 2'b00;         // Cabecera.
    else if (VID_RD) SEL_WORD = 2'b01;           // Píxeles.
    else if (CNT == CNT_CRC) SEL_WORD = 2'b10;   // CRC final.
    else SEL_WORD = 2'b11;                       // Sin palabra.
  end
endmodule
