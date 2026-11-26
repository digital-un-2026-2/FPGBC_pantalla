// Una instancia por carril. El modo indica qué tomar en el próximo ↓ de byte.
module hs_serializer (
    input CLK_BYTE,
    input CLK_HS,
    input RST_BYTE,
    input ISO,
    input [1:0] SER_MODE,
    input [7:0] HS_BYTE,
    output HS_D
);
  localparam [1:0] WORD = 2'b10, TRAIL = 2'b11;

  wire RST_SER = ISO || RST_BYTE;
  reg [8:0] SLOT_D;
  reg [7:0] SLOT_Q;
  reg LAST_BIT;

  always @(*) begin
    case (SER_MODE)
      WORD:    SLOT_D = {HS_BYTE[7], HS_BYTE};
      TRAIL:   SLOT_D = {LAST_BIT, {8{~LAST_BIT}}};
      default: SLOT_D = 9'b0;  // OFF y ZERO (HS-0).
    endcase
  end

  always @(negedge CLK_BYTE or posedge RST_SER) begin
    if (RST_SER) {LAST_BIT, SLOT_Q} <= 9'b0;
    else         {LAST_BIT, SLOT_Q} <= SLOT_D;
  end

  // Carga paralela en ↑PCLK. Mantener Q0 en la ruta dedicada de IOLOGIC.
  OSER8 #(.HWL("false"), .LSREN("true"), .GSREN("false")) serializer (
      .D0(SLOT_Q[0]), .D1(SLOT_Q[1]), .D2(SLOT_Q[2]), .D3(SLOT_Q[3]),
      .D4(SLOT_Q[4]), .D5(SLOT_Q[5]), .D6(SLOT_Q[6]), .D7(SLOT_Q[7]),
      .TX0(1'b0), .TX1(1'b0), .TX2(1'b0), .TX3(1'b0),
      .PCLK(CLK_BYTE), .FCLK(CLK_HS), .RESET(RST_SER),
      .Q0(HS_D), .Q1()
  );
endmodule
