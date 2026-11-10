`timescale 1ns/1ps
// Physical-domain exception: asynchronous assertion, two-edge release.
module gowin_tx_reset_sync (input clk, request, output rst);
  (* async_reg = "true" *) reg [1:0] stages;
  always @(posedge clk or posedge request) begin
    if (request) stages <= 2'b11;
    else stages <= {stages[0],1'b0};
  end
  assign rst = stages[1];
endmodule
