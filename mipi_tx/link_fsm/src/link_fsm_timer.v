module link_fsm_timer #(
    parameter integer W = 1
) (
    input CLK_BYTE,
    input RST_BYTE,
    input LOAD_T,
    input CNT_EN,
    input [W-1:0] N,

    output TIMER_DONE
);
  reg [W-1:0] CNT;

  assign TIMER_DONE = (CNT == 0);

  always @(negedge CLK_BYTE) begin
    if (RST_BYTE) CNT <= 0;
    else if (LOAD_T) CNT <= N - 1'b1;
    else if (CNT_EN && !TIMER_DONE) CNT <= CNT - 1'b1;
  end
endmodule
