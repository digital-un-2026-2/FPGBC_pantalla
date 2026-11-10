`timescale 1ns/1ps
// Ordinary datapath storage: R_FRAME[16] + L * R_CTRL[18], posedge only.
module gowin_tx_datapath #(
    parameter J=0, parameter L=2+J,
    parameter [5:0] P_LP_RUN_EN=6'h3f, P_LP_BLOCK_EN=6'h00, P_LP_BLOCK_DATA=6'h00
) (
    input byte_clk, rst_byte, phy_abort, run_b, lock_raw, inhibit, uc_block, ev_raw,
    input lp_grant, input [1:0] estado_D0,
    input [15:0] hs_frame_data, input [1:0] hs_frame_kind,
    input hs_data_on, hs_clk_on, clk_toggle,
    input [1:0] lp_clk, lp_d0, lp_d1,
    input clk_prepared_s, data_prepared_s, data_stopped_s, clk_stopped_s, local_stop_s,
    output [15:0] frame_q, output [7:0] clock_d,
    output [5:0] lp_dat, lp_en, output [2:0] hs_oe,
    output clk_prepared_p, data_prepared_p, data_stopped_p, clk_stopped_p,
    output stop_ready, pll_ready, pipe_valid
);
  wire rst_pipe = rst_byte | phy_abort | !run_b;
  wire ld_cmd = run_b & !rst_pipe;
  wire [1:0] selected_d0;
  wire [16:0] ctrl_in;
  wire [17:0] ctrl [0:L-1];
  wire [16:0] ctrl_p = ctrl[L-1][16:0];
  wire [2:0] hs_req = {ctrl_p[3],ctrl_p[2],ctrl_p[2]};
  wire [3:0] ack_out;
  wire [4:0] cond;
  wire safe;
  gowin_tx_mux #(.WIDTH(2)) m0 (.d0(lp_d0),.d1(estado_D0),.sel(lp_grant),.q(selected_d0));
  assign ctrl_in = {local_stop_s,clk_stopped_s,data_stopped_s,data_prepared_s,
      clk_prepared_s,lp_grant,lp_clk,lp_d1,selected_d0,
      clk_toggle,hs_clk_on,hs_data_on,hs_frame_kind};
  gowin_tx_register #(.WIDTH(16),.RESET_DATA(0)) r_frame (
      .clk(byte_clk),.rst(rst_pipe),.en(ld_cmd),.d(hs_frame_data),.q(frame_q));
  gowin_tx_register #(.WIDTH(18)) r_ctrl0 (
      .clk(byte_clk),.rst(rst_pipe),.en(ld_cmd),.d({1'b1,ctrl_in}),.q(ctrl[0]));
  genvar i;
  generate for (i=1;i<L;i=i+1) begin: control_pipe
    gowin_tx_register #(.WIDTH(18)) r_ctrl (
        .clk(byte_clk),.rst(rst_pipe),.en(ld_cmd),.d(ctrl[i-1]),.q(ctrl[i]));
  end endgenerate
  gowin_tx_mux #(.WIDTH(8)) m1 (.d0(8'h00),.d1(8'haa),.sel(ctrl[0][4]),.q(clock_d));
  assign pipe_valid = ctrl[L-1][17];
  assign pll_ready = run_b & !rst_byte & lock_raw & !inhibit & !uc_block & !ev_raw;
  // Do not feed phy_abort combinationally back into arbiter.pll_locked.
  // INHIBIT/EV retain the abort; SAFE still masks it directly at the pads.
  assign safe = pll_ready & pipe_valid & !phy_abort;
  gowin_tx_mux #(.WIDTH(6)) m2 (.d0(P_LP_BLOCK_DATA),.d1(ctrl_p[10:5]),.sel(safe),.q(lp_dat));
  gowin_tx_mux #(.WIDTH(6)) m3 (.d0(P_LP_BLOCK_EN),.d1(P_LP_RUN_EN),.sel(safe),.q(lp_en));
  assign hs_oe = hs_req & {3{safe}};
  assign ack_out = ctrl_p[15:12] & {4{safe}};
  assign {clk_stopped_p,data_stopped_p,data_prepared_p,clk_prepared_p} = ack_out;
  assign cond = {estado_D0==2'b11,!(ctrl_p[11]|lp_grant),hs_req==3'b000,
      lp_en==6'h3f,lp_dat==6'h3f};
  assign stop_ready = safe & ctrl_p[16] & (&cond);
endmodule
