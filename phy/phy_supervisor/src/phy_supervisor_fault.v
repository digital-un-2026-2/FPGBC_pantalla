module phy_supervisor_fault (
    input CLK_WD, RST_WD, FAULT,
    output FAST_OK, OK
);
  wire CLEAR_FAST = RST_WD || FAULT;
  (* async_reg = "true" *) reg [3:0] STRETCH;
  (* async_reg = "true" *) reg [1:0] OBSERVE;

  // The fast path cuts asynchronously. Stretch its low level long enough
  // that control sees the fault through a separate CDC before it can clear.
  always @(negedge CLK_WD or posedge CLEAR_FAST) begin
    if (CLEAR_FAST) STRETCH <= 4'b0000;
    else STRETCH <= {STRETCH[2:0], 1'b1};
  end

  always @(negedge CLK_WD or posedge RST_WD) begin
    if (RST_WD) OBSERVE <= 2'b00;
    else OBSERVE <= {OBSERVE[0], FAST_OK};
  end

  assign FAST_OK = STRETCH[3];
  assign OK = OBSERVE[1];
endmodule
