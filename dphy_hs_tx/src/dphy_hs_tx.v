`timescale 1ns/1ps
// Logical HS sequencer, S320 profile. No OSER, PLL, pads or delay statements.
module dphy_hs_tx #(parameter integer BYTE_HZ=40000000) (
    input clk, rst, phy_abort,
    input clk_start_req, data_start_req, data_stop_req, clk_stop_req,
    input hs_grant, input [15:0] hs_word_data, input [1:0] hs_word_keep,
    input hs_word_valid, hs_word_last,
    output clk_prepared, data_prepared, data_stopped, clk_stopped,
    output hs_local_stop, phy_error, output [2:0] error_code,
    output [15:0] hs_frame_data, output [1:0] hs_frame_kind,
    output hs_data_on, hs_clk_on, clk_toggle,
    output [1:0] lp_clk, lp_d0, lp_d1
);
  wire capture, move, retire, clear_pipe;
  wire [3:0] time_sel;
  wire time_load, time_step, post_load, post_step;
  wire p_valid, p_last, a_valid, a_last, mask_ok, time_last, post_last;
  wire time_sel_ok; // Diagnostic; nominal selector validated before override in UC.
  hs_phy_control control (
    .clk(clk),.rst(rst),.phy_abort(phy_abort),
    .cs(clk_start_req),.ds(data_start_req),.dt(data_stop_req),.ct(clk_stop_req),
    .valid(hs_word_valid),.last(hs_word_last),.grant(hs_grant),
    .p_valid(p_valid),.p_last(p_last),.a_valid(a_valid),.a_last(a_last),
    .mask_ok(mask_ok),.time_last(time_last),.post_last(post_last),
    .capture(capture),.move(move),.retire(retire),.clear_pipe(clear_pipe),
    .sel_word(hs_frame_kind),.time_sel(time_sel),.time_load(time_load),
    .time_step(time_step),.post_load(post_load),.post_step(post_step),
    .clk_prepared(clk_prepared),.data_prepared(data_prepared),
    .data_stopped(data_stopped),.clk_stopped(clk_stopped),
    .local_stop(hs_local_stop),.phy_error(phy_error),.error_code(error_code),
    .hs_data_on(hs_data_on),.hs_clk_on(hs_clk_on),.clk_toggle(clk_toggle),
    .lp_clk(lp_clk),.lp_d0(lp_d0),.lp_d1(lp_d1));
  hs_phy_datapath #(.BYTE_HZ(BYTE_HZ)) datapath (
    .clk(clk),.rst(rst),.word_data(hs_word_data),.word_last(hs_word_last),
    .word_keep(hs_word_keep),.capture(capture),.move(move),.retire(retire),
    .clear_pipe(clear_pipe),.sel_word(hs_frame_kind),.time_sel(time_sel),
    .time_load(time_load),.time_step(time_step),.post_load(post_load),.post_step(post_step),
    .p_valid(p_valid),.p_last(p_last),.a_valid(a_valid),.a_last(a_last),
    .mask_ok(mask_ok),.time_last(time_last),.post_last(post_last),
    .time_sel_ok(time_sel_ok),.frame_data(hs_frame_data));
endmodule
