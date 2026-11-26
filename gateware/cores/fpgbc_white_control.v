// Board reset and backlight. The watchdog and the PHY own link isolation.
module fpgbc_white_control (
    input CLK_REF, CLK_BYTE, GLOBAL_RST_N, RST_BYTE, ISO, INIT_DONE,
    output RST_SUP, BL_EN, BL_PWM
);
  wire BUTTON_RESET, RST_BL;
  reg [15:0] POR = 16'hffff;
  wire CUT_BL = RST_SUP || RST_BYTE || ISO;
  reg INIT_BYTE_DONE = 1'b0;
  (* async_reg = "true" *) reg [1:0] INIT_REF = 2'b00;
  reg [15:0] COUNT = 0;
  reg EN = 0, PWM = 0;

  phy_supervisor_reset_sync button (
      .CLK(CLK_REF), .RESET_IN(!GLOBAL_RST_N), .RESET_OUT(BUTTON_RESET)
  );
  always @(negedge CLK_REF or posedge BUTTON_RESET) begin
    if (BUTTON_RESET) POR <= 16'hffff;
    else POR <= POR >> 1;
  end
  assign RST_SUP = BUTTON_RESET || (POR != 0);

  phy_supervisor_reset_sync backlight_reset (
      .CLK(CLK_REF), .RESET_IN(CUT_BL), .RESET_OUT(RST_BL)
  );
  // Register the sequencer's state decode before crossing to CLK_REF.
  always @(negedge CLK_BYTE) begin
    if (RST_BYTE) INIT_BYTE_DONE <= 1'b0;
    else INIT_BYTE_DONE <= INIT_DONE;
  end

  always @(posedge CLK_REF or posedge RST_BL) begin
    if (RST_BL) INIT_REF <= 2'b00;
    else INIT_REF <= {INIT_REF[0], INIT_BYTE_DONE};
  end

  always @(negedge CLK_REF or posedge RST_BL) begin
    if (RST_BL) begin
      EN <= 1'b0;
      PWM <= 1'b0;
      COUNT <= 0;
    end else begin
      EN <= INIT_REF[1];
      if (EN) begin
        PWM <= COUNT < 16'd20000;
        if (COUNT == 16'd39999) COUNT <= 0;
        else COUNT <= COUNT + 1'b1;
      end else begin
        PWM <= 1'b0;
        COUNT <= 0;
      end
    end
  end

  assign BL_EN = !CUT_BL && !RST_BL && EN;
  assign BL_PWM = BL_EN && PWM;
endmodule
