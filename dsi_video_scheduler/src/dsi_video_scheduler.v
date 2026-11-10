`timescale 1ns / 1ps

// Planificador WAIT/RGB/END. Fuente, preparador, packer, transporte y PHY
// son externos. Ordenes tipo strobe, listas para un futuro adaptador CSR.
module dsi_video_scheduler #(
    parameter integer SOURCE_WIDTH = 720,
    parameter integer SOURCE_HEIGHT = 720,
    parameter integer BUFFER_WORDS = 2048,
    parameter integer N_PROFILES = 1,
    parameter integer E_MAX = 1,
    parameter [N_PROFILES*16-1:0] WIDTH_TABLE = {N_PROFILES{SOURCE_WIDTH[15:0]}},
    parameter [N_PROFILES*16-1:0] HEIGHT_TABLE = {N_PROFILES{SOURCE_HEIGHT[15:0]}},
    parameter [N_PROFILES*16-1:0] N_EVENTS_TABLE = 0,
    parameter [N_PROFILES*32-1:0] T_FRAME_TABLE = 0,
    parameter [N_PROFILES-1:0] TIMING_OK_TABLE = 0,
    parameter [N_PROFILES-1:0] TARGET_OK_TABLE = 0,
    parameter [N_PROFILES*E_MAX*66-1:0] EVENT_TABLE = {N_PROFILES*E_MAX{66'h30000000000000000}}
) (
    input clk, input rst,
    input cfg_write, input [7:0] cfg_profile_id, input [1:0] cfg_vc,
    input cfg_apply, input start, input stop, input panel_set, input panel_clear,
    input [2:0] status_addr, output reg [31:0] status_data,
    output config_ok, output panel_initialized, output running, output stopped,
    output error, output [3:0] error_cause, output [31:0] frame_count,

    output source_start_valid, input source_start_ready,
    input [7:0] source_byte_data, input source_byte_valid, output source_byte_ready,
    input source_line_last, input source_frame_last,
    input source_busy, input source_frame_done,

    output cmd_valid, input cmd_ready, output [1:0] cmd_vc,
    output [5:0] cmd_dt, output [15:0] cmd_wc,
    output [7:0] payload_data, output payload_valid, input payload_ready,
    input packet_busy, input packet_done,
    input transport_busy, input transport_error, input hs_done,
    input arbiter_busy, input arbiter_error, input hs_complete,
    input phy_available, input phy_error, input phy_abort
);
  wire [9:0] shadow, active;
  wire [15:0] width, height, n_events, ip, bcnt, line_count;
  wire [15:0] cfg_width, cfg_height, cfg_n_events;
  wire [31:0] t_frame, cfg_t_frame, tick;
  wire timing_ok, target_ok, cfg_timing_ok, cfg_target_ok;
  wire [65:0] rom_event;
  wire [3:0] state;
  wire [4:0] error_status;
  wire [1:0] kind;
  wire frame_active, event_valid, illegal_state, hard_block;
  wire cfg_accept, start_accept, payload_window, source_fire, descriptor_fire;
  wire pkt_window, frame_window, stop_window;
  wire frame_begin, event_load, event_advance, rgb_complete, frame_complete;
  wire released, ip_ok, next_ip_ok, bytes_remaining, last_bf, pkt_ok, end_ok;
  wire stop_next, urgent_fault, fault_req;
  wire chain_free = !source_busy && !packet_busy && !transport_busy && !arbiter_busy;
  wire phy_fault = phy_error || phy_abort || arbiter_error;
  wire external_fault = phy_fault || transport_error;
  wire g = payload_window && bytes_remaining;
  wire byte_fire = payload_valid && payload_ready;
  // Extender antes de sumar o desplazar; nunca validar un WC truncado.
  wire [17:0] cfg_width_ext = {2'd0, cfg_width};
  wire [17:0] cfg_wc_ext = cfg_width_ext + (cfg_width_ext << 1);
  wire [18:0] cfg_packet_bytes = {1'b0, cfg_wc_ext} + 19'd6;
  wire [17:0] width_ext = {2'd0, width};
  wire [17:0] wc_ext = width_ext + (width_ext << 1);
  localparam [63:0] CAPACITY_BYTES = 64'd2 * BUFFER_WORDS;
  wire cfg_match = {1'b0, shadow[9:2]} < N_PROFILES &&
      cfg_width == SOURCE_WIDTH && cfg_width >= 8 && cfg_width[2:0] == 0 &&
      cfg_height == SOURCE_HEIGHT && cfg_height >= 1 &&
      cfg_wc_ext <= 18'd65535 && cfg_packet_bytes <= CAPACITY_BYTES &&
      !cfg_packet_bytes[0] && cfg_n_events >= 1 && cfg_n_events <= E_MAX &&
      cfg_t_frame <= 32'hfffffffe && cfg_timing_ok && cfg_target_ok;

  generate
    if (SOURCE_WIDTH < 8 || SOURCE_WIDTH > 65535 || SOURCE_WIDTH % 8 != 0 ||
        SOURCE_HEIGHT < 1 || SOURCE_HEIGHT > 65535 || BUFFER_WORDS < 1) begin : invalid_parameters
      DSI_SCHEDULER_INVALID_SOURCE_OR_BUFFER invalid_config ();
    end
  endgenerate

  scheduler_register #(.BITS(10)) r_shadow (
      .clk(clk), .rst(rst), .ld(cfg_accept), .d({cfg_profile_id, cfg_vc}), .q(shadow)
  );
  // Dos puertos logicos de lectura: candidato y ejecucion. Sin metadatos
  // registrados ni transferencia de configuracion durante los cuadros.
  scheduler_profile_rom #(
      .N_PROFILES(N_PROFILES), .E_MAX(E_MAX), .WIDTH_TABLE(WIDTH_TABLE),
      .HEIGHT_TABLE(HEIGHT_TABLE), .N_EVENTS_TABLE(N_EVENTS_TABLE),
      .T_FRAME_TABLE(T_FRAME_TABLE), .TIMING_OK_TABLE(TIMING_OK_TABLE),
      .TARGET_OK_TABLE(TARGET_OK_TABLE), .EVENT_TABLE(EVENT_TABLE)
  ) candidate_rom (
      .profile_id(shadow[9:2]), .ip(16'd0), .width(cfg_width), .height(cfg_height),
      .n_events(cfg_n_events), .t_frame(cfg_t_frame), .timing_ok(cfg_timing_ok),
      .target_ok(cfg_target_ok), .event_data()
  );
  scheduler_profile_rom #(
      .N_PROFILES(N_PROFILES), .E_MAX(E_MAX), .WIDTH_TABLE(WIDTH_TABLE),
      .HEIGHT_TABLE(HEIGHT_TABLE), .N_EVENTS_TABLE(N_EVENTS_TABLE),
      .T_FRAME_TABLE(T_FRAME_TABLE), .TIMING_OK_TABLE(TIMING_OK_TABLE),
      .TARGET_OK_TABLE(TARGET_OK_TABLE), .EVENT_TABLE(EVENT_TABLE)
  ) active_rom (
      .profile_id(active[9:2]), .ip(ip), .width(width), .height(height),
      .n_events(n_events), .t_frame(t_frame), .timing_ok(timing_ok),
      .target_ok(target_ok), .event_data(rom_event)
  );

  assign cmd_vc = active[1:0];
  assign cmd_dt = 6'h3e;
  assign cmd_wc = wc_ext[15:0];
  assign payload_data = source_byte_data;
  assign payload_valid = source_byte_valid && g;
  assign source_byte_ready = payload_ready && g;
  assign error = error_status[4];
  assign error_cause = error_status[3:0];

  scheduler_control control (
      .clk(clk), .rst(rst), .cfg_write(cfg_write), .cfg_apply(cfg_apply),
      .panel_set(panel_set), .panel_clear(panel_clear), .start(start),
      .cfg_match(cfg_match), .chain_free(chain_free), .phy_available(phy_available),
      .external_fault(external_fault), .error_valid(error), .urgent_fault(urgent_fault),
      .fault_req(fault_req), .source_start_ready(source_start_ready), .cmd_ready(cmd_ready),
      .last_bf(last_bf), .ip_ok(ip_ok), .next_ip_ok(next_ip_ok), .kind(kind),
      .released(released), .pkt_ok(pkt_ok), .end_ok(end_ok), .stop_next(stop_next),
      .state(state), .config_ok(config_ok), .panel_initialized(panel_initialized),
      .running(running), .stopped(stopped), .frame_active(frame_active),
      .event_valid(event_valid), .illegal_state(illegal_state), .hard_block(hard_block),
      .cfg_accept(cfg_accept), .start_accept(start_accept),
      .source_start_valid(source_start_valid), .cmd_valid(cmd_valid), .payload_window(payload_window),
      .source_fire(source_fire), .descriptor_fire(descriptor_fire),
      .pkt_window(pkt_window), .frame_window(frame_window), .stop_window(stop_window),
      .frame_begin(frame_begin), .event_load(event_load), .event_advance(event_advance),
      .rgb_complete(rgb_complete), .frame_complete(frame_complete)
  );
  scheduler_datapath datapath (
      .clk(clk), .rst(rst), .shadow(shadow), .start_accept(start_accept),
      .frame_begin(frame_begin), .event_load(event_load), .event_advance(event_advance),
      .rgb_complete(rgb_complete), .frame_complete(frame_complete),
      .running(running), .frame_active(frame_active), .event_valid(event_valid),
      .illegal_state(illegal_state), .state(state), .pkt_window(pkt_window),
      .frame_window(frame_window), .stop_window(stop_window), .descriptor_fire(descriptor_fire),
      .byte_fire(byte_fire), .source_fire(source_fire), .stop(stop), .rom_event(rom_event),
      .height(height), .n_events(n_events), .t_frame(t_frame), .wc(cmd_wc),
      .source_line_last(source_line_last), .source_frame_last(source_frame_last),
      .source_frame_done(source_frame_done), .packet_done(packet_done),
      .hs_done(hs_done), .hs_complete(hs_complete), .packet_busy(packet_busy),
      .transport_busy(transport_busy), .chain_free(chain_free), .phy_fault(phy_fault),
      .transport_error(transport_error), .active(active), .ip(ip), .tick(tick),
      .bcnt(bcnt), .line_count(line_count), .frame_count(frame_count), .error_status(error_status),
      .kind(kind), .released(released), .ip_ok(ip_ok), .next_ip_ok(next_ip_ok),
      .bytes_remaining(bytes_remaining), .last_bf(last_bf), .pkt_ok(pkt_ok),
      .end_ok(end_ok), .stop_next(stop_next), .urgent_fault(urgent_fault), .fault_req(fault_req)
  );
  // Direcciones de seleccion logicas; no son un esclavo de bus LiteX.
  always @(*) begin
    status_data = 0;
    case (status_addr)
      0: status_data = {20'd0, state, error, panel_initialized, config_ok, stopped, running};
      1: status_data = frame_count;
      2: status_data = {27'd0, error_status};
      3: status_data = {22'd0, active};
      4: status_data = {16'd0, width};
      5: status_data = {16'd0, height};
    endcase
  end
endmodule
