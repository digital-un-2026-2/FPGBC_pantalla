`timescale 1ns/1ps
module gowin_tx_safety (
    input ref_clk, byte_clk, fclk_d, fclk_c, rst, phy_abort, lock_raw,
    input uc_block, ev_raw, release_safe,
    output rst_byte, ser_reset_d, ser_reset_c, run_b, output reg inhibit
);
  wire set_inhibit = rst | phy_abort | !lock_raw | uc_block | ev_raw;
  wire rst_pclk, ser_ready_b;
  (* async_reg = "true" *) reg [1:0] run_sync, ready_sync;
  // SET is independent of every derived clock. Clear only in RELEASE.
  always @(posedge ref_clk or posedge set_inhibit) begin
    if (set_inhibit) inhibit <= 1;
    else if (release_safe) inhibit <= 0;
  end
  gowin_tx_reset_sync byte_reset (.clk(byte_clk),.request(rst|!lock_raw),.rst(rst_byte));
  gowin_tx_reset_sync p_reset (.clk(byte_clk),.request(inhibit),.rst(rst_pclk));
  // First release PCLK, then each FCLK domain. No RUN_B feedback loop.
  gowin_tx_reset_sync d_reset (.clk(fclk_d),.request(inhibit|rst_pclk),.rst(ser_reset_d));
  gowin_tx_reset_sync c_reset (.clk(fclk_c),.request(inhibit|rst_pclk),.rst(ser_reset_c));
  always @(posedge byte_clk or posedge inhibit) begin
    if (inhibit) begin run_sync <= 0; ready_sync <= 0; end
    else begin
      run_sync <= {run_sync[0],1'b1};
      ready_sync <= {ready_sync[0],!(rst_pclk|ser_reset_d|ser_reset_c)};
    end
  end
  assign ser_ready_b = ready_sync[1];
  assign run_b = run_sync[1] & ser_ready_b;
endmodule
