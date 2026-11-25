module lp_tx_bit_cnt (
    input CLK_BYTE,
    input RST_BYTE,
    input BIT_EN,

    output MARK0,
    output reg SPACE_NEXT,
    output SHIFT
);
  reg [2:0] BIT_IDX;

  assign MARK0 = !SPACE_NEXT && (BIT_IDX == 3'd0);
  assign SHIFT = BIT_EN && SPACE_NEXT;

  always @(negedge CLK_BYTE) begin
    if (RST_BYTE) begin
      BIT_IDX <= 3'd0;
      SPACE_NEXT <= 1'b0;
    end else begin
      if (BIT_EN) SPACE_NEXT <= !SPACE_NEXT;
      if (SHIFT) BIT_IDX <= BIT_IDX + 3'd1;
    end
  end
endmodule
