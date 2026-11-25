module hs_packer_word_mux (
    input [1:0] SEL_WORD,
    input [15:0] HDR_WORD,
    input [15:0] VID_WORD,
    input [15:0] CRC_WORD,

    output reg [15:0] WORD
);
  always @(*) begin
    case (SEL_WORD)
      2'b00: WORD = HDR_WORD;
      2'b01: WORD = VID_WORD;
      2'b10: WORD = CRC_WORD;
      default: WORD = 16'h0000;
    endcase
  end
endmodule
