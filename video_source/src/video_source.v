// Fuente de payload RGB888 en CLK_BYTE; no arma paquetes DSI.
module video_source (
    input CLK_BYTE,
    input RST_BYTE,  // Síncrono en ↓ para el datapath; común con los vecinos.
    input INIT_DONE,
    input VID_RD,

    output VID_REQ,
    output VID_LINE_RDY,
    output [15:0] VID_WORD
);
  wire ADV, AT_START;
  wire [10:0] ADDR;
  wire [1:0] RGB_PHASE;

  video_timing timing (
      .RST_BYTE(RST_BYTE), .INIT_DONE(INIT_DONE), .AT_START(AT_START), .VID_RD(VID_RD),
      .VID_REQ(VID_REQ), .VID_LINE_RDY(VID_LINE_RDY), .ADV(ADV)
  );

  v_count count (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE), .ADV(ADV),
      .ADDR(ADDR), .RGB_PHASE(RGB_PHASE), .AT_START(AT_START)
  );

  video_mem mem (
      .ADDR(ADDR), .RGB_PHASE(RGB_PHASE), .VID_WORD(VID_WORD)
  );
endmodule
