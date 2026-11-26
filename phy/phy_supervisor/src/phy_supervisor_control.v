module phy_supervisor_control (
    input CLK_WD, RST_WD, REF_OK, BYTE_OK, BYTE_ACK, LOCK_OK, LINK_OK,
    output RESET, ALLOW
);
  localparam [1:0] WAIT_REF = 2'b10, ACQUIRE = 2'b00, ENABLED = 2'b01;
  // The state bits directly encode the PLL reset and byte release permission.
  (* fsm_encoding = "none" *) reg [1:0] STATE = WAIT_REF;
  reg [6:0] REF_CNT;
  reg [1:0] BYTE_PROOFS;
  reg [15:0] QUAL_CNT;
  reg [16:0] TRY_CNT;
  wire QUAL_INPUTS = REF_OK && BYTE_OK && LOCK_OK && LINK_OK && BYTE_PROOFS == 2'd2;

  always @(negedge CLK_WD or posedge RST_WD) begin
    if (RST_WD) begin
      REF_CNT <= 7'd0;
      BYTE_PROOFS <= 2'd0;
      QUAL_CNT <= 16'd0;
      TRY_CNT <= 17'd0;
    end else begin
      if (STATE != WAIT_REF || !REF_OK) REF_CNT <= 7'd0;
      else if (REF_CNT < 7'd64) REF_CNT <= REF_CNT + 1'b1;

      // The first ACK in ACQUIRE may match a request sent before entry.
      if (STATE != ACQUIRE || !BYTE_OK) BYTE_PROOFS <= 2'd0;
      else if (BYTE_ACK && BYTE_PROOFS != 2'd2) BYTE_PROOFS <= BYTE_PROOFS + 1'b1;

      // 62 000 full CLK_WD periods at 31 MHz are 2 ms.
      if (STATE != ACQUIRE || !QUAL_INPUTS) QUAL_CNT <= 16'd0;
      else if (QUAL_CNT < 16'd62000) QUAL_CNT <= QUAL_CNT + 1'b1;

      if (STATE != ACQUIRE || !LINK_OK) TRY_CNT <= 17'd0;
      else if (TRY_CNT < 17'd124000) TRY_CNT <= TRY_CNT + 1'b1;
    end
  end

  always @(posedge CLK_WD or posedge RST_WD) begin
    if (RST_WD) STATE <= WAIT_REF;
    else begin
      case (STATE)
        WAIT_REF: if (REF_OK && REF_CNT == 7'd64) STATE <= ACQUIRE;
        ACQUIRE: begin
          if (!REF_OK) STATE <= WAIT_REF;
          else if (QUAL_INPUTS && QUAL_CNT == 16'd62000) STATE <= ENABLED;
          else if (LINK_OK && TRY_CNT == 17'd124000) STATE <= WAIT_REF;
        end
        ENABLED: begin
          if (!REF_OK || !BYTE_OK) STATE <= WAIT_REF;
          else if (!LOCK_OK || !LINK_OK) STATE <= ACQUIRE;
        end
        default: STATE <= WAIT_REF;
      endcase
    end
  end

  assign RESET = STATE[1];
  assign ALLOW = STATE[0] && !STATE[1];
endmodule
