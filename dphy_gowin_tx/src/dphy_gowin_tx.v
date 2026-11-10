`timescale 1ns/1ps
// DPHY_GOWIN_TX.drawio pages 5-9. No changes to upstream interfaces.
module dphy_gowin_tx #(
    parameter J=0, parameter L=2+J, parameter PROFILE_OK=0,
    parameter [5:0] P_LP_RUN_EN=6'h3f, P_LP_BLOCK_EN=6'h00, P_LP_BLOCK_DATA=6'h00,
    parameter [23:0] MAP_BITS=24'hfac688, parameter SER_HWL="false",
    parameter PLL_IDIV=0, PLL_FBDIV=3, PLL_ODIV=4, PLL_SDIV=4,
    parameter PLL_PHASE="0000", parameter DEVICE="GW2AR-18"
) (
    input ref_clk, rst, phy_abort, lp_grant, input [1:0] estado_D0,
    input [15:0] hs_frame_data, input [1:0] hs_frame_kind,
    input hs_data_on, hs_clk_on, clk_toggle,
    input [1:0] lp_clk, lp_d0, lp_d1,
    input clk_prepared_s, data_prepared_s, data_stopped_s, clk_stopped_s, local_stop_s,
    output byte_clk, rst_byte,
    output clk_prepared_p, data_prepared_p, data_stopped_p, clk_stopped_p,
    output stop_ready, pll_ready, clock_fault,
    output [2:0] lp_pad_p, lp_pad_n, hs_pad_p, hs_pad_n
);
  // A mismatch cannot accidentally authorize conduction, including synthesis.
  localparam CONFIG_OK = J>=0 && L==2+J && PLL_SDIV==4;
  wire fclk_d, fclk_c, lock_raw, lock_sync, abort_ref, ev_ref, ready_ref;
  wire release_safe, uc_block, ev_raw, run_started, inhibit, run_b, pipe_valid;
  wire ser_reset_d, ser_reset_c;
  wire [15:0] frame_q;
  wire [7:0] clock_d;
  wire [5:0] lp_dat, lp_en;
  wire [2:0] hs_oe, serial;
  gowin_tx_pll #(.IDIV(PLL_IDIV),.FBDIV(PLL_FBDIV),.ODIV(PLL_ODIV),
      .SDIV(PLL_SDIV),.PHASE(PLL_PHASE),.DEVICE(DEVICE)) clocks (
      .ref_clk(ref_clk),.rst(rst),.byte_clk(byte_clk),.fclk_d(fclk_d),.fclk_c(fclk_c),.lock_raw(lock_raw));
  gowin_tx_sync lock_cdc (.clk(ref_clk),.rst(rst),.d(lock_raw),.q(lock_sync));
  gowin_tx_sync abort_cdc (.clk(ref_clk),.rst(rst),.d(phy_abort),.q(abort_ref));
  gowin_tx_sync event_cdc (.clk(ref_clk),.rst(rst),.d(ev_raw),.q(ev_ref));
  gowin_tx_sync ready_cdc (.clk(ref_clk),.rst(rst),.d(run_b & pipe_valid & !rst_byte),.q(ready_ref));
  gowin_tx_control #(.PROFILE_OK(PROFILE_OK && CONFIG_OK)) uc (
      .ref_clk(ref_clk),.rst(rst),.lock_raw(lock_raw),.lock_sync(lock_sync),
      .phy_abort(phy_abort),.abort_ref(abort_ref),.ev_ref(ev_ref),.ready_ref(ready_ref),
      .release_safe(release_safe),.uc_block(uc_block),.ev_raw(ev_raw),
      .clock_fault(clock_fault),.run_started(run_started));
  gowin_tx_safety safety (
      .ref_clk(ref_clk),.byte_clk(byte_clk),.fclk_d(fclk_d),.fclk_c(fclk_c),
      .rst(rst),.phy_abort(phy_abort),.lock_raw(lock_raw),.uc_block(uc_block),
      .ev_raw(ev_raw),.release_safe(release_safe),.rst_byte(rst_byte),
      .ser_reset_d(ser_reset_d),.ser_reset_c(ser_reset_c),.run_b(run_b),.inhibit(inhibit));
  gowin_tx_datapath #(.J(J),.L(L),.P_LP_RUN_EN(P_LP_RUN_EN),
      .P_LP_BLOCK_EN(P_LP_BLOCK_EN),.P_LP_BLOCK_DATA(P_LP_BLOCK_DATA)) dp (
      .byte_clk(byte_clk),.rst_byte(rst_byte),.phy_abort(phy_abort),.run_b(run_b),
      .lock_raw(lock_raw),.inhibit(inhibit),.uc_block(uc_block),.ev_raw(ev_raw),
      .lp_grant(lp_grant),.estado_D0(estado_D0),.hs_frame_data(hs_frame_data),
      .hs_frame_kind(hs_frame_kind),.hs_data_on(hs_data_on),.hs_clk_on(hs_clk_on),
      .clk_toggle(clk_toggle),.lp_clk(lp_clk),.lp_d0(lp_d0),.lp_d1(lp_d1),
      .clk_prepared_s(clk_prepared_s),.data_prepared_s(data_prepared_s),
      .data_stopped_s(data_stopped_s),.clk_stopped_s(clk_stopped_s),.local_stop_s(local_stop_s),
      .frame_q(frame_q),.clock_d(clock_d),.lp_dat(lp_dat),.lp_en(lp_en),.hs_oe(hs_oe),
      .clk_prepared_p(clk_prepared_p),.data_prepared_p(data_prepared_p),
      .data_stopped_p(data_stopped_p),.clk_stopped_p(clk_stopped_p),
      .stop_ready(stop_ready),.pll_ready(pll_ready),.pipe_valid(pipe_valid));
  gowin_tx_ser8 #(.MAP_BITS(MAP_BITS),.HWL(SER_HWL)) s0 (
      .d(frame_q[7:0]),.pclk(byte_clk),.fclk(fclk_d),.rst(ser_reset_d),.q(serial[0]));
  gowin_tx_ser8 #(.MAP_BITS(MAP_BITS),.HWL(SER_HWL)) s1 (
      .d(frame_q[15:8]),.pclk(byte_clk),.fclk(fclk_d),.rst(ser_reset_d),.q(serial[1]));
  gowin_tx_ser8 #(.MAP_BITS(MAP_BITS),.HWL(SER_HWL)) s2 (
      .d(clock_d),.pclk(byte_clk),.fclk(fclk_c),.rst(ser_reset_c),.q(serial[2]));
  gowin_tx_pads pads (.lp_dat(lp_dat),.lp_en(lp_en),.serial(serial),.hs_oe(hs_oe),
      .lp_pad_p(lp_pad_p),.lp_pad_n(lp_pad_n),.hs_pad_p(hs_pad_p),.hs_pad_n(hs_pad_n));
endmodule
