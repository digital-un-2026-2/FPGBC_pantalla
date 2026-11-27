module hs_packer_word_mux #(
    parameter FRAME_MODE = 1'b0
) (
    input [1:0] SEL_WORD,
    input [15:0] HDR_WORD,
    input [15:0] VID_WORD,
    input [15:0] CRC_WORD,
    input [3:0] PREFIX_IDX,
    input [1:0] BURST_KIND,

    output reg [15:0] WORD
);
  always @(*) begin
    case (SEL_WORD)
      2'b00: WORD = HDR_WORD;
      2'b01: WORD = VID_WORD;
      2'b10: WORD = CRC_WORD;
      default: WORD = 16'h0000;
    endcase
    if (FRAME_MODE && PREFIX_IDX < 8) begin
      case (PREFIX_IDX)
        0: WORD = (BURST_KIND == 2'b00) ? 16'h0001 : 16'h0021;
        1: WORD = (BURST_KIND == 2'b00) ? 16'h0700 : 16'h1200;
        2: WORD = 16'h0619;
        3: WORD = 16'h2500;
        7: WORD = 16'h0870;  // CRC de seis ceros.
        default: WORD = 16'h0000;
      endcase
    end
  end
endmodule
