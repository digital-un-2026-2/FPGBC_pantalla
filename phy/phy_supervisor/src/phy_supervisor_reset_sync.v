module phy_supervisor_reset_sync (
    input CLK, RESET_IN,
    output RESET_OUT
);
  (* async_reg = "true" *) reg [1:0] PIPE = 2'b11;

  always @(negedge CLK or posedge RESET_IN) begin
    if (RESET_IN) PIPE <= 2'b11;
    else PIPE <= {PIPE[0], 1'b0};
  end

  assign RESET_OUT = PIPE[1];
endmodule
