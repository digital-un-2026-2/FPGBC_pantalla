// Auxiliary to MIPI_TX. The watchdog clock does not depend on either monitored clock.
module phy_supervisor (
    input CLK_REF, CLK_BYTE, LOCK_RAW,
    input RST_SUP, RST_LINK,
    output RESET, RST_BYTE
);
  wire OSC_CLK, CLK_WD, RST_WD;
  wire REF_OK, BYTE_OK, BYTE_ACK;
  wire LOCK_OK, LINK_OK, LOCK_FAST, LINK_FAST;
  wire ALLOW;
  wire CUT_REQ = RST_SUP || !ALLOW || !LOCK_FAST || !LINK_FAST;

  OSC #(.FREQ_DIV(10), .DEVICE("GW2AR-18")) oscillator (.OSCOUT(OSC_CLK));
  BUFG watchdog_clock (.I(OSC_CLK), .O(CLK_WD));
  phy_supervisor_reset_sync reset_wd (.CLK(CLK_WD), .RESET_IN(RST_SUP), .RESET_OUT(RST_WD));

  phy_supervisor_watch ref_watch (
      .CLK_WD(CLK_WD), .RST_WD(RST_WD), .CLK_WATCH(CLK_REF), .RST_SUP(RST_SUP),
      .OK(REF_OK), .ACKED()
  );
  phy_supervisor_watch byte_watch (
      .CLK_WD(CLK_WD), .RST_WD(RST_WD), .CLK_WATCH(CLK_BYTE), .RST_SUP(RST_SUP),
      .OK(BYTE_OK), .ACKED(BYTE_ACK)
  );
  phy_supervisor_fault lock_fault (
      .CLK_WD(CLK_WD), .RST_WD(RST_WD), .FAULT(!LOCK_RAW), .FAST_OK(LOCK_FAST), .OK(LOCK_OK)
  );
  phy_supervisor_fault link_fault (
      .CLK_WD(CLK_WD), .RST_WD(RST_WD), .FAULT(RST_LINK), .FAST_OK(LINK_FAST), .OK(LINK_OK)
  );
  phy_supervisor_control control (
      .CLK_WD(CLK_WD), .RST_WD(RST_WD), .REF_OK(REF_OK), .BYTE_OK(BYTE_OK),
      .BYTE_ACK(BYTE_ACK), .LOCK_OK(LOCK_OK), .LINK_OK(LINK_OK), .RESET(RESET), .ALLOW(ALLOW)
  );
  phy_supervisor_rearm rearm (.CLK_BYTE(CLK_BYTE), .CUT_REQ(CUT_REQ), .RST_BYTE(RST_BYTE));
endmodule
