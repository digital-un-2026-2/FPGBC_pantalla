module lp_tx_phase_div #(
    parameter integer LP_DIV = 1
) (
    input CLK_BYTE,
    input RST_BYTE,
    input DIV_EN,

    output TICK
);
  localparam integer W = (LP_DIV > 1) ? $clog2(LP_DIV) : 1;
  localparam integer LAST_COUNT = LP_DIV - 1;
  localparam [W-1:0] RELOAD = LAST_COUNT[W-1:0];

  reg [W-1:0] P_CNT;

  // TICK se observa antes de ↓; al emitir se recarga el intervalo completo.
  assign TICK = (P_CNT == 0);

  always @(negedge CLK_BYTE) begin
    if (RST_BYTE || !DIV_EN) P_CNT <= 0;
    else if (TICK) P_CNT <= RELOAD;
    else P_CNT <= P_CNT - 1'b1;
  end
endmodule
