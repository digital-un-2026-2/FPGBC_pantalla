// Conexiones internas del PHY. RESET reinicia la PLL; RST_BYTE es externo.
module phy #(
    parameter USE_IODELAY = 1'b0,
    parameter integer STATIC_DELAY_TAPS = 0,
    // Ensayo separado: no excitar CLK en los pads; no cambia los datos.
    parameter DATA_ONLY = 1'b0,
    parameter DATA_TIMING = 1'b0
) (
    input CLK_REF, RESET, RST_BYTE,
    input HS_REQ, CLK_REQ,
    input [2:0] LP_P, LP_N,
    input [7:0] HS_BYTE0, HS_BYTE1,
    output CLK_BYTE, LOCK, READY,
    output LP_D0_P, LP_D0_N, LP_D1_P, LP_D1_N, LP_CLK_P, LP_CLK_N,
    output HS_D0_P, HS_D0_N, HS_D1_P, HS_D1_N,
    inout HS_CLK_P, HS_CLK_N,
    output LOCK_RAW,
    (* keep *) output ISO
);
  wire CLK_HS;
  wire HS_D0, HS_D1, HS_CLK;
  wire HS_EN, CLK_EN, CLK_TOGGLE;
  wire [1:0] LP_DAT_MODE, LP_CLK_MODE, LP_CLK_PN, SER_MODE;
  // Observación aportada: CLK P/N pasan a 00 y se mantienen durante vídeo.
  // Registro ↓, reset síncrono a 1; solo puede volver a 1 tras reset común.
  (* keep *) reg DATA_ONLY_LP_CLK;
  always @(negedge CLK_BYTE) begin
    if (RST_BYTE || !DATA_ONLY) DATA_ONLY_LP_CLK <= 1'b1;
    else if (CLK_REQ) DATA_ONLY_LP_CLK <= 1'b0;
  end

  clock_gen clocks (
      .CLK_REF(CLK_REF), .RESET(RESET), .CLK_BYTE(CLK_BYTE), .CLK_HS(CLK_HS), .LOCK_RAW(LOCK_RAW)
  );
  phy_ctrl_gowin #(.DATA_TIMING(DATA_TIMING)) control (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE), .LOCK_RAW(LOCK_RAW),
      .HS_REQ(HS_REQ), .CLK_REQ(CLK_REQ), .LOCK(LOCK), .READY(READY), .ISO(ISO),
      .LP_DAT_MODE(LP_DAT_MODE), .LP_CLK_MODE(LP_CLK_MODE), .LP_CLK_PN(LP_CLK_PN),
      .HS_EN(HS_EN), .CLK_EN(CLK_EN), .CLK_TOGGLE(CLK_TOGGLE), .SER_MODE(SER_MODE)
  );
  hs_serializer d0 (
      .CLK_BYTE(CLK_BYTE), .CLK_HS(CLK_HS), .RST_BYTE(RST_BYTE), .ISO(ISO),
      .SER_MODE(SER_MODE), .HS_BYTE(HS_BYTE0), .HS_D(HS_D0)
  );
  hs_serializer d1 (
      .CLK_BYTE(CLK_BYTE), .CLK_HS(CLK_HS), .RST_BYTE(RST_BYTE), .ISO(ISO),
      .SER_MODE(SER_MODE), .HS_BYTE(HS_BYTE1), .HS_D(HS_D1)
  );
  clock_ddr #(.USE_IODELAY(USE_IODELAY), .STATIC_DELAY_TAPS(STATIC_DELAY_TAPS)) forwarded (
      .CLK_HS(CLK_HS), .ISO(ISO), .CLK_TOGGLE(CLK_TOGGLE), .HS_CLK(HS_CLK)
  );
  dphy_pads #(.DATA_ONLY(DATA_ONLY)) pads (
      .LP_P({DATA_ONLY ? DATA_ONLY_LP_CLK : LP_CLK_PN[1], LP_P[1:0]}),
      .LP_N({DATA_ONLY ? DATA_ONLY_LP_CLK : LP_CLK_PN[0], LP_N[1:0]}),
      .HS_D0(HS_D0), .HS_D1(HS_D1), .HS_CLK(DATA_ONLY ? 1'b0 : HS_CLK),
      .LP_DAT_MODE(LP_DAT_MODE), .LP_CLK_MODE(DATA_ONLY ? 2'b01 : LP_CLK_MODE),
      .HS_EN(HS_EN), .CLK_EN(DATA_ONLY ? 1'b0 : CLK_EN), .ISO(ISO),
      .LP_D0_P(LP_D0_P), .LP_D0_N(LP_D0_N), .LP_D1_P(LP_D1_P), .LP_D1_N(LP_D1_N),
      .LP_CLK_P(LP_CLK_P), .LP_CLK_N(LP_CLK_N),
      .HS_D0_P(HS_D0_P), .HS_D0_N(HS_D0_N), .HS_D1_P(HS_D1_P), .HS_D1_N(HS_D1_N),
      .HS_CLK_P(HS_CLK_P), .HS_CLK_N(HS_CLK_N)
  );
`ifndef SYNTHESIS
  initial if (DATA_TIMING && (!DATA_ONLY || USE_IODELAY))
    $fatal(1, "DATA_TIMING requiere DATA_ONLY y no admite retardo de CLK externo");
`endif
endmodule
