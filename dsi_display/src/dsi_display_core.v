`timescale 1ns/1ps

// Byte-clock integration. No CPU or physical timing model is hidden here.
module dsi_display_core #(
    parameter integer WIDTH=720, HEIGHT=720, BUFFER_WORDS=2048,
    parameter VIDEO_ENABLE=1,
    parameter integer N_PROFILES=1, E_MAX=1,
    parameter [N_PROFILES*16-1:0] WIDTH_TABLE={N_PROFILES{WIDTH[15:0]}},
    parameter [N_PROFILES*16-1:0] HEIGHT_TABLE={N_PROFILES{HEIGHT[15:0]}},
    parameter [N_PROFILES*16-1:0] N_EVENTS_TABLE=0,
    parameter [N_PROFILES*32-1:0] T_FRAME_TABLE=0,
    parameter [N_PROFILES-1:0] TIMING_OK_TABLE=0, TARGET_OK_TABLE=0,
    parameter [N_PROFILES*E_MAX*66-1:0] EVENT_TABLE={N_PROFILES*E_MAX{66'h30000000000000000}}
) (
    input clk, rst,
    input [31:0] command, input command_valid, output command_ready,
    output [127:0] response, output response_valid,
    input phy_available, clock_fault,
    input clk_prepared, data_prepared, data_stopped, clk_stopped, stop_ready,
    output clk_prepared_s, data_prepared_s, data_stopped_s, clk_stopped_s, local_stop_s,
    output phy_abort, lp_grant, output [1:0] estado_D0,
    output [15:0] hs_frame_data, output [1:0] hs_frame_kind,
    output hs_data_on, hs_clk_on, clk_toggle,
    output [1:0] lp_clk, lp_d0, lp_d1
);
  wire running, stopped, config_ok, panel_initialized, scheduler_error;
  wire [3:0] error_cause;
  wire [31:0] frame_count;
  wire source_start, source_ready, source_valid, source_take, line_last, frame_last;
  wire source_busy, source_done;
  wire [7:0] source_data, payload_data, packet_data;
  wire cmd_valid, cmd_ready, payload_valid, payload_ready, packet_busy, packet_done;
  wire [1:0] cmd_vc;
  wire [5:0] cmd_dt;
  wire [15:0] cmd_wc;
  wire packet_valid, packet_last, packet_ready;
  wire [15:0] packed_data, hs_word_data;
  wire [1:0] packed_keep, hs_word_keep;
  wire packed_valid, packed_last, packed_ready, hs_word_valid, hs_word_last;
  wire transport_busy, transport_error, hs_req, hs_req_ready, hs_reserved;
  wire hs_grant, hs_done, hs_complete, mode_busy, mode_error, phy_error;
  wire [1:0] transport_code, mode_code;
  wire [2:0] phy_code;
  wire cs, ds, dt, ct;
  wire [7:0] lp_byte;
  wire lp_valid, lp_last, lp_ready, lp_packet_busy, lp_cmd_ready;
  wire lp_req, lp_done, lp_complete, bridge_busy, lp_packet_error;
  reg lp_pending=0, lp_fault=0;
  // Break the asynchronous inhibit -> PLL-ready -> arbiter-abort return path.
  // Pad inhibition and PLL-loss reset remain immediate in the Gowin wrapper.
  reg link_ready=0;
  reg [31:0] lp_count=0;
  reg reply_pending=0, rejected=0;
  wire [3:0] op=command[3:0];
  wire chain_fault=scheduler_error || transport_error || mode_error || phy_error || clock_fault || lp_fault;
  wire idle=stopped && !lp_pending && !lp_packet_busy && !bridge_busy && !mode_busy && !chain_fault;
  wire fire=command_valid && command_ready;
  wire lp_accept=fire && op==7 && idle && phy_available && stop_ready && lp_cmd_ready;
  wire start_accept=VIDEO_ENABLE && fire && op==5 && idle && config_ok && panel_initialized && phy_available && stop_ready;
  wire cfg_write=fire && op==1 && idle;
  wire cfg_apply=VIDEO_ENABLE && fire && op==2 && idle;
  wire panel_set=fire && op==3 && idle && phy_available && stop_ready;
  wire panel_clear=(fire && op==4 && idle) || lp_accept;
  wire stop=fire && op==6;
  wire accepted=op==0 || cfg_write || cfg_apply || panel_set || panel_clear ||
                start_accept || (op==6 && (running || idle)) || lp_accept;
  assign command_ready=!rst && !reply_pending;
  assign response_valid=reply_pending && !rst;
  wire [31:0] flags={11'd0, transport_code, mode_code, phy_code, error_cause,
      rejected, clock_fault, mode_busy, lp_pending, phy_available,
      chain_fault, panel_initialized, config_ok, stopped && !lp_pending, running};
  // Low word: flags; +4 frames; +8 completed LP transactions; +12 geometry.
  assign response={{HEIGHT[15:0], WIDTH[15:0]}, lp_count, frame_count, flags};
  always @(posedge clk) begin
    if (rst) begin
      reply_pending<=0; rejected<=0; lp_pending<=0; lp_count<=0; lp_fault<=0;
      link_ready<=0;
    end else begin
      link_ready<=phy_available;
      reply_pending<=fire;
      if (fire) rejected<=!accepted;
      if (lp_accept) lp_pending<=1;
      if (lp_complete) begin lp_pending<=0; lp_count<=lp_count+1; end
      if (lp_packet_error) lp_fault<=1;
    end
  end

  dsi_test_pattern #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) source (
    .clk(clk),.rst(rst),.start_valid(source_start),.start_ready(source_ready),
    .tx_byte_data(source_data),.tx_byte_valid(source_valid),.tx_byte_ready(source_take),
    .tx_line_last(line_last),.tx_frame_last(frame_last),.busy(source_busy),.frame_done(source_done));
  dsi_video_scheduler #(
    .SOURCE_WIDTH(WIDTH),.SOURCE_HEIGHT(HEIGHT),.BUFFER_WORDS(BUFFER_WORDS),
    .N_PROFILES(N_PROFILES),.E_MAX(E_MAX),.WIDTH_TABLE(WIDTH_TABLE),.HEIGHT_TABLE(HEIGHT_TABLE),
    .N_EVENTS_TABLE(N_EVENTS_TABLE),.T_FRAME_TABLE(T_FRAME_TABLE),
    .TIMING_OK_TABLE(TIMING_OK_TABLE),.TARGET_OK_TABLE(TARGET_OK_TABLE),.EVENT_TABLE(EVENT_TABLE)
  ) scheduler (
    .clk(clk),.rst(rst),.cfg_write(cfg_write),.cfg_profile_id(command[11:4]),.cfg_vc(command[13:12]),
    .cfg_apply(cfg_apply),.start(start_accept),.stop(stop),.panel_set(panel_set),.panel_clear(panel_clear),
    .status_addr(3'd0),.status_data(),.config_ok(config_ok),.panel_initialized(panel_initialized),
    .running(running),.stopped(stopped),.error(scheduler_error),.error_cause(error_cause),.frame_count(frame_count),
    .source_start_valid(source_start),.source_start_ready(source_ready),.source_byte_data(source_data),
    .source_byte_valid(source_valid),.source_byte_ready(source_take),.source_line_last(line_last),
    .source_frame_last(frame_last),.source_busy(source_busy),.source_frame_done(source_done),
    .cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_vc(cmd_vc),.cmd_dt(cmd_dt),.cmd_wc(cmd_wc),
    .payload_data(payload_data),.payload_valid(payload_valid),.payload_ready(payload_ready),
    .packet_busy(packet_busy),.packet_done(packet_done),.transport_busy(transport_busy),
    .transport_error(transport_error),.hs_done(hs_done),
    .arbiter_busy(mode_busy || lp_pending || lp_packet_busy || bridge_busy),
    .arbiter_error(mode_error || lp_fault),.hs_complete(hs_complete),
    .phy_available(phy_available && stop_ready),.phy_error(phy_error || clock_fault),.phy_abort(phy_abort));
  dsi_long_packet_tx packet (
    .clk(clk),.rst(rst),.cmd_valid(cmd_valid),.cmd_ready(cmd_ready),.cmd_vc(cmd_vc),.cmd_dt(cmd_dt),.cmd_wc(cmd_wc),
    .payload_data(payload_data),.payload_valid(payload_valid),.payload_ready(payload_ready),
    .tx_byte_data(packet_data),.tx_byte_valid(packet_valid),.tx_byte_last(packet_last),
    .tx_byte_ready(packet_ready),.busy(packet_busy),.packet_done(packet_done));
  dsi_lane_packer packer (
    .clk(clk),.rst(rst),.tx_byte_data(packet_data),.tx_byte_valid(packet_valid),.tx_byte_last(packet_last),
    .tx_byte_ready(packet_ready),.tx_word_data(packed_data),.tx_word_keep(packed_keep),
    .tx_word_valid(packed_valid),.tx_word_last(packed_last),.tx_word_ready(packed_ready));
  dsi_hs_transport #(.BUFFER_WORDS(BUFFER_WORDS)) transport (
    .clk(clk),.rst(rst),.tx_word_data(packed_data),.tx_word_keep(packed_keep),
    .tx_word_valid(packed_valid),.tx_word_last(packed_last),.tx_word_ready(packed_ready),
    .hs_req(hs_req),.hs_req_ready(hs_req_ready),.hs_data_ready(hs_reserved),.hs_grant(hs_grant),
    .hs_done(hs_done),.hs_error(transport_error),.hs_complete(hs_complete),.phy_abort(phy_abort),
    .hs_word_data(hs_word_data),.hs_word_keep(hs_word_keep),.hs_word_valid(hs_word_valid),.hs_word_last(hs_word_last),
    .busy(transport_busy),.error(),.error_code(transport_code));
  dsi_lp_packet_tx lp_packet (
    .clk(clk),.rst(rst),.cmd_valid(lp_accept),.cmd_ready(lp_cmd_ready),
    .cmd_opcode(command[11:4]),.cmd_has_param(command[12]),.cmd_param(command[20:13]),
    .tx_byte_data(lp_byte),.tx_byte_valid(lp_valid),.tx_byte_last(lp_last),.tx_byte_ready(lp_ready),
    .busy(lp_packet_busy),.packet_done());
  dsi_lpdt_bridge bridge (
    .clk(clk),.rst(rst),.tx_byte_data(lp_byte),.tx_byte_valid(lp_valid),.tx_byte_last(lp_last),
    .tx_byte_ready(lp_ready),.permiso_arranque(lp_grant),.lp_req(lp_req),.busy(bridge_busy),
    .tx_done(lp_done),.packet_error(lp_packet_error),.estado_D0(estado_D0));
  dphy_mode_ctrl arbiter (
    .clk(clk),.rst(rst),.lp_req(lp_req),.lp_req_ready(),.lp_done(lp_done),.lp_grant(lp_grant),.lp_complete(lp_complete),
    .hs_req(hs_req),.hs_req_ready(hs_req_ready),.hs_done(hs_done),
    .hs_error(transport_error || phy_error || clock_fault || lp_fault),
    .hs_data_ready(hs_reserved),.pll_locked(link_ready),.hs_grant(hs_grant),.hs_complete(hs_complete),
    .clk_start_req(cs),.data_start_req(ds),.data_stop_req(dt),.clk_stop_req(ct),
    .clk_prepared(clk_prepared),.data_prepared(data_prepared),.data_stopped(data_stopped),.clk_stopped(clk_stopped),
    .stop_ready(stop_ready),.clear_error(1'b0),.busy(mode_busy),.error(mode_error),.error_code(mode_code),.phy_abort(phy_abort));
  dphy_hs_tx phy (
    .clk(clk),.rst(rst),.phy_abort(phy_abort),.clk_start_req(cs),.data_start_req(ds),
    .data_stop_req(dt),.clk_stop_req(ct),.hs_grant(hs_grant),.hs_word_data(hs_word_data),
    .hs_word_keep(hs_word_keep),.hs_word_valid(hs_word_valid),.hs_word_last(hs_word_last),
    .clk_prepared(clk_prepared_s),.data_prepared(data_prepared_s),.data_stopped(data_stopped_s),
    .clk_stopped(clk_stopped_s),.hs_local_stop(local_stop_s),.phy_error(phy_error),.error_code(phy_code),
    .hs_frame_data(hs_frame_data),.hs_frame_kind(hs_frame_kind),.hs_data_on(hs_data_on),.hs_clk_on(hs_clk_on),
    .clk_toggle(clk_toggle),.lp_clk(lp_clk),.lp_d0(lp_d0),.lp_d1(lp_d1));
endmodule
