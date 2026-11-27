// Descriptor de la ráfaga actual; los controles se decodifican fuera.
module frame_timing_kind (
    input CLK_BYTE,
    input RST_BYTE,
    input BURST_START,
    input [9:0] NEXT_PERIOD,
    output reg [1:0] BURST_KIND
);
  localparam [1:0] VSS = 2'b00, HSS = 2'b01, RGB = 2'b10;
  wire [1:0] NEXT_KIND = (NEXT_PERIOD < 10'd3) ? VSS :
                        (NEXT_PERIOD >= 10'd11 && NEXT_PERIOD < 10'd731) ? RGB : HSS;

  // Captura el índice previo al mismo ↓ que avanza el contador vecino.
  always @(negedge CLK_BYTE) begin
    if (RST_BYTE) BURST_KIND <= VSS;
    else if (BURST_START) BURST_KIND <= NEXT_KIND;
  end
endmodule
