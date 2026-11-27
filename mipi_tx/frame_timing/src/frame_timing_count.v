module frame_timing_count (
    input CLK_BYTE,
    input RST_BYTE,
    input BURST_START,
    output reg [9:0] NEXT_PERIOD
);
  localparam [9:0] LAST_PERIOD = 10'd742;

  always @(negedge CLK_BYTE) begin
    if (RST_BYTE) NEXT_PERIOD <= 10'd0;
    else if (BURST_START)
      NEXT_PERIOD <= (NEXT_PERIOD == LAST_PERIOD) ? 10'd0 : NEXT_PERIOD + 10'd1;
  end
endmodule
