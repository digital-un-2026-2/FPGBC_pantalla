`timescale 1ns / 1ps

module scheduler_datapath (
    input clk, input rst, input [9:0] shadow,
    input start_accept, input frame_begin, input event_load, input event_advance,
    input rgb_complete, input frame_complete,
    input running, input frame_active, input event_valid, input illegal_state,
    input [3:0] state,
    input pkt_window, input frame_window, input stop_window,
    input descriptor_fire, input byte_fire, input source_fire, input stop,
    input [65:0] rom_event,
    input [15:0] height, input [15:0] n_events,
    input [31:0] t_frame, input [15:0] wc,
    input source_line_last, input source_frame_last, input source_frame_done,
    input packet_done, input hs_done, input hs_complete,
    input packet_busy, input transport_busy, input chain_free,
    input phy_fault, input transport_error,
    output [9:0] active, output [15:0] ip,
    output [31:0] tick, output [15:0] bcnt, output [15:0] line_count,
    output [31:0] frame_count, output [4:0] error_status,
    output [1:0] kind, output released, output ip_ok, output next_ip_ok,
    output bytes_remaining, output last_bf, output pkt_ok, output end_ok,
    output stop_next, output urgent_fault, output fault_req
);
  wire [65:0] event_q;
  wire [2:0] pkt_seen, pkt_next;
  wire frame_seen, frame_next, stop_q;
  wire [31:0] a0 = tick + 32'd1;
  wire [16:0] ip_extended = {1'b0, ip} + 17'd1;
  wire [15:0] a1 = ip_extended[15:0];
  wire [15:0] a2 = bcnt + 16'd1;
  wire [15:0] a3 = line_count + 16'd1;
  wire [31:0] a4 = frame_count + 32'd1;
  wire [31:0] m0 = frame_begin ? 32'd0 : a0;
  wire [15:0] m1 = frame_begin ? 16'd0 : a1;
  wire [15:0] m2 = descriptor_fire ? 16'd0 : a2;
  wire [15:0] m3 = frame_begin ? 16'd0 : a3;
  wire overflow = frame_active && tick == 32'hffffffff;
  wire late = (event_valid && tick > event_q[31:0]) ||
              (frame_active && tick > t_frame);
  wire event_error = illegal_state || (running && (
      (state == 4'd2 && !ip_ok) || (state == 4'd7 && !next_ip_ok) ||
      (event_valid && (kind == 3 || (kind == 2 && ip != n_events-16'd1)))));
  wire count_error = (byte_fire && bcnt >= wc) ||
      (pkt_window && packet_done && bcnt != wc) ||
      (event_valid && kind == 1 && line_count >= height);
  wire expect_line_last = bcnt == wc-16'd1;
  wire expect_frame_last = expect_line_last && line_count == height-16'd1;
  wire mark_error = byte_fire && ((source_line_last != expect_line_last) ||
                                       (source_frame_last != expect_frame_last));
  wire source_error = frame_window && source_frame_done &&
      !((bcnt == wc && line_count == height-16'd1) || line_count == height);
  wire [3:0] cause = running && phy_fault ? 4'd1 :
                     running && transport_error ? 4'd2 :
                     overflow ? 4'd3 : late ? 4'd4 : event_error ? 4'd5 :
                     count_error ? 4'd6 : mark_error ? 4'd7 :
                     source_error ? 4'd8 : 4'd0;
  assign urgent_fault = running && (phy_fault || transport_error || overflow || late);
  assign fault_req = cause != 0;
  assign kind = event_q[65:64];
  assign released = tick >= event_q[63:32];
  assign ip_ok = ip < n_events;
  assign next_ip_ok = ip_extended < {1'b0, n_events};
  assign bytes_remaining = bcnt < wc;
  assign last_bf = byte_fire && expect_line_last;
  assign pkt_next = (descriptor_fire ? 3'd0 : pkt_seen) |
                    (pkt_window ? {hs_complete, hs_done, packet_done} : 3'd0);
  // SF limpia el valor combinacional; FRAME_BEGIN habilita su registro.
  assign frame_next = (source_fire ? 1'b0 : frame_seen) |
                      (frame_window && source_frame_done);
  assign stop_next = (start_accept ? 1'b0 : stop_q) | (stop_window && stop);
  assign pkt_ok = pkt_next == 3'b111 && !transport_busy && !packet_busy &&
                  bcnt == wc && line_count < height;
  assign end_ok = released && kind == 2 && ip == n_events-16'd1 &&
                  line_count == height && frame_next && chain_free;

  scheduler_register #(.BITS(10)) r_active (.clk(clk), .rst(rst), .ld(start_accept), .d(shadow), .q(active));
  scheduler_register #(.BITS(32)) r_tick (.clk(clk), .rst(rst), .ld(frame_begin || (frame_active && !overflow)), .d(m0), .q(tick));
  scheduler_register #(.BITS(16)) r_ip (.clk(clk), .rst(rst), .ld(frame_begin || event_advance), .d(m1), .q(ip));
  scheduler_register #(.BITS(66)) r_evt (.clk(clk), .rst(rst), .ld(event_load), .d(rom_event), .q(event_q));
  scheduler_register #(.BITS(16)) r_bcnt (.clk(clk), .rst(rst), .ld(descriptor_fire || byte_fire), .d(m2), .q(bcnt));
  scheduler_register #(.BITS(16)) r_line (.clk(clk), .rst(rst), .ld(frame_begin || rgb_complete), .d(m3), .q(line_count));
  scheduler_register #(.BITS(3)) r_pkt (.clk(clk), .rst(rst), .ld(pkt_window), .d(pkt_next), .q(pkt_seen));
  scheduler_register r_frame (.clk(clk), .rst(rst), .ld(frame_begin || frame_active), .d(frame_next), .q(frame_seen));
  scheduler_register r_stop (.clk(clk), .rst(rst), .ld(stop_window), .d(stop_next), .q(stop_q));
  scheduler_register #(.BITS(5)) r_error (.clk(clk), .rst(rst), .ld(fault_req && !error_status[4]), .d({1'b1, cause}), .q(error_status));
  scheduler_register #(.BITS(32)) r_frames (.clk(clk), .rst(rst), .ld(frame_complete), .d(a4), .q(frame_count));
endmodule
