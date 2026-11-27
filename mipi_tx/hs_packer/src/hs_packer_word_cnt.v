// CNT=0 mantiene W0 preparada hasta aceptar PK_START.
// CNT_DONE dura un ciclo después de transferir el CRC; no indexa una palabra.
module hs_packer_word_cnt #(
    parameter integer W = 11,
    parameter [W-1:0] CNT_DONE = 1083
) (
    input CLK_BYTE,
    input RST_BYTE,
    input CNT_EN,

    output reg [W-1:0] CNT
);
  always @(negedge CLK_BYTE) begin
    if (RST_BYTE) begin
      CNT <= 11'd0;
    end else if (CNT_EN) begin
      if (CNT == CNT_DONE) CNT <= 11'd0;
      else CNT <= CNT + 11'd1;
    end
  end
endmodule
