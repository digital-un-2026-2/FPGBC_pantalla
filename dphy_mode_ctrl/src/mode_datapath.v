`timescale 1ns / 1ps

module mode_datapath (
    input clk, input rst,
    input lp_req, input hs_req, input pll_locked, input hs_data_ready,
    input hs_error, input stop_ready,
    input arb_libre, input hs_active, input fault_active, input busy_ctrl,
    input [5:0] intents,
    input take_lp, input take_hs, input ld_err, input [1:0] sel_err,
    input pll_cause, input fin_lp_evt, input fin_hs_evt,
    output lp_fire, output hs_fire, output hs_fault,
    output lp_req_ready, output hs_req_ready,
    output lp_grant, output hs_grant,
    output clk_start_req, output data_start_req,
    output data_stop_req, output clk_stop_req,
    output lp_complete, output hs_complete,
    output [1:0] error_code,
    output busy, output error, output phy_abort
);
  wire r_lp, r_hs, pref;
  wire d_lp, d_hs, d_pref;
  wire [1:0] hs_cause, d_cause;
  wire lp_eligible = lp_req && r_lp;
  wire hs_eligible = hs_req && r_hs && pll_locked && hs_data_ready && !hs_error;
  wire en_arb = !rst && arb_libre && stop_ready;
  assign lp_req_ready = en_arb && lp_eligible && (!hs_eligible || !pref);
  assign hs_req_ready = en_arb && hs_eligible && (!lp_eligible || pref);
  assign lp_fire = lp_req && lp_req_ready;
  assign hs_fire = hs_req && hs_req_ready;

  // M0/M1: req ya bajo en negedge rearma, incluso si se acepto en el posedge
  // anterior. Req mantenido alto se consume; la aceptacion viene de UC.
  mode_mux m0 (.data_in({1'b0, 1'b1}), .sel(take_lp && lp_req), .data_out(d_lp));
  mode_mux m1 (.data_in({1'b0, 1'b1}), .sel(take_hs && hs_req), .data_out(d_hs));
  mode_mux m2 (.data_in({1'b0, 1'b1}), .sel(take_hs), .data_out(d_pref));
  mode_register #(.RESET_VALUE(1'b1)) reg_lp (
      .clk(clk), .rst(rst), .ld(!lp_req || take_lp), .data_in(d_lp), .data_out(r_lp)
  );
  mode_register #(.RESET_VALUE(1'b1)) reg_hs (
      .clk(clk), .rst(rst), .ld(!hs_req || take_hs), .data_in(d_hs), .data_out(r_hs)
  );
  mode_register reg_pref (
      .clk(clk), .rst(rst), .ld(take_lp || take_hs), .data_in(d_pref), .data_out(pref)
  );
  // M3 selecciona la causa decidida en posedge, no la PLL viva de negedge.
  mode_mux #(.BITS(2)) m3 (
      .data_in({2'b01, 2'b10}), .sel(pll_cause), .data_out(hs_cause)
  );
  mode_mux #(.INPUTS(3), .BITS(2)) m4 (
      .data_in({2'b11, hs_cause, 2'b00}), .sel(sel_err), .data_out(d_cause)
  );
  mode_register #(.BITS(2)) reg_cause (
      .clk(clk), .rst(rst), .ld(ld_err), .data_in(d_cause), .data_out(error_code)
  );
  mode_register reg_fin_lp (
      .clk(clk), .rst(rst), .ld(1'b1), .data_in(fin_lp_evt), .data_out(lp_complete)
  );
  mode_register reg_fin_hs (
      .clk(clk), .rst(rst), .ld(1'b1), .data_in(fin_hs_evt), .data_out(hs_complete)
  );
  assign hs_fault = hs_active && (!pll_locked || hs_error);
  assign {lp_grant, hs_grant, clk_start_req, data_start_req, data_stop_req, clk_stop_req}
      = intents & {6{!rst && !hs_fault}};
  assign busy = busy_ctrl;
  assign error = !rst && fault_active;
  assign phy_abort = rst || fault_active || hs_fault;
endmodule
