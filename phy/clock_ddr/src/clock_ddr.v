// Reloj reenviado. Cambiar el patrón en el gearbox, con OE externo.
module clock_ddr #(
    parameter USE_IODELAY = 1'b0,
    parameter integer STATIC_DELAY_TAPS = 0
) (
    input  CLK_HS,
    input  ISO,
    input  CLK_TOGGLE,
    output HS_CLK
);
  wire PCLK_110, Q0;
  (* async_reg = "true" *) reg [1:0] RST_HS;
  wire RST_LOCAL = RST_HS[1];
  (* async_reg = "true" *) reg [1:0] TOGGLE_PIPE;

  always @(negedge CLK_HS or posedge ISO) begin
    if (ISO) RST_HS <= 2'b11;
    else     RST_HS <= {RST_HS[0], 1'b0};
  end

  always @(negedge PCLK_110 or posedge RST_LOCAL) begin
    if (RST_LOCAL) TOGGLE_PIPE <= 2'b00;
    else           TOGGLE_PIPE <= {TOGGLE_PIPE[0], CLK_TOGGLE};
  end

  CLKDIV #(.DIV_MODE("2"), .GSREN("false")) divider (
      .HCLKIN(CLK_HS), .RESETN(!RST_LOCAL), .CALIB(1'b0), .CLKOUT(PCLK_110)
  );

  OSER4 #(.HWL("false"), .LSREN("true"), .GSREN("false")) serializer (
      .D0(TOGGLE_PIPE[1]), .D1(1'b0), .D2(TOGGLE_PIPE[1]), .D3(1'b0),
      .TX0(1'b0), .TX1(1'b0),
      .PCLK(PCLK_110), .FCLK(CLK_HS), .RESET(RST_LOCAL),
      .Q0(Q0), .Q1()
  );

  generate
    if (USE_IODELAY) begin : delayed
      IODELAY #(.C_STATIC_DLY(STATIC_DELAY_TAPS)) phase_delay (
          .DI(Q0), .SDTAP(1'b0), .VALUE(1'b0), .SETN(1'b0),
          .DO(HS_CLK), .DF()
      );
    end else begin : direct
      assign HS_CLK = Q0;
    end
  endgenerate

`ifndef SYNTHESIS
  initial begin
    if (USE_IODELAY && (STATIC_DELAY_TAPS < 0 || STATIC_DELAY_TAPS > 127))
      $fatal(1, "STATIC_DELAY_TAPS debe estar entre 0 y 127");
  end
`endif
endmodule
