module v_count (
    input CLK_BYTE,
    input RST_BYTE,
    input ADV,

    output reg [10:0] ADDR,
    output reg [1:0] RGB_PHASE,
    output AT_START
);
  localparam [10:0] LAST_ADDR = 11'd1079;

  assign AT_START = (ADDR == 11'd0);

  // El packer lee la palabra del índice previo a ↓. Al consumir la
  // última, ambos contadores vuelven al inicio sin esperar el CRC.
  always @(negedge CLK_BYTE) begin
    if (RST_BYTE) begin
      ADDR <= 11'd0;
      RGB_PHASE <= 2'd0;
    end else if (ADV) begin
      ADDR <= (ADDR == LAST_ADDR) ? 11'd0 : ADDR + 11'd1;
      RGB_PHASE <= (RGB_PHASE == 2'd2) ? 2'd0 : RGB_PHASE + 2'd1;
    end
  end
endmodule
