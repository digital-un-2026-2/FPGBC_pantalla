module phy_ctrl_timer #(
    parameter integer W = 1
) (
    input CLK_BYTE,
    input RST_BYTE,
    input RUN,
    input LOAD_T,
    input [W-1:0] N,

    output DONE
);
  reg [W-1:0] CNT;

  assign DONE = (CNT == 0);

  // N=1 carga cero en el primer ↓; la FSM avanza en el ↑ posterior.
  always @(negedge CLK_BYTE) begin
    if (RST_BYTE || !RUN) CNT <= 0;
    else if (LOAD_T) CNT <= N - 1'b1;
    else if (!DONE) CNT <= CNT - 1'b1;
  end
endmodule
