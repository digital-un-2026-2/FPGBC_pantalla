`timescale 1ps / 1fs

// Sustituto ideal de los puertos usados de rPLL, solo para el banco.
// Los cuatro flancos de arranque son arbitrarios. Ni el comportamiento en
// RESET ni el estímulo DROP_LOCK describen la respuesta física de una PLL.
// No modela frecuencia/fase transitoria, jitter ni pérdida de CLKIN.
module rPLL #(
    parameter DEVICE = "GW1N-1",
    parameter FCLKIN = "100.0",
    parameter DYN_IDIV_SEL = "false",
    parameter integer IDIV_SEL = 0,
    parameter DYN_FBDIV_SEL = "false",
    parameter integer FBDIV_SEL = 0,
    parameter DYN_ODIV_SEL = "false",
    parameter integer ODIV_SEL = 8,
    parameter CLKFB_SEL = "internal",
    parameter DYN_DA_EN = "false",
    parameter CLKOUT_BYPASS = "false",
    parameter CLKOUTD_BYPASS = "false",
    parameter CLKOUTD_SRC = "CLKOUT",
    parameter integer DYN_SDIV_SEL = 2
) (
    input CLKIN, RESET, RESET_P, CLKFB,
    input [5:0] IDSEL, FBDSEL, ODSEL,
    input [3:0] PSDA, DUTYDA, FDLY,
    output CLKOUT, CLKOUTD, CLKOUTP, CLKOUTD3, LOCK
);
  localparam realtime HALF_HS_PS = 12500.0 * (IDIV_SEL + 1) / (FBDIV_SEL + 1);
  reg [2:0] REF_EDGES = 0;
  reg OSC_HS = 0, OSC_BYTE = 0;
  integer DIV_COUNT = 0;
  reg DROP_LOCK = 0;  // Inyección de estado crudo, no un detector de reloj.
  wire RUNNING = (REF_EDGES != 0);

  initial begin
    if (DEVICE != "GW2AR-18" || FCLKIN != "40" || ODIV_SEL != 4 ||
        DYN_IDIV_SEL != "false" || DYN_FBDIV_SEL != "false" ||
        DYN_ODIV_SEL != "false" || DYN_DA_EN != "false" ||
        CLKFB_SEL != "internal" || CLKOUTD_SRC != "CLKOUT" ||
        CLKOUT_BYPASS != "false" || CLKOUTD_BYPASS != "false" ||
        DYN_SDIV_SEL < 2 || DYN_SDIV_SEL % 2 != 0)
      $fatal(1, "Configuración no soportada por el modelo ideal de rPLL");
  end

  // Necesita la referencia para arrancar tras RESET; una vez arrancado,
  // la oscilación ideal no pretende detectar si desaparece la referencia.
  always @(posedge CLKIN or posedge RESET or posedge RESET_P) begin
    if (RESET || RESET_P) REF_EDGES <= 0;
    else if (REF_EDGES < 4) REF_EDGES <= REF_EDGES + 1'b1;
  end

  always begin
    wait (RUNNING);
    #(HALF_HS_PS);
    OSC_HS = RUNNING && !OSC_HS;
  end

  always @(negedge OSC_HS or negedge RUNNING) begin
    if (!RUNNING) begin
      OSC_BYTE <= 0;
      DIV_COUNT <= 0;
    end else if (DIV_COUNT == DYN_SDIV_SEL / 2 - 1) begin
      OSC_BYTE <= !OSC_BYTE;
      DIV_COUNT <= 0;
    end else begin
      DIV_COUNT <= DIV_COUNT + 1;
    end
  end

  assign CLKOUT = RUNNING && OSC_HS;
  assign CLKOUTD = RUNNING && OSC_BYTE;
  assign LOCK = REF_EDGES == 4 && !DROP_LOCK;
  assign CLKOUTP = 1'bx;
  assign CLKOUTD3 = 1'bx;
endmodule
