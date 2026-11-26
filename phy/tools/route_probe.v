// Sonda offline de la cadena hasta los pads; RESET_N es un estímulo de prueba.
module route_probe #(
    parameter DELAY = 1'b0,
    parameter integer INIT_HZ = 55_000_000,
    parameter SUPERVISED = 1'b0
) (
    input CLK_REF, RESET_N,
    output LP_D0_P, LP_D0_N, LP_D1_P, LP_D1_N, LP_CLK_P, LP_CLK_N,
    output HS_D0_P, HS_D0_N, HS_D1_P, HS_D1_N, HS_CLK_P, HS_CLK_N
);
  wire CLK_BYTE, INIT_REQ, INIT_READY, INIT_NEXT, INIT_DONE_TX, INIT_LAST, INIT_DONE;
  wire VID_REQ, VID_LINE_RDY, VID_RD, HS_REQ, CLK_REQ, READY, LOCK;
  wire [15:0] VID_WORD;
  wire [7:0] INIT_BYTE, HS_BYTE0, HS_BYTE1;
  wire [2:0] LP_P, LP_N;
  wire RESET, RST_BYTE, LOCK_RAW;

  generate
    if (SUPERVISED) begin : supervised
      phy_supervisor supervisor (
          .CLK_REF(CLK_REF), .CLK_BYTE(CLK_BYTE), .LOCK_RAW(LOCK_RAW),
          .RST_SUP(!RESET_N), .RST_LINK(1'b0), .RESET(RESET), .RST_BYTE(RST_BYTE)
      );
    end else begin : manual_reset
      assign RESET = 1'b0;
      assign RST_BYTE = !RESET_N;
    end
  endgenerate

  init_sequencer #(.CLK_BYTE_HZ(INIT_HZ)) seq (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE),
      .INIT_REQ(INIT_REQ), .INIT_READY(INIT_READY), .INIT_DONE_TX(INIT_DONE_TX),
      .INIT_BYTE(INIT_BYTE), .INIT_LAST(INIT_LAST), .INIT_NEXT(INIT_NEXT), .INIT_DONE(INIT_DONE)
  );
  video_source video (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE), .INIT_DONE(INIT_DONE),
      .VID_REQ(VID_REQ), .VID_LINE_RDY(VID_LINE_RDY), .VID_WORD(VID_WORD), .VID_RD(VID_RD)
  );
  mipi_tx #(.LP_DIV(6), .T_LPX(4), .T_PREP(3), .T_ZERO(7), .T_TRAIL(4),
            .T_CLK_START(27), .C_LINE(1166)) tx (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE),
      .INIT_REQ(INIT_REQ), .INIT_READY(INIT_READY), .INIT_DONE_TX(INIT_DONE_TX),
      .INIT_BYTE(INIT_BYTE), .INIT_LAST(INIT_LAST), .INIT_NEXT(INIT_NEXT),
      .VID_REQ(VID_REQ), .VID_LINE_RDY(VID_LINE_RDY), .VID_WORD(VID_WORD), .VID_RD(VID_RD),
      .READY(READY), .LOCK(LOCK), .HS_REQ(HS_REQ), .CLK_REQ(CLK_REQ),
      .LP_P(LP_P), .LP_N(LP_N), .HS_BYTE0(HS_BYTE0), .HS_BYTE1(HS_BYTE1)
  );
  phy #(.USE_IODELAY(DELAY), .STATIC_DELAY_TAPS(32)) link (
      .CLK_REF(CLK_REF), .RESET(RESET), .RST_BYTE(RST_BYTE), .LOCK_RAW(LOCK_RAW),
      .HS_REQ(HS_REQ), .CLK_REQ(CLK_REQ), .LP_P(LP_P), .LP_N(LP_N),
      .HS_BYTE0(HS_BYTE0), .HS_BYTE1(HS_BYTE1), .CLK_BYTE(CLK_BYTE), .LOCK(LOCK), .READY(READY),
      .LP_D0_P(LP_D0_P), .LP_D0_N(LP_D0_N), .LP_D1_P(LP_D1_P), .LP_D1_N(LP_D1_N),
      .LP_CLK_P(LP_CLK_P), .LP_CLK_N(LP_CLK_N), .HS_D0_P(HS_D0_P), .HS_D0_N(HS_D0_N),
      .HS_D1_P(HS_D1_P), .HS_D1_N(HS_D1_N), .HS_CLK_P(HS_CLK_P), .HS_CLK_N(HS_CLK_N)
  );
endmodule
