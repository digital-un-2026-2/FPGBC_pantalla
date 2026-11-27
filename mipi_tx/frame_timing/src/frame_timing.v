// Datapath de encuadre: cuenta ráfagas ya admitidas, no ciclos de línea.
module frame_timing (
    input CLK_BYTE,
    input RST_BYTE,  // Síncrono activo en 1, consumido en negedge.
    input BURST_START,
    output [1:0] BURST_KIND
);
  wire [9:0] NEXT_PERIOD;

  frame_timing_count count (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE), .BURST_START(BURST_START),
      .NEXT_PERIOD(NEXT_PERIOD)
  );

  frame_timing_kind kind (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE), .BURST_START(BURST_START),
      .NEXT_PERIOD(NEXT_PERIOD), .BURST_KIND(BURST_KIND)
  );
endmodule
