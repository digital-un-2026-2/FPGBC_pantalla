module phy_if_out_sel (
    input [1:0] SEL_OUT,
    input [1:0] LP_FORCE,
    input SOT_EN,

    output reg LP_USE_D0,
    output reg [1:0] FORCED_PN,
    output reg [1:0] HS_SEL
);
  // SEL_OUT: 00 reposo, 01 LPDT, 10 LP forzado, 11 HS.
  // HS_SEL: 00 sin dato, 01 SoT, 10 WORD.
  always @(*) begin
    LP_USE_D0 = 1'b0;
    FORCED_PN = 2'b11;
    HS_SEL = 2'b00;
    case (SEL_OUT)
      2'b01: LP_USE_D0 = 1'b1;
      2'b10: FORCED_PN = LP_FORCE;
      2'b11: begin
        FORCED_PN = 2'b00;
        HS_SEL = SOT_EN ? 2'b01 : 2'b10;
      end
      default: begin end  // LP11 de reposo.
    endcase
  end
endmodule
