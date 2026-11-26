module init_sequencer_a_count (
    input CLK_BYTE,
    input RST_ALL,
    input INC_A,

    output reg [7:0] ADDR
);
  always @(negedge CLK_BYTE) begin
    if (RST_ALL) ADDR <= 8'd0;
    else if (INC_A && ADDR < 8'd222) ADDR <= ADDR + 1'b1;
  end
endmodule
