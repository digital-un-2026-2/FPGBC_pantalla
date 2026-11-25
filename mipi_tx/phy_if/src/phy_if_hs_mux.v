module phy_if_hs_mux (
    input [15:0] WORD,
    input [1:0] HS_SEL,

    output reg [7:0] BYTE0_D,
    output reg [7:0] BYTE1_D
);
  always @(*) begin
    case (HS_SEL)
      2'b01: {BYTE1_D, BYTE0_D} = 16'hb8b8;
      2'b10: {BYTE1_D, BYTE0_D} = WORD;  // D0 = [7:0], D1 = [15:8].
      default: {BYTE1_D, BYTE0_D} = 16'h0000;
    endcase
  end
endmodule
