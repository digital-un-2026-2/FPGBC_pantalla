`timescale 1ps / 1ps

// Modelos funcionales limitados a la configuración de CLOCK_DDR.
module CLKDIV #(parameter DIV_MODE = "2", GSREN = "false") (
    input HCLKIN, RESETN, CALIB,
    output reg CLKOUT
);
  reg running;
  always @(posedge HCLKIN or negedge RESETN) begin
    if (!RESETN) begin
      running <= 0;
      CLKOUT <= 0;
    end else begin
      running <= 1;
      CLKOUT <= running && !CLKOUT;
    end
  end
endmodule

module OSER4 #(parameter HWL = "false", LSREN = "true", GSREN = "false") (
    input D0, D1, D2, D3, TX0, TX1, PCLK, FCLK, RESET,
    output Q0, Q1
);
  reg [3:0] parallel_word, pending_word, shift_word;
  reg [1:0] startup;
  reg second_pair, odd_bit, even_bit;

  always @(posedge PCLK or posedge RESET) begin
    if (RESET) parallel_word <= 0;
    else       parallel_word <= {D3, D2, D1, D0};
  end

  always @(posedge FCLK or posedge RESET) begin
    if (RESET) begin
      startup <= 0;
      second_pair <= 0;
      pending_word <= 0;
      shift_word <= 0;
      odd_bit <= 0;
    end else begin
      startup <= {startup[0], 1'b1};
      odd_bit <= shift_word[1];
      if (startup[1]) begin
        second_pair <= !second_pair;
        if (second_pair) shift_word <= pending_word;
        else begin
          pending_word <= parallel_word;
          shift_word <= {2'b0, shift_word[3:2]};
        end
      end
    end
  end

  always @(negedge FCLK or posedge RESET) begin
    if (RESET) even_bit <= 0;
    else       even_bit <= shift_word[0];
  end

  assign Q0 = FCLK ? even_bit : odd_bit;
  assign Q1 = 1'b0;
endmodule

// 25 ps/paso como en prim_sim; únicamente para probar la variante de ruta.
module IODELAY #(parameter integer C_STATIC_DLY = 0) (
    input DI, SDTAP, VALUE, SETN,
    output DO, DF
);
  assign #(25 * C_STATIC_DLY) DO = DI;
  assign DF = 1'b0;
endmodule
