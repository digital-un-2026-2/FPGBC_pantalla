`timescale 1ns / 1ps

// Preparador de paquetes largos DSI. Todos los registros: posedge clk.
module dsi_long_packet_tx (
    input clk,
    input rst,
    input cmd_valid,
    input [1:0] cmd_vc,
    input [5:0] cmd_dt,
    input [15:0] cmd_wc,
    output cmd_ready,

    input [7:0] payload_data,
    input payload_valid,
    output payload_ready,

    output [7:0] tx_byte_data,
    output tx_byte_valid,
    output tx_byte_last,
    input tx_byte_ready,
    output busy,
    output packet_done
);
  wire [23:0] header_in = {cmd_wc, cmd_vc, cmd_dt};
  wire [7:0] ecc;
  wire [31:0] header;
  wire [7:0] byte_actual;
  wire [15:0] crc_actual, crc_sig;
  wire [1:0] idx_header;
  wire [15:0] enviados;
  wire idx_crc;
  wire [7:0] header_byte, crc_byte;
  wire ld_desc, ld_payload, init_crc, upd_crc;
  wire clr_header, inc_header, clr_payload, inc_payload, clr_crc, inc_crc;
  wire z_header_last, z_payload_done;
  wire [1:0] sel_tx;

  long_packet_ecc ecc_header (.header(header_in), .ecc(ecc));

  long_packet_register #(.BITS(32)) reg_header (
      .clk(clk), .rst(rst), .reg_in({ecc, header_in}),
      .ld(ld_desc), .reg_out(header)
  );
  long_packet_register #(.BITS(8)) reg_payload (
      .clk(clk), .rst(rst), .reg_in(payload_data),
      .ld(ld_payload), .reg_out(byte_actual)
  );
  long_packet_crc16 crc_next (
      .crc_in(crc_actual), .byte_in(byte_actual), .crc_out(crc_sig)
  );
  long_packet_register #(.BITS(16)) reg_crc (
      .clk(clk), .rst(rst), .reg_in(init_crc ? 16'hffff : crc_sig),
      .ld(init_crc || upd_crc), .reg_out(crc_actual)
  );

  long_packet_counter #(.BITS(2)) count_header (
      .clk(clk), .rst(rst || clr_header), .inc(inc_header), .count_out(idx_header)
  );
  long_packet_counter #(.BITS(16)) count_payload (
      .clk(clk), .rst(rst || clr_payload), .inc(inc_payload), .count_out(enviados)
  );
  long_packet_counter #(.BITS(1)) count_crc (
      .clk(clk), .rst(rst || clr_crc), .inc(inc_crc), .count_out(idx_crc)
  );
  long_packet_compare #(.BITS(2)) comp_header (
      .A(idx_header), .B(2'd3), .z(z_header_last)
  );
  long_packet_compare #(.BITS(16)) comp_payload (
      .A(enviados), .B(header[23:8]), .z(z_payload_done)
  );

  long_packet_mux #(.INPUTS(4), .BITS(8)) mux_header (
      .data_in(header), .sel(idx_header), .data_out(header_byte)
  );
  long_packet_mux #(.INPUTS(2), .BITS(8)) mux_crc (
      .data_in(crc_actual), .sel(idx_crc), .data_out(crc_byte)
  );
  long_packet_mux #(.INPUTS(3), .BITS(8)) mux_tx (
      .data_in({crc_byte, byte_actual, header_byte}), .sel(sel_tx),
      .data_out(tx_byte_data)
  );

  long_packet_control ctrl (
      .clk(clk), .rst(rst), .cmd_valid(cmd_valid), .payload_valid(payload_valid),
      .tx_byte_ready(tx_byte_ready), .z_header_last(z_header_last),
      .z_payload_done(z_payload_done), .z_crc_last(idx_crc),
      .ld_desc(ld_desc), .ld_payload(ld_payload), .init_crc(init_crc), .upd_crc(upd_crc),
      .clr_header(clr_header), .inc_header(inc_header),
      .clr_payload(clr_payload), .inc_payload(inc_payload),
      .clr_crc(clr_crc), .inc_crc(inc_crc), .sel_tx(sel_tx),
      .cmd_ready(cmd_ready), .payload_ready(payload_ready),
      .tx_byte_valid(tx_byte_valid), .tx_byte_last(tx_byte_last),
      .busy(busy), .packet_done(packet_done)
  );
endmodule
