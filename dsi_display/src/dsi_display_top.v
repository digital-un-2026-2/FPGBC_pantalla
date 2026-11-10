`timescale 1ns/1ps
// Full display chain. Commands and snapshots use ref_clk; pixels use byte_clk.
// Defaults have no enabled panel schedule and no authorized physical profile.
module dsi_display_top #(
    parameter integer WIDTH=720, HEIGHT=720, BUFFER_WORDS=2048,
    parameter integer N_PROFILES=1, E_MAX=1,
    parameter [N_PROFILES*16-1:0] WIDTH_TABLE={N_PROFILES{WIDTH[15:0]}},
    parameter [N_PROFILES*16-1:0] HEIGHT_TABLE={N_PROFILES{HEIGHT[15:0]}},
    parameter [N_PROFILES*16-1:0] N_EVENTS_TABLE=0,
    parameter [N_PROFILES*32-1:0] T_FRAME_TABLE=0,
    parameter [N_PROFILES-1:0] TIMING_OK_TABLE=0, TARGET_OK_TABLE=0,
    parameter [N_PROFILES*E_MAX*66-1:0] EVENT_TABLE={N_PROFILES*E_MAX{66'h30000000000000000}},
    parameter J=0, PROFILE_OK=0, LP_ONLY=0,
    parameter PLL_IDIV=0, PLL_FBDIV=3, PLL_ODIV=4, PLL_SDIV=4,
    parameter PLL_PHASE="0000", SER_HWL="false",
    parameter [23:0] MAP_BITS=24'hfac688
) (
    input ref_clk, rst,
    input [31:0] command, input command_valid, output command_ready,
    output [127:0] response, output response_valid,
    output byte_clk, rst_byte, phy_available, clock_fault,
    output [2:0] lp_pad_p, lp_pad_n, hs_pad_p, hs_pad_n
);
  wire ref_rst;
  wire core_rst=rst | rst_byte;
  wire [31:0] byte_command;
  wire [127:0] byte_response;
  wire byte_valid, byte_ready, byte_response_valid;
  wire [15:0] hs_frame_data;
  wire [1:0] estado_D0, hs_frame_kind, lp_clk, lp_d0, lp_d1;
  wire clk_prepared, data_prepared, data_stopped, clk_stopped, stop_ready, clk_prepared_s, data_prepared_s, data_stopped_s, clk_stopped_s, local_stop_s, phy_abort, lp_grant, hs_data_on, hs_clk_on, clk_toggle;
  gowin_tx_reset_sync control_reset (.clk(ref_clk),.request(core_rst),.rst(ref_rst));
  display_mailbox mailbox (
    .ref_clk(ref_clk),.ref_rst(ref_rst),.byte_clk(byte_clk),.byte_rst(core_rst),
    .command(command),.command_valid(command_valid),.command_ready(command_ready),
    .response(response),.response_valid(response_valid),
    .byte_command(byte_command),.byte_valid(byte_valid),.byte_ready(byte_ready),
    .byte_response(byte_response),.byte_response_valid(byte_response_valid));
  dsi_display_core #(
    .VIDEO_ENABLE(!LP_ONLY),
    .WIDTH(WIDTH),
    .HEIGHT(HEIGHT),
    .BUFFER_WORDS(BUFFER_WORDS),
    .N_PROFILES(N_PROFILES),
    .E_MAX(E_MAX),
    .WIDTH_TABLE(WIDTH_TABLE),
    .HEIGHT_TABLE(HEIGHT_TABLE),
    .N_EVENTS_TABLE(N_EVENTS_TABLE),
    .T_FRAME_TABLE(T_FRAME_TABLE),
    .TIMING_OK_TABLE(TIMING_OK_TABLE),
    .TARGET_OK_TABLE(TARGET_OK_TABLE),
    .EVENT_TABLE(EVENT_TABLE)
  ) core (
    .clk(byte_clk),.rst(core_rst),.command(byte_command),.command_valid(byte_valid),.command_ready(byte_ready),
    .response(byte_response),.response_valid(byte_response_valid),.phy_available(phy_available),.clock_fault(clock_fault),
    .clk_prepared(clk_prepared),
    .data_prepared(data_prepared),
    .data_stopped(data_stopped),
    .clk_stopped(clk_stopped),
    .stop_ready(stop_ready),
    .clk_prepared_s(clk_prepared_s),
    .data_prepared_s(data_prepared_s),
    .data_stopped_s(data_stopped_s),
    .clk_stopped_s(clk_stopped_s),
    .local_stop_s(local_stop_s),
    .phy_abort(phy_abort),
    .lp_grant(lp_grant),
    .hs_data_on(hs_data_on),
    .hs_clk_on(hs_clk_on),
    .clk_toggle(clk_toggle),
    .estado_D0(estado_D0),
    .hs_frame_data(hs_frame_data),
    .hs_frame_kind(hs_frame_kind),
    .lp_clk(lp_clk),
    .lp_d0(lp_d0),
    .lp_d1(lp_d1));
  generate if (LP_ONLY) begin: lp_only
    assign byte_clk=ref_clk;
    assign clock_fault=1'b0;
    gowin_tx_reset_sync byte_reset (.clk(ref_clk),.request(rst),.rst(rst_byte));
    assign phy_available=PROFILE_OK && !rst && !rst_byte;
    assign {clk_prepared,data_prepared}=2'b00;
    assign {data_stopped,clk_stopped}=2'b11;
    wire safe=phy_available && !phy_abort;
    assign stop_ready=safe && local_stop_s && !lp_grant && estado_D0==2'b11;
    display_lp_pads #(.PROFILE_OK(PROFILE_OK)) pads (
      .rst(rst | rst_byte),.phy_abort(phy_abort),.lp_grant(lp_grant),.estado_D0(estado_D0),
      .lp_pad_p(lp_pad_p),.lp_pad_n(lp_pad_n),.hs_pad_p(hs_pad_p),.hs_pad_n(hs_pad_n));
  end else begin: hs_phy
  dphy_gowin_tx #(.J(J),.PROFILE_OK(PROFILE_OK),.PLL_IDIV(PLL_IDIV),.PLL_FBDIV(PLL_FBDIV),
    .PLL_ODIV(PLL_ODIV),.PLL_SDIV(PLL_SDIV),.PLL_PHASE(PLL_PHASE),.SER_HWL(SER_HWL),.MAP_BITS(MAP_BITS)) wrapper (
    .ref_clk(ref_clk),.rst(rst),.byte_clk(byte_clk),.rst_byte(rst_byte),
    .pll_ready(phy_available),.clock_fault(clock_fault),
    .phy_abort(phy_abort),
    .lp_grant(lp_grant),
    .estado_D0(estado_D0),
    .hs_frame_data(hs_frame_data),
    .hs_frame_kind(hs_frame_kind),
    .hs_data_on(hs_data_on),
    .hs_clk_on(hs_clk_on),
    .clk_toggle(clk_toggle),
    .lp_clk(lp_clk),
    .lp_d0(lp_d0),
    .lp_d1(lp_d1),
    .clk_prepared_s(clk_prepared_s),
    .data_prepared_s(data_prepared_s),
    .data_stopped_s(data_stopped_s),
    .clk_stopped_s(clk_stopped_s),
    .local_stop_s(local_stop_s),
    .clk_prepared_p(clk_prepared),.data_prepared_p(data_prepared),
    .data_stopped_p(data_stopped),.clk_stopped_p(clk_stopped),.stop_ready(stop_ready),
    .lp_pad_p(lp_pad_p),.lp_pad_n(lp_pad_n),.hs_pad_p(hs_pad_p),.hs_pad_n(hs_pad_n));
  end endgenerate
endmodule
