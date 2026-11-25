// Paquete RGB888 fijo: W0...W1082, una palabra por negedge de CLK_BYTE.
// PHY_IF captura W0 en el mismo flanco que acepta PK_START con CNT=0.
// VIDEO_SOURCE presenta la palabra actual antes del negedge con VID_RD=1.
// WORD solo se transfiere cuando PHY_IF lo selecciona; no hay VALID ni pausa.
// PK_DONE se decodifica después del negedge de W1082; LINK_FSM lo lee en posedge.
module hs_packer (
    input CLK_BYTE,
    input RST_BYTE,  // Síncrono activo en 1, compartido con los módulos vecinos.
    input PK_START,
    input [15:0] VID_WORD,

    output VID_RD,
    output PK_DONE,
    output [15:0] WORD
);
  localparam [10:0] CNT_DONE = 11'd1083;

  wire [10:0] CNT;
  wire CNT_EN;
  wire [1:0] SEL_WORD;
  wire [15:0] HDR_WORD;
  wire [15:0] CRC_WORD;
  wire CRC_CLR;

  hs_packer_word_cnt #(.CNT_DONE(CNT_DONE)) word_cnt (
      .CLK_BYTE(CLK_BYTE),
      .RST_BYTE(RST_BYTE),
      .CNT_EN(CNT_EN),
      .CNT(CNT)
  );

  hs_packer_sel_dec #(.CNT_DONE(CNT_DONE)) sel_dec (
      .CNT(CNT),
      .PK_START(PK_START),
      .SEL_WORD(SEL_WORD),
      .CNT_EN(CNT_EN),
      .VID_RD(VID_RD),
      .CRC_CLR(CRC_CLR),
      .PK_DONE(PK_DONE)
  );

  // HDR_CONST: D0 = [7:0], D1 = [15:8]. Cabecera fija 3E 70 08 13.
  assign HDR_WORD = CNT[0] ? 16'h1308 : 16'h703e;

  hs_packer_crc16 crc16 (
      .CLK_BYTE(CLK_BYTE),
      .RST_BYTE(RST_BYTE),
      .CRC_CLR(CRC_CLR),
      .CRC_EN(VID_RD),
      .VID_WORD(VID_WORD),
      .CRC_WORD(CRC_WORD)
  );

  hs_packer_word_mux word_mux (
      .SEL_WORD(SEL_WORD),
      .HDR_WORD(HDR_WORD),
      .VID_WORD(VID_WORD),
      .CRC_WORD(CRC_WORD),
      .WORD(WORD)
  );
endmodule
