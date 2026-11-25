// Control lógico de un paquete LPDT o una línea HS. Los límites por defecto
// son para simulación, no tiempos de placa. No habilita los drivers físicos.
module link_fsm #(
    parameter integer T_LPX = 1,
    parameter integer T_PREP = 1,
    parameter integer T_ZERO = 1,
    parameter integer T_TRAIL = 1,
    parameter integer C_LINE = 1091
) (
    input CLK_BYTE,
    input RST_BYTE,  // Síncrono activo en 1: cubrir un ↑ y el ↓ siguiente.
    input INIT_REQ,
    input VID_REQ,
    input VID_LINE_RDY,
    input READY,
    input LOCK,
    input LP_DONE,
    input PK_DONE,

    output reg INIT_READY,
    output reg INIT_DONE_TX,
    output reg LP_START,
    output reg PK_START,
    output reg HS_REQ,
    output reg CLK_REQ,
    output reg [1:0] SEL_OUT,
    output reg [1:0] LP_FORCE,
    output reg SOT_EN
);
  localparam [1:0] REPOSO = 2'b00, LPDT = 2'b01, FORZADO = 2'b10, HS = 2'b11;

  localparam [3:0] LINE_WAIT = 4'd0, LP_BEGIN = 4'd1, LP_RUN = 4'd2, LP_ACK = 4'd3,
                   LP01 = 4'd4, LP00_PREP = 4'd5, LP00_ZERO = 4'd6, SOT = 4'd7,
                   DATA0 = 4'd8, DATA = 4'd9, EOT = 4'd10, LP11 = 4'd11;

  localparam integer N_DRAIN = 1;  // Latencia de cierre del modelo, por validar con el PHY.
  localparam integer N_EOT = N_DRAIN + T_TRAIL;
  localparam integer SOT_DATA_DRAIN = 1 + 1083 + N_DRAIN;
  // La suma ancha permite detectar un presupuesto inviable antes de recortar.
  localparam [34:0] C_ACTIVE = {3'b0, T_LPX} + {3'b0, T_PREP} + {3'b0, T_ZERO}
                            + {3'b0, SOT_DATA_DRAIN} + {3'b0, T_TRAIL};
  localparam integer T_GAP = C_LINE - C_ACTIVE[31:0] - 1;  // Un ciclo para LINE_WAIT.

  function integer max_ticks(input integer a, b);
    max_ticks = (a > b) ? a : b;
  endfunction

  localparam integer N_MAX = max_ticks(max_ticks(T_LPX, T_PREP),
                              max_ticks(T_ZERO, max_ticks(N_EOT, T_GAP)));
  localparam integer W = (N_MAX > 1) ? $clog2(N_MAX + 1) : 1;

  wire PHY_AVAILABLE = READY && LOCK;
  reg [3:0] STATE;
  reg ENTER_T;
  reg LOAD_T, CNT_EN;
  reg [W-1:0] N;
  wire TIMER_DONE;

  link_fsm_timer #(.W(W)) timer (
      .CLK_BYTE(CLK_BYTE),
      .RST_BYTE(RST_BYTE),
      .LOAD_T(LOAD_T),
      .CNT_EN(CNT_EN),
      .N(N),
      .TIMER_DONE(TIMER_DONE)
  );

  // ENTER_T pertenece al estado: marca la carga en el primer ↓ de la fase.
  // TIMER_DONE se lee después de ese ↓, incluso si la fase dura un ciclo.
  always @(posedge CLK_BYTE) begin
    ENTER_T <= 1'b0;
    if (RST_BYTE) STATE <= LINE_WAIT;
    else begin
      case (STATE)
        LINE_WAIT: if (PHY_AVAILABLE) begin
          if (INIT_REQ) STATE <= LP_BEGIN;
          else if (VID_REQ && VID_LINE_RDY) begin
            STATE <= LP01;
            ENTER_T <= 1'b1;
          end
        end
        LP_BEGIN: STATE <= LP_RUN;
        LP_RUN: if (LP_DONE) STATE <= LP_ACK;
        LP_ACK: STATE <= LINE_WAIT;
        LP01: if (TIMER_DONE) begin
          STATE <= LP00_PREP;
          ENTER_T <= 1'b1;
        end
        LP00_PREP: if (TIMER_DONE) begin
          STATE <= LP00_ZERO;
          ENTER_T <= 1'b1;
        end
        LP00_ZERO: if (TIMER_DONE) STATE <= SOT;
        SOT: STATE <= DATA0;
        DATA0: STATE <= DATA;
        DATA: if (PK_DONE) begin
          // CRC ya registrado en PHY_IF; todavía no ha salido del PHY.
          STATE <= EOT;
          ENTER_T <= 1'b1;
        end
        EOT: if (TIMER_DONE) begin
          STATE <= LP11;
          ENTER_T <= 1'b1;
        end
        LP11: if (TIMER_DONE) STATE <= LINE_WAIT;
        default: STATE <= LINE_WAIT;
      endcase
    end
  end

  always @(*) begin
    INIT_READY = 1'b0;
    INIT_DONE_TX = 1'b0;
    LP_START = 1'b0;
    PK_START = 1'b0;
    HS_REQ = 1'b0;
    CLK_REQ = 1'b0;
    SEL_OUT = REPOSO;
    LP_FORCE = 2'b11;
    SOT_EN = 1'b0;
    CNT_EN = 1'b0;
    N = 0;

    if (!RST_BYTE) begin
      case (STATE)
        LINE_WAIT: INIT_READY = PHY_AVAILABLE;
        LP_BEGIN, LP_RUN: begin
          SEL_OUT = LPDT;
          LP_START = (STATE == LP_BEGIN);
        end
        LP_ACK: INIT_DONE_TX = 1'b1;
        LP01: begin
          SEL_OUT = FORZADO;
          LP_FORCE = 2'b01;
          CLK_REQ = 1'b1;
          CNT_EN = 1'b1;
          N = T_LPX[W-1:0];
        end
        LP00_PREP, LP00_ZERO: begin
          SEL_OUT = FORZADO;
          LP_FORCE = 2'b00;
          CLK_REQ = 1'b1;
          HS_REQ = (STATE == LP00_ZERO);
          CNT_EN = 1'b1;
          N = (STATE == LP00_ZERO) ? T_ZERO[W-1:0] : T_PREP[W-1:0];
        end
        SOT, DATA0, DATA: begin
          SEL_OUT = HS;
          CLK_REQ = 1'b1;
          HS_REQ = 1'b1;
          SOT_EN = (STATE == SOT);
          PK_START = (STATE == DATA0);
        end
        EOT: begin
          SEL_OUT = FORZADO;
          LP_FORCE = 2'b00;
          CLK_REQ = 1'b1;
          CNT_EN = 1'b1;
          N = N_EOT[W-1:0];
        end
        LP11: begin
          CNT_EN = 1'b1;
          N = T_GAP[W-1:0];
        end
        default: begin end
      endcase
    end
    LOAD_T = CNT_EN && ENTER_T;
  end

`ifndef SYNTHESIS
  initial begin
    if (T_LPX < 1 || T_PREP < 1 || T_ZERO < 1 || T_TRAIL < 1)
      $fatal(1, "T_LPX, T_PREP, T_ZERO y T_TRAIL deben ser >= 1");
    if (C_LINE < 1 || {3'b0, C_LINE} < C_ACTIVE + 35'd2)
      $fatal(1, "C_LINE=%0d no cubre %0d ciclos activos + LP11 y LINE_WAIT", C_LINE, C_ACTIVE);
  end
`endif
endmodule
