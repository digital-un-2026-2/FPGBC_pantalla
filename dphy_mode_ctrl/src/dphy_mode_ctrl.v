`timescale 1ns / 1ps

// Integracion estructural: UC en posedge, datapath en negedge.
// Las ordenes siguen siendo logicas para el modelo de PHY, sin pads.
module dphy_mode_ctrl (
    input clk, input rst,
    input lp_req, output lp_req_ready, input lp_done,
    output lp_grant, output lp_complete,
    input hs_req, output hs_req_ready, input hs_done,
    input hs_error, input hs_data_ready, input pll_locked,
    output hs_grant, output hs_complete,
    output clk_start_req, input clk_prepared,
    output data_start_req, input data_prepared,
    output data_stop_req, input data_stopped,
    output clk_stop_req, input clk_stopped,
    input stop_ready, input clear_error,
    output busy, output error, output [1:0] error_code, output phy_abort
);
  wire lp_fire, hs_fire, hs_fault;
  wire arb_libre, hs_active, fault_active, busy_ctrl;
  wire [5:0] intents;
  wire take_lp, take_hs, ld_err, pll_cause, fin_lp_evt, fin_hs_evt;
  wire [1:0] sel_err;

  mode_control control (
      .clk(clk), .rst(rst), .lp_fire(lp_fire), .hs_fire(hs_fire),
      .hs_fault(hs_fault), .pll_locked(pll_locked),
      .lp_done(lp_done), .hs_done(hs_done),
      .clk_prepared(clk_prepared), .data_prepared(data_prepared),
      .hs_data_ready(hs_data_ready), .data_stopped(data_stopped),
      .clk_stopped(clk_stopped), .stop_ready(stop_ready), .clear_error(clear_error),
      .arb_libre(arb_libre), .hs_active(hs_active),
      .fault_active(fault_active), .busy_ctrl(busy_ctrl), .intents(intents),
      .take_lp(take_lp), .take_hs(take_hs), .ld_err(ld_err),
      .sel_err(sel_err), .pll_cause(pll_cause),
      .fin_lp_evt(fin_lp_evt), .fin_hs_evt(fin_hs_evt)
  );

  mode_datapath datapath (
      .clk(clk), .rst(rst), .lp_req(lp_req), .hs_req(hs_req),
      .pll_locked(pll_locked), .hs_data_ready(hs_data_ready),
      .hs_error(hs_error), .stop_ready(stop_ready),
      .arb_libre(arb_libre), .hs_active(hs_active),
      .fault_active(fault_active), .busy_ctrl(busy_ctrl), .intents(intents),
      .take_lp(take_lp), .take_hs(take_hs), .ld_err(ld_err),
      .sel_err(sel_err), .pll_cause(pll_cause),
      .fin_lp_evt(fin_lp_evt), .fin_hs_evt(fin_hs_evt),
      .lp_fire(lp_fire), .hs_fire(hs_fire), .hs_fault(hs_fault),
      .lp_req_ready(lp_req_ready), .hs_req_ready(hs_req_ready),
      .lp_grant(lp_grant), .hs_grant(hs_grant),
      .clk_start_req(clk_start_req), .data_start_req(data_start_req),
      .data_stop_req(data_stop_req), .clk_stop_req(clk_stop_req),
      .lp_complete(lp_complete), .hs_complete(hs_complete),
      .error_code(error_code), .busy(busy), .error(error), .phy_abort(phy_abort)
  );
endmodule
