// Paquete RGB888 fijo: W0...W1082, una palabra por negedge de CLK_BYTE.
// PHY_IF captura W0 en el mismo flanco que acepta PK_START con CNT=0.
// VIDEO_SOURCE presenta la palabra actual antes del negedge con VID_RD=1.
// WORD solo se transfiere cuando PHY_IF lo selecciona; no hay VALID ni pausa.
// PK_DONE se decodifica después del negedge de W1082; LINK_FSM lo lee en posedge.
module hs_packer #(
    parameter FRAME_MODE = 1'b0
) (
    input CLK_BYTE,
    input RST_BYTE,  // Síncrono activo en 1, compartido con los módulos vecinos.
    input PK_START,
    input [15:0] VID_WORD,
    input [1:0] BURST_KIND,

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
  wire RGB_RD, RGB_DONE;
  wire [3:0] PREFIX_IDX;
  wire RGB_BURST = BURST_KIND == 2'b10;
  wire RGB_START = FRAME_MODE ? (RGB_BURST && PREFIX_IDX == 4'd8) : PK_START;

  // El camino RGB de 1083 palabras no cambia. El prefijo se consume antes
  // de su START; los paquetes cortos nunca arrancan ese camino.
  hs_packer_word_cnt #(.W(4), .CNT_DONE(4'd9)) prefix_count (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE || (FRAME_MODE && PK_DONE)),
      .CNT_EN(FRAME_MODE && (PK_START || (PREFIX_IDX != 0 && PREFIX_IDX < 9))),
      .CNT(PREFIX_IDX)
  );
  assign VID_RD = RGB_RD && (!FRAME_MODE || (RGB_BURST && PREFIX_IDX >= 8));
  assign PK_DONE = FRAME_MODE && !RGB_BURST ? (PREFIX_IDX == 2) : RGB_DONE;

  hs_packer_word_cnt #(.CNT_DONE(CNT_DONE)) word_cnt (
      .CLK_BYTE(CLK_BYTE),
      .RST_BYTE(RST_BYTE),
      .CNT_EN(CNT_EN),
      .CNT(CNT)
  );

  hs_packer_sel_dec #(.CNT_DONE(CNT_DONE)) sel_dec (
      .CNT(CNT),
      .PK_START(RGB_START),
      .SEL_WORD(SEL_WORD),
      .CNT_EN(CNT_EN),
      .VID_RD(RGB_RD),
      .CRC_CLR(CRC_CLR),
      .PK_DONE(RGB_DONE)
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

  hs_packer_word_mux #(.FRAME_MODE(FRAME_MODE)) word_mux (
      .SEL_WORD(SEL_WORD),
      .HDR_WORD(HDR_WORD),
      .VID_WORD(VID_WORD),
      .CRC_WORD(CRC_WORD), .PREFIX_IDX(PREFIX_IDX), .BURST_KIND(BURST_KIND),
      .WORD(WORD)
  );
endmodule
