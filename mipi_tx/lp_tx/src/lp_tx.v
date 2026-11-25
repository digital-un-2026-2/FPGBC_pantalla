// Transmisor LPDT de D0. No interpreta ni modifica los bytes DSI.
module lp_tx #(
    parameter integer LP_DIV = 1  // Ciclos por fase (>= 1); valor físico por validar.
) (
    input CLK_BYTE,
    input RST_BYTE,  // Síncrono activo en 1; cubrir posedge y negedge.
    input LP_START,
    input [7:0] INIT_BYTE,
    input INIT_LAST,  // Marca WAIT, no el último byte.

    output LP_DONE,
    output INIT_NEXT,
    output [1:0] LP_D0
);
  wire DIV_EN, TICK;
  wire BIT_EN, MARK0, SPACE_NEXT, SHIFT;
  wire SEL_CMD, LD_BYTE, BIT;
  wire [7:0] BYTE;
  wire USE_MARK, LP_WE;
  wire [1:0] FIX_CODE, LP_SYMBOL;

  lp_tx_step_seq step_seq (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE),
      .LP_START(LP_START), .INIT_LAST(INIT_LAST),
      .TICK(TICK), .MARK0(MARK0), .SPACE_NEXT(SPACE_NEXT),
      .LP_DONE(LP_DONE), .INIT_NEXT(INIT_NEXT),
      .DIV_EN(DIV_EN), .BIT_EN(BIT_EN), .SEL_CMD(SEL_CMD), .LD_BYTE(LD_BYTE),
      .USE_MARK(USE_MARK), .FIX_CODE(FIX_CODE), .LP_WE(LP_WE)
  );

  lp_tx_phase_div #(.LP_DIV(LP_DIV)) phase_div (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE), .DIV_EN(DIV_EN), .TICK(TICK)
  );

  lp_tx_bit_cnt bit_cnt (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE), .BIT_EN(BIT_EN),
      .MARK0(MARK0), .SPACE_NEXT(SPACE_NEXT), .SHIFT(SHIFT)
  );

  // BYTE_SEL no compara el valor de INIT_BYTE: un 87 en DATA se conserva.
  assign BYTE = SEL_CMD ? 8'h87 : INIT_BYTE;
  lp_tx_shift_reg shift_reg (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE), .LD_BYTE(LD_BYTE),
      .SHIFT(SHIFT), .BYTE(BYTE), .BIT(BIT)
  );

  // SYMBOL_ENC: LP_D0 = {P,N}. PHY_IF captura este símbolo en el ↓ siguiente.
  assign LP_SYMBOL = USE_MARK ? {BIT, !BIT} : FIX_CODE;
  reg_0 #(.BITS(2), .RESET_VALUE(2'b11)) symbol_enc (
      .clk(CLK_BYTE), .rst(RST_BYTE), .ld(LP_WE),
      .reg_in(LP_SYMBOL), .reg_out(LP_D0)
  );
endmodule
