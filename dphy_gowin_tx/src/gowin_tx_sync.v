`timescale 1ns/1ps
// Single-bit CDC only. Never used for FRAME, LP, CTRL or ACK buses.
module gowin_tx_sync (input clk, rst, d, output q);
  (* async_reg = "true" *) reg [1:0] stages;
  always @(posedge clk) begin
    if (rst) stages <= 0;
    else stages <= {stages[0],d};
  end
  assign q = stages[1];
endmodule
