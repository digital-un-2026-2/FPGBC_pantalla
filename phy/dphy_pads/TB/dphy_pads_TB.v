`timescale 1ps / 1ps

module dphy_pads_TB;
  localparam [1:0] OFF = 2'b00, DRIVE = 2'b01, BIAS = 2'b10;
  reg [2:0] LP_P, LP_N, serial;
  reg [1:0] LP_DAT_MODE, LP_CLK_MODE;
  reg HS_EN, CLK_EN, ISO;
  wire [2:0] lp_p, lp_n, hs_p, hs_n;

  dphy_pads dut (
      .LP_P(LP_P), .LP_N(LP_N), .HS_D0(serial[0]), .HS_D1(serial[1]), .HS_CLK(serial[2]),
      .LP_DAT_MODE(LP_DAT_MODE), .LP_CLK_MODE(LP_CLK_MODE),
      .HS_EN(HS_EN), .CLK_EN(CLK_EN), .ISO(ISO),
      .LP_D0_P(lp_p[0]), .LP_D0_N(lp_n[0]), .LP_D1_P(lp_p[1]), .LP_D1_N(lp_n[1]),
      .LP_CLK_P(lp_p[2]), .LP_CLK_N(lp_n[2]),
      .HS_D0_P(hs_p[0]), .HS_D0_N(hs_n[0]), .HS_D1_P(hs_p[1]), .HS_D1_N(hs_n[1]),
      .HS_CLK_P(hs_p[2]), .HS_CLK_N(hs_n[2])
  );

  task check_pair;
    input integer lane;
    input [1:0] mode;
    input hs_en;
    reg [1:0] lp_expected, hs_expected;
    begin
      lp_expected = 2'bzz;
      hs_expected = 2'bzz;
      if (!ISO) begin
        case ({mode, hs_en})
          {DRIVE, 1'b0}: lp_expected = {LP_P[lane], LP_N[lane]};
          {BIAS, 1'b0}: lp_expected = 2'b00;
          {BIAS, 1'b1}: begin
            lp_expected = 2'b00;
            hs_expected = {serial[lane], ~serial[lane]};
          end
          default: ;
        endcase
      end
      if ({lp_p[lane], lp_n[lane], hs_p[lane], hs_n[lane]} !== {lp_expected, hs_expected})
        $fatal(1, "par %0d modo=%b hs_en=%b ISO=%b: LP/HS=%b/%b, esperado %b/%b",
               lane, mode, hs_en, ISO, {lp_p[lane], lp_n[lane]}, {hs_p[lane], hs_n[lane]},
               lp_expected, hs_expected);
    end
  endtask

  task check_pads;
    begin
      #2000;
      check_pair(0, LP_DAT_MODE, HS_EN);
      check_pair(1, LP_DAT_MODE, HS_EN);
      check_pair(2, LP_CLK_MODE, CLK_EN);
    end
  endtask

  integer controls, levels;
  initial begin
    if ($test$plusargs("waves")) begin
      $dumpfile("dphy_pads_TB.fst");
      $dumpvars(0, dphy_pads_TB);
    end

    // No clock edges: each serial output is held at a fixed level while
    // only ISO changes, including both possible stopped HS_CLK levels.
    for (controls = 0; controls < 64; controls = controls + 1) begin
      {LP_DAT_MODE, LP_CLK_MODE, HS_EN, CLK_EN} = controls[5:0];
      for (levels = 0; levels < 512; levels = levels + 1) begin
        {LP_P, LP_N, serial} = levels[8:0];
        ISO = 0;
        check_pads;
        ISO = 1;
        check_pads;
      end
    end

    // Start from bias only, enable both differential drivers, then release
    // data to LP11 while CLK remains differential. Isolate that mixed state.
    ISO = 0;
    {LP_P, LP_N} = 6'b111111;
    {LP_DAT_MODE, LP_CLK_MODE, HS_EN, CLK_EN} = {BIAS, BIAS, 2'b00};
    check_pads;
    {HS_EN, CLK_EN} = 2'b11;
    check_pads;
    HS_EN = 0;
    LP_DAT_MODE = OFF;
    check_pads;
    LP_DAT_MODE = DRIVE;
    check_pads;
    ISO = 1;
    check_pads;
    $display("PASS DPHY_PADS: P/N, bias, OE independientes e ISO sin flancos");
    $finish;
  end
endmodule
