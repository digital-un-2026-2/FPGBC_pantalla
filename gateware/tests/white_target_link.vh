  reg GLOBAL_RST_N = 0;
  wire BL_EN, BL_PWM;
  wire [1:0] D0_HS, D1_HS, CLK_HS_PAD;
  wire white_line = WHITE;  // Expected pattern; the TOP generates the real data.
  assign hs_activity = {D0_HS, D1_HS, CLK_HS_PAD} !== 6'bzzzzzz;

  fpgbc_white board (
      .clk40(CLK_REF), .global_rst_n(GLOBAL_RST_N),
      .backlight_en(BL_EN), .backlight_pwm(BL_PWM),
      .LP_D0_P(D0_LP[1]), .LP_D0_N(D0_LP[0]), .LP_D1_P(D1_LP[1]), .LP_D1_N(D1_LP[0]),
      .LP_CLK_P(CLK_LP[1]), .LP_CLK_N(CLK_LP[0]),
      .HS_D0_P(D0_HS[1]), .HS_D0_N(D0_HS[0]), .HS_D1_P(D1_HS[1]), .HS_D1_N(D1_HS[0]),
      .HS_CLK_P(CLK_HS_PAD[1]), .HS_CLK_N(CLK_HS_PAD[0])
  );
  defparam board.supervisor.oscillator.TEST_HZ = OSC_HZ;

  assign CLK_BYTE = board.clk_byte;
  assign {RESET, RST_BYTE, LOCK_RAW, READY} =
         {board.reset_pll, board.rst_byte, board.lock_raw, board.ready};
  assign {INIT_REQ, INIT_READY, INIT_LAST, INIT_NEXT, INIT_DONE_TX, INIT_DONE, INIT_BYTE} =
         {board.init_req, board.init_ready, board.init_last, board.init_next,
          board.init_done_tx, board.init_done, board.init_byte};
  assign {VID_REQ, VID_LINE_RDY, VID_RD, HS_REQ, CLK_REQ, HS_BYTE0, HS_BYTE1} =
         {board.vid_req, board.vid_line_rdy, board.vid_rd,
          board.hs_req, board.clk_req, board.hs_byte0, board.hs_byte1};
