module video_timing (
    input RST_BYTE,
    input INIT_DONE,
    input AT_START,
    input VID_RD,

    output VID_REQ,
    output VID_LINE_RDY,
    output ADV
);
  wire ENABLED = INIT_DONE && !RST_BYTE;

  // El patrón fijo garantiza la línea completa. La oferta dura hasta que
  // la primera lectura mueve ADDR; LINK_FSM no devuelve un acuse.
  assign VID_REQ = ENABLED && AT_START;
  assign VID_LINE_RDY = VID_REQ;
  assign ADV = ENABLED && VID_RD;
endmodule
