`timescale 1ps / 1ps

// Modelo funcional del camino Q0 para HWL=false. Tras liberar reset, la
// transferencia PCLK→FCLK ocurre en la cuarta subida rápida y luego cada
// cuatro. El byte transferido aparece un periodo de byte después.
module OSER8 #(
    parameter HWL = "false",
    parameter LSREN = "true",
    parameter GSREN = "false"
) (
    input D0, D1, D2, D3, D4, D5, D6, D7,
    input TX0, TX1, TX2, TX3,
    input PCLK, FCLK, RESET,
    output reg Q0,
    output Q1
);
  reg [7:0] parallel_byte, pending_byte;
  reg [5:0] remaining_bits;
  reg odd_bit;
  reg [1:0] phase;

  assign Q1 = 1'b0;

  initial begin
    if (HWL != "false" || LSREN != "true" || GSREN != "false")
      $fatal(1, "Configuración de OSER8 fuera del modelo de datos");
  end

  always @(posedge PCLK or posedge RESET) begin
    if (RESET) parallel_byte <= 8'h00;
    else       parallel_byte <= {D7, D6, D5, D4, D3, D2, D1, D0};
  end

  always @(FCLK or posedge RESET) begin
    if (RESET) begin
      pending_byte <= 0;
      remaining_bits <= 0;
      odd_bit <= 0;
      phase <= 0;
      Q0 <= 0;
    end else if (FCLK) begin
      phase <= phase + 1'b1;
      if (phase == 2'd3) begin
        pending_byte <= parallel_byte;
        {remaining_bits, odd_bit, Q0} <= pending_byte;
      end else begin
        {odd_bit, Q0} <= remaining_bits[1:0];
        remaining_bits <= remaining_bits >> 2;
      end
    end else begin
      Q0 <= odd_bit;
    end
  end
endmodule
