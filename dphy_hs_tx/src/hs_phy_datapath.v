`timescale 1ns/1ps
// Fixed S320 and S480 timer tables. All storage updates on posedge clk.
module hs_phy_datapath #(parameter integer BYTE_HZ=40000000) (
    input clk, rst, capture, move, retire, clear_pipe,
    input [15:0] word_data, input word_last, input [1:0] word_keep,
    input [1:0] sel_word, input [3:0] time_sel,
    input time_load, time_step, post_load, post_step,
    output p_valid, p_last, a_valid, a_last, mask_ok,
    output time_last, post_last, time_sel_ok,
    output [15:0] frame_data
);
  wire [15:0] p_data, a_data;
  localparam integer TIMER_BITS=BYTE_HZ==60000000 ? 13 : 12;
  wire [TIMER_BITS-1:0] ticks, ticks_dec, ticks_d, profile_d;
  wire [3:0] post, post_dec, post_d;
  wire [15:0] trail = {{8{~a_data[15]}},{8{~a_data[7]}}};
  // M0: constants N-1, in selector order 0..9.
  generate if(BYTE_HZ==60000000) begin: s480
  // 480 Mbit/s/lane: init=100us; LPX=50ns; CLK Prepare/Zero=50/250ns;
  // DATA Prepare/Zero=66.67/116.67ns; Trail=83.33ns; Exit=100ns.
  hs_phy_mux #(.WIDTH(TIMER_BITS),.INPUTS(10),.SEL_WIDTH(4)) m0 (
    .values({13'd3,13'd5,13'd4,13'd6,13'd3,13'd0,13'd14,13'd2,13'd2,13'd5999}),
    .sel(time_sel),.value(profile_d));
  end else if(BYTE_HZ==40000000) begin: s320
  hs_phy_mux #(.WIDTH(TIMER_BITS),.INPUTS(10),.SEL_WIDTH(4)) m0 (
    .values({12'd2,12'd3,12'd2,12'd4,12'd2,12'd0,12'd9,12'd1,12'd1,12'd3999}),
    .sel(time_sel),.value(profile_d));
  end else begin: invalid_rate
    DPHY_HS_REQUIRES_40_OR_60_MHZ invalid_config ();
  end endgenerate
  hs_phy_mux #(.WIDTH(16),.INPUTS(4),.SEL_WIDTH(2)) m1 (
    .values({trail,a_data,16'hb8b8,16'h0000}),.sel(sel_word),.value(frame_data));
  hs_phy_mux #(.WIDTH(TIMER_BITS)) m2 (
    .values({profile_d,ticks_dec}),.sel(time_load),.value(ticks_d));
  hs_phy_mux #(.WIDTH(4)) m3 (
    .values({(BYTE_HZ==60000000 ? 4'd10 : 4'd8),post_dec}),.sel(post_load),.value(post_d));
  hs_phy_sub #(.WIDTH(TIMER_BITS)) sum0 (.value(ticks),.result(ticks_dec));
  hs_phy_sub #(.WIDTH(4)) sum1 (.value(post),.result(post_dec));
  hs_phy_zero #(.WIDTH(TIMER_BITS)) c0 (.value(ticks),.is_zero(time_last));
  hs_phy_zero #(.WIDTH(4)) c1 (.value(post),.is_zero(post_last));
  assign mask_ok = (word_keep == 2'b11);
  assign time_sel_ok = time_sel <= 4'd9;
  hs_phy_register #(.WIDTH(16),.RESET_DATA(0)) pd (
    .clk(clk),.rst(rst),.en(capture),.d(word_data),.q(p_data));
  hs_phy_register pl (.clk(clk),.rst(rst),.en(capture),.d(word_last),.q(p_last));
  hs_phy_register pv (.clk(clk),.rst(rst),.en(clear_pipe|capture|move),
    .d(!clear_pipe && capture),.q(p_valid));
  hs_phy_register #(.WIDTH(16),.RESET_DATA(0)) ad (
    .clk(clk),.rst(rst),.en(move),.d(p_data),.q(a_data));
  hs_phy_register al (.clk(clk),.rst(rst),.en(move),.d(p_last),.q(a_last));
  hs_phy_register av (.clk(clk),.rst(rst),.en(clear_pipe|move|retire),
    .d(!clear_pipe && move),.q(a_valid));
  hs_phy_register #(.WIDTH(TIMER_BITS)) timer (
    .clk(clk),.rst(rst),.en(time_load|(time_step & !time_last)),.d(ticks_d),.q(ticks));
  hs_phy_register #(.WIDTH(4)) post_timer (
    .clk(clk),.rst(rst),.en(post_load|(post_step & !post_last)),.d(post_d),.q(post));
endmodule
